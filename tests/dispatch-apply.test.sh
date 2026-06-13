#!/usr/bin/env bash
# Tests for scripts/dispatch-apply.sh
# Verifies: explicit host argument, HOST env var, fail-closed behavior

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT

# Create a curl shim that returns 204 No Content (success response)
cat >"$SHIM_DIR/curl" <<'EOF'
#!/usr/bin/env bash
# Stub for tests/dispatch-apply.test.sh — echoes a 204 in the format
# scripts/dispatch-apply.sh:19 expects (body then HTTP code on the last line).
printf '\n204\n'
EOF
chmod +x "$SHIM_DIR/curl"

export PATH="$SHIM_DIR:$PATH"
export GITHUB_TOKEN="fake-token-for-test"
export MYRMIDONS_REPO="HomericIntelligence/Myrmidons"

# Case 1: explicit host argument — exits 0, prints host in output.
out=$("$REPO_ROOT/scripts/dispatch-apply.sh" multihost-a 2>&1)
echo "$out" | grep -q "for host: multihost-a" \
  || { echo "FAIL case1: expected 'for host: multihost-a' in output"; echo "$out"; exit 1; }

# Case 2: HOST env var set, no argument — exits 0, prints HOST in output.
unset HOST
out=$(env HOST=multihost-b "$REPO_ROOT/scripts/dispatch-apply.sh" 2>&1)
echo "$out" | grep -q "for host: multihost-b" \
  || { echo "FAIL case2: expected 'for host: multihost-b' in output"; echo "$out"; exit 1; }

# Case 3: NO host (neither arg nor env) — must FAIL CLOSED with nonzero exit.
unset HOST
if "$REPO_ROOT/scripts/dispatch-apply.sh" 2>err.txt; then
  echo "FAIL case3: expected nonzero exit, got 0"; cat err.txt; exit 1
fi
grep -q "host is required" err.txt \
  || { echo "FAIL case3: expected 'host is required' in stderr"; cat err.txt; exit 1; }

echo "OK: all 3 cases passed"
