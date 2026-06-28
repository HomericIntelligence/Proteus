#!/usr/bin/env bash
# Shell-level tests for scripts/dispatch-apply.sh.
# Stubs curl via the CURL_BIN env var the script honours.
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub `curl`: captures the --data argument into $BODY_OUT, prints HTTP 204.
cat > "$TMP/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data) printf '%s' "$2" > "$BODY_OUT"; shift 2 ;;
    *) shift ;;
  esac
done
printf '\n204\n'
EOF
chmod +x "$TMP/fake-curl"

export CURL_BIN="$TMP/fake-curl"
export BODY_OUT="$TMP/body"
export GITHUB_TOKEN=stub-token
export MYRMIDONS_REPO=test-org/test-repo

run() { unset IMAGE_NAME IMAGE_TAG IMAGE_DIGEST SOURCE_REPO; "$@"; }

# 1. Legacy: HOST arg, no metadata env. Body has host, no image_* keys.
run "$SCRIPTS_DIR/dispatch-apply.sh" hermes >/dev/null
jq -e '.event_type == "agamemnon-apply"
       and .client_payload.host == "hermes"
       and (.client_payload | has("image_name") | not)' "$TMP/body" >/dev/null

# 2. Metadata forwarding: all four optional fields set.
IMAGE_NAME=myapp IMAGE_TAG=v1.2.3 \
  IMAGE_DIGEST='sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' \
  SOURCE_REPO=AchaeanFleet \
  "$SCRIPTS_DIR/dispatch-apply.sh" hermes >/dev/null
jq -e '.client_payload.image_name == "myapp"
       and .client_payload.image_tag == "v1.2.3"
       and (.client_payload.image_digest | startswith("sha256:"))
       and .client_payload.source == "AchaeanFleet"' "$TMP/body" >/dev/null

# 3. JSON-safe construction: a value with a literal double quote is escaped.
unset IMAGE_TAG IMAGE_DIGEST SOURCE_REPO
IMAGE_NAME='ev"il' "$SCRIPTS_DIR/dispatch-apply.sh" hermes >/dev/null
jq -e '.client_payload.image_name == "ev\"il"' "$TMP/body" >/dev/null

# 4. Fail-closed: no HOST arg and no HOST env must exit non-zero (#84),
#    rather than silently defaulting to a host and risking a misroute.
if env -u HOST -u IMAGE_NAME -u IMAGE_TAG -u IMAGE_DIGEST -u SOURCE_REPO \
     "$SCRIPTS_DIR/dispatch-apply.sh" >/dev/null 2>&1; then
  echo "FAIL: dispatch-apply.sh should fail closed when HOST is unset (#84)" >&2
  exit 1
fi

echo "ok"
