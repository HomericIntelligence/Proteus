#!/usr/bin/env bash
# verify-branch-protection.sh — Detect drift between live ruleset and the
# committed source of truth on the #95/#102 invariant fields. Read-only.
# Schema reference: https://docs.github.com/en/rest/branches/branch-protection#get-branch-protection
# Boolean toggles come back as { "enabled": <bool> }; PR-review fields are inline.
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-HomericIntelligence/Proteus}}"
BRANCH="${BRANCH:-main}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN is required (needs repo admin scope)." >&2
    exit 1
fi

RESPONSE=$(curl --silent --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 --write-out "\n%{http_code}" \
    --request GET \
    --url "https://api.github.com/repos/${REPO}/branches/${BRANCH}/protection" \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "X-GitHub-Api-Version: 2022-11-28")

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n1)
LIVE=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo "Error: GET branch protection failed (HTTP ${HTTP_CODE}):" >&2
    echo "$LIVE" >&2
    exit 1
fi

fail=0
check() {
    local path="$1" want="$2" got
    got="$(printf '%s' "$LIVE" | jq -r "$path")"
    if [[ "$got" != "$want" ]]; then
        echo "Drift: ${path} = ${got} (want ${want})" >&2
        fail=1
    fi
}

# Org policy (HomericIntelligence/Charybdis#279): 0 required approvals across
# all org repos — merging without human approval is deliberate. This tracks
# the committed .github/branch-protection.main.json, not aspirational policy.
check '.required_pull_request_reviews.required_approving_review_count' '0'
check '.required_pull_request_reviews.require_code_owner_reviews'      'true'
check '.required_pull_request_reviews.dismiss_stale_reviews'           'true'
check '.allow_force_pushes.enabled'                                    'false'
check '.allow_deletions.enabled'                                       'false'
check '.required_linear_history.enabled'                               'true'
check '.enforce_admins.enabled'                                        'true'

if [[ "$fail" -ne 0 ]]; then
    echo "Error: branch protection drift detected; run 'just apply-branch-protection' as admin." >&2
    exit 1
fi
echo "Branch protection matches .github/branch-protection.main.json"
