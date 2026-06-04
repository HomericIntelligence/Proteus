#!/usr/bin/env bash
# dispatch-apply.sh — Send a repository_dispatch event to trigger Myrmidons apply.
# Usage: HOST=<host> [IMAGE_TAG=<tag>] [SOURCE=<src>] GITHUB_TOKEN=<token> \
#        ./scripts/dispatch-apply.sh [host] [image_tag] [source]
# host is required (CLI arg or HOST env). image_tag and source are optional
# but recommended for Myrmidons audit logging; absent fields are omitted
# from client_payload. See #6, #15.

set -euo pipefail

HOST="${1:-${HOST:-}}"
IMAGE_TAG="${2:-${IMAGE_TAG:-}}"
SOURCE="${3:-${SOURCE:-}}"
MYRMIDONS_REPO="${MYRMIDONS_REPO:-HomericIntelligence/Myrmidons}"

if [[ -z "${HOST}" ]]; then
    echo "Error: host is required (pass as \$1 or set HOST env var). See docs/dispatch-contract.md (#84)." >&2
    exit 1
fi
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN is required." >&2
    exit 1
fi
if [[ -z "$IMAGE_TAG" || -z "$SOURCE" ]]; then
    echo "Warning: image_tag and/or source not provided; Myrmidons audit log will be incomplete (#6)." >&2
fi

PAYLOAD="$(jq -nc \
    --arg h "$HOST" --arg t "$IMAGE_TAG" --arg s "$SOURCE" \
    '{event_type:"agamemnon-apply",
      client_payload: (
        {host:$h}
        + (if $t == "" then {} else {image_tag:$t} end)
        + (if $s == "" then {} else {source:$s}    end)
      )}')"

echo "Dispatching agamemnon-apply to ${MYRMIDONS_REPO} for host: ${HOST}"

RESPONSE=$(curl --silent --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 \
    --write-out "\n%{http_code}" \
    --request POST \
    --url "https://api.github.com/repos/${MYRMIDONS_REPO}/dispatches" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --data "${PAYLOAD}")

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -eq 204 ]]; then
    echo "Dispatch successful (204 No Content). Myrmidons apply triggered for host: ${HOST}"
else
    echo "Dispatch failed with HTTP ${HTTP_CODE}:" >&2
    echo "$BODY" >&2
    exit 1
fi
