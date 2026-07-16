#!/usr/bin/env bash
# Offline fail-safe tests for scripts/activate-merge-queue.sh (issue #214).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"
QUEUE_RULE="$REPO_ROOT/.github/rulesets/main-merge-queue.json"
SCRIPT="$REPO_ROOT/scripts/activate-merge-queue.sh"
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT

make_shim() {
    local mode="$1" state_dir="$2"
    mkdir -p "$state_dir"
    printf '0\n' >"$state_dir/put-count"
    printf '0\n' >"$state_dir/target-get-count"
    : >"$state_dir/calls"

    cat >"$SHIM_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

mode="${MOCK_MODE:?}"
state_dir="${MOCK_STATE_DIR:?}"
fixtures="${MOCK_FIXTURES:?}"
queue_rule="${MOCK_QUEUE_RULE:?}"
printf '%s\n' "$*" >>"$state_dir/calls"

[[ "${1:-}" == "api" ]] || exit 98
shift
method="GET"
endpoint=""
input=""
while (($#)); do
    case "$1" in
        --method|-X)
            method="$2"; shift 2 ;;
        --input)
            input="$2"; shift 2 ;;
        -H|--header)
            shift 2 ;;
        --paginate)
            shift ;;
        *)
            endpoint="$1"; shift ;;
    esac
done

put_count="$(<"$state_dir/put-count")"
if [[ "$method" == "PUT" ]]; then
    put_count=$((put_count + 1))
    printf '%s\n' "$put_count" >"$state_dir/put-count"
    cp "$input" "$state_dir/put-${put_count}.json"
    if [[ "$mode" == "term-during-put" && "$put_count" -eq 1 ]]; then
        kill -TERM "$PPID"
        sleep 0.1
    fi
    printf '{}\n'
    exit 0
fi

case "$endpoint" in
    'repos/HomericIntelligence/Proteus/rulesets?per_page=100')
        if [[ "$mode" == "inventory-drift" && "$put_count" -eq 1 ]]; then
            jq '.[0:1]' "$fixtures/merge-queue-rulesets.json"
        else
            cat "$fixtures/merge-queue-rulesets.json"
        fi
        ;;
    repos/HomericIntelligence/Proteus/rulesets/15556490)
        target_get_count="$(<"$state_dir/target-get-count")"
        target_get_count=$((target_get_count + 1))
        printf '%s\n' "$target_get_count" >"$state_dir/target-get-count"
        if [[ "$put_count" -eq 0 || "$put_count" -ge 2 ]]; then
            cat "$fixtures/merge-queue-baseline.json"
        elif [[ "$mode" == "stale-once" && "$target_get_count" -eq 2 ]]; then
            cat "$fixtures/merge-queue-baseline.json"
        elif [[ "$mode" == "term-after-put" ]]; then
            kill -TERM "$PPID"
            sleep 0.1
            exit 1
        elif [[ "$mode" == "get-failure" ]]; then
            exit 1
        else
            jq --slurpfile queue "$queue_rule" '.rules += $queue' \
                "$fixtures/merge-queue-baseline.json"
        fi
        ;;
    repos/HomericIntelligence/Proteus/rules/branches/main)
        if [[ "$put_count" -eq 0 || "$put_count" -ge 2 ]]; then
            cat "$fixtures/merge-queue-effective-before.json"
        elif [[ "$mode" == "context-drift" ]]; then
            jq --slurpfile queue "$queue_rule" '
              .[3].parameters.required_status_checks[0].context = "broken-lint"
              | . + [($queue[0] + {
                  ruleset_source_type: "Repository",
                  ruleset_source: "HomericIntelligence/Proteus",
                  ruleset_id: 15556490
                })]
            ' "$fixtures/merge-queue-effective-before.json"
        else
            jq --slurpfile queue "$queue_rule" '. + [($queue[0] + {
              ruleset_source_type: "Repository",
              ruleset_source: "HomericIntelligence/Proteus",
              ruleset_id: 15556490
            })]' "$fixtures/merge-queue-effective-before.json"
        fi
        ;;
    *)
        echo "mock gh: unhandled endpoint $endpoint" >&2
        exit 97
        ;;
esac
SHIM
    chmod +x "$SHIM_DIR/gh"
}

run_script() {
    local mode="$1" state_dir="$2"
    shift 2
    PATH="$SHIM_DIR:$PATH" \
        MOCK_MODE="$mode" \
        MOCK_STATE_DIR="$state_dir" \
        MOCK_FIXTURES="$FIXTURES" \
        MOCK_QUEUE_RULE="$QUEUE_RULE" \
        MERGE_QUEUE_VERIFY_ATTEMPTS=2 \
        MERGE_QUEUE_VERIFY_DELAY_SECONDS=0 \
        "$SCRIPT" "$@"
}

# Case 1: planning is read-only and includes the exact staged queue rule.
STATE1="$SHIM_DIR/state-1"
PLAN1="$SHIM_DIR/plan-1.json"
make_shim success "$STATE1"
run_script success "$STATE1" --dry-run >"$PLAN1"
[[ "$(<"$STATE1/put-count")" == "0" ]] || {
    echo "FAIL case1a: dry-run performed a PUT"; exit 1;
}
jq -e --slurpfile queue "$QUEUE_RULE" \
    '[.rules[] | select(.type == "merge_queue")] == $queue' "$PLAN1" >/dev/null || {
    echo "FAIL case1b: dry-run payload omitted or changed queue policy"; exit 1;
}

# Case 2: successful activation performs one PUT and disarms rollback.
STATE2="$SHIM_DIR/state-2"
make_shim success "$STATE2"
run_script success "$STATE2" --apply >/dev/null
[[ "$(<"$STATE2/put-count")" == "1" ]] || {
    echo "FAIL case2: successful activation should perform exactly one PUT"; exit 1;
}

# Case 3: PUT succeeds but every read-back GET fails; rollback must PUT the
# exact pre-mutation writable payload before the script exits non-zero.
STATE3="$SHIM_DIR/state-3"
ERR3="$SHIM_DIR/error-3"
make_shim get-failure "$STATE3"
if run_script get-failure "$STATE3" --apply >/dev/null 2>"$ERR3"; then
    echo "FAIL case3a: read-back failure should fail activation"; exit 1
fi
[[ "$(<"$STATE3/put-count")" == "2" ]] || {
    echo "FAIL case3b: PUT-success/GET-failure did not trigger rollback PUT"; exit 1;
}
[[ "$(grep -c '^api repos/HomericIntelligence/Proteus/rulesets/15556490$' \
    "$STATE3/calls")" == "3" ]] || {
    echo "FAIL case3c: post-mutation GET was not retried twice"; exit 1;
}
jq '{name, target, enforcement, bypass_actors: (.bypass_actors // []), conditions, rules}' \
    "$FIXTURES/merge-queue-baseline.json" >"$SHIM_DIR/expected-rollback.json"
diff -u <(jq -S . "$SHIM_DIR/expected-rollback.json") \
    <(jq -S . "$STATE3/put-2.json") || {
    echo "FAIL case3d: rollback payload differs from the pre-mutation ruleset"; exit 1;
}
grep -q "rollback" "$ERR3" || {
    echo "FAIL case3e: failure output did not report rollback"; cat "$ERR3"; exit 1;
}

# Case 4: effective branch-state drift, including required-context drift,
# invalidates activation and restores the original target ruleset.
STATE4="$SHIM_DIR/state-4"
make_shim context-drift "$STATE4"
if run_script context-drift "$STATE4" --apply >/dev/null 2>&1; then
    echo "FAIL case4a: effective required-context drift should fail"; exit 1
fi
[[ "$(<"$STATE4/put-count")" == "2" ]] || {
    echo "FAIL case4b: effective-state drift did not trigger rollback"; exit 1;
}

# Case 5: every live ruleset must remain present after activation.
STATE5="$SHIM_DIR/state-5"
make_shim inventory-drift "$STATE5"
if run_script inventory-drift "$STATE5" --apply >/dev/null 2>&1; then
    echo "FAIL case5a: ruleset inventory drift should fail"; exit 1
fi
[[ "$(<"$STATE5/put-count")" == "2" ]] || {
    echo "FAIL case5b: ruleset inventory drift did not trigger rollback"; exit 1;
}

# Case 6: interruption after mutation rolls back and must not report success.
STATE6="$SHIM_DIR/state-6"
make_shim term-after-put "$STATE6"
if run_script term-after-put "$STATE6" --apply >/dev/null 2>&1; then
    echo "FAIL case6a: interrupted activation must exit non-zero"; exit 1
fi
[[ "$(<"$STATE6/put-count")" == "2" ]] || {
    echo "FAIL case6b: interrupted activation did not trigger rollback"; exit 1;
}

# Case 7: a signal delivered while the mutating PUT returns successfully still
# rolls back and exits non-zero rather than masking the interruption.
STATE7="$SHIM_DIR/state-7"
make_shim term-during-put "$STATE7"
if run_script term-during-put "$STATE7" --apply >/dev/null 2>&1; then
    echo "FAIL case7a: signal during successful PUT must exit non-zero"; exit 1
fi
[[ "$(<"$STATE7/put-count")" == "2" ]] || {
    echo "FAIL case7b: signal during successful PUT did not trigger rollback"; exit 1;
}

# Case 8: a successful but stale first read-back is retried before rollback.
STATE8="$SHIM_DIR/state-8"
make_shim stale-once "$STATE8"
run_script stale-once "$STATE8" --apply >/dev/null
[[ "$(<"$STATE8/put-count")" == "1" ]] || {
    echo "FAIL case8a: transient stale read-back should not trigger rollback"; exit 1;
}
[[ "$(<"$STATE8/target-get-count")" == "3" ]] || {
    echo "FAIL case8b: stale target read-back was not retried"; exit 1;
}

echo "OK: merge-queue activation is read-only by default and fail-safe on post-PUT failures"
