# Shared setup for the dev package's suites: an isolated HOME whose sources are clones of local
# bare repos (file://, no network), and the core the commands run against.
#
# The dev package's commands source lib/anfs from ~/.local/lib/anfs, as every tool does. In the
# test HOME that is a link to a core checkout: $ANFS_CORE_DIR when set, else the core beside this
# one (a job's layout: ~/work/<job>/{core,anfs-dev}), else the installed source.

dev_core_dir() {
  local here="$BATS_TEST_DIRNAME/../../.." d
  for d in "${ANFS_CORE_DIR:-}" "$here/../core" "${XDG_DATA_HOME:-$HOME/.local/share}/anfs/sources/core"; do
    [[ -n "$d" && -f "$d/packages/anfs/home/.local/lib/anfs/cli.sh" ]] && { (cd "$d" && pwd -P); return 0; }
  done
  return 1
}

dev_setup() {
  CORE=$(dev_core_dir) || skip "no core checkout (set ANFS_CORE_DIR)"
  DEV="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  T=$(cd "$BATS_TEST_TMPDIR" && pwd -P)
  export HOME="$T/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  unset ANFS_CONFIG_HOME ANFS_DATA_HOME ANFS_CACHE_HOME ANFS_STATE_HOME ANFS_JSON ANFS_ISO_HOME
  unset WSM_CONFIG_HOME WSM_DATA_HOME WSM_STATE_HOME WSM_CACHE_HOME WSM_SPACES_HOME
  unset ANFS_WORK_JOB ANFS_WORK_NUMBER ROUNDTRIP_SRC_ROOT PMM_SOCK_DIR PMM_SSH_PORT_BASE
  export ANFS_LOG=off ANFS_TABLE=tsv GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=t@t
  export ANFS_WORK_HOME="$T/work" ANFS_WORK_TMP="$T/tmp"
  SOURCES="$HOME/.local/share/anfs/sources"
  mkdir -p "$HOME/.local/lib" "$HOME/.local/bin" "$HOME/.config/anfs" "$SOURCES" "$T/bare" "$T/seed"
  ln -s "$CORE/packages/anfs/home/.local/lib/anfs" "$HOME/.local/lib/anfs"
  : > "$HOME/.config/anfs/user.list"
  : > "$HOME/.config/anfs/system.list"
  WORK="$DEV/home/.local/bin/anfs-work"
  HOOKS="$DEV/home/.local/bin/anfs-hooks"
}

work() { "$WORK" "$@"; }

# A bare repo <name> with one commit on main, cloneable over file://. Prints its URL.
mkbare() {
  local name="$1" seed="$T/seed/$1"
  git init -q -b main "$seed"
  echo "$name" > "$seed/README"
  git -C "$seed" add -A
  git -C "$seed" commit -q -m "init $name"
  git clone -q --bare "$seed" "$T/bare/$name.git"
  printf 'file://%s\n' "$T/bare/$name.git"
}

# A source <alias>: a bare repo, cloned into the sources dir and listed in user.list, as `anfs src
# add` leaves one. Prints the clone's path.
mksource() {
  local alias="$1" url
  url=$(mkbare "$alias")
  git clone -q "$url" "$SOURCES/$alias"
  printf '%s  %s\n' "$url" "$alias" >> "$HOME/.config/anfs/user.list"
  printf '%s\n' "$SOURCES/$alias"
}

# A source that is a local path: linked, not cloned
mklocal() {
  local alias="$1" dir="$T/local/$1"
  mkdir -p "$dir"
  git init -q -b main "$dir"
  ln -s "$dir" "$SOURCES/$alias"
  printf '%s  %s\n' "$dir" "$alias" >> "$HOME/.config/anfs/user.list"
}

# commit <dir> [file]: one more commit in a worktree or clone
commit() {
  local f="${2:-change}"
  echo "$RANDOM" >> "$1/$f"
  git -C "$1" add -A
  git -C "$1" commit -q -m "change $f"
}
