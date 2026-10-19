# dev

# `anfs hooks` is this package's executable (home/.local/bin/anfs-hooks). Run from the package
# rather than from ~/.local/bin, so the hooks do not depend on where the install put the link.
_dev_hooks() {
  "$(dirname "${BASH_SOURCE[0]}")/home/.local/bin/anfs-hooks" "$@"
}

# Wire the git hooks into the package repos. Hooks are not carried by git clone, so this runs on
# install rather than being part of a repo's contents; re-run `anfs hooks install` after
# `anfs src add`. user.list repos are opt-in (`anfs hooks install --all`).
post_install() {
  echo "Wiring git hooks into the system.list repos:"
  _dev_hooks install || true
}

# Unset core.hooksPath again, but only in repos where it was set to these hooks. The hook files
# are already unstowed by now; a leftover hooksPath pointing at a missing directory is harmless
# to git (commits just find no hooks), but leaving it behind would be untidy.
post_remove() {
  echo "Removing git hooks from the package repos:"
  _dev_hooks uninstall --all || true
}
