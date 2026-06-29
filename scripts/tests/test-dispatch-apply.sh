#!/usr/bin/env bash
# Helper and test-case functions are dispatched indirectly (via `$test_fn` in
# run_test and through PATH-shimmed curl), so ShellCheck cannot see the call
# sites and reports their bodies as unreachable (SC2317). Each test also
# deliberately exports its env inside a `( ... )` subshell so the variables are
# scoped to that single dispatch-apply.sh invocation — SC2030/SC2031 flag this
# intentional isolation. Disable all three file-wide.
# shellcheck disable=SC2317,SC2030,SC2031
#
# test-dispatch-apply.sh — Unit tests for scripts/dispatch-apply.sh
# Tests the dispatch-apply script with stubbed curl, verifying:
# - Exact exit codes (0 success, 1 fail-closed/error)
# - JSON payload structure and encoding
# - Environment variable handling
# - HTTP response codes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d)
# Expand TEST_DIR now (it is fixed for the run); single-quoted inner path keeps
# the value safe if it ever contains spaces.
# shellcheck disable=SC2064
trap "rm -rf '$TEST_DIR'" EXIT

# Helper to create a curl stub. The stub reads STUB_HTTP_CODE and
# STUB_RESPONSE_BODY from the environment (each test exports them), so this
# helper only needs the target directory.
# Args: stub_dir
create_curl_stub() {
    local stub_dir="$1"

    cat > "$stub_dir/curl" << 'STUB_EOF'
#!/usr/bin/env bash
# curl stub — records arguments and returns a fixed HTTP code
STUB_DIR="$(dirname "$0")"

# Record the call arguments
{
    echo "=== curl invocation ==="
    for arg in "$@"; do
        echo "$arg"
    done
} >> "$STUB_DIR/calls" 2>&1

# Create sentinel to prove the stub was invoked
touch "$STUB_DIR/invoked"

# Simulate curl's output: response body + newline + HTTP code
printf '%s' "$STUB_RESPONSE_BODY"
printf '\n%s\n' "$STUB_HTTP_CODE"
STUB_EOF

    chmod +x "$stub_dir/curl"
}

# Helper to run a test case
# Args: test_name, test_function
run_test() {
    local test_name="$1"
    local test_fn="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo -e "${YELLOW}Test $TESTS_RUN: $test_name${NC}"

    if $test_fn; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}"
    fi
}

# Helper to assert exit code
# Args: expected_exit_code, actual_exit_code
assert_exit_code() {
    local expected="$1"
    local actual="$2"

    if [[ "$actual" -eq "$expected" ]]; then
        echo "  Exit code: $actual (expected $expected) ✓"
        return 0
    else
        echo "  Exit code: $actual (expected $expected) ✗"
        return 1
    fi
}

# Helper to assert JSON field
# Args: json_string, jq_filter, expected_value
assert_json_field() {
    local json="$1"
    local filter="$2"
    local expected="$3"

    local actual
    actual=$(echo "$json" | jq -r "$filter" 2>/dev/null) || {
        echo "  Failed to parse JSON with jq filter '$filter' ✗"
        echo "  JSON was: $json"
        return 1
    }

    if [[ "$actual" == "$expected" ]]; then
        echo "  $filter = $actual ✓"
        return 0
    else
        echo "  $filter = $actual (expected $expected) ✗"
        return 1
    fi
}

# Helper to extract JSON payload from curl stub calls
# The payload is passed via --data argument
extract_payload_from_calls() {
    local calls_file="$1"
    # Find the line that starts with '--data' and read all following lines until we have valid JSON
    local in_data=0
    local payload=""
    while IFS= read -r line; do
        if [[ "$line" == "--data" ]]; then
            in_data=1
        elif [[ $in_data -eq 1 ]]; then
            if [[ -z "$payload" ]]; then
                payload="$line"
            else
                payload+=$'\n'"$line"
            fi
            # Try to parse as complete JSON
            if echo "$payload" | jq . &>/dev/null; then
                echo "$payload"
                return 0
            fi
        fi
    done < "$calls_file"
    return 1
}

# ============================================================================
# Test Cases
# ============================================================================

test_happy_path() {
    local stub_dir="$TEST_DIR/happy"
    mkdir -p "$stub_dir"
    create_curl_stub "$stub_dir"

    echo "  Testing: HOST=hermes IMAGE_TAG=v1 SOURCE=AchaeanFleet"

    local exit_code=0
    (
        export GITHUB_TOKEN="test-token"
        export HOST="hermes"
        export IMAGE_TAG="v1"
        export SOURCE="AchaeanFleet"
        export STUB_HTTP_CODE="204"
        export STUB_RESPONSE_BODY=""
        export PATH="$stub_dir:$PATH"
        bash ./scripts/dispatch-apply.sh hermes
    ) || exit_code=$?

    if ! assert_exit_code 0 "$exit_code"; then return 1; fi

    if [[ ! -f "$stub_dir/invoked" ]]; then
        echo "  Curl stub not invoked (invoked sentinel missing) ✗"
        return 1
    fi
    echo "  Curl stub was invoked ✓"

    # Extract the JSON payload from the curl invocation
    local payload
    payload=$(extract_payload_from_calls "$stub_dir/calls") || {
        echo "  Payload not found in curl call ✗"
        cat "$stub_dir/calls" >&2
        return 1
    }

    # Verify JSON structure
    assert_json_field "$payload" ".event_type" "agamemnon-apply" || return 1
    assert_json_field "$payload" ".client_payload.host" "hermes" || return 1
    assert_json_field "$payload" ".client_payload.image_tag" "v1" || return 1
    assert_json_field "$payload" ".client_payload.source" "AchaeanFleet" || return 1

    return 0
}

test_missing_token() {
    local stub_dir="$TEST_DIR/missing_token"
    mkdir -p "$stub_dir"
    create_curl_stub "$stub_dir"

    echo "  Testing: missing GITHUB_TOKEN"

    local exit_code=0
    (
        unset GITHUB_TOKEN || true
        export HOST="hermes"
        export STUB_HTTP_CODE="204"
        export STUB_RESPONSE_BODY=""
        export PATH="$stub_dir:$PATH"
        bash ./scripts/dispatch-apply.sh hermes 2>/dev/null
    ) || exit_code=$?

    if ! assert_exit_code 1 "$exit_code"; then return 1; fi

    if [[ -f "$stub_dir/invoked" ]]; then
        echo "  Curl stub should not be invoked when token is missing ✗"
        return 1
    fi
    echo "  Curl stub was not invoked ✓"

    return 0
}

test_missing_host() {
    local stub_dir="$TEST_DIR/missing_host"
    mkdir -p "$stub_dir"
    create_curl_stub "$stub_dir"

    echo "  Testing: missing host argument and HOST env"

    local exit_code=0
    (
        export GITHUB_TOKEN="test-token"
        unset HOST || true
        export STUB_HTTP_CODE="204"
        export STUB_RESPONSE_BODY=""
        export PATH="$stub_dir:$PATH"
        bash ./scripts/dispatch-apply.sh 2>/dev/null
    ) || exit_code=$?

    # Fail-closed on missing host is canonical exit 1 (#84).
    if ! assert_exit_code 1 "$exit_code"; then return 1; fi

    if [[ -f "$stub_dir/invoked" ]]; then
        echo "  Curl stub should not be invoked when host is missing ✗"
        return 1
    fi
    echo "  Curl stub was not invoked ✓"

    return 0
}

test_special_characters() {
    local stub_dir="$TEST_DIR/special_chars"
    mkdir -p "$stub_dir"
    create_curl_stub "$stub_dir"

    echo "  Testing: special characters (quotes, newlines, backslashes)"
    local image_tag='v"with quotes'
    local source=$'line1\nline2'

    local exit_code=0
    (
        export GITHUB_TOKEN="test-token"
        export HOST="h"
        export IMAGE_TAG="$image_tag"
        export SOURCE="$source"
        export STUB_HTTP_CODE="204"
        export STUB_RESPONSE_BODY=""
        export PATH="$stub_dir:$PATH"
        bash ./scripts/dispatch-apply.sh h
    ) || exit_code=$?

    if ! assert_exit_code 0 "$exit_code"; then return 1; fi

    if [[ ! -f "$stub_dir/invoked" ]]; then
        echo "  Curl stub not invoked ✗"
        return 1
    fi
    echo "  Curl stub was invoked ✓"

    # Extract the JSON payload
    local payload
    payload=$(extract_payload_from_calls "$stub_dir/calls") || {
        echo "  Payload not found in curl call ✗"
        return 1
    }

    # Verify special characters are correctly JSON-encoded
    assert_json_field "$payload" ".client_payload.image_tag" 'v"with quotes' || return 1

    # For newline, check that it's preserved in the JSON string
    local source_from_json
    source_from_json=$(echo "$payload" | jq -r ".client_payload.source")
    if [[ "$source_from_json" == "line1
line2" ]]; then
        echo "  source field contains literal newline ✓"
    else
        echo "  source field does not contain literal newline ✗"
        return 1
    fi

    return 0
}

test_http_failure() {
    local stub_dir="$TEST_DIR/http_failure"
    mkdir -p "$stub_dir"
    create_curl_stub "$stub_dir"

    echo "  Testing: HTTP 422 error response"

    local exit_code=0
    (
        export GITHUB_TOKEN="test-token"
        export HOST="hermes"
        export STUB_HTTP_CODE="422"
        export STUB_RESPONSE_BODY='{"message":"bad"}'
        export PATH="$stub_dir:$PATH"
        bash ./scripts/dispatch-apply.sh hermes 2>/dev/null
    ) || exit_code=$?

    if ! assert_exit_code 1 "$exit_code"; then return 1; fi

    if [[ ! -f "$stub_dir/invoked" ]]; then
        echo "  Curl stub not invoked ✗"
        return 1
    fi
    echo "  Curl stub was invoked ✓"

    return 0
}

# ============================================================================
# Run all tests
# ============================================================================

echo "========================================"
echo "dispatch-apply.sh Unit Tests"
echo "========================================"
echo ""
echo "Test environment:"
echo "  SCRIPT: ./scripts/dispatch-apply.sh"
echo "  SHELL: $SHELL"
echo "  JQ: $(jq --version 2>/dev/null || echo 'not found')"
echo ""

# Change to repo root
cd "$(dirname "$0")/../.."

run_test "Happy path (hermes, v1, AchaeanFleet)" test_happy_path
run_test "Missing GITHUB_TOKEN" test_missing_token
run_test "Missing host argument and HOST env" test_missing_host
run_test "Special characters (quotes, newlines)" test_special_characters
run_test "HTTP error response (422)" test_http_failure

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================"
echo "Test Results"
echo "========================================"
echo "Run:    $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
