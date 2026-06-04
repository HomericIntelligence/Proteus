#!/usr/bin/env bats

setup() {
  [ "${JUST_RUN_E2E:-0}" = "1" ] || skip "set JUST_RUN_E2E=1 to run e2e"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/ctx"
  printf 'FROM alpine:3.20\nRUN echo hi > /hi\n' > "$TMP/ctx/Dockerfile"
}

teardown() { rm -rf "$TMP"; }

@test "dagger call build returns a non-empty digest (publish=false)" {
  [ "${JUST_RUN_E2E:-0}" = "1" ] || skip "set JUST_RUN_E2E=1 to run e2e"
  run dagger call -m dagger build --context "$TMP/ctx" --name e2etest --tag t --publish=false
  [ "$status" -eq 0 ]
  [[ -n "$output" ]]
}

@test "dagger call lint-shellcheck succeeds on repo scripts" {
  [ "${JUST_RUN_E2E:-0}" = "1" ] || skip "set JUST_RUN_E2E=1 to run e2e"
  run dagger call -m dagger lint-shellcheck --source .
  [ "$status" -eq 0 ]
}
