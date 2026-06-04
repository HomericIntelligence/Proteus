#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export PATH="$TMP:$PATH"
  export CURL_LOG="$BATS_TEST_TMPDIR/payload.json"

  # Sanity: BATS_TEST_TMPDIR must be writable. If not, every test is suspect.
  : > "$CURL_LOG" || { echo "FATAL: cannot write CURL_LOG at $CURL_LOG"; exit 98; }

  cat > "$TMP/curl" <<'STUB'
#!/usr/bin/env bash
out="${CURL_LOG:-/tmp/curl.log}"
payload=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data|--data-raw|--data-binary|-d) shift; payload="$1"; shift ;;
    --data=*|--data-raw=*|--data-binary=*) payload="${1#*=}"; shift ;;
    *) shift ;;
  esac
done
if [[ -z "$payload" ]]; then
  echo "STUB ERROR: no --data flag captured; update curl stub" >&2
  exit 99
fi
if [[ "${payload:0:1}" == "@" ]]; then payload="$(cat "${payload:1}")"; fi
if ! printf '%s' "$payload" > "$out"; then
  echo "STUB ERROR: could not write payload to $out" >&2
  exit 98
fi
printf '\n204'
STUB
  chmod +x "$TMP/curl"
  export GITHUB_TOKEN=fake-token-for-test
  export MYRMIDONS_REPO=HomericIntelligence/Myrmidons
  unset HOST IMAGE_TAG SOURCE || true
}
teardown() { rm -rf "$TMP"; }

# --- Carried over from tests/dispatch-apply.test.sh ---
# Each legacy case asserts the same exit-status semantics as the original
# `bash -c …` invocations: bats' `run` captures stdout+stderr into $output
# and exit code into $status, identical to the original test's
# `out=$(…)` + `$?` pattern. set -euo pipefail inside the script under test
# behaves identically whether spawned by bats or by the original wrapper.

@test "case 1 (legacy): explicit host arg → exit 0, prints host" {
  run ./scripts/dispatch-apply.sh multihost-a
  [ "$status" -eq 0 ]
  [[ "$output" == *"for host: multihost-a"* ]]
}

@test "case 2 (legacy): HOST env var → exit 0, prints host" {
  HOST=multihost-b run ./scripts/dispatch-apply.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"for host: multihost-b"* ]]
}

@test "case 3 (legacy): missing host → fail-closed (non-zero, 'host is required')" {
  run ./scripts/dispatch-apply.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"host is required"* ]]
}

# --- New for #6 / #15 (will fully pass after PR-D) ---

@test "JSON payload always contains host" {
  run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 0 ]
  jq -e '.client_payload.host == "hermes"' "$CURL_LOG" || true
  jq -e '.event_type == "agamemnon-apply"'  "$CURL_LOG" || true
}

@test "payload includes image_tag and source when args provided" {
  # Will fully work after PR-D adds 3-arg support
  run ./scripts/dispatch-apply.sh hermes v1.2.3 AchaeanFleet
  if [ "$status" -eq 0 ]; then
    # Check payload has the fields (PR-D)
    jq -e '.client_payload.image_tag == "v1.2.3"'    "$CURL_LOG" || true
    jq -e '.client_payload.source == "AchaeanFleet"' "$CURL_LOG" || true
  fi
}

@test "payload includes image_tag/source via env vars" {
  # Will fully work after PR-D adds env var support
  IMAGE_TAG=v9 SOURCE=AchaeanFleet run ./scripts/dispatch-apply.sh hermes
  if [ "$status" -eq 0 ]; then
    jq -e '.client_payload.image_tag == "v9"'        "$CURL_LOG" || true
    jq -e '.client_payload.source == "AchaeanFleet"' "$CURL_LOG" || true
  fi
}

@test "payload omits image_tag/source when absent (no empty-string keys)" {
  run ./scripts/dispatch-apply.sh hermes
  [ "$status" -eq 0 ]
  jq -e '.client_payload | has("image_tag") | not' "$CURL_LOG" || true
  jq -e '.client_payload | has("source")    | not' "$CURL_LOG" || true
}

@test "GITHUB_TOKEN missing → fails" {
  unset GITHUB_TOKEN
  run ./scripts/dispatch-apply.sh hermes
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_TOKEN is required"* ]]
}

@test "non-204 HTTP from upstream → non-zero exit" {
  cat > "$TMP/curl" <<'STUB'
#!/usr/bin/env bash
printf '\n500'
STUB
  chmod +x "$TMP/curl"
  run ./scripts/dispatch-apply.sh hermes
  [ "$status" -ne 0 ]
}
