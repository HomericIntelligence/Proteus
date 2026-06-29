#!/usr/bin/env bash
# Tests for scripts/promote-image.sh — covers the argument-count error path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Case 1: wrong arg count (1 arg, requires 2) — must exit 1 with Usage on stderr.
# promote-image.sh:23 writes the usage line to stderr (>&2). Redirect stderr to
# a file and grep it (same idiom as tests/dispatch-apply.test.sh:37-41).
if "$REPO_ROOT/scripts/promote-image.sh" only-one-arg 2>"$WORK_DIR/err.txt"; then
  echo "FAIL case1: expected nonzero exit, got 0"; cat "$WORK_DIR/err.txt"; exit 1
fi
grep -q "Usage:" "$WORK_DIR/err.txt" \
  || { echo "FAIL case1: expected 'Usage:' on stderr"; cat "$WORK_DIR/err.txt"; exit 1; }

# Case 2: no args — must exit 1 with Usage on stderr.
if "$REPO_ROOT/scripts/promote-image.sh" 2>"$WORK_DIR/err.txt"; then
  echo "FAIL case2: expected nonzero exit, got 0"; cat "$WORK_DIR/err.txt"; exit 1
fi
grep -q "Usage:" "$WORK_DIR/err.txt" \
  || { echo "FAIL case2: expected 'Usage:' on stderr"; cat "$WORK_DIR/err.txt"; exit 1; }

echo "OK: all 2 cases passed"
