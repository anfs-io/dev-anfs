# anfs-dev — working on the anfs toolkit

The anfs-dev source (`anfs-io/dev-anfs`): what a person or an agent needs to work on anfs itself,
and nothing a user of anfs needs. Core's AGENTS.md is the reference for the toolkit; this file is
about the tooling around it. It is a `user.list` source (`anfs src add`).

## Layout

- `packages/dev/` — `anfs work` (jobs in git worktrees), `anfs hooks` and the git hooks,
  `ppm container`, `ppm vm`, `ppm user`, `ppm move` (`packages/dev/README.md`). Its `tests/` hold
  the bats suites (`bats packages/dev/tests </dev/null`), and the end-to-end round trips: the
  `harness`, `roundtrip`, `roundtrip-macos`, `roundtrip-sources` and the `fixtures/acme` org.
- `containers/anfs-test-debian`, `containers/anfs-test-fedora` — the Linux test boxes, pcm services
- `machines/anfs-test-macos` — the macOS test box, a pmm machine; `machines/images/anfs-test-macos`
  is its image, and `machines/images/anfs-dev` a Debian image with the toolkit installed. Both
  build on core's base images with `from:` (core is lower priority, which is the way `from:`
  resolves).
- `spaces/space.yml` — the docs space (`anfs-io/docs`), cloned by wsm.

Moved from core (core 1066363) in plan `dev-source/01-move`.

## Git Hooks

`anfs-dev/dev` ships a `pre-commit` hook that bumps a resource's patch version when a commit
touches it, and creates the manifest of a resource that has none. A resource is a directory with
a manifest named for its kind:

| Directory | Manifest |
|-----------|----------|
| `packages/<p>/` | `package.yml` |
| `containers/<c>/` | `container.yml` |
| `machines/<m>/` | `machine.yml` |
| `machines/images/<i>/` | `image.yml` |
| `machines/networks/<n>/` | `network.yml` |
| `stacks/<s>/` | `stack.yml` |

It then refuses the commit if any resource directory would be left without its manifest (one
deleted on its own, or a resource that predates the hook), or with one that is not a YAML map
(`package.yml`: with `categories`, if present, a list; checked when `yq` is installed). A
manifest without a `version:` gets `0.1.0`. Files in no resource (`containers/README.md`,
`machines/profiles.yml`) are left alone. The table is `META_KINDS` in `lib/package-meta.sh`: a
new kind is one line. The files live in the package at
`packages/dev/home/.config/git/ppm-hooks/` and are stowed to `~/.config/git/ppm-hooks/`.

`anfs hooks` (the package's `anfs-hooks`) wires them up, because **git does not carry hooks
through a clone** — so this is an install step, not repo content:

```
anfs hooks status [--all] [repo...]
anfs hooks install [--all] [repo...]
anfs hooks uninstall [--all] [repo...]
```

With no repo names it acts on the `system.list` repos and the source the `dev` package was
installed from (found from where the stowed hooks really live); `--all` adds the rest of your
`user.list` ones.
The package's `post_install` runs `anfs hooks install`, and its `post_remove` runs
`anfs hooks uninstall --all`. Re-run `anfs hooks install` after `anfs src add`, since `post_install`
can't know about a repo added later. `anfs work new` wires the hooks into a job's worktrees itself.

How it is wired, and why:

- Each repo gets **`core.hooksPath` set locally**, pointed at the stowed directory. Pointing at
  the stowed path (not into the package) means editing a hook takes effect in every repo at once,
  and a higher-priority layer can override a single hook file through stow.
- **Never set `core.hooksPath` globally.** A global value applies to every repo on the machine
  *and* suppresses each repo's own `.git/hooks`, which would silently disable husky/lefthook/
  overcommit in unrelated projects. `init.templateDir` is no good either: it copies at
  `git init`/`clone` only, isn't retroactive, and the copies go stale.
- `core.hooksPath` replaces a repo's `.git/hooks` wholesale, so `anfs hooks install` warns when
  the repo already has real hooks there, and leaves a `core.hooksPath` it didn't set alone.
  `uninstall` only unsets the value it wrote.
- A `core.hooksPath` pointing at a missing directory is harmless — git finds no hooks and commits
  normally — so a leftover setting can never block a commit.

The bump rule is **once per unpushed series**: the hook compares the working version against the
version at the push base (`@{upstream}`, else `origin/HEAD`/`main`/`master`) and only bumps when
they match. So a run of commits before one push bumps once, `git commit --amend` doesn't bump
again, and a version you set by hand is respected. A repo with nothing pushed yet has had zero
pushes, so it gets zero bumps: a new resource settles at `0.1.0` and stays until its first push.
A version that isn't `N.N.N` is left alone rather than mangled.

`lib/package-meta.sh` next to the hook is deliberately standalone — it uses `sed` rather than
`yq` so a hook never depends on ppm's environment, and it stays out of `~/.local/lib/ppm/`
because its `meta_*` names would share a namespace with `packages.sh`'s.

## Moving a Package Between Repos

`anfs-dev/dev` ships `ppm move`, which relocates a package from one source repo to another. The files
live in the package at `packages/dev/home/.local/lib/ppm/move.sh`, stowed to
`~/.local/lib/ppm/move.sh` — a function named `move` there becomes `ppm move`, like `ppm user`
(the old seam; a new command is an `anfs-<name>`, see "The Command Line").

```
ppm move <repo/package> <target-repo>      # e.g. ppm move stack/rails user
  -f, --force   move despite uncommitted changes or a broken dependency
```

It unstows the package, moves the directory, stows it again from its new home, moves the install
tracker (`installed/<repo>/<pkg>.yml`, keeping its version, files and `installed_deps`), repoints
any `claims.yml` entry that names the package as claimant or owner, and commits both repos. The
source spec must be fully qualified: a bare name matches a layer in every repo.

- **Install hooks are not re-run.** The package's content is unchanged, only its path, so
  `pre_remove`/`post_install` would tear down services and rewrite generated config for nothing.
- **Restowing is not a plain `stow_package`.** `stow -D` only removed the links that point into
  *this* package dir, so re-stowing the whole directory would collide with the files a
  higher-priority layer owns. The tracker lists what this layer actually had, so `move` stows with
  the *complement* as the ignore list — which also leaves `ppm file protect`ed files alone. stow
  aborts the whole operation on the first conflict, so a failed stow rolls the move back; if the
  same conflict then fails the restore, it says to run `ppm install -f <pkg>`.
- **It refuses a move that would break a dependent**, unless `-f`. `_resolve_one` passes the
  depending layer's repo index as `min_index`, so a dependency only ever resolves to the same or a
  lower-priority repo — moving a package *up* in priority orphans anything below it that depends
  on it. `depends:` names a package, not a repo, so no dependent needs editing otherwise; there is
  deliberately no rename.
- **It refuses a repo with uncommitted changes**, unless `-f`. The commits are pathspec-limited to
  `packages/<pkg>`, so even under `-f` unrelated changes stay out of them, and the index is
  re-added afterwards because a partial commit leaves the pre-hook content staged for whatever the
  `pre-commit` hook rewrote (the version bump).
- **An existing package of that name in the target is refused outright**, `-f` included: `-f` must
  never overwrite package sources.

## The Round Trips and the Test Boxes

End to end, on a fresh Linux box:

```
packages/dev/tests/roundtrip [debian|fedora] [source...]
    # install.sh, ppm install stack/pi, anfs install acme (or the named sources), checks,
    # anfs implode, then $HOME diffed against its pre-install state
```

On macOS (Apple silicon), in a tart VM from `ppm vm build macos`'s vanilla base:

```
packages/dev/tests/roundtrip-macos [--all]
    # the same sequence on a Mac with no Homebrew or CLT: install.sh installs both. Checks the CLT,
    # /opt/homebrew, a cask (acme/acme-mac), the bash floor under /bin/bash, and with --all the
    # login-shell guard (stack/bash makes Homebrew's bash the login shell; implode --all refuses)
```

pcm cannot run containers in the macOS VM: a macOS guest gets no nested virtualization, so the
podman machine cannot start (the check is that pcm reports it and implode leaves nothing).

- `packages/dev/tests/harness` builds and runs the same boxes as `ppm container` (this source's
  `containers/anfs-test-<distro>/Containerfile`) with podman alone, so changing anfs — pcm
  included — can never break the thing that tests it. `--nested` runs the box privileged with
  `/dev/fuse`, which is what rootless podman inside it needs (pcm's containers really start in
  the round trip).
- `--all` holds `$HOME` to the stricter standard of `anfs implode --all`, and `--scratch` starts
  from a bare image so install.sh installs Homebrew itself (and `--all` must remove it).
- `packages/dev/tests/fixtures/acme` is a stand-in org source with every resource kind: a package depending on
  another source's, a container, a skill, and spaces that depend on each other.
- The round trip starts from a `bootstrap` snapshot (Homebrew, stow, yq, mise; passwordless sudo),
  built on first use, and tests a copy of the checkouts in `ROUNDTRIP_SRC_ROOT`: a job's directory
  under `anfs work run`, by default the directory the running anfs-dev checkout is in. Of core,
  stack and anfs-dev, one the root does not hold is the installed source (`roundtrip-sources`).
- Anything the diff reports is a tool writing outside its own directories, or an implode missing
  it. What implode keeps on purpose (Homebrew and its caches, mise's tools, podman's storage,
  GitHub's host keys, space contents) is listed in the script's `IGNORE_RE`.

`anfs-dev/dev` provides the throwaway machines to validate them on. `ppm container` (Debian, Fedora; the
boxes are pcm services, `containers/anfs-test-<distro>`) and
`ppm vm` (macOS on Apple silicon; the boxes are pmm machines, `machines/anfs-test-<target>`, from
the image of the same name on the tart backend) share one contract: two test users, `owner` (sudo with
a password) and `other` (none), and the host's source repos mounted **read-only at `/src/<alias>`**,
so a box tests the working tree rather than the pushed repos. `ppm user` makes a throwaway user on
the host instead, which is the cheapest way to exercise the non-owner Homebrew path.

Both harnesses link the mounted sources into `~/.local/share/anfs/sources` and list them in
`~/.config/anfs/user.list` *before* `install.sh` runs, which would otherwise clone anfs from GitHub
and test the pushed repo instead of the mount.

`ppm vm` differs from `ppm container` in four places, each forced by the platform rather than by
taste (the first two live in the image, `machines/images/anfs-test-macos/provision/10-provision.sh`; the
second two in the tart backend: pmm's `tart.sh`, and its machine and snapshot code over it):

- **`/src` comes from `/etc/synthetic.conf`**, realized at boot. tart mounts shares under
  `/Volumes/My Shared Files/<name>`, and `collect_repos` splits source lines on whitespace, so a
  path with spaces is unusable; `/` is read-only, so the link cannot be made directly.
- **A snapshot recreates the box rather than restarting it.** `tart clone` of a stopped VM captures
  its state correctly, but the restarted original has been observed to come back without those
  writes. The tart backend (`_tart_shutdown`) also shuts the guest down from inside and waits, because `tart stop` can
  return while writes are still buffered and the clone then catches an older APFS checkpoint.
- **Provisioning raises sudo's `timestamp_timeout`.** `_system_sudo` primes the cache then uses
  `sudo -n`, but macOS defaults to 5 minutes with per-tty tickets and there is no tty over ssh, so
  a cold run outlives it. The password stays — the prompt is part of what is being tested.
- **ssh re-parses the remote command line** where `podman exec` passes argv straight through, so
  multi-word values travel as env vars, not positional arguments.
