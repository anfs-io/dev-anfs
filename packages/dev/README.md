# dev — working on the toolkit

Install this package when you are changing the toolkit itself rather than using it. It adds `anfs
work` (jobs in their own git worktrees), commands for testing installs on machines you can throw
away, and wires up the git hooks that version packages.

```bash
anfs src add git@github.com:anfs-io/dev-anfs anfs-dev
ppm install anfs-dev/dev
```

`anfs work` and `anfs hooks` are executables (`~/.local/bin/anfs-work`, `anfs-hooks`) that anfs
runs for a command it does not declare itself (core's "commands from packages": `anfs help` lists
them under "From packages", and `anfs work cd` is core's `sh/anfs.sh` function). `ppm container`, `ppm vm`, `ppm user` and `ppm
move` are still ppm commands, stowed into `~/.local/lib/ppm/`. Run any of them for its usage.
What follows is what each one is for and when to reach for it.

## Working on the toolkit

Work on the toolkit is done in jobs, never in the checkouts under `~/.local/share/anfs/sources/`:
those are the live install (the tools on PATH are linked from them) and stay on main. A job is a
directory holding a git worktree of every repo the work touches, all on one branch named for the
job:

```
~/work/                       $ANFS_WORK_HOME (anfs.conf), default ~/work
  <job>/                      the job's name is the branch's name
    core/  stack/  anfs-dev/  worktrees of the clones under sources/, named by alias
    docs/                     a worktree of a repository a space clones
    .job.yml                  what the job is: branch, number, created, and each repo's origin,
                              base commit and main branch
```

```
anfs work new <job> [repo...] [--from REF]   worktrees on a new branch <job> (default repo: core)
anfs work add <job> <repo...>                another repo joins the job, on the same branch
anfs work list                               JOB BRANCH REPOS STATUS NUMBER (keys: job, branch,
                                             repos[], status, number)
anfs work show <job>                         each repo: path, branch, ahead of main, dirty; the env
anfs work path <job> [repo]                  the job's directory, or one repo's worktree
anfs work cd <job> [repo]                    the same, through the shell function in sh/anfs.sh
anfs work env <job>                          the isolation variables, as export lines
anfs work run <job> [repo] -- <cmd...>       a command with them set, in the job's directory or
                                             a repo's worktree (run a core -- bats packages/...)
anfs work remove [-f] [-y] <job>             worktrees, merged branches, the directory
```

- A repo is a source's alias (`core`, `stack`, `anfs-dev`, `user`) or the name of a repository an
  installed space's `space.yml` clones (`docs`, found through `wsm repo ls --json`: its `path`
  ends in the name and its `dir` is a clone). A source that is a local path, or has no git, is refused, and so is a job name that
  is not a branch name, has a `/` or is `main` or `master` (64). A job that exists is 73.
- `new` cuts each branch from REF, default the repo's main (a branch of that name that exists
  already is checked out as it is), and wires the git hooks into a source's worktree when the
  repo has no `core.hooksPath` of its own. It never pushes and never commits.
- A job's state is the worst of its repos': `missing` (the worktree is gone), `dirty`, `ahead N`
  (commits not in main, summed), `clean` (nothing done yet), `merged` (its commits are in main).
  Commits are counted on the branch `<job>` in the origin as well as at the worktree's HEAD, so a
  worktree that is gone or was switched to another branch does not hide them.
- `remove` refuses a dirty worktree, a branch with commits not in main, and files in the job's
  directory that are in no worktree (notes, logs). `-f` lists what would be lost and asks
  (`anfs_confirm`; `-y` does not ask). It deletes each branch that is merged into main (with
  `-f`, the others too), the directory and the job's `TMPDIR` and `PMM_SOCK_DIR`, so the next job
  of that number starts empty.
- The number is chosen under a lock (`$ANFS_WORK_HOME/.numbers.lock`), so jobs made at the same
  moment get different ones.

### Isolation: what a job's tests may share

Each job gets a number at `new`, the lowest free one from 1, kept in `.job.yml`. `anfs work env`
and `run` derive from it, and core's test helpers and e2e scripts use these when they are set:

| Variable | Value | Why |
| --- | --- | --- |
| `ANFS_WORK_JOB` | the job's name | so a helper can tell it runs inside a job |
| `ANFS_WORK_NUMBER` | the job's number | names that must differ per job (the harness's containers) |
| `ROUNDTRIP_SRC_ROOT` | `~/work/<job>` | the round trips test this job's trees |
| `PMM_SOCK_DIR` | `/tmp/pmm-work-<uid>-<n>` | never the live `/tmp/pmm-<uid>` |
| `PMM_SSH_PORT_BASE` | `2222 + 100 × n` | two jobs' machines never want the same port |
| `TMPDIR` | `/tmp/anfs-work-<uid>-<n>` | temp homes are found and cleaned per job |

- The round trips take a source the job does not hold (of `core`, `stack` and `anfs-dev`) from the installed
  sources, by alias.
- The ISO store (`~/.cache/anfs/isos`) is shared and read-only to every test: an ISO downloads
  once. The bats helpers use a temp one; only an e2e reads the real store.
- tart allows two macOS guests in all, and the live install may be using one: `roundtrip-macos`
  takes a host-wide lock (`$ANFS_STATE_HOME/work/tart.lock`) and says who holds it.
- podman is shared: the harness adds `ANFS_WORK_NUMBER` to its containers' names.
- No test in any of core's suites may name `/tmp/pmm-$(id -u)`, a real `*_HOME` or use a broad
  `pkill`; a bats test in core's anfs suite (`isolation.bats`) greps for them.

The tests of this package: `bats packages/dev/tests </dev/null`. They run against a core checkout:
`$ANFS_CORE_DIR`, else the `core` beside this checkout (a job's layout), else the installed one.

## Three Ways to Test an Install

ppm's riskiest code is the part that runs once, on a machine that has nothing: prerequisites,
Homebrew, the first stow. That is exactly the code you cannot test on your own workstation, because
your workstation is already set up. So this package offers three kinds of throwaway machine, and
the differences between them are the whole point:

| | Isolation | Cost | Reaches |
| --- | --- | --- | --- |
| `ppm user` | a second user on **your** machine | seconds | user-level install, a second user against your Homebrew |
| `ppm container` | a Debian or Fedora container | seconds | everything except the kernel and the session |
| `ppm vm` | a full macOS guest | ~11s from a snapshot | everything, including login shells |

**`ppm user`** creates a throwaway user, runs the installer as them and logs you in. It is the
cheapest way to see what a *second* user experiences — the non-owner Homebrew path in particular —
but it shares your machine, so it proves nothing about a bare one.

**`ppm container`** is the workhorse. The boxes are ordinary pcm services, this source's
`containers/anfs-test-debian` and `anfs-test-fedora`. Each has two test users (`owner`, who has
sudo with a password, and `other`, who has none) and every source repo mounted read-only at
`/src/<alias>` (pcm's `anfs-sources` mount set), so the box tests your **working tree** — edits
show up without committing. The boxes run privileged so podman works inside them, and that is
declared in their definitions with the reason. Snapshots make the expensive part reusable:
install Homebrew once, `ppm container snapshot debian brew`, and every later
`ppm container reset debian brew` starts from there in seconds. `ppm container` itself only adds
what is about anfs (linking the mounts and running `install.sh`); the rest is
`pcm up|shell|snapshot|reset anfs-test-<distro>`.

What containers cannot reach is the reason the third row exists: no systemd services, no login
sessions (so nothing that `chsh` touches, and no rc files being sourced for real), no kernel
features like NFS or KVM. And nothing on that list covers macOS at all, which is where ppm's most
fragile paths live — Xcode Command Line Tools, the Homebrew prefix, `sysadminctl`, `/etc/shells`.

**`ppm vm`** is the macOS answer, and deliberately the same motion: the same subcommands, the same
two users, the same read-only `/src` mounts, so a change is tested on macOS the way it is tested on
Debian. It needs Apple silicon, because that is where macOS guests can run at all, and `tart`:

```bash
brew trust --formula openai/tools/softnet && brew install openai/tools/tart
```

Building the base box downloads a stock macOS image (~25GB, once) and provisions it. The image is
deliberately a *vanilla* one with no Homebrew and no Xcode Command Line Tools, so a run against it
exercises the whole of `install.sh` — the part that only ever executes on a machine that has
nothing, and the part most likely to break.

Snapshots are what make that affordable. They are APFS copy-on-write clones, so a cold install
(~3 min, most of it Homebrew and the CLT) is paid once and every later run starts from the snapshot
in about ten seconds.

## Why a VM and Not Another Container

Containers share the host kernel and never start a session, so three things ppm does are invisible
to them: a login shell actually sourcing the rc files and mise activation, `chsh` and `/etc/shells`,
and anything a service manager runs. On top of that, none of ppm's macOS-specific code exists on
Linux at all — the Xcode CLT, the Homebrew prefix and its ownership, `sysadminctl`. Those paths had
no test before `ppm vm`, and they are the ones that run exactly once on a new machine, where a
failure is most expensive.

The design findings behind the implementation — why `/src` has to come from `synthetic.conf`, why a
snapshot recreates the box instead of restarting it, why sudo needs a longer timestamp on a
headless box — are recorded in [anfs-io/docs](https://github.com/anfs-io/docs).

## Git Hooks

`anfs hooks` points a repo's `core.hooksPath` at the hooks this package stows, which bump a
package's patch version whenever a commit touches it.

This is an install step rather than repo content because **git does not carry hooks through a
clone** — a hook committed to a repository does nothing for whoever clones it. So the hook files
ship in a package, get stowed once, and each repo is pointed at the stowed copy. Editing a hook
then takes effect everywhere at once, and a higher-priority repo can override a single hook file
through the same stow layering as any other file.

The setting is always written per repo, never globally. A global `core.hooksPath` applies to every
repository on the machine *and* suppresses each one's own `.git/hooks`, which would silently
disable husky, lefthook or overcommit in unrelated projects.

The version bump happens **once per unpushed series**: the hook compares the working version
against the version at the push base, and only bumps when they match. A run of commits before one
push bumps once, `--amend` does not bump again, and a version you set by hand is left alone. A repo
with nothing pushed yet gets no bumps at all, so a new package sits at `0.1.0` until its first
push.

Because hooks are wired per repo, `anfs hooks install` has to be re-run after `anfs src add` — this
package's install hook cannot know about a repo you add later.
