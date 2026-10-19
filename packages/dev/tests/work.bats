#!/usr/bin/env bats
# anfs work (home/.local/bin/anfs-work): jobs made of git worktrees, against sources that are
# clones of local bare repos, and a space's repository cloned by the real wsm (from the core
# checkout, helper.bash). No network.
# Run: bats packages/dev/tests </dev/null

load helper

setup() {
  dev_setup
  CORE_SRC=$(mksource core)
  STACK_SRC=$(mksource stack)
}

# The job's yml, one key
job_key() { yq -r ".$2" "$ANFS_WORK_HOME/$1/.job.yml"; }

# A source anfs-dev whose space.yml clones a repository docs, installed with wsm
docs_space() {
  command -v stow >/dev/null || skip "no stow"
  local dev url
  dev=$(mksource anfs-dev)
  url=$(mkbare docs)
  mkdir -p "$dev/spaces"
  printf 'repositories:\n  - url: %s\n' "$url" > "$dev/spaces/space.yml"
  git -C "$dev" add -A && git -C "$dev" commit -q -m spaces
  ln -s "$CORE/packages/wsm/home/.local/bin/wsm" "$HOME/.local/bin/wsm"
  "$HOME/.local/bin/wsm" install anfs-dev/ "$T/spaces" >/dev/null
  [ -d "$T/spaces/anfs-dev/docs/.git" ]
}

@test "new with two repos: two worktrees on branch <job>, .job.yml, number 1; the next gets 2" {
  run work new one core stack
  [ "$status" -eq 0 ]
  [[ "$output" == *"Job one (number 1)"* ]]
  for r in core stack; do
    [ "$(git -C "$ANFS_WORK_HOME/one/$r" symbolic-ref --short HEAD)" = one ]
    [ "$(git -C "$ANFS_WORK_HOME/one/$r" rev-parse --git-common-dir)" = "$SOURCES/$r/.git" ]
  done
  [ "$(job_key one number)" = 1 ]
  [ "$(job_key one branch)" = one ]
  [ "$(yq -r '[.repos[].name] | join(" ")' "$ANFS_WORK_HOME/one/.job.yml")" = "core stack" ]
  # the live clones stay on main
  [ "$(git -C "$CORE_SRC" symbolic-ref --short HEAD)" = main ]
  run work new two
  [ "$status" -eq 0 ]
  [ "$(job_key two number)" = 2 ]
  [ "$(yq -r '[.repos[].name] | join(" ")' "$ANFS_WORK_HOME/two/.job.yml")" = core ]
}

@test "after removing the first job, a third gets its number" {
  work new one core >/dev/null
  work new two core >/dev/null
  work remove one >/dev/null
  work new three core >/dev/null
  [ "$(job_key three number)" = 1 ]
}

@test "new: --from cuts the branch from REF; a job that exists is 73" {
  commit "$CORE_SRC"
  run work new old core --from main~1
  [ "$status" -eq 0 ]
  [ "$(git -C "$ANFS_WORK_HOME/old/core" rev-parse HEAD)" = "$(git -C "$CORE_SRC" rev-parse main~1)" ]
  run work new old core
  [ "$status" -eq 73 ]
}

@test "a repository of a space is found through space.yml and gets a worktree" {
  docs_space
  run work new d core docs
  [ "$status" -eq 0 ]
  [ "$(git -C "$ANFS_WORK_HOME/d/docs" symbolic-ref --short HEAD)" = d ]
  [ "$(git -C "$ANFS_WORK_HOME/d/docs" rev-parse --git-common-dir)" = "$T/spaces/anfs-dev/docs/.git" ]
}

@test "add: another repo joins a job on its branch; one already in it is left alone" {
  work new one core >/dev/null
  run work add one stack
  [ "$status" -eq 0 ]
  [ "$(git -C "$ANFS_WORK_HOME/one/stack" symbolic-ref --short HEAD)" = one ]
  [ "$(yq -r '[.repos[].name] | join(" ")' "$ANFS_WORK_HOME/one/.job.yml")" = "core stack" ]
  run work add one core
  [ "$status" -eq 0 ]
  [[ "$output" == *"core is in job one already"* ]]
  run work add nope core
  [ "$status" -eq 1 ]
}

@test "refused: a local-path source, an unknown repo, a job name that is not a branch name (64)" {
  mklocal mine
  run work new l mine
  [ "$status" -eq 1 ]
  [[ "$output" == *"local path"* ]]
  [ ! -e "$ANFS_WORK_HOME/l" ]
  run work new u nosuch
  [ "$status" -eq 1 ]
  [ ! -e "$ANFS_WORK_HOME/u" ]
  run work new "a/b" core
  [ "$status" -eq 64 ]
  run work new "bad..name" core
  [ "$status" -eq 64 ]
  run work new "-x" core
  [ "$status" -eq 64 ]
}

@test "a failure part way leaves nothing behind" {
  # stack's clone has the branch checked out already: its worktree cannot be made
  git -C "$STACK_SRC" checkout -q -b half
  run work new half core stack
  [ "$status" -eq 1 ]
  [ ! -e "$ANFS_WORK_HOME/half" ]
  run git -C "$CORE_SRC" worktree list
  [ "${#lines[@]}" -eq 1 ]
  ! git -C "$CORE_SRC" show-ref --verify -q refs/heads/half
}

@test "env: the isolation variables; two jobs' values differ" {
  work new one core >/dev/null
  work new two core >/dev/null
  run work env one
  [ "$status" -eq 0 ]
  local uid; uid=$(id -u)
  [[ "$output" == *"export ANFS_WORK_JOB=one"* ]]
  [[ "$output" == *"export ROUNDTRIP_SRC_ROOT=$ANFS_WORK_HOME/one"* ]]
  [[ "$output" == *"export PMM_SOCK_DIR=$ANFS_WORK_TMP/pmm-work-$uid-1"* ]]
  [[ "$output" == *"export PMM_SSH_PORT_BASE=2322"* ]]
  [[ "$output" == *"export TMPDIR=$ANFS_WORK_TMP/anfs-work-$uid-1"* ]]
  local one="$output"
  run work env two
  [[ "$output" == *"export PMM_SSH_PORT_BASE=2422"* ]]
  [[ "$output" == *"pmm-work-$uid-2"* && "$output" == *"anfs-work-$uid-2"* ]]
  [ "$output" != "$one" ]
  # what it prints is for eval
  eval "$(work env two)"
  [ "$ANFS_WORK_JOB" = two ] && [ "$PMM_SSH_PORT_BASE" = 2422 ]
}

@test "run: the command runs in the job's directory with the variables; its status is run's" {
  work new one core >/dev/null
  run work run one -- bash -c 'echo "$PWD $ANFS_WORK_JOB $PMM_SSH_PORT_BASE $TMPDIR"; [ -d "$TMPDIR" ]; exit 7'
  [ "$status" -eq 7 ]
  [ "$output" = "$ANFS_WORK_HOME/one one 2322 $ANFS_WORK_TMP/anfs-work-$(id -u)-1" ]
  run work run one
  [ "$status" -eq 64 ]
}

@test "path and show" {
  work new one core stack >/dev/null
  run work path one
  [ "$output" = "$ANFS_WORK_HOME/one" ]
  run work path one stack
  [ "$output" = "$ANFS_WORK_HOME/one/stack" ]
  run work path one docs
  [ "$status" -eq 1 ]
  commit "$ANFS_WORK_HOME/one/core"
  run work show one
  [ "$status" -eq 0 ]
  [[ "$output" == *"number 1"* ]]
  [[ "$output" == *"core"*"branch one, 1 ahead of main"* ]]
  [[ "$output" == *"PMM_SSH_PORT_BASE=2322"* ]]
  run work cd one
  [ "$status" -eq 1 ]
  [[ "$output" == *"shell function"* ]]
}

@test "list: clean, dirty, ahead, merged, and its --json keys" {
  work new c core >/dev/null
  work new d core >/dev/null
  work new a core stack >/dev/null
  work new m core >/dev/null
  echo x > "$ANFS_WORK_HOME/d/core/new-file"
  commit "$ANFS_WORK_HOME/a/core"
  commit "$ANFS_WORK_HOME/a/stack"
  commit "$ANFS_WORK_HOME/m/core"
  git -C "$CORE_SRC" merge -q --no-edit m
  run work list
  [ "$status" -eq 0 ]
  [[ "$output" == *"c"$'\t'"c"$'\t'"core"$'\t'"clean"$'\t'"1"* ]]
  [[ "$output" == *"d"$'\t'"d"$'\t'"core"$'\t'"dirty"$'\t'"2"* ]]
  [[ "$output" == *"a"$'\t'"a"$'\t'"core stack"$'\t'"ahead 2"$'\t'"3"* ]]
  [[ "$output" == *"m"$'\t'"m"$'\t'"core"$'\t'"merged"$'\t'"4"* ]]
  run env -u ANFS_TABLE "$WORK" --json list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | yq -p json -r '.[] | select(.job == "a") | .repos | join(",")')" = "core,stack" ]
  [ "$(printf '%s' "$output" | yq -p json -r '.[0] | keys | sort | join(" ")')" = "branch job number repos state" ]
}

@test "remove: refuses dirty and unmerged; removes a merged job's worktrees, branches and directory" {
  work new d core >/dev/null
  echo x > "$ANFS_WORK_HOME/d/core/new-file"
  run work remove d
  [ "$status" -eq 1 ]
  [[ "$output" == *"core: uncommitted changes"* ]]
  [ -d "$ANFS_WORK_HOME/d/core" ]

  work new u core stack >/dev/null
  commit "$ANFS_WORK_HOME/u/stack"
  run work remove u
  [ "$status" -eq 1 ]
  [[ "$output" == *"stack: 1 commits not in main"* ]]

  work new m core stack >/dev/null
  commit "$ANFS_WORK_HOME/m/core"
  git -C "$CORE_SRC" merge -q --no-edit m
  run work remove m
  [ "$status" -eq 0 ]
  [ ! -e "$ANFS_WORK_HOME/m" ]
  for r in "$CORE_SRC" "$STACK_SRC"; do
    ! git -C "$r" show-ref --verify -q refs/heads/m
    ! git -C "$r" worktree list | grep -q "/m/"
  done
}

@test "remove -f: asks, says what would be lost, then removes" {
  work new u core >/dev/null
  commit "$ANFS_WORK_HOME/u/core" lost-file
  # no terminal and no -y: it asks for -y, nothing done
  run work remove -f u </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"change lost-file"* ]]
  [[ "$output" == *"pass -y"* ]]
  [ -d "$ANFS_WORK_HOME/u/core" ]
  run work remove -f -y u
  [ "$status" -eq 0 ]
  [ ! -e "$ANFS_WORK_HOME/u" ]
  ! git -C "$CORE_SRC" show-ref --verify -q refs/heads/u
  run git -C "$CORE_SRC" worktree list
  [ "${#lines[@]}" -eq 1 ]
}

@test "the git hooks are wired into a source's worktree when anfs hooks' directory exists" {
  mkdir -p "$XDG_CONFIG_HOME/git/ppm-hooks"
  work new h core >/dev/null
  [ "$(git -C "$ANFS_WORK_HOME/h/core" config --get core.hooksPath)" = "$XDG_CONFIG_HOME/git/ppm-hooks" ]
}

@test "completion: jobs from the file names" {
  work new one core >/dev/null
  run work __complete show ""
  [ "$output" = one ]
  run work __complete new j ""
  [[ "$output" == *core* && "$output" == *stack* ]]
}

@test "through anfs: anfs work is anfs-work, its help is listed, and the shell function's cd" {
  ln -s "$CORE/packages/anfs/home/.local/bin/anfs" "$HOME/.local/bin/anfs"
  ln -s "$WORK" "$HOME/.local/bin/anfs-work"
  local anfs="$HOME/.local/bin/anfs"
  run "$anfs" work new one core
  [ "$status" -eq 0 ]
  run "$anfs" work path one core
  [ "$output" = "$ANFS_WORK_HOME/one/core" ]
  run "$anfs" help
  [[ "$output" == *$'From packages:\n  work'* ]]
  run "$anfs" work bogus
  [ "$status" -eq 64 ]
  [[ "$output" == *"anfs work: unknown command 'bogus'"* ]]
  # anfs work cd, through core's sh/anfs.sh
  run bash -c 'PATH="$HOME/.local/bin:$PATH"; . "$1"; anfs work cd one core && pwd' _ "$CORE/packages/anfs/home/.config/sh/anfs.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$ANFS_WORK_HOME/one/core" ]
}
