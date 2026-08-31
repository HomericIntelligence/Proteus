"""Regression coverage for the main-branch merge-queue rollout (issue #214)."""

from __future__ import annotations

import ast
import json
import os
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]

# Effective rules on 2026-07-16 are split across homeric-main-baseline
# (15556490) and homeric-main-extras (18221113). Every required context must
# remain attached to a workflow that validates both PR and merge-group SHAs.
REQUIRED_CONTEXTS_BY_WORKFLOW = {
    ".github/workflows/_required.yml": {
        "lint",
        "unit-tests",
        "integration-tests",
        "security/dependency-scan",
        "security/secrets-scan",
        "build",
        "schema-validation",
        "deps/version-sync",
        "test",
        "package",
        "install",
        "required-checks-gate",
    },
    ".github/workflows/ci.yml": {"Lint Shell Scripts"},
    ".github/workflows/release.yml": {"release"},
}

REQUIRED_GATE_JOB_ID = "required-checks-gate"

# Every job in _required.yml is a gating validator. Keep this set explicit so
# a new job cannot silently bypass the aggregate. A future informational job
# must be classified separately and must not appear in the gate's needs list.
GATING_JOB_IDS = frozenset(
    {
        "branch-protection-test",
        "build",
        "deps-version-sync",
        "forbid-suppressions",
        "install",
        "integration-tests",
        "justfile-check",
        "lint",
        "markdownlint",
        "package",
        "pixi-check",
        "schema-validation",
        "security-dependency-scan",
        "security-npm-audit",
        "security-secrets-scan",
        "symlink-check",
        "test",
        "unit-tests",
        "version-consistency",
    }
)
INFORMATIONAL_JOB_IDS = frozenset()

EXPECTED_QUEUE_RULE = {
    "type": "merge_queue",
    "parameters": {
        "check_response_timeout_minutes": 60,
        "grouping_strategy": "ALLGREEN",
        "max_entries_to_build": 10,
        "max_entries_to_merge": 5,
        "merge_method": "SQUASH",
        "min_entries_to_merge": 1,
        "min_entries_to_merge_wait_minutes": 5,
    },
}


def _load_workflow(path: str) -> dict[str, object]:
    """Load Actions YAML without YAML 1.1 coercing the ``on`` key to bool."""

    return yaml.load((ROOT / path).read_text(), Loader=yaml.BaseLoader)


def _job_contexts(workflow: dict[str, object]) -> set[str]:
    jobs = workflow["jobs"]
    assert isinstance(jobs, dict)
    contexts: set[str] = set()
    for job_id, job in jobs.items():
        if not isinstance(job_id, str) or not isinstance(job, dict):
            continue
        job_name = job.get("name")
        contexts.add(job_name if isinstance(job_name, str) else job_id)
    return contexts


def _required_gate_step() -> dict[str, object]:
    workflow = _load_workflow(".github/workflows/_required.yml")
    jobs = workflow["jobs"]
    assert isinstance(jobs, dict)
    assert REQUIRED_GATE_JOB_ID in jobs, "required-checks-gate job is missing"
    gate = jobs[REQUIRED_GATE_JOB_ID]
    assert isinstance(gate, dict)
    steps = gate["steps"]
    assert isinstance(steps, list)
    assert len(steps) == 1
    step = steps[0]
    assert isinstance(step, dict)
    return step


def _run_required_gate(
    results: dict[str, dict[str, str]],
) -> subprocess.CompletedProcess[str]:
    step = _required_gate_step()
    script = step["run"]
    assert isinstance(script, str)
    step_env = step["env"]
    assert isinstance(step_env, dict)
    expected_needs_json = step_env["EXPECTED_NEEDS_JSON"]
    assert isinstance(expected_needs_json, str)
    return subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        env={
            **os.environ,
            "EXPECTED_NEEDS_JSON": expected_needs_json,
            "NEEDS_JSON": json.dumps(results),
        },
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )


def _assert_required_workflow_ready(
    workflow: dict[str, object], path: str, required_contexts: set[str]
) -> None:
    """Assert one required-context workflow is safe for queued merge groups."""

    triggers = workflow["on"]
    assert isinstance(triggers, dict)
    assert "push" in triggers, f"{path} must preserve push behavior"
    assert "pull_request" in triggers, f"{path} must preserve pull_request behavior"
    assert triggers.get("merge_group") == {"types": ["checks_requested"]}

    missing = required_contexts - _job_contexts(workflow)
    assert not missing, (
        f"{path} no longer supplies required contexts: {sorted(missing)}"
    )


@pytest.mark.parametrize(
    ("path", "required_contexts"), REQUIRED_CONTEXTS_BY_WORKFLOW.items()
)
def test_required_context_workflows_support_merge_groups(
    path: str, required_contexts: set[str]
) -> None:
    workflow = _load_workflow(path)
    _assert_required_workflow_ready(workflow, path, required_contexts)


def test_required_workflow_guard_detects_missing_merge_group() -> None:
    synthetic = {
        "on": {"push": {}, "pull_request": {}},
        "jobs": {"lint": {"name": "lint"}},
    }
    with pytest.raises(AssertionError):
        _assert_required_workflow_ready(synthetic, "synthetic.yml", {"lint"})


def test_required_checks_gate_is_complete_read_only_and_bounded() -> None:
    workflow_text = (ROOT / ".github/workflows/_required.yml").read_text()
    workflow_lines = workflow_text.splitlines()
    assert workflow_lines.count(f"  {REQUIRED_GATE_JOB_ID}:") == 1
    assert workflow_lines.count(f"    name: {REQUIRED_GATE_JOB_ID}") == 1

    workflow = _load_workflow(".github/workflows/_required.yml")
    jobs = workflow["jobs"]
    assert isinstance(jobs, dict)

    expected_job_ids = GATING_JOB_IDS | INFORMATIONAL_JOB_IDS | {REQUIRED_GATE_JOB_ID}
    assert set(jobs) == expected_job_ids
    gate_names = [
        job.get("name")
        for job in jobs.values()
        if isinstance(job, dict) and job.get("name") == REQUIRED_GATE_JOB_ID
    ]
    assert gate_names == [REQUIRED_GATE_JOB_ID]

    gate = jobs[REQUIRED_GATE_JOB_ID]
    assert isinstance(gate, dict)
    assert set(gate) == {
        "name",
        "runs-on",
        "timeout-minutes",
        "permissions",
        "if",
        "needs",
        "steps",
    }
    assert gate["name"] == REQUIRED_GATE_JOB_ID
    assert gate["if"] == "${{ always() }}"
    assert gate["permissions"] == {"contents": "read"}
    assert 0 < int(gate["timeout-minutes"]) <= 5

    needs = gate["needs"]
    assert isinstance(needs, list)
    assert set(needs) == GATING_JOB_IDS
    assert len(needs) == len(GATING_JOB_IDS)
    assert set(needs).isdisjoint(INFORMATIONAL_JOB_IDS)

    step = _required_gate_step()
    assert set(step) == {"name", "env", "run"}
    env = step["env"]
    assert isinstance(env, dict)
    assert set(env) == {"EXPECTED_NEEDS_JSON", "NEEDS_JSON"}
    assert env["NEEDS_JSON"] == "${{ toJson(needs) }}"
    assert json.loads(env["EXPECTED_NEEDS_JSON"]) == sorted(GATING_JOB_IDS)

    script = step["run"]
    assert isinstance(script, str)
    python_prefix = "set -euo pipefail\npython3 - <<'PY'\n"
    python_suffix = "\nPY\n"
    assert script.startswith(python_prefix)
    assert script.endswith(python_suffix)
    python_tree = ast.parse(script[len(python_prefix) : -len(python_suffix)])
    imported_modules = {
        alias.name
        for node in ast.walk(python_tree)
        if isinstance(node, ast.Import)
        for alias in node.names
    }
    assert imported_modules == {"json", "os", "sys"}
    assert not any(isinstance(node, ast.ImportFrom) for node in ast.walk(python_tree))
    assert {
        node.attr
        for node in ast.walk(python_tree)
        if isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id == "os"
    } == {"environ"}

    lowered_script = script.lower()
    for forbidden in (
        "actions/checkout",
        "artifact",
        "cache",
        "curl ",
        "github.token",
        "git ",
        "http://",
        "https://",
        "npm ",
        "pip ",
        "pixi ",
        "secret",
        "uses:",
        "wget ",
    ):
        assert forbidden not in lowered_script


@pytest.mark.parametrize(
    ("case", "overrides", "missing_job", "expected_success"),
    [
        ("all-success", {}, None, True),
        ("failed", {"lint": "failure"}, None, False),
        ("cancelled", {"build": "cancelled"}, None, False),
        ("skipped", {"install": "skipped"}, None, False),
        ("missing-result", {"schema-validation": None}, None, False),
        ("missing-job", {}, "schema-validation", False),
        ("unknown", {"unit-tests": "unexpected"}, None, False),
    ],
)
def test_required_checks_gate_fails_closed_for_real_needs_results(
    case: str,
    overrides: dict[str, str | None],
    missing_job: str | None,
    expected_success: bool,
) -> None:
    results = {job_id: {"result": "success"} for job_id in GATING_JOB_IDS}
    for job_id, result in overrides.items():
        if result is None:
            del results[job_id]["result"]
        else:
            results[job_id]["result"] = result
    if missing_job is not None:
        del results[missing_job]

    completed = _run_required_gate(results)

    assert (completed.returncode == 0) is expected_success, (
        f"{case}: stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )


def test_release_workflow_preserves_dry_run_and_publish_guards() -> None:
    jobs = _load_workflow(".github/workflows/release.yml")["jobs"]
    assert isinstance(jobs, dict)
    assert jobs["release"]["if"] == "github.ref_type != 'tag'"
    assert jobs["publish"]["if"] == "github.ref_type == 'tag'"


def test_staged_merge_queue_rule_matches_approved_policy() -> None:
    rule_path = ROOT / ".github/rulesets/main-merge-queue.json"
    rule = json.loads(rule_path.read_text())
    assert rule == EXPECTED_QUEUE_RULE
