#!/usr/bin/env bash
# scripts/branch-protection-apply.sh
# Enforce CODEOWNERS review on `main` (#102).
# READS current protection via `gh api -i` (HTTP status line in stdout, stable
# contract) and round-trips every sibling field, including non-null restrictions,
# so #94 (status checks), #95 (approving review count), and any configured push
# restrictions are NOT clobbered. Idempotent: safe to re-run.
# Requires `gh` authenticated with admin scope on the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
# shellcheck disable=SC1091  # lib/log.sh resolved at runtime; CI runs shellcheck without -x
. "$SCRIPT_DIR/lib/log.sh"

REPO="${REPO:-HomericIntelligence/Proteus}"
BRANCH="${BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"
DRY_RUN_OUT="${DRY_RUN_OUT:-/dev/stdout}"

log_info "Reading current protection for $REPO@$BRANCH" >&2

# `gh api -i` prepends the HTTP status line and headers, then a blank line,
# then the body. This is documented and stable across `gh` versions, unlike
# stderr formatting. We always exit-mask the non-2xx, parse the status code
# ourselves, then branch.
raw=$(gh api -i "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || true)

if [[ -z "$raw" ]]; then
  log_error "Empty response from gh api — is gh installed and authenticated? Run: gh auth status"
  exit 1
fi

status_line=$(printf '%s\n' "$raw" | head -n1)
status_code=$(printf '%s' "$status_line" | sed -nE 's|^HTTP/[0-9.]+ ([0-9]{3}).*|\1|p')
# Body is everything after the first blank line.
body=$(printf '%s\n' "$raw" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')

case "$status_code" in
  200)
    current="$body"
    ;;
  404)
    log_warn "No existing protection on $REPO@$BRANCH; will create minimal protection with require_code_owner_reviews=true" >&2
    current='{}'
    ;;
  401|403)
    log_error "GET /branches/$BRANCH/protection returned HTTP $status_code — admin scope required. Run: gh auth refresh -s admin:repo_hook,repo" >&2
    exit 1
    ;;
  *)
    log_error "GET /branches/$BRANCH/protection returned unexpected HTTP $status_code:" >&2
    printf '%s\n' "$body" >&2
    exit 1
    ;;
esac

# Map GET response shape → PUT request shape, mutating ONLY
# required_pull_request_reviews.require_code_owner_reviews. Every sibling
# sub-object — including restrictions — is round-tripped. The jq filter is
# pinned by the fixture diff in tests/branch-protection-apply.test.sh case 1.
payload=$(jq '
  {
    required_status_checks: (
      if .required_status_checks then
        { strict: (.required_status_checks.strict // false),
          contexts: (.required_status_checks.contexts // []) }
      else null end
    ),
    enforce_admins: (.enforce_admins.enabled // false),
    required_pull_request_reviews: (
      if .required_pull_request_reviews then
        {
          dismiss_stale_reviews: (.required_pull_request_reviews.dismiss_stale_reviews // true),
          require_code_owner_reviews: true,
          required_approving_review_count: (.required_pull_request_reviews.required_approving_review_count // 1),
          require_last_push_approval: (.required_pull_request_reviews.require_last_push_approval // false)
        }
      else
        { dismiss_stale_reviews: true,
          require_code_owner_reviews: true,
          required_approving_review_count: 1,
          require_last_push_approval: false }
      end
    ),
    restrictions: (
      if (.restrictions // null) == null then null
      else
        { users: [(.restrictions.users // [])[] | .login],
          teams: [(.restrictions.teams // [])[] | .slug],
          apps:  [(.restrictions.apps  // [])[] | .slug] }
      end
    ),
    required_linear_history: (.required_linear_history.enabled // false),
    allow_force_pushes: (.allow_force_pushes.enabled // false),
    allow_deletions: (.allow_deletions.enabled // false),
    block_creations: (.block_creations.enabled // false),
    required_conversation_resolution: (.required_conversation_resolution.enabled // false),
    lock_branch: (.lock_branch.enabled // false),
    allow_fork_syncing: (.allow_fork_syncing.enabled // false)
  }
' <<<"$current")

if [[ "$DRY_RUN" == "1" ]]; then
  log_info "DRY_RUN=1 — payload written to $DRY_RUN_OUT (PUT not called)" >&2
  printf '%s\n' "$payload" > "$DRY_RUN_OUT"
  exit 0
fi

log_info "Applying CODEOWNERS enforcement (#102) — round-tripping sibling fields" >&2
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<<"$payload" >/dev/null

result=$(gh api "repos/$REPO/branches/$BRANCH/protection" \
  --jq '.required_pull_request_reviews.require_code_owner_reviews')

if [[ "$result" != "true" ]]; then
  log_error "Verification failed: require_code_owner_reviews=$result (expected true)"
  exit 1
fi
log_info "OK: require_code_owner_reviews=true on $REPO@$BRANCH"
