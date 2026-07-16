"""Regression coverage for the main-branch merge-queue rollout (issue #214)."""

from __future__ import annotations

import json
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
    },
    ".github/workflows/ci.yml": {"Lint Shell Scripts"},
    ".github/workflows/release.yml": {"release"},
}

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


def test_release_workflow_preserves_dry_run_and_publish_guards() -> None:
    jobs = _load_workflow(".github/workflows/release.yml")["jobs"]
    assert isinstance(jobs, dict)
    assert jobs["release"]["if"] == "github.ref_type != 'tag'"
    assert jobs["publish"]["if"] == "github.ref_type == 'tag'"


def test_staged_merge_queue_rule_matches_approved_policy() -> None:
    rule_path = ROOT / ".github/rulesets/main-merge-queue.json"
    rule = json.loads(rule_path.read_text())
    assert rule == EXPECTED_QUEUE_RULE
