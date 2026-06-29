#!/usr/bin/env bash
# Tests for scripts/check-symlinks.sh — verifies exit 0 on clean tree, exit 1
# on broken symlink.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Case 1: tree with only a valid symlink — exit 0.
mkdir -p "$WORK_DIR/case1"
ln -s /tmp "$WORK_DIR/case1/good"
(cd "$WORK_DIR/case1" && "$REPO_ROOT/scripts/check-symlinks.sh") >"$WORK_DIR/case1.out" 2>&1 \
  || { echo "FAIL case1: expected exit 0 on clean tree"; cat "$WORK_DIR/case1.out"; exit 1; }

# Case 2: tree with a broken symlink — exit 1, error message on stdout.
# check-symlinks.sh:13 writes the `::error::` line via plain `echo` (no >&2
# anywhere in the script — verified `grep -n ">&2" scripts/check-symlinks.sh`
# returns zero matches during planning).
mkdir -p "$WORK_DIR/case2"
ln -s /this/path/does/not/exist "$WORK_DIR/case2/broken"
if (cd "$WORK_DIR/case2" && "$REPO_ROOT/scripts/check-symlinks.sh") >"$WORK_DIR/case2.out" 2>&1; then
  echo "FAIL case2: expected nonzero exit on broken symlink"; cat "$WORK_DIR/case2.out"; exit 1
fi
grep -q "Broken symlinks" "$WORK_DIR/case2.out" \
  || { echo "FAIL case2: expected 'Broken symlinks' in output"; cat "$WORK_DIR/case2.out"; exit 1; }

echo "OK: all 2 cases passed"
