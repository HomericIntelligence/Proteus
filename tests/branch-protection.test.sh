#!/usr/bin/env bash
# Tests for scripts/verify-branch-protection.sh — pass, drift, missing-token, malformed-JSON.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM_DIR="$(mktemp -d)"
WORK_OUT="$(mktemp)"
trap 'rm -rf "$SHIM_DIR" "$WORK_OUT"' EXIT

# Org policy (Charybdis#279): required_approving_review_count is 0 — the
# clean response mirrors .github/branch-protection.main.json; the drift
# response deviates on the review count (1 != 0) and the codeowner flag.
CLEAN_RESPONSE='{"required_pull_request_reviews":{"required_approving_review_count":0,"require_code_owner_reviews":true,"dismiss_stale_reviews":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false},"required_linear_history":{"enabled":true},"enforce_admins":{"enabled":true}}'
DRIFT_RESPONSE='{"required_pull_request_reviews":{"required_approving_review_count":1,"require_code_owner_reviews":false,"dismiss_stale_reviews":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false},"required_linear_history":{"enabled":true},"enforce_admins":{"enabled":true}}'

# write_shim "<json>" — install a curl shim that prints <json>, a newline, "200", a newline.
# Heredoc terminator is UNQUOTED so $1 expands here; the printf inside the shim then
# treats the JSON as a literal positional argument (single quotes inside the heredoc
# become literal in the written file).
write_shim() {
    local payload="$1"
    cat >"$SHIM_DIR/curl" <<EOF
#!/usr/bin/env bash
cat <<'PAYLOAD'
${payload}
200
PAYLOAD
EOF
    chmod +x "$SHIM_DIR/curl"
}

export PATH="$SHIM_DIR:$PATH"

# Case A: clean response → exit 0.
write_shim "$CLEAN_RESPONSE"
export GITHUB_TOKEN=fake
"$REPO_ROOT/scripts/verify-branch-protection.sh" >/dev/null \
    || { echo "FAIL caseA: clean ruleset should pass"; exit 1; }

# Case B: drifted response → exit nonzero, message names the drifted fields.
write_shim "$DRIFT_RESPONSE"
if "$REPO_ROOT/scripts/verify-branch-protection.sh" >"$WORK_OUT" 2>&1; then
    echo "FAIL caseB: drifted ruleset should exit nonzero"; cat "$WORK_OUT"; exit 1
fi
grep -q "required_approving_review_count" "$WORK_OUT" \
    || { echo "FAIL caseB: expected drift message for review count"; cat "$WORK_OUT"; exit 1; }
grep -q "require_code_owner_reviews" "$WORK_OUT" \
    || { echo "FAIL caseB: expected drift message for codeowner flag"; cat "$WORK_OUT"; exit 1; }

# Case C: missing GITHUB_TOKEN → fail closed.
unset GITHUB_TOKEN
if "$REPO_ROOT/scripts/verify-branch-protection.sh" >/dev/null 2>&1; then
    echo "FAIL caseC: expected nonzero exit with GITHUB_TOKEN unset"; exit 1
fi

# Case D: the committed ruleset is valid JSON (catches editor corruption regressions).
if ! jq . "$REPO_ROOT/.github/branch-protection.main.json" >/dev/null 2>&1; then
    echo "FAIL caseD: .github/branch-protection.main.json is not valid JSON"; exit 1
fi

echo "OK: branch-protection.test.sh"
