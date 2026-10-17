#!/usr/bin/env bash
# Reading and writing package.yml, for the ppm git hooks.
#
# Deliberately standalone: it uses sed rather than yq so a hook never depends on ppm's own
# environment, and it stays out of ~/.local/lib/ppm/ because its meta_* names share a
# namespace with the meta_* functions in ppm's packages.sh.

# Read a single key from a package's package.yml; empty if the file or key is absent
# Usage: meta_read <package_dir> <key>
meta_read() {
  local pkg_dir="$1" key="$2"
  local meta_file="$pkg_dir/package.yml"
  [[ -f "$meta_file" ]] || return 0
  sed -n "s/^${key}: *//p" "$meta_file" | head -n 1
}

# Write a key-value pair, creating package.yml if needed
# Usage: meta_write <package_dir> <key> <value>
meta_write() {
  local pkg_dir="$1" key="$2" value="$3"
  local meta_file="$pkg_dir/package.yml"

  if [[ ! -f "$meta_file" ]]; then
    echo "${key}: ${value}" > "$meta_file"
  elif grep -q "^${key}:" "$meta_file"; then
    # BSD sed needs an explicit empty suffix for -i, GNU sed must not get one
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s/^${key}: .*/${key}: ${value}/" "$meta_file"
    else
      sed -i "s/^${key}: .*/${key}: ${value}/" "$meta_file"
    fi
  else
    echo "${key}: ${value}" >> "$meta_file"
  fi
}

# Bump the patch version and echo the new value. A version that isn't plain semver is left
# alone (echoes nothing) rather than mangled.
# Usage: meta_bump_patch <package_dir>
meta_bump_patch() {
  local pkg_dir="$1" version major minor patch
  version=$(meta_read "$pkg_dir" version)

  if [[ -z "$version" ]]; then
    meta_write "$pkg_dir" version 0.1.0
    echo 0.1.0
    return 0
  fi

  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0

  IFS='.' read -r major minor patch <<< "$version"
  # 10# forces base 10: bash reads a zero-padded component like 09 as octal and dies on it
  local new_version="${major}.${minor}.$((10#$patch + 1))"
  meta_write "$pkg_dir" version "$new_version"
  echo "$new_version"
}

# Create a minimal package.yml for a package that has none
# Usage: meta_bootstrap <package_dir>
meta_bootstrap() {
  local pkg_dir="$1"
  [[ -f "$pkg_dir/package.yml" ]] && return 0
  echo "version: 0.1.0" > "$pkg_dir/package.yml"
}

# The commit the next push would build on: this branch's upstream, else the remote's default
# branch. Echoes nothing when the repo has no remote tracking at all, which the caller reads as
# "nothing has been pushed from here yet".
meta_push_base() {
  local ref
  for ref in '@{upstream}' origin/HEAD origin/main origin/master; do
    if git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done
  return 0
}

# A package's version as of <ref>; empty if the package or its package.yml isn't there yet
# Usage: meta_version_at <ref> <package_name>
meta_version_at() {
  local ref="$1" pkg_name="$2" yml
  yml=$(git show "${ref}:packages/${pkg_name}/package.yml" 2>/dev/null) || return 0
  printf '%s\n' "$yml" | sed -n 's/^version: *//p' | head -n 1
}
