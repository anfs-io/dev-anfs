#!/usr/bin/env bats
# The dev package's entry points keep to the bash floor (core's lib/anfs/bash.sh) as core's own do
# (core: packages/anfs/tests/bash.bats): each sources bash.sh before anything else of lib/anfs.
# Run: bats packages/dev/tests </dev/null

@test "every entry point sources the floor before anything else of lib/anfs" {
  local dev="$BATS_TEST_DIRNAME/.." f first n=0
  for f in "$dev"/home/.local/bin/* "$dev"/home/.config/git/ppm-hooks/pre-commit; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    first=$(grep -n 'lib/anfs/\|\$ANFS_LIB/' "$f" | grep 'source ' | head -1)
    [[ "$first" == *bash.sh* ]] || { echo "$f: first lib/anfs source is: $first"; return 1; }
  done
  # anfs-hooks, anfs-work and the hook
  (( n >= 3 ))
}

@test "every entry point parses" {
  local f
  for f in "$BATS_TEST_DIRNAME"/../home/.local/bin/*; do
    bash -n "$f" || { echo "$f does not parse"; return 1; }
  done
}
