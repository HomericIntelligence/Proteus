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
# Override curl for tests:
#   CURL_BIN=/path/to/fake-curl ./scripts/dispatch-apply.sh ...

set -euo pipefail

HOST="${1:-${HOST:-}}"
MYRMIDONS_REPO="${MYRMIDONS_REPO:-HomericIntelligence/Myrmidons}"

if [[ -z "${HOST}" ]]; then
    echo "Error: host is required (pass as \$1 or set HOST env var). See docs/dispatch-contract.md (#84)." >&2
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN is required." >&2
    exit 1
fi

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

echo "Dispatching agamemnon-apply to ${MYRMIDONS_REPO} for host: ${HOST}"

CURL_BIN="${CURL_BIN:-curl}"
RESPONSE=$("$CURL_BIN" --silent --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 --write-out "\n%{http_code}" \
    --request POST \
    --url "https://api.github.com/repos/${MYRMIDONS_REPO}/dispatches" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --data "$PAYLOAD")

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
# Use sed to drop the last line (HTTP code) — portable across GNU and BSD
# (BSD `head` does not support the GNU-only `-n-1` extension).
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -eq 204 ]]; then
    echo "Dispatch successful (204 No Content). Myrmidons apply triggered for host: ${HOST}"
else
    echo "Dispatch failed with HTTP ${HTTP_CODE}:" >&2
    echo "$BODY" >&2
    exit 1
fi
