#!/usr/bin/env bats
# anfs hooks (home/.local/bin/anfs-hooks): core.hooksPath in the sources' repos, set and unset
# only where it pointed at the stowed hooks.
# Run: bats packages/dev/tests </dev/null

load helper

setup() {
  dev_setup
  mksource core >/dev/null
  mksource mine >/dev/null
  # core in system.list, mine only in user.list
  grep ' core$' "$HOME/.config/anfs/user.list" > "$HOME/.config/anfs/system.list"
  grep -v ' core$' "$HOME/.config/anfs/user.list" > "$T/u" && mv "$T/u" "$HOME/.config/anfs/user.list"
  HOOKDIR="$XDG_CONFIG_HOME/git/ppm-hooks"
  mkdir -p "$HOOKDIR"
}

hooks() { "$HOOKS" "$@"; }
hookspath() { git -C "$SOURCES/$1" config --local --get core.hooksPath || true; }

@test "install: the system.list repos, then --all adds yours; status says so" {
  run hooks install
  [ "$status" -eq 0 ]
  [ "$(hookspath core)" = "$HOOKDIR" ]
  [ -z "$(hookspath mine)" ]
  run hooks install --all
  [ "$(hookspath mine)" = "$HOOKDIR" ]
  run hooks status --all
  [[ "$output" == *"core"*"installed"* && "$output" == *"mine"*"installed"* ]]
}

@test "a hooksPath of the repo's own is left alone, by install and by uninstall" {
  git -C "$SOURCES/core" config core.hooksPath /elsewhere
  run hooks install core mine
  [[ "$output" == *"leaving its own core.hooksPath alone"* ]]
  run hooks uninstall core mine
  [ "$(hookspath core)" = /elsewhere ]
  [ -z "$(hookspath mine)" ]
}

@test "its messages and usage read as anfs hooks" {
  run hooks bogus
  [ "$status" -eq 64 ]
  [[ "$output" == *"anfs hooks: unknown command 'bogus'"* ]]
  run hooks --help
  [[ "$output" == "Usage: anfs hooks <command>"* ]]
}

# The dev package installed from a user.list source: its stowed hook links into that source
devsource() {
  local src
  src=$(mksource devsrc)
  mkdir -p "$src/packages/dev/home/.config/git/ppm-hooks"
  echo '#!/bin/sh' > "$src/packages/dev/home/.config/git/ppm-hooks/pre-commit"
  if [[ "${1:-}" == folded ]]; then
    rmdir "$HOOKDIR"
    ln -s "../../.local/share/anfs/sources/devsrc/packages/dev/home/.config/git/ppm-hooks" "$HOOKDIR"
  else
    ln -s "$src/packages/dev/home/.config/git/ppm-hooks/pre-commit" "$HOOKDIR/pre-commit"
  fi
}

@test "install with no names: the dev package's own source too, not the rest of user.list" {
  devsource
  run hooks install
  [ "$status" -eq 0 ]
  [ "$(hookspath core)" = "$HOOKDIR" ]
  [ "$(hookspath devsrc)" = "$HOOKDIR" ]
  [ -z "$(hookspath mine)" ]
  run hooks status
  [[ "$output" == *"devsrc"*"installed"* && "$output" != *"mine"* ]]
  run hooks install --all
  [ "$(hookspath mine)" = "$HOOKDIR" ]
}

@test "the dev package's source is found when stow folded the hook directory into a link" {
  devsource folded
  run hooks install
  [ "$status" -eq 0 ]
  [ "$(hookspath devsrc)" = "$HOOKDIR" ]
  [ -z "$(hookspath mine)" ]
}

@test "hooks stowed from outside the sources wire only system.list" {
  mkdir -p "$T/elsewhere/packages/dev/home/.config/git/ppm-hooks"
  echo '#!/bin/sh' > "$T/elsewhere/packages/dev/home/.config/git/ppm-hooks/pre-commit"
  ln -s "$T/elsewhere/packages/dev/home/.config/git/ppm-hooks/pre-commit" "$HOOKDIR/pre-commit"
  run hooks install
  [ "$(hookspath core)" = "$HOOKDIR" ]
  [ -z "$(hookspath mine)" ]
}
