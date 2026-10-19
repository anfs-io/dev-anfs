#!/usr/bin/env bash
# Reading and writing resource manifests (package.yml, container.yml, ...), for the ppm git hooks.
#
# Deliberately standalone: it uses sed rather than yq so a hook never depends on ppm's own
# environment, and it stays out of ~/.local/lib/ppm/ because its meta_* names share a
# namespace with the meta_* functions in ppm's packages.sh.

# Every kind of resource directory and the manifest it holds: "<parent dir>:<manifest>". A
# resource is a directory right under <parent dir>; a new kind is one line. The more specific
# parent comes first: machines/images/<i> is an image, not a machine named images.
META_KINDS=(
  "packages:package.yml"
  "containers:container.yml"
  "machines/images:image.yml"
  "machines/networks:network.yml"
  "machines:machine.yml"
  "stacks:stack.yml"
)

# The resource directory a repo path belongs to and its manifest, as "<dir> <manifest>"
# (machines/images/z/provision/10.sh -> "machines/images/z image.yml"); nothing for a path that
# is in no resource (README.md, containers/README.md, machines/profiles.yml)
# Usage: meta_resource <path>
meta_resource() {
  local path="$1" kind parent rest name
  for kind in "${META_KINDS[@]}"; do
    parent="${kind%%:*}"
    [[ "$path" == "$parent"/* ]] || continue
    rest="${path#"$parent"/}"
    [[ "$rest" == */* ]] || return 0          # a file in the parent itself
    name="${rest%%/*}"
    # machines/images/... belongs to the images line above, never to machines
    if [[ "$parent" == machines ]]; then
      case "$name" in images|networks) return 0 ;; esac
    fi
    echo "$parent/$name ${kind#*:}"
    return 0
  done
}

# The resource directories of the paths on stdin, one "<dir> <manifest>" per line, sorted, unique
meta_resources() {
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] && meta_resource "$path"
  done | sort -u
}

# Read a single key from a manifest; empty if the file or key is absent
# Usage: meta_read <manifest_file> <key>
meta_read() {
  local meta_file="$1" key="$2"
  [[ -f "$meta_file" ]] || return 0
  sed -n "s/^${key}: *//p" "$meta_file" | head -n 1
}

# Write a key-value pair, creating the manifest if needed. A key that is not there yet goes
# first, after the file's opening comment.
# Usage: meta_write <manifest_file> <key> <value>
meta_write() {
  local meta_file="$1" key="$2" value="$3"

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
    awk -v line="${key}: ${value}" '!done && !/^#/ { print line; done = 1 } { print } END { if (!done) print line }' \
      "$meta_file" > "$meta_file.tmp" && cat "$meta_file.tmp" > "$meta_file" && rm -f "$meta_file.tmp"
  fi
}

# Bump the patch version and echo the new value; a manifest with no version gets 0.1.0. A
# version that isn't plain semver is left alone (echoes nothing) rather than mangled.
# Usage: meta_bump_patch <manifest_file>
meta_bump_patch() {
  local meta_file="$1" version major minor patch
  version=$(meta_read "$meta_file" version)

  if [[ -z "$version" ]]; then
    meta_write "$meta_file" version 0.1.0
    echo 0.1.0
    return 0
  fi

  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0

  IFS='.' read -r major minor patch <<< "$version"
  # 10# forces base 10: bash reads a zero-padded component like 09 as octal and dies on it
  local new_version="${major}.${minor}.$((10#$patch + 1))"
  meta_write "$meta_file" version "$new_version"
  echo "$new_version"
}

# Create a minimal manifest for a resource that has none
# Usage: meta_bootstrap <manifest_file>
meta_bootstrap() {
  local meta_file="$1"
  [[ -f "$meta_file" ]] && return 0
  echo "version: 0.1.0" > "$meta_file"
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

# A manifest's version as of <ref>; empty if the resource or its manifest isn't there yet
# Usage: meta_version_at <ref> <repo-relative manifest path>
meta_version_at() {
  local ref="$1" path="$2" yml
  yml=$(git show "${ref}:${path}" 2>/dev/null) || return 0
  printf '%s\n' "$yml" | sed -n 's/^version: *//p' | head -n 1
}
