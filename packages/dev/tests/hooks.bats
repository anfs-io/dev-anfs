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

# --- the pre-commit hook: every resource's manifest ----------------------------------------
# A clone of a bare repo with one push, and its core.hooksPath at this checkout's hooks (never
# the stowed ones): the commits below run the hook as a person's would.

PRECOMMIT_DIR() { echo "$DEV/home/.config/git/ppm-hooks"; }

# A repo at $T/r whose main is pushed, with a package, a container, a stack and an image, each
# at 0.1.0, plus files that are in no resource
hookrepo() {
  local url
  url=$(mkbare r)
  git clone -q "$url" "$T/r"
  R="$T/r"
  mkdir -p "$R/packages/p" "$R/containers/x" "$R/stacks/y" "$R/machines/images/z" "$R/machines/m"
  echo 'version: 0.1.0' > "$R/packages/p/package.yml"
  echo 'services: {}' > "$R/containers/x/compose.yml"
  echo 'version: 0.1.0' > "$R/containers/x/container.yml"
  echo 'version: 0.1.0' > "$R/stacks/y/stack.yml"
  echo y > "$R/stacks/y/README.md"
  printf '# an image\nversion: 0.1.0\ndescription: z\n' > "$R/machines/images/z/image.yml"
  printf '# a machine\nimage: z\n' > "$R/machines/m/machine.yml"
  echo notes > "$R/containers/README.md"
  echo 'default: {}' > "$R/machines/profiles.yml"
  git -C "$R" add -A
  git -C "$R" commit -q -m resources
  git -C "$R" push -q origin main
  git -C "$R" config core.hooksPath "$(PRECOMMIT_DIR)"
}

version_of() { sed -n 's/^version: *//p' "$R/$1"; }
in_head() { git -C "$R" show "HEAD:$1" | sed -n 's/^version: *//p'; }

@test "pre-commit: a change in containers/x, stacks/y and machines/images/z bumps that manifest, once per push" {
  hookrepo
  echo a >> "$R/containers/x/compose.yml"
  echo b >> "$R/stacks/y/README.md"
  mkdir -p "$R/machines/images/z/provision"; echo c > "$R/machines/images/z/provision/10.sh"
  git -C "$R" add -A
  run git -C "$R" commit -q -m change
  [ "$status" -eq 0 ]
  [ "$(in_head containers/x/container.yml)" = 0.1.1 ]
  [ "$(in_head stacks/y/stack.yml)" = 0.1.1 ]
  [ "$(in_head machines/images/z/image.yml)" = 0.1.1 ]
  [ "$(in_head packages/p/package.yml)" = 0.1.0 ]
  [[ "$output" == *"containers/x — bumped to 0.1.1"* ]]
  # Not pushed since: the next commit leaves them alone
  echo d >> "$R/containers/x/compose.yml"
  git -C "$R" add -A
  run git -C "$R" commit -q -m again
  [ "$(in_head containers/x/container.yml)" = 0.1.1 ]
  [[ "$output" == *"already 0.1.1 since 0.1.0 was pushed"* ]]
}

@test "pre-commit: packages are bumped as before" {
  hookrepo
  echo x > "$R/packages/p/README.md"
  git -C "$R" add -A
  git -C "$R" commit -q -m pkg
  [ "$(in_head packages/p/package.yml)" = 0.1.1 ]
}

@test "pre-commit: a manifest deleted on its own fails the commit" {
  hookrepo
  git -C "$R" rm -q containers/x/container.yml
  run git -C "$R" commit -q -m drop
  [ "$status" -ne 0 ]
  [[ "$output" == *"every resource needs its manifest"*"containers/x/container.yml"* ]]
  git -C "$R" reset -q --hard
  git -C "$R" rm -q stacks/y/stack.yml
  run git -C "$R" commit -q -m drop
  [ "$status" -ne 0 ]
  [[ "$output" == *"stacks/y/stack.yml"* ]]
}

@test "pre-commit: a resource that predates its manifest fails any commit to a resource until it has one" {
  hookrepo
  # As if made before the hook: a container with no container.yml, committed without the hook
  mkdir -p "$R/containers/old"; echo 'services: {}' > "$R/containers/old/compose.yml"
  git -C "$R" add -A
  git -C "$R" -c core.hooksPath=/dev/null commit -q -m old
  echo e >> "$R/stacks/y/README.md"
  git -C "$R" add -A
  run git -C "$R" commit -q -m other
  [ "$status" -ne 0 ]
  [[ "$output" == *"containers/old/container.yml"* ]]
}

@test "pre-commit: a new resource gets its manifest at 0.1.0; one without a version gets one" {
  hookrepo
  mkdir -p "$R/containers/new" "$R/machines/networks/n"
  echo 'services: {}' > "$R/containers/new/compose.yml"
  echo x > "$R/machines/networks/n/notes"
  echo 'cpus: 2' >> "$R/machines/m/machine.yml"
  git -C "$R" add -A
  run git -C "$R" commit -q -m new
  [ "$status" -eq 0 ]
  [ "$(in_head containers/new/container.yml)" = 0.1.0 ]
  [ "$(in_head machines/networks/n/network.yml)" = 0.1.0 ]
  [ "$(in_head machines/m/machine.yml)" = 0.1.0 ]
  # after the file's opening comment
  [ "$(git -C "$R" show HEAD:machines/m/machine.yml | sed -n 2p)" = "version: 0.1.0" ]
}

@test "pre-commit: files in no resource are left alone; machines/images is not a machine" {
  hookrepo
  echo more >> "$R/containers/README.md"
  echo 'x: {}' >> "$R/machines/profiles.yml"
  git -C "$R" add -A
  run git -C "$R" commit -q -m docs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$R/machines/images/machine.yml" ]
  [ ! -e "$R/containers/container.yml" ]
}

@test "pre-commit: a manifest that is not a YAML map fails (when yq is there)" {
  command -v yq >/dev/null || skip "no yq"
  hookrepo
  echo '- a list' > "$R/stacks/y/stack.yml"
  git -C "$R" add -A
  run git -C "$R" commit -q -m bad
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid manifest"*"stacks/y/stack.yml (a YAML map)"* ]]
}
