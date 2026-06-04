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

# Build an OCI image using Dagger
build NAME:
    dagger call build --context . --name {{NAME}} --tag {{IMAGE_TAG}} --registry {{REGISTRY}}

# Run tests for a given repo using Dagger
dagger-test NAME:
    dagger call test --source . --command "just dagger-test {{NAME}}"

# Full pipeline: build → test → promote → dispatch
pipeline NAME HOST="hermes": (build NAME) (dagger-test NAME)
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

# Run lint + validate together
check: lint validate

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

# ===========================
# Test Suite (issue #5)
# ===========================

# Run Dagger TypeScript unit tests (Jest)
test-unit:
    cd dagger && npm ci --prefer-offline --no-audit && npx jest

# Run shell integration tests (bats)
test-integration:
    bats tests/integration

# Run e2e tests; requires JUST_RUN_E2E=1 + a running Dagger engine
test-e2e:
    JUST_RUN_E2E=1 bats tests/e2e

# Run everything (unit + integration; e2e is opt-in)
test-all: test-unit test-integration
