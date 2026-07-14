#!/usr/bin/env bash
# audit-main-ruleset.sh — Read-only audit of the live `homeric-main-baseline`
# repository ruleset. Used by apply-branch-protection.yml as the fail-closed
# fallback when no admin PAT (BRANCH_PROTECTION_PAT) is configured: the
# workflow's default GITHUB_TOKEN cannot mutate protection settings, but it
# CAN read rulesets, so this script verifies main is still governed.
#
# Org policy (HomericIntelligence/Charybdis#279): required_approving_review_count
# is deliberately 0 across all org repos — merging without human approval is
# intentional. This audit therefore asserts the pull_request rule and its
# review-count parameter are PRESENT (>= 0), not that approvals are required.
#
# Asserts:
#   1. A ruleset named "homeric-main-baseline" exists and is active.
#   2. It contains a pull_request rule with a required_approving_review_count
#      parameter >= MIN_REVIEWERS (default 0, per org policy).
#   3. It contains a required_status_checks rule with a non-empty context list.
#
# Usage: GH_TOKEN=<token> ./scripts/audit-main-ruleset.sh
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-HomericIntelligence/Proteus}}"
RULESET_NAME="${RULESET_NAME:-homeric-main-baseline}"
# Org policy is 0 required approvals (Charybdis#279). Track the real ruleset
# config here, not aspirational policy.
MIN_REVIEWERS="${MIN_REVIEWERS:-0}"

echo "Auditing ruleset '${RULESET_NAME}' on ${REPO} (read-only)"

ruleset_id=$(gh api "repos/${REPO}/rulesets" \
    --jq ".[] | select(.name == \"${RULESET_NAME}\" and .enforcement == \"active\") | .id")
if [[ -z "$ruleset_id" ]]; then
    echo "Error: no active ruleset named '${RULESET_NAME}' found on ${REPO}." >&2
    exit 1
fi

ruleset=$(gh api "repos/${REPO}/rulesets/${ruleset_id}")

review_count=$(jq -r \
    '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' \
    <<<"$ruleset")
if [[ -z "$review_count" || "$review_count" == "null" ]]; then
    echo "Error: ruleset '${RULESET_NAME}' has no pull_request rule with a required_approving_review_count parameter." >&2
    exit 1
fi
if [[ "$review_count" -lt "$MIN_REVIEWERS" ]]; then
    echo "Error: required_approving_review_count is ${review_count}, expected >= ${MIN_REVIEWERS}." >&2
    exit 1
fi

context_count=$(jq -r \
    '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | length' \
    <<<"$ruleset")
if [[ "$context_count" -eq 0 ]]; then
    echo "Error: ruleset '${RULESET_NAME}' has no required status-check contexts." >&2
    exit 1
fi

echo "OK: ruleset '${RULESET_NAME}' (id ${ruleset_id}) is active with a pull_request rule (review count ${review_count} >= ${MIN_REVIEWERS}) and ${context_count} required status-check context(s)."
