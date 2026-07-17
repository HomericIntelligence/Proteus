#!/usr/bin/env bash
# Offline fail-safe tests for scripts/activate-merge-queue.sh (issue #214).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"
QUEUE_RULE="$REPO_ROOT/.github/rulesets/main-merge-queue.json"
SCRIPT="$REPO_ROOT/scripts/activate-merge-queue.sh"
REQUIRED_WORKFLOW="$REPO_ROOT/.github/workflows/_required.yml"
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT

make_shim() {
    local mode="$1" state_dir="$2"
    mkdir -p "$state_dir"
    printf '0\n' >"$state_dir/put-count"
    printf '0\n' >"$state_dir/target-get-count"
    printf '0\n' >"$state_dir/post-target-get-count"
    printf '0\n' >"$state_dir/rollback-target-get-count"
    printf '0\n' >"$state_dir/rulesets-get-count"
    printf '0\n' >"$state_dir/effective-get-count"
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
    printf '%s\n' "$input" >"$state_dir/put-${put_count}-input-path"
    cp "$input" "$state_dir/put-${put_count}.json"
    if [[ "$mode" == "term-during-put" && "$put_count" -eq 1 ]]; then
        kill -TERM "$PPID"
        sleep 0.1
    fi
    printf '{}\n'
    exit 0
fi

case "$endpoint" in
    'repos/HomericIntelligence/Proteus/rulesets?per_page=100&page=1')
        rulesets_get_count="$(<"$state_dir/rulesets-get-count")"
        rulesets_get_count=$((rulesets_get_count + 1))
        printf '%s\n' "$rulesets_get_count" >"$state_dir/rulesets-get-count"
        if [[ "$mode" == "preput-inventory-writer" \
            && "$put_count" -eq 0 && "$rulesets_get_count" -eq 2 ]]
        then
            cat "$fixtures/merge-queue-concurrent-inventory.json"
        elif [[ "$mode" == "inventory-drift" && "$put_count" -eq 1 ]]; then
            jq '.[0:1] | .[0].updated_at = "2026-07-17T01:30:00Z"' \
                "$fixtures/merge-queue-rulesets.json"
        elif [[ "$put_count" -eq 1 ]]; then
            jq '.[0].updated_at = "2026-07-17T01:30:00Z"' \
                "$fixtures/merge-queue-rulesets.json"
        else
            cat "$fixtures/merge-queue-rulesets.json"
        fi
        ;;
    repos/HomericIntelligence/Proteus/rulesets/15556490)
        target_get_count="$(<"$state_dir/target-get-count")"
        target_get_count=$((target_get_count + 1))
        printf '%s\n' "$target_get_count" >"$state_dir/target-get-count"
        post_target_get_count=0
        rollback_target_get_count=0
        if [[ "$put_count" -eq 1 ]]; then
            post_target_get_count="$(<"$state_dir/post-target-get-count")"
            post_target_get_count=$((post_target_get_count + 1))
            printf '%s\n' "$post_target_get_count" >"$state_dir/post-target-get-count"
        elif [[ "$put_count" -ge 2 ]]; then
            rollback_target_get_count="$(<"$state_dir/rollback-target-get-count")"
            rollback_target_get_count=$((rollback_target_get_count + 1))
            printf '%s\n' "$rollback_target_get_count" >"$state_dir/rollback-target-get-count"
        fi
        if [[ "$put_count" -eq 0 ]]; then
            if [[ "$mode" == "widened-scope" ]]; then
                jq --slurpfile scope "$fixtures/merge-queue-widened-scope.json" \
                    '.conditions = $scope[0]' "$fixtures/merge-queue-baseline.json"
            elif [[ "$mode" == "target-identity-mismatch" ]]; then
                jq '.source = "HomericIntelligence/Other"' \
                    "$fixtures/merge-queue-baseline.json"
            elif [[ "$mode" == "preput-target-writer" \
                && "$target_get_count" -eq 2 ]]
            then
                jq --slurpfile writer "$fixtures/merge-queue-concurrent-writer-rule.json" \
                    '.rules += $writer' "$fixtures/merge-queue-baseline.json"
            else
                cat "$fixtures/merge-queue-baseline.json"
            fi
        elif [[ "$put_count" -ge 2 ]]; then
            if [[ "$mode" == "rollback-get-failure" ]]; then
                exit 1
            elif [[ "$mode" == "rollback-readback-mismatch" \
                && "$rollback_target_get_count" -eq 1 ]]
            then
                jq '.enforcement = "evaluate"' \
                    "$fixtures/merge-queue-baseline.json"
                exit 0
            fi
            cat "$fixtures/merge-queue-baseline.json"
        elif [[ "$mode" == "stale-once" && "$post_target_get_count" -eq 1 ]]; then
            cat "$fixtures/merge-queue-baseline.json"
        elif [[ "$mode" == "term-after-put" && "$post_target_get_count" -eq 1 ]]; then
            kill -TERM "$PPID"
            sleep 0.1
            exit 1
        elif [[ "$mode" == "get-failure" && "$post_target_get_count" -le 2 ]]; then
            exit 1
        elif [[ "$mode" == "rollback-concurrent-writer" ]]; then
            jq --slurpfile queue "$queue_rule" \
                --slurpfile writer "$fixtures/merge-queue-concurrent-writer-rule.json" \
                '.rules += $queue | .rules += $writer' \
                "$fixtures/merge-queue-baseline.json"
        else
            jq --slurpfile queue "$queue_rule" '.rules += $queue' \
                "$fixtures/merge-queue-baseline.json"
        fi
        ;;
    'repos/HomericIntelligence/Proteus/rules/branches/main?per_page=100&page=1')
        effective_get_count="$(<"$state_dir/effective-get-count")"
        effective_get_count=$((effective_get_count + 1))
        printf '%s\n' "$effective_get_count" >"$state_dir/effective-get-count"
        if [[ "$put_count" -eq 0 ]]; then
            if [[ "$mode" == "sibling-queue" ]]; then
                jq '. as $base
                  | $base + [range(0; 100 - ($base | length)) | {
                      type: "mock_policy",
                      parameters: {mock_index: .},
                      ruleset_source_type: "Repository",
                      ruleset_source: "HomericIntelligence/Proteus",
                      ruleset_id: 18221113
                    }]
                ' "$fixtures/merge-queue-effective-before.json"
            elif [[ "$mode" == "required-context-mismatch" ]]; then
                jq '.[3].parameters.required_status_checks |= map(select(.context != "lint"))' \
                    "$fixtures/merge-queue-effective-before.json"
            elif [[ "$mode" == "preput-effective-writer" \
                && "$effective_get_count" -eq 2 ]]
            then
                jq '.[2].parameters.required_review_thread_resolution = false' \
                    "$fixtures/merge-queue-effective-before.json"
            else
                cat "$fixtures/merge-queue-effective-before.json"
            fi
        elif [[ "$put_count" -ge 2 ]]; then
            if [[ "$mode" == "rollback-readback-mismatch" ]]; then
                jq '.[3].parameters.required_status_checks[0].context = "broken-lint"' \
                    "$fixtures/merge-queue-effective-before.json"
            else
                cat "$fixtures/merge-queue-effective-before.json"
            fi
        elif [[ "$mode" == "context-drift" \
            || "$mode" == "rollback-get-failure" \
            || "$mode" == "rollback-readback-mismatch" ]]
        then
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
    'repos/HomericIntelligence/Proteus/rules/branches/main?per_page=100&page=2')
        if [[ "$mode" == "sibling-queue" && "$put_count" -eq 0 ]]; then
            cat "$fixtures/merge-queue-sibling-rule.json"
        else
            echo "mock gh: unexpected effective-state page 2" >&2
            exit 96
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
jq -e '.bypass_actors == [{
  actor_id: 5,
  actor_type: "RepositoryRole",
  bypass_mode: "pull_request"
}]' "$PLAN1" >/dev/null || {
    echo "FAIL case1c: dry-run payload did not preserve repository-role bypass"; exit 1;
}
awk '
  /^  integration-tests:$/ { in_job = 1; next }
  in_job && /^  [[:alnum:]_-]+:$/ { exit }
  in_job && index($0, "run: bash tests/merge-queue-activation.test.sh") { found = 1 }
  END { exit(found ? 0 : 1) }
' "$REQUIRED_WORKFLOW" || {
    echo "FAIL case1d: activation suite is not wired into required integration-tests"; exit 1;
}

# Case 2: successful activation performs one PUT and disarms rollback.
STATE2="$SHIM_DIR/state-2"
make_shim success "$STATE2"
run_script success "$STATE2" --apply >/dev/null
[[ "$(<"$STATE2/put-count")" == "1" ]] || {
    echo "FAIL case2: successful activation should perform exactly one PUT"; exit 1;
}
jq -e '.bypass_actors == [{
  actor_id: 5,
  actor_type: "RepositoryRole",
  bypass_mode: "pull_request"
}]' "$STATE2/put-1.json" >/dev/null || {
    echo "FAIL case2b: activation payload did not preserve repository-role bypass"; exit 1;
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
    "$STATE3/calls")" == "6" ]] || {
    echo "FAIL case3c: post-mutation GET retries or rollback GET missing"; exit 1;
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
jq -e '.bypass_actors == [{
  actor_id: 5,
  actor_type: "RepositoryRole",
  bypass_mode: "pull_request"
}]' "$STATE4/put-2.json" >/dev/null || {
    echo "FAIL case4c: rollback payload did not preserve repository-role bypass"; exit 1;
}
[[ ! -e "$(<"$STATE4/put-2-input-path")" ]] || {
    echo "FAIL case4d: verified rollback did not delete its recovery snapshot"; exit 1;
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
[[ "$(<"$STATE8/target-get-count")" == "4" ]] || {
    echo "FAIL case8b: stale target read-back was not retried"; exit 1;
}

# Case 9: a successful rollback PUT followed by unavailable rollback GETs is
# critical unverified recovery, not restoration, and preserves the snapshot.
STATE9="$SHIM_DIR/state-9"
ERR9="$SHIM_DIR/error-9"
make_shim rollback-get-failure "$STATE9"
if run_script rollback-get-failure "$STATE9" --apply >/dev/null 2>"$ERR9"; then
    echo "FAIL case9a: unavailable rollback verification must fail"; exit 1
fi
[[ "$(<"$STATE9/put-count")" == "2" ]] || {
    echo "FAIL case9b: rollback verification failure should not issue another PUT"; exit 1;
}
grep -q "CRITICAL: rollback could not be verified" "$ERR9" || {
    echo "FAIL case9c: unavailable rollback was not reported as critical"; cat "$ERR9"; exit 1;
}
! grep -q "Rollback restored" "$ERR9" || {
    echo "FAIL case9d: unavailable rollback was falsely reported as restored"; exit 1;
}
SNAPSHOT9="$(sed -n 's/^CRITICAL: recovery snapshot preserved at: //p' "$ERR9" | tail -n 1)"
[[ -n "$SNAPSHOT9" && -f "$SNAPSHOT9" ]] || {
    echo "FAIL case9e: unavailable rollback did not preserve a readable snapshot"; cat "$ERR9"; exit 1;
}
diff -u <(jq -S . "$SHIM_DIR/expected-rollback.json") \
    <(jq -S . "$SNAPSHOT9") || {
    echo "FAIL case9f: preserved snapshot differs from the pre-mutation payload"; exit 1;
}

# Case 10: a stale rollback target payload is retried, but the later target
# match plus effective-rule mismatch is still critical unverified recovery.
STATE10="$SHIM_DIR/state-10"
ERR10="$SHIM_DIR/error-10"
make_shim rollback-readback-mismatch "$STATE10"
if run_script rollback-readback-mismatch "$STATE10" --apply >/dev/null 2>"$ERR10"; then
    echo "FAIL case10a: mismatched rollback read-back must fail"; exit 1
fi
[[ "$(<"$STATE10/put-count")" == "2" ]] || {
    echo "FAIL case10b: rollback mismatch should not issue another PUT"; exit 1;
}
grep -q "CRITICAL: rollback could not be verified" "$ERR10" || {
    echo "FAIL case10c: rollback mismatch was not reported as critical"; cat "$ERR10"; exit 1;
}
grep -q "rollback target ruleset read-back differs" "$ERR10" || {
    echo "FAIL case10d: normalized rollback payload mismatch was not detected"; cat "$ERR10"; exit 1;
}
grep -q "rollback effective branch rules differ" "$ERR10" || {
    echo "FAIL case10e: effective rollback mismatch was not detected"; cat "$ERR10"; exit 1;
}
! grep -q "Rollback restored" "$ERR10" || {
    echo "FAIL case10f: rollback mismatch was falsely reported as restored"; exit 1;
}
SNAPSHOT10="$(sed -n 's/^CRITICAL: recovery snapshot preserved at: //p' "$ERR10" | tail -n 1)"
[[ -n "$SNAPSHOT10" && -f "$SNAPSHOT10" ]] || {
    echo "FAIL case10g: rollback mismatch did not preserve a readable snapshot"; cat "$ERR10"; exit 1;
}

# Case 11: an applicable sibling ruleset with a queue on effective-state page 2
# is combined and rejected before any mutation, including in dry-run planning.
STATE11="$SHIM_DIR/state-11"
make_shim sibling-queue "$STATE11"
if run_script sibling-queue "$STATE11" --dry-run >/dev/null 2>&1; then
    echo "FAIL case11a: sibling merge queue should fail closed"; exit 1
fi
[[ "$(<"$STATE11/put-count")" == "0" ]] || {
    echo "FAIL case11b: sibling merge queue performed a PUT"; exit 1;
}
grep -Fq \
    'api repos/HomericIntelligence/Proteus/rules/branches/main?per_page=100&page=2' \
    "$STATE11/calls" || {
        echo "FAIL case11c: effective-state page 2 was not fetched"; exit 1;
    }

# Case 12: a target widened beyond exactly refs/heads/main is rejected.
STATE12="$SHIM_DIR/state-12"
make_shim widened-scope "$STATE12"
if run_script widened-scope "$STATE12" --dry-run >/dev/null 2>&1; then
    echo "FAIL case12a: widened target scope should fail closed"; exit 1
fi
[[ "$(<"$STATE12/put-count")" == "0" ]] || {
    echo "FAIL case12b: widened target scope performed a PUT"; exit 1;
}

# Case 13: target identity must be the exact Proteus repository ruleset.
STATE13="$SHIM_DIR/state-13"
make_shim target-identity-mismatch "$STATE13"
if run_script target-identity-mismatch "$STATE13" --dry-run >/dev/null 2>&1; then
    echo "FAIL case13a: mismatched target identity should fail closed"; exit 1
fi

# Case 14: the effective required-context union must equal the 13-context live
# contract, not merely remain stable relative to an already-wrong snapshot.
STATE14="$SHIM_DIR/state-14"
make_shim required-context-mismatch "$STATE14"
if run_script required-context-mismatch "$STATE14" --dry-run >/dev/null 2>&1; then
    echo "FAIL case14a: required-context mismatch should fail closed"; exit 1
fi

# Case 15: a concurrent target writer between planning and PUT is detected by
# the immediate full-target re-fetch and prevents mutation.
STATE15="$SHIM_DIR/state-15"
make_shim preput-target-writer "$STATE15"
if run_script preput-target-writer "$STATE15" --apply >/dev/null 2>&1; then
    echo "FAIL case15a: pre-PUT target writer should fail closed"; exit 1
fi
[[ "$(<"$STATE15/put-count")" == "0" ]] || {
    echo "FAIL case15b: pre-PUT target writer was overwritten"; exit 1;
}

# Case 16: complete inventory comparison catches drift in a field omitted by
# the old reduced inventory projection.
STATE16="$SHIM_DIR/state-16"
make_shim preput-inventory-writer "$STATE16"
if run_script preput-inventory-writer "$STATE16" --apply >/dev/null 2>&1; then
    echo "FAIL case16a: pre-PUT inventory writer should fail closed"; exit 1
fi
[[ "$(<"$STATE16/put-count")" == "0" ]] || {
    echo "FAIL case16b: pre-PUT inventory writer was ignored"; exit 1;
}

# Case 17: complete effective-state comparison catches a concurrent policy
# change immediately before PUT.
STATE17="$SHIM_DIR/state-17"
make_shim preput-effective-writer "$STATE17"
if run_script preput-effective-writer "$STATE17" --apply >/dev/null 2>&1; then
    echo "FAIL case17a: pre-PUT effective-state writer should fail closed"; exit 1
fi
[[ "$(<"$STATE17/put-count")" == "0" ]] || {
    echo "FAIL case17b: pre-PUT effective-state writer was ignored"; exit 1;
}

# Case 18: if another writer changes the target after our PUT, rollback must
# refuse to overwrite that state and preserve the recovery payload.
STATE18="$SHIM_DIR/state-18"
ERR18="$SHIM_DIR/error-18"
make_shim rollback-concurrent-writer "$STATE18"
if run_script rollback-concurrent-writer "$STATE18" --apply >/dev/null 2>"$ERR18"; then
    echo "FAIL case18a: rollback contention should fail activation"; exit 1
fi
[[ "$(<"$STATE18/put-count")" == "1" ]] || {
    echo "FAIL case18b: rollback overwrote concurrent target state"; exit 1;
}
grep -q "refusing rollback PUT" "$ERR18" || {
    echo "FAIL case18c: rollback contention was not reported"; cat "$ERR18"; exit 1;
}
SNAPSHOT18="$(sed -n 's/^CRITICAL: recovery snapshot preserved at: //p' "$ERR18" | tail -n 1)"
[[ -n "$SNAPSHOT18" && -f "$SNAPSHOT18" ]] || {
    echo "FAIL case18d: rollback contention did not preserve recovery payload"; exit 1;
}

echo "OK: 18 merge-queue activation cases preserve policy and fail closed on concurrent changes"
