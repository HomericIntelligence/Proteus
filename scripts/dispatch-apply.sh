#!/usr/bin/env bash
# dispatch-apply.sh — Send a repository_dispatch event to trigger Myrmidons apply.
# Usage: HOST=<host> GITHUB_TOKEN=<token> MYRMIDONS_REPO=HomericIntelligence/Myrmidons \
#            ./scripts/dispatch-apply.sh [host]
# The HOST argument overrides the HOST env var if both are provided.
# If neither is set, the script FAILS CLOSED (exits 1) — see docs/dispatch-contract.md (#84).
#
# Optional metadata env vars (forwarded into client_payload when non-empty):
#   IMAGE_NAME, IMAGE_TAG, IMAGE_DIGEST, SOURCE_REPO
#
# The host is additionally validated against configs/allowed-hosts.txt (#97);
# an unknown or malformed host also FAILS CLOSED.
#
# Retries transient failures (408/429/5xx, curl exits 6/7/28/35/52/56) with
# exponential backoff + jitter; persists unsent payload to a dead-letter file
# on exhaustion. See docs/dispatch-contract.md and issue #98.

set -euo pipefail

# shellcheck source=scripts/lib/log.sh disable=SC1091
source "$(dirname "$0")/lib/log.sh"

HOST="${1:-${HOST:-}}"
MYRMIDONS_REPO="${MYRMIDONS_REPO:-HomericIntelligence/Myrmidons}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="${ALLOWED_HOSTS_FILE:-${SCRIPT_DIR}/../configs/allowed-hosts.txt}"
DISPATCH_MAX_ATTEMPTS="${DISPATCH_MAX_ATTEMPTS:-5}"
DISPATCH_BASE_DELAY_MS="${DISPATCH_BASE_DELAY_MS:-1000}"
DISPATCH_MAX_DELAY_MS="${DISPATCH_MAX_DELAY_MS:-30000}"
DLQ_DIR="${DISPATCH_DLQ_DIR:-${GITHUB_WORKSPACE:-$PWD}/.dispatch-dlq}"
# Allow tests to substitute a stub curl via CURL_BIN; default to the real binary.
CURL_BIN="${CURL_BIN:-curl}"

if [[ -z "${HOST}" ]]; then
    log_error "host is required (pass as \$1 or set HOST env var). See docs/dispatch-contract.md (#84, #97)."
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log_error "GITHUB_TOKEN is required."
    exit 1
fi

# shellcheck source=scripts/validate-host.sh disable=SC1091
source "${SCRIPT_DIR}/validate-host.sh"
if ! validate_host "${HOST}" "${ALLOWLIST}"; then
    echo "Error: host validation failed for '${HOST}'. See docs/dispatch-contract.md (#97)." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for dead-letter encoding (see docs/dispatch-contract.md §Retry & Dead-Letter)."
    exit 1
fi

# Build the client_payload with jq so any character (quotes, newlines,
# backslashes) is encoded safely, forwarding optional metadata when present
# (#6, #15).
PAYLOAD=$(jq -n \
  --arg host         "$HOST" \
  --arg image_name   "${IMAGE_NAME:-}" \
  --arg image_tag    "${IMAGE_TAG:-}" \
  --arg image_digest "${IMAGE_DIGEST:-}" \
  --arg source_repo  "${SOURCE_REPO:-}" \
  '{
     event_type: "agamemnon-apply",
     client_payload: (
       {host: $host}
       + (if $image_name   != "" then {image_name:   $image_name}   else {} end)
       + (if $image_tag    != "" then {image_tag:    $image_tag}    else {} end)
       + (if $image_digest != "" then {image_digest: $image_digest} else {} end)
       + (if $source_repo  != "" then {source:       $source_repo}  else {} end)
     )
   }')

_is_retryable_http() {
  case "$1" in
    408|429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

_is_retryable_curl_exit() {
  # 6 DNS, 7 connect, 28 timeout, 35 SSL connect, 52 empty reply, 56 recv.
  case "$1" in
    6|7|28|35|52|56) return 0 ;;
    *) return 1 ;;
  esac
}

# Backoff: base_ms * 2^(attempt-1), capped at max_ms, scaled by jitter in [0.5, 1.5).
# Implemented with bash-builtin arithmetic + RANDOM (no awk srand, no xargs sleep).
_sleep_backoff() {
  local attempt="$1"
  local d=$DISPATCH_BASE_DELAY_MS
  local i=1
  while [ "$i" -lt "$attempt" ]; do
    d=$((d * 2))
    i=$((i + 1))
  done
  if [ "$d" -gt "$DISPATCH_MAX_DELAY_MS" ]; then d=$DISPATCH_MAX_DELAY_MS; fi
  # RANDOM in [0, 32767]; jitter_num/2 maps to roughly [0.5, 1.5).
  local jitter_num=$(( 16384 + (RANDOM % 32768) ))   # [16384, 49151]
  local out_ms=$(( d * jitter_num / 32768 ))
  local sec=$(( out_ms / 1000 ))
  local ms=$(( out_ms % 1000 ))
  sleep "$(printf '%d.%03d' "$sec" "$ms")"
}

_persist_dlq() {
  local code="$1" body="$2"
  mkdir -p "$DLQ_DIR"
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local f="$DLQ_DIR/${ts}-${HOST}.json"
  # jq -R -s '.' reads stdin as one raw string and emits a valid JSON string
  # (handles NULs, quotes, backslashes, newlines). No python3 dependency.
  local body_json; body_json=$(printf '%s' "$body" | jq -R -s '.')
  local payload_json; payload_json=$(printf '%s' "$PAYLOAD" | jq -R -s '.')
  jq -n \
    --arg ts "$ts" \
    --arg host "$HOST" \
    --arg repo "$MYRMIDONS_REPO" \
    --arg last_code "$code" \
    --argjson payload "$payload_json" \
    --argjson body "$body_json" \
    '{ts: $ts, host: $host, repo: $repo, last_code: $last_code,
      payload: $payload, last_body: $body}' \
    > "$f"
  log_error "dead-letter written: %s" "$f"
}

log_info "dispatching agamemnon-apply repo=%s host=%s max_attempts=%s" \
  "$MYRMIDONS_REPO" "$HOST" "$DISPATCH_MAX_ATTEMPTS"

attempt=1
last_code=""
last_body=""
while : ; do
  set +e
  RESPONSE=$("$CURL_BIN" --silent --connect-timeout 10 --max-time 30 \
    --write-out "\n%{http_code}" \
    --request POST \
    --url "https://api.github.com/repos/${MYRMIDONS_REPO}/dispatches" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --data "$PAYLOAD")
  curl_exit=$?
  set -e

  if [ "$curl_exit" -ne 0 ]; then
    last_code="curl_exit_${curl_exit}"
    last_body=""
    log_warn "attempt=%d curl_exit=%d" "$attempt" "$curl_exit"
    if ! _is_retryable_curl_exit "$curl_exit"; then
      log_error "non-retryable curl_exit=%d — failing fast" "$curl_exit"
      _persist_dlq "$last_code" ""
      exit 1
    fi
  else
    last_code=$(printf '%s' "$RESPONSE" | tail -n1)
    last_body=$(printf '%s' "$RESPONSE" | sed '$d')
    if [ "$last_code" = "204" ]; then
      log_info "dispatch successful (204) attempt=%d host=%s" "$attempt" "$HOST"
      exit 0
    fi
    log_warn "attempt=%d http=%s" "$attempt" "$last_code"
    if ! _is_retryable_http "$last_code"; then
      log_error "non-retryable http=%s — failing fast (auth/payload/repo)" "$last_code"
      _persist_dlq "$last_code" "$last_body"
      exit 1
    fi
  fi

  if [ "$attempt" -ge "$DISPATCH_MAX_ATTEMPTS" ]; then
    log_error "exhausted %d attempts; writing dead-letter" "$DISPATCH_MAX_ATTEMPTS"
    _persist_dlq "${last_code:-0}" "${last_body:-}"
    exit 1
  fi

  _sleep_backoff "$attempt"
  attempt=$((attempt + 1))
done
