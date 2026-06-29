# ===========================
# ProjectProteus — justfile
# CI/CD pipeline automation hub
# ===========================

REGISTRY := env_var_or_default("REGISTRY", "ghcr.io/homeric-intelligence")
IMAGE_TAG := env_var_or_default("IMAGE_TAG", "latest")
GITHUB_TOKEN := env_var_or_default("GITHUB_TOKEN", "")
MYRMIDONS_REPO := env_var_or_default("MYRMIDONS_REPO", "HomericIntelligence/Myrmidons")

# ===========================
# Default
# ===========================

# List all available recipes
default:
    @just --list

# ===========================
# Core Pipeline
# ===========================

# Build an OCI image using Dagger (local only — does NOT push; use `just publish` to publish)
build NAME:
    dagger call build --context . --name {{NAME}} --tag {{IMAGE_TAG}} --registry {{REGISTRY}}

# Build and publish an OCI image to REGISTRY/NAME:IMAGE_TAG-staging
publish NAME:
    dagger call build --context . --name {{NAME}} --tag {{IMAGE_TAG}} --registry {{REGISTRY}} --publish

# Run tests for a given repo using Dagger
test NAME:
    dagger call test --source . --command "just test {{NAME}}"

# Full pipeline driven by configs/pipelines/<NAME>.yaml
# (build → test → promote staging→latest → dispatch, per the config's stages)
pipeline NAME HOST="hermes":
    pixi run bootstrap-proteus
    pixi run python -m proteus run configs/pipelines/{{NAME}}.yaml \
        --service {{NAME}} --host {{HOST}}

# Config-driven pipeline from configs/pipelines/<CONFIG>.yaml (topological stage run).
# Example: just pipeline-config achaean-fleet
pipeline-config CONFIG:
    pixi run bootstrap-proteus
    pixi run python -m proteus.pipeline run configs/pipelines/{{CONFIG}}.yaml

# ===========================
# Promotion
# ===========================

# Promote (copy) an image from source registry to destination using skopeo
promote SRC DEST:
    ./scripts/promote-image.sh "{{SRC}}" "{{DEST}}"

# ===========================
# Dispatch
# ===========================

# Send repository_dispatch to trigger Myrmidons apply on HOST
dispatch-apply HOST:
    GITHUB_TOKEN={{GITHUB_TOKEN}} MYRMIDONS_REPO={{MYRMIDONS_REPO}} ./scripts/dispatch-apply.sh {{HOST}}

# ===========================
# Branch Protection
# ===========================

# Apply branch protection to enforce CODEOWNERS reviews on main (#102)
branch-protection-apply:
    ./scripts/branch-protection-apply.sh

# Print the protection payload that would be applied, without calling PUT (#102)
branch-protection-dry-run:
    DRY_RUN=1 ./scripts/branch-protection-apply.sh

# ===========================
# Setup
# ===========================

# Install pixi environment
bootstrap:
    pixi install

# ===========================
# Quality
# ===========================

# Run lint checks via Dagger
lint:
    dagger call lint --source .

# Static check that issue #92's lintTsc invariants are still present
lint-verify-92:
    bash scripts/verify-issue-92-invariants.sh

# Verify remediation-plan checkboxes match expected issue state (#183)
test-plan-sync:
	bash tests/remediation-plan-sync.test.sh

# Apply branch protection ruleset to main (requires admin GITHUB_TOKEN) — Refs #95, #102.
apply-branch-protection:
    GITHUB_TOKEN={{GITHUB_TOKEN}} ./scripts/apply-branch-protection.sh

# Verify live branch protection matches .github/branch-protection.main.json — Refs #95.
verify-branch-protection:
    GITHUB_TOKEN={{GITHUB_TOKEN}} ./scripts/verify-branch-protection.sh

# Offline shim test — runs in CI without secrets.
test-branch-protection:
    bash tests/branch-protection.test.sh

# Run lint + validate + plan-sync + branch-protection test together
check: lint validate test-plan-sync test-branch-protection

# Run the full local test suite (shell integration tests + config validation)
test-all:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "== Running pipeline test suite =="
	failed=0
	shopt -s nullglob
	for t in tests/*.test.sh; do
	    echo "--- $t ---"
	    bash "$t" || failed=1
	done
	if command -v pixi >/dev/null 2>&1; then
	    just validate || failed=1
	else
	    echo "WARNING: pixi not on PATH — skipping config validation (install pixi to enable)"
	fi
	if [ "$failed" -ne 0 ]; then
	    echo "FAILED: one or more test suites failed" >&2
	    exit 1
	fi
	echo "PASSED: all test suites passed"

# Schema-validate all pipeline configs in configs/pipelines/
validate:
    pixi run bootstrap-proteus
    pixi run python -m proteus validate configs/pipelines/

# Verify version is consistent across pixi.toml, dagger/package.json, CHANGELOG.md
version:
	bash tests/version-consistency.test.sh
