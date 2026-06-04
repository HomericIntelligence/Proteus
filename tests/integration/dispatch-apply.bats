#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin"
  export PATH="$TMP/bin:$PATH"
  export CURL_LOG="$TMP/curl.log"
  cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${CURL_LOG}"
# Replay any --data payload last so the test can grep it deterministically.
for ((i=1;i<=$#;i++)); do
  [[ "${!i}" == "--data" ]] && { j=$((i+1)); echo "DATA:${!j}" >> "${CURL_LOG}"; }
done
printf '%s\n%s' "${CURL_BODY:-}" "${CURL_HTTP:-204}"
EOF
  chmod +x "$TMP/bin/curl"
}

teardown() { rm -rf "$TMP"; }

@test "fails when GITHUB_TOKEN missing" {
  unset GITHUB_TOKEN
  run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITHUB_TOKEN is required"* ]]
}

@test "204 → success, exit 0" {
  GITHUB_TOKEN=t CURL_HTTP=204 run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 0 ]
  grep -q 'DATA:.*"event_type":"agamemnon-apply"' "$CURL_LOG"
  grep -q 'DATA:.*"host":"hermes"' "$CURL_LOG"
}

@test "non-204 → exit 1, body printed to stderr" {
  GITHUB_TOKEN=t CURL_HTTP=422 CURL_BODY='{"message":"bad ref"}' run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dispatch failed with HTTP 422"* ]]
  [[ "$output" == *"bad ref"* ]]
}

@test "HOST positional arg overrides HOST env" {
  GITHUB_TOKEN=t HOST=athena run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 0 ]
  grep -q 'DATA:.*"host":"hermes"' "$CURL_LOG"
}

@test "MYRMIDONS_REPO override is used in URL" {
  GITHUB_TOKEN=t MYRMIDONS_REPO=org/repo run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 0 ]
  grep -q 'api.github.com/repos/org/repo/dispatches' "$CURL_LOG"
}
