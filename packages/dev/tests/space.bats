#!/usr/bin/env bats
# anfs-dev's space.yml as anfsd reads it (agents/02b): the two dispatch rules and their prompt,
# through `anfsd rules` and `anfsd match` (anfsd's one parser), never a run. The anfsd is built from
# the runtime beside this checkout (a job's layout: ~/work/<job>/{anfs-dev,runtime}), or $ANFSD;
# skipped when neither is there. claude and anfs-work are stubs on a PATH of their own: nothing is
# ever started, they only have to be found.
# Run: bats packages/dev/tests/space.bats </dev/null

unset ANFS_WORK ANFS_WORK_SAID  # a person's ANFS_WORK never reaches a test (lib/anfs/work.sh)

setup_file() {
  local rt
  rt="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)/runtime/go"
  if [[ -z "${ANFSD:-}" && -f "$rt/go.mod" ]] && command -v go >/dev/null; then
    export ANFSD="$BATS_FILE_TMPDIR/anfsd"
    (cd "$rt" && go build -o "$ANFSD" ./cmd/anfsd) || ANFSD=""
  fi
}

setup() {
  [[ -n "${ANFSD:-}" && -x "$ANFSD" ]] || skip "no anfsd (a runtime checkout beside this one, or ANFSD=<binary>)"
  T="$BATS_TEST_TMPDIR"
  SPACE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/spaces/space.yml"
  mkdir -p "$T/home" "$T/bin"
  for b in claude anfs-work; do printf '#!/bin/sh\nexit 1\n' > "$T/bin/$b"; chmod +x "$T/bin/$b"; done
}

anfsd() { run env -i HOME="$T/home" USER=tester PATH="$T/bin:/usr/bin:/bin" "$ANFSD" "$@"; }

@test "the two rules are valid and committed disabled" {
  anfsd rules --json "$SPACE"
  [ "$status" -eq 0 ]
  [ "$(yq -p json -r '[.[] | .rule + "=" + .status] | join(" ")' <<< "$output")" = "fix-core-report=disabled fix-stack-report=disabled" ]
  [ "$(yq -p json -r '[.[] | .space_id + " " + .as + " " + .harness + " " + .job] | unique | .[]' <<< "$output")" = "tkj76y3nfx maintainer claude fix-{{subject}}" ]
}

@test "enabled (the enabled: false lines gone), both are ok" {
  mkdir -p "$T/sp/prompts"
  sed 's/ enabled: false,//' "$SPACE" > "$T/sp/space.yml"
  cp "$(dirname "$SPACE")/prompts/report-filed.md" "$T/sp/prompts/"
  anfsd rules --json "$T/sp/space.yml"
  [ "$status" -eq 0 ]
  [ "$(yq -p json -r '[.[] | .rule + "=" + .status] | join(" ")' <<< "$output")" = "fix-core-report=ok fix-stack-report=ok" ]
}

@test "match: a core report would start a core job; a stack one a stack job; none without a package" {
  anfsd match --json --type report.filed --space tkj76y3nfx --subject r-20261023-7 --data to=file --data package=core/pcm \
    --data title="pcm logs" "$SPACE"
  [ "$status" -eq 0 ]
  [ "$(yq -p json -r '.[0].result + " " + .[0].job + " " + (.[0].repos | join(",")) + " " + .[1].result' <<< "$output")" = \
    "disabled fix-r-20261023-7 core no match" ]
  [[ "$(yq -p json -r '.[0].prompt' <<< "$output")" == 'A bug report, r-20261023-7, was filed in anfs-dev: "pcm logs" (core/pcm).'* ]]
  anfsd match --json --type report.filed --space tkj76y3nfx --subject r-1 --data to=file --data package=stack/go "$SPACE"
  [ "$(yq -p json -r '.[0].result + " / " + .[1].result + " " + .[1].job' <<< "$output")" = "no match / disabled fix-r-1" ]
  anfsd match --json --type report.filed --space tkj76y3nfx --subject r-2 --data to=file "$SPACE"
  [ "$(yq -p json -r '[.[] | .result] | join(" ")' <<< "$output")" = "no match no match" ]
  # nothing written in the temp HOME
  [ ! -e "$T/home/.local/state/anfsd" ]
}
