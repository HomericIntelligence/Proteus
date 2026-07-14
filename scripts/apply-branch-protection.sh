#!/usr/bin/env bash
# apply-branch-protection.sh — Apply .github/branch-protection.main.json to main.
# Closes audit defect #95 (PR review enforcement); API half of #102 (CODEOWNERS).
# Usage: GITHUB_TOKEN=<admin-pat> ./scripts/apply-branch-protection.sh
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-HomericIntelligence/Proteus}}"
BRANCH="${BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULESET="${SCRIPT_DIR}/../.github/branch-protection.main.json"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN is required (needs repo admin scope)." >&2
    exit 1
fi
if [[ ! -r "$RULESET" ]]; then
    echo "Error: ruleset file missing or unreadable: $RULESET" >&2
    exit 2
fi

echo "Applying branch protection to ${BRANCH} on ${REPO}"

RESPONSE=$(curl --silent --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 --write-out "\n%{http_code}" \
    --request PUT \
    --url "https://api.github.com/repos/${REPO}/branches/${BRANCH}/protection" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --data-binary "@${RULESET}")

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -eq 200 ]]; then
    echo "Branch protection applied (HTTP ${HTTP_CODE})"
else
    echo "Apply failed with HTTP ${HTTP_CODE}:" >&2
    echo "$BODY" >&2
    exit 1
fi
