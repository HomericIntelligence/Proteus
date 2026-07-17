#!/usr/bin/env bash
# Safely activate Proteus's staged merge-queue rule on the live main ruleset.
# Read-only by default. Pass --apply only after this script is present on main.
set -euo pipefail

REPO="${REPO:-HomericIntelligence/Proteus}"
BRANCH="${BRANCH:-main}"
RULESET_NAME="${RULESET_NAME:-homeric-main-baseline}"
EXPECTED_REPO="HomericIntelligence/Proteus"
EXPECTED_BRANCH="main"
EXPECTED_RULESET_NAME="homeric-main-baseline"
VERIFY_ATTEMPTS="${MERGE_QUEUE_VERIFY_ATTEMPTS:-5}"
VERIFY_DELAY_SECONDS="${MERGE_QUEUE_VERIFY_DELAY_SECONDS:-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_RULE="${SCRIPT_DIR}/../.github/rulesets/main-merge-queue.json"

mode="${1:---dry-run}"
if [[ "$mode" != "--dry-run" && "$mode" != "--apply" ]]; then
    echo "Usage: $0 [--dry-run|--apply]" >&2
    exit 2
fi

for command in gh jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 2
    fi
done
if [[ ! -r "$QUEUE_RULE" ]]; then
    echo "Error: staged queue rule is missing or unreadable: $QUEUE_RULE" >&2
    exit 2
fi
if ! [[ "$VERIFY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MERGE_QUEUE_VERIFY_ATTEMPTS must be a positive integer" >&2
    exit 2
fi
if ! [[ "$VERIFY_DELAY_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: MERGE_QUEUE_VERIFY_DELAY_SECONDS must be a non-negative number" >&2
    exit 2
fi

work_dir="$(mktemp -d)"
rulesets_before="$work_dir/rulesets-before.json"
rulesets_after="$work_dir/rulesets-after.json"
target_before="$work_dir/target-before.json"
target_preput="$work_dir/target-preput.json"
target_after="$work_dir/target-after.json"
rollback_guard_target="$work_dir/rollback-guard-target.json"
rollback_guard_writable="$work_dir/rollback-guard-writable.json"
rollback_target_after="$work_dir/rollback-target-after.json"
rollback_target_writable="$work_dir/rollback-target-writable.json"
rollback_payload="$work_dir/rollback.json"
desired_payload="$work_dir/desired.json"
effective_before="$work_dir/effective-before.json"
effective_preput="$work_dir/effective-preput.json"
effective_after="$work_dir/effective-after.json"
rollback_effective_after="$work_dir/rollback-effective-after.json"
expected_effective_after="$work_dir/effective-expected.json"
rulesets_preput="$work_dir/rulesets-preput.json"
rollback_armed=0
target_endpoint=""

rollback_on_exit() {
    local status=$?
    local preserve_recovery=0
    local rollback_verified=0
    local attempt
    trap - EXIT INT TERM
    if [[ "$rollback_armed" -eq 1 ]]; then
        rollback_armed=0
        echo "Activation failed after mutation; checking whether rollback is still safe." >&2
        if ! api_get_with_retry "$target_endpoint" "$rollback_guard_target" \
            "rollback guard target ruleset"
        then
            echo "CRITICAL: live target state is unavailable; refusing rollback PUT." >&2
            status=1
            preserve_recovery=1
        else
            writable_ruleset_payload "$rollback_guard_target" >"$rollback_guard_writable"
            if [[ "$(jq -Sc . "$desired_payload")" != \
                "$(jq -Sc . "$rollback_guard_writable")" ]]
            then
                echo "CRITICAL: live target no longer equals the attempted desired state; refusing rollback PUT." >&2
                status=1
                preserve_recovery=1
            elif gh api --method PUT "$target_endpoint" \
                --input "$rollback_payload" >/dev/null
            then
                for ((attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt++)); do
                    if verify_rollback_once; then
                        rollback_verified=1
                        break
                    fi
                    echo "WARN: rollback verification incomplete (attempt $attempt/$VERIFY_ATTEMPTS)." >&2
                    if ((attempt < VERIFY_ATTEMPTS)); then
                        sleep "$VERIFY_DELAY_SECONDS"
                    fi
                done
                if [[ "$rollback_verified" -eq 1 ]]; then
                    echo "Rollback restored the pre-activation target ruleset payload, effective rules, and required contexts." >&2
                else
                    echo "CRITICAL: rollback could not be verified; live ruleset state requires operator review." >&2
                    status=1
                    preserve_recovery=1
                fi
            else
                echo "CRITICAL: rollback PUT failed; live ruleset state requires operator review." >&2
                status=1
                preserve_recovery=1
            fi
        fi
    fi
    if [[ "$preserve_recovery" -eq 1 ]]; then
        echo "CRITICAL: recovery snapshot preserved at: $rollback_payload" >&2
    else
        rm -rf "$work_dir"
    fi
    exit "$status"
}
trap rollback_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

api_get_with_retry() {
    local endpoint="$1"
    local output="$2"
    local label="$3"
    local attempt

    for ((attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt++)); do
        if gh api "$endpoint" >"$output"; then
            return 0
        fi
        echo "WARN: $label GET failed (attempt $attempt/$VERIFY_ATTEMPTS)." >&2
        if ((attempt < VERIFY_ATTEMPTS)); then
            sleep "$VERIFY_DELAY_SECONDS"
        fi
    done
    echo "Error: $label GET failed after $VERIFY_ATTEMPTS attempts." >&2
    return 1
}

api_get_paginated_array_with_retry() {
    local endpoint="$1"
    local output="$2"
    local label="$3"
    local page=1
    local page_count
    local page_output
    local combined

    page_output="$(mktemp "$work_dir/paginated-page.XXXXXX")"
    combined="$(mktemp "$work_dir/paginated-combined.XXXXXX")"
    : >"$combined"

    while true; do
        if ! api_get_with_retry "${endpoint}&page=${page}" "$page_output" \
            "$label page $page"
        then
            return 1
        fi
        if ! jq -e '
          type == "array"
          and length <= 100
          and all(.[]; type == "object")
        ' "$page_output" >/dev/null
        then
            echo "Error: $label page $page was not an array of at most 100 objects." >&2
            return 1
        fi

        jq -c '.[]' "$page_output" >>"$combined"
        page_count="$(jq 'length' "$page_output")"
        if [[ "$page_count" -lt 100 ]]; then
            break
        fi
        if [[ "$page" -ge 1000 ]]; then
            echo "Error: $label exceeded the 1000-page safety limit." >&2
            return 1
        fi
        page=$((page + 1))
    done

    jq -sc '.' "$combined" >"$output"
}

normalize_ruleset_inventory() {
    jq -Sc 'sort_by(.id)' "$1"
}

normalize_postput_ruleset_inventory() {
    jq -Sc --argjson target_id "$target_id" '
      map(if .id == $target_id then del(.updated_at) else . end)
      | sort_by(.id)
    ' "$1"
}

normalize_effective_rules() {
    jq -Sc 'sort_by(.ruleset_id, .type, ((.parameters // {}) | tostring))' "$1"
}

required_contexts() {
    jq -Sc '[.[]
      | select(.type == "required_status_checks")
      | .parameters.required_status_checks[]
      | {context, integration_id}]
      | sort_by(.context, .integration_id)' "$1"
}

expected_required_contexts() {
    jq -ncS '[
      {context: "Lint Shell Scripts", integration_id: 15368},
      {context: "build", integration_id: 15368},
      {context: "deps/version-sync", integration_id: 15368},
      {context: "install", integration_id: 15368},
      {context: "integration-tests", integration_id: 15368},
      {context: "lint", integration_id: 15368},
      {context: "package", integration_id: 15368},
      {context: "release", integration_id: 15368},
      {context: "schema-validation", integration_id: 15368},
      {context: "security/dependency-scan", integration_id: 15368},
      {context: "security/secrets-scan", integration_id: 15368},
      {context: "test", integration_id: 15368},
      {context: "unit-tests", integration_id: 15368}
    ] | sort_by(.context, .integration_id)'
}

writable_ruleset_payload() {
    jq '{
      name,
      target,
      enforcement,
      bypass_actors: (.bypass_actors // []),
      conditions,
      rules
    }' "$1"
}

validate_live_contract() {
    local inventory="$1"
    local target="$2"
    local effective="$3"
    local target_id="$4"

    if ! jq -e \
        --arg repo "$EXPECTED_REPO" \
        --arg name "$EXPECTED_RULESET_NAME" \
        --arg ref "refs/heads/$EXPECTED_BRANCH" \
        --argjson id "$target_id" '
          .id == $id
          and .name == $name
          and .target == "branch"
          and .source_type == "Repository"
          and .source == $repo
          and .enforcement == "active"
          and .conditions == {
            ref_name: {exclude: [], include: [$ref]}
          }
          and any((.bypass_actors // [])[];
            .actor_id == 5
            and .actor_type == "RepositoryRole"
            and .bypass_mode == "pull_request")
        ' "$target" >/dev/null
    then
        echo "Error: target ruleset identity, main-only scope, or repository-role bypass does not match the activation contract." >&2
        return 1
    fi

    if [[ "$(jq -r --arg name "$EXPECTED_RULESET_NAME" \
        --argjson id "$target_id" '
          [.[] | select(
            .id == $id
            and .name == $name
            and .target == "branch"
            and .source_type == "Repository"
            and .enforcement == "active"
          )] | length
        ' "$inventory")" -ne 1 ]]
    then
        echo "Error: target ruleset inventory identity changed or is ambiguous." >&2
        return 1
    fi

    if [[ "$(required_contexts "$effective")" != \
        "$(expected_required_contexts)" ]]
    then
        echo "Error: effective required contexts do not match Proteus's exact 13-context contract." >&2
        return 1
    fi

    if [[ "$(jq '[.[] | select(.type == "merge_queue")] | length' \
        "$effective")" -ne 0 ]]
    then
        echo "Error: an applicable ruleset already supplies a merge_queue rule; refusing layered activation." >&2
        return 1
    fi
}

verify_preput_snapshot() {
    api_get_with_retry "$target_endpoint" "$target_preput" \
        "pre-PUT target ruleset"
    api_get_paginated_array_with_retry "$rulesets_endpoint" "$rulesets_preput" \
        "pre-PUT ruleset inventory"
    api_get_paginated_array_with_retry "$effective_endpoint" "$effective_preput" \
        "pre-PUT effective branch rules"

    if [[ "$(jq -Sc . "$target_before")" != \
        "$(jq -Sc . "$target_preput")" ]]
    then
        echo "Error: target ruleset changed concurrently before PUT." >&2
        return 1
    fi
    if [[ "$(normalize_ruleset_inventory "$rulesets_before")" != \
        "$(normalize_ruleset_inventory "$rulesets_preput")" ]]
    then
        echo "Error: ruleset inventory changed concurrently before PUT." >&2
        return 1
    fi
    if [[ "$(normalize_effective_rules "$effective_before")" != \
        "$(normalize_effective_rules "$effective_preput")" ]]
    then
        echo "Error: effective branch rules changed concurrently before PUT." >&2
        return 1
    fi

    validate_live_contract "$rulesets_preput" "$target_preput" \
        "$effective_preput" "$target_id"
}

verify_rollback_once() {
    if ! gh api "$target_endpoint" >"$rollback_target_after"; then
        echo "WARN: rollback target ruleset GET failed." >&2
        return 1
    fi
    writable_ruleset_payload "$rollback_target_after" >"$rollback_target_writable"
    if [[ "$(jq -Sc . "$rollback_payload")" != \
        "$(jq -Sc . "$rollback_target_writable")" ]]
    then
        echo "WARN: rollback target ruleset read-back differs from the recovery payload." >&2
        return 1
    fi

    if ! api_get_paginated_array_with_retry "$effective_endpoint" \
        "$rollback_effective_after" "rollback effective branch rules"
    then
        echo "WARN: rollback effective branch rules GET failed." >&2
        return 1
    fi
    if [[ "$(normalize_effective_rules "$effective_before")" != \
        "$(normalize_effective_rules "$rollback_effective_after")" ]]
    then
        echo "WARN: rollback effective branch rules differ from their pre-mutation state." >&2
        return 1
    fi
    if [[ "$(required_contexts "$effective_before")" != \
        "$(required_contexts "$rollback_effective_after")" ]]
    then
        echo "WARN: rollback required contexts differ from their pre-mutation state." >&2
        return 1
    fi
}

verify_postconditions_once() {
    if ! gh api "$target_endpoint" >"$target_after"; then
        echo "WARN: post-mutation target ruleset GET failed." >&2
        return 1
    fi
    writable_ruleset_payload "$target_after" >"$work_dir/target-after-writable.json"
    if ! diff -u <(jq -S . "$desired_payload") \
        <(jq -S . "$work_dir/target-after-writable.json") >/dev/null
    then
        echo "WARN: target ruleset read-back has not reached the requested state." >&2
        return 1
    fi

    if ! api_get_paginated_array_with_retry "$rulesets_endpoint" \
        "$rulesets_after" "post-mutation ruleset inventory"
    then
        echo "WARN: post-mutation ruleset inventory GET failed." >&2
        return 1
    fi
    # PUT legitimately advances the target summary's updated_at. Compare every
    # other inventory field, including every field on sibling rulesets.
    if [[ "$(normalize_postput_ruleset_inventory "$rulesets_before")" != \
        "$(normalize_postput_ruleset_inventory "$rulesets_after")" ]]
    then
        echo "WARN: live ruleset inventory differs from its pre-mutation state." >&2
        return 1
    fi

    if ! api_get_paginated_array_with_retry "$effective_endpoint" \
        "$effective_after" "post-mutation effective branch rules"
    then
        echo "WARN: post-mutation effective branch rules GET failed." >&2
        return 1
    fi
    if [[ "$(normalize_effective_rules "$expected_effective_after")" != \
        "$(normalize_effective_rules "$effective_after")" ]]
    then
        echo "WARN: effective branch state has not reached the expected state." >&2
        return 1
    fi
    if [[ "$(required_contexts "$effective_before")" != \
        "$(required_contexts "$effective_after")" ]]
    then
        echo "WARN: required status-check contexts differ from their pre-mutation state." >&2
        return 1
    fi
}

rulesets_endpoint="repos/${REPO}/rulesets?per_page=100"
effective_endpoint="repos/${REPO}/rules/branches/${BRANCH}?per_page=100"
if [[ "$REPO" != "$EXPECTED_REPO" \
    || "$BRANCH" != "$EXPECTED_BRANCH" \
    || "$RULESET_NAME" != "$EXPECTED_RULESET_NAME" ]]
then
    echo "Error: activation is pinned to ${EXPECTED_REPO}@${EXPECTED_BRANCH} ruleset ${EXPECTED_RULESET_NAME}." >&2
    exit 1
fi
api_get_paginated_array_with_retry "$rulesets_endpoint" "$rulesets_before" \
    "ruleset inventory"

target_id="$(jq -er --arg name "$RULESET_NAME" '
  [.[] | select(
    .name == $name
    and .target == "branch"
    and .source_type == "Repository"
    and .enforcement == "active"
  )]
  | if length == 1 then .[0].id
    else error("expected exactly one active repository ruleset named " + $name)
    end
' "$rulesets_before")"
target_endpoint="repos/${REPO}/rulesets/${target_id}"

api_get_with_retry "$target_endpoint" "$target_before" "target ruleset"
api_get_paginated_array_with_retry "$effective_endpoint" "$effective_before" \
    "effective branch rules"

validate_live_contract "$rulesets_before" "$target_before" \
    "$effective_before" "$target_id"

writable_ruleset_payload "$target_before" >"$rollback_payload"

queue_count="$(jq '[.rules[] | select(.type == "merge_queue")] | length' \
    "$rollback_payload")"
if [[ "$queue_count" -ne 0 ]]; then
    echo "Error: $RULESET_NAME already contains a merge_queue rule; refusing to replace it." >&2
    exit 1
fi

jq --slurpfile queue "$QUEUE_RULE" '.rules += $queue' \
    "$rollback_payload" >"$desired_payload"

jq --slurpfile queue "$QUEUE_RULE" \
    --arg repo "$REPO" \
    --argjson target_id "$target_id" \
    '. + [($queue[0] + {
      ruleset_source_type: "Repository",
      ruleset_source: $repo,
      ruleset_id: $target_id
    })]' "$effective_before" >"$expected_effective_after"

if [[ "$mode" == "--dry-run" ]]; then
    jq . "$desired_payload"
    echo "Dry run only: no live ruleset mutation performed." >&2
    exit 0
fi

# GitHub's ruleset API does not expose a transaction across the target,
# inventory, and effective state. Re-read all three immediately before PUT and
# require exact equality with the snapshots used to build the desired payload.
verify_preput_snapshot

# Arm rollback before the first mutating request. On any subsequent failure,
# including an ambiguous PUT response or failed read-back, the EXIT trap first
# proves the live target still equals our desired payload before restoring the
# exact pre-mutation payload.
rollback_armed=1
gh api --method PUT "$target_endpoint" --input "$desired_payload" >/dev/null

postconditions_verified=0
for ((attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt++)); do
    if verify_postconditions_once; then
        postconditions_verified=1
        break
    fi
    echo "WARN: post-mutation verification incomplete (attempt $attempt/$VERIFY_ATTEMPTS)." >&2
    if ((attempt < VERIFY_ATTEMPTS)); then
        sleep "$VERIFY_DELAY_SECONDS"
    fi
done
if [[ "$postconditions_verified" -ne 1 ]]; then
    echo "Error: post-mutation verification failed after $VERIFY_ATTEMPTS attempts." >&2
    exit 1
fi

# All target, inventory, effective-state, and context postconditions passed.
# Only now is automatic rollback disarmed.
rollback_armed=0
echo "Merge queue activated on ${REPO}@${BRANCH}; all live rulesets and required contexts were preserved."
