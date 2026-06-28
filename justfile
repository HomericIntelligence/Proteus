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

# Full pipeline: publish (→ :TAG-staging) → test → promote (:TAG-staging → :TAG) → dispatch
pipeline NAME HOST="hermes": (publish NAME) (test NAME)
    just promote {{REGISTRY}}/{{NAME}}:{{IMAGE_TAG}}-staging {{REGISTRY}}/{{NAME}}:{{IMAGE_TAG}}
    just dispatch-apply {{HOST}}

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

# Run lint + validate together
check: lint validate

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
	just validate || failed=1
	if [ "$failed" -ne 0 ]; then
	    echo "FAILED: one or more test suites failed" >&2
	    exit 1
	fi
	echo "PASSED: all test suites passed"

# Validate all pipeline configs in configs/pipelines/
validate:
	#!/usr/bin/env bash
	set -euo pipefail
	echo "Validating pipeline configs..."
	shopt -s nullglob
	files=(configs/pipelines/*.yaml)
	if [ ${#files[@]} -eq 0 ]; then
	    echo "  No pipeline configs found."
	    exit 0
	fi
	errors=0
	for f in "${files[@]}"; do
	    if pixi run python -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
	        echo "  OK: $f"
	    else
	        echo "  FAIL: $f"
	        errors=$((errors + 1))
	    fi
	done
	echo "All pipeline configs valid."
	exit $errors
