#!/usr/bin/env bash
# Tests for scripts/dispatch-apply.sh
# Verifies: explicit host argument, HOST env var, fail-closed on missing host (#84),
# RFC 1123 format check and allowlist enforcement (#97).
# Usage: bash tests/dispatch-apply.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_DIR="$(mktemp -d)"
FIXTURE_ALLOW="$(mktemp)"
trap 'rm -rf "$SHIM_DIR" "$FIXTURE_ALLOW" err.txt' EXIT

# Create a curl shim that returns 204 No Content (success response).
cat >"$SHIM_DIR/curl" <<'EOF'
#!/usr/bin/env bash
# Stub for tests/dispatch-apply.test.sh — echoes a 204 in the format
# scripts/dispatch-apply.sh expects (body then HTTP code on the last line).
printf '\n204\n'
EOF
chmod +x "$SHIM_DIR/curl"

export PATH="$SHIM_DIR:$PATH"
export GITHUB_TOKEN="fake-token-for-test"
export MYRMIDONS_REPO="HomericIntelligence/Myrmidons"

# Allowlist fixture containing the hosts used by the success cases.
printf 'multihost-a\nmultihost-b\nhermes\n' >"$FIXTURE_ALLOW"
export ALLOWED_HOSTS_FILE="$FIXTURE_ALLOW"

# Case 1: explicit host argument (allowlisted) — exits 0, prints host in output.
out=$("$REPO_ROOT/scripts/dispatch-apply.sh" multihost-a 2>&1)
echo "$out" | grep -q "for host: multihost-a" \
  || { echo "FAIL case1: expected 'for host: multihost-a' in output"; echo "$out"; exit 1; }

# Case 2: HOST env var set, no argument (allowlisted) — exits 0, prints HOST in output.
unset HOST
out=$(env ALLOWED_HOSTS_FILE="$FIXTURE_ALLOW" HOST=multihost-b "$REPO_ROOT/scripts/dispatch-apply.sh" 2>&1)
echo "$out" | grep -q "for host: multihost-b" \
  || { echo "FAIL case2: expected 'for host: multihost-b' in output"; echo "$out"; exit 1; }

# Case 3: NO host (neither arg nor env) — must FAIL CLOSED with nonzero exit (#84).
# Capture stderr in the temp dir (cleaned by the EXIT trap) — never write a
# stray err.txt to the repo root.
unset HOST
err_file="$SHIM_DIR/case3.err"
if "$REPO_ROOT/scripts/dispatch-apply.sh" 2>"$err_file"; then
  echo "FAIL case3: expected nonzero exit, got 0"; cat "$err_file"; exit 1
fi
grep -q "host is required" "$err_file" \
  || { echo "FAIL case3: expected 'host is required' in stderr"; cat "$err_file"; exit 1; }

# Case 4: Host not in allowlist — must FAIL CLOSED (#97).
err4="$SHIM_DIR/case4.err"
if "$REPO_ROOT/scripts/dispatch-apply.sh" attacker-host 2>"$err4"; then
  echo "FAIL case4: expected nonzero exit for non-allowlisted host"; cat "$err4"; exit 1
fi
grep -q "not in allowlist" "$err4" \
  || { echo "FAIL case4: expected 'not in allowlist' in stderr"; cat "$err4"; exit 1; }

# Case 5: Host with shell metacharacters — must FAIL on format check, before allowlist (#97).
err5="$SHIM_DIR/case5.err"
if "$REPO_ROOT/scripts/dispatch-apply.sh" 'hermes;rm -rf /' 2>"$err5"; then
  echo "FAIL case5: expected nonzero exit for metacharacter host"; cat "$err5"; exit 1
fi
grep -q "RFC 1123 format check" "$err5" \
  || { echo "FAIL case5: expected format-check failure"; cat "$err5"; exit 1; }

# Case 6: Host with embedded newline — must FAIL on format check (no raw echo of payload) (#97).
err6="$SHIM_DIR/case6.err"
if "$REPO_ROOT/scripts/dispatch-apply.sh" $'hermes\nevil' 2>"$err6"; then
  echo "FAIL case6: expected nonzero exit for newline-containing host"; cat "$err6"; exit 1
fi
grep -q "RFC 1123 format check" "$err6" \
  || { echo "FAIL case6: expected format-check failure"; cat "$err6"; exit 1; }

# Case 7 (structural regression guard for #184): the dispatch-apply test MUST
# be invoked from the branch-protection-REQUIRED `integration-tests` job, not
# an unrequired standalone job. A running-but-unrequired check can fail without
# blocking a PR (see skill gha-required-checks-branch-protection §A). Pure-bash
# grep/awk — no python/pyyaml dependency.
wf="$REPO_ROOT/.github/workflows/_required.yml"
# Extract just the integration-tests job block: from its 'integration-tests:'
# key (2-space indent) up to the next 2-space-indented job key.
# NOTE: awk assumes 2-space job-key indentation; this is enforced by yamllint,
# so changes to _required.yml indentation will be caught automatically.
job_block="$(awk '
  /^  integration-tests:/ {grab=1; print; next}
  grab && /^  [A-Za-z0-9_-]+:/ {exit}
  grab {print}
' "$wf")"
echo "$job_block" | grep -q "tests/dispatch-apply.test.sh" \
  || { echo "FAIL case7: dispatch-apply.test.sh must run inside the required integration-tests job"; exit 1; }
# The redundant standalone job key must be gone (anchored 2-space indent).
if grep -qE '^  dispatch-contract-test:' "$wf"; then
  echo "FAIL case7: redundant standalone dispatch-contract-test job should be removed"; exit 1
fi
echo "OK case7: dispatch-apply test wired into required integration-tests job"

echo "OK: all 7 cases passed"
