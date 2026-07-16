# Proteus

[![CI](https://github.com/HomericIntelligence/Proteus/actions/workflows/ci.yml/badge.svg)](https://github.com/HomericIntelligence/Proteus/actions/workflows/ci.yml)
[![Promote](https://github.com/HomericIntelligence/Proteus/actions/workflows/promote.yml/badge.svg)](https://github.com/HomericIntelligence/Proteus/actions/workflows/promote.yml)
[![Cross-Repo Dispatch](https://github.com/HomericIntelligence/Proteus/actions/workflows/cross-repo-dispatch.yml/badge.svg)](https://github.com/HomericIntelligence/Proteus/actions/workflows/cross-repo-dispatch.yml)

CI/CD pipeline automation hub for the HomericIntelligence ecosystem.

> **Version:** see [`CHANGELOG.md`](CHANGELOG.md). Downstream repos should pin to a released tag (e.g. `v0.1.0`); untagged refs are not supported.

## Purpose

Proteus is the centralized pipeline orchestration layer for all HomericIntelligence services. It provides reusable Dagger modules for building OCI images, running test suites, and promoting images across registries. Cross-repo dispatch patterns ensure that image pushes from AchaeanFleet automatically trigger deployment workflows in Myrmidons.

## Architecture

### Dagger Modules

- **build** — Builds OCI images from Dockerfiles, returns image digest.
- **test** — Runs test suites inside containers, returns output.
- **promote** — Uses Skopeo to copy images between registries (staging → production).
- **lint** — Runs linting checks across source directories.

### Cross-Repo Dispatch Pattern

```
AchaeanFleet (image push)
    └─► Proteus (cross-repo-dispatch.yml receives repository_dispatch)
            └─► Myrmidons (triggers apply via repository_dispatch)
```

AchaeanFleet sends a `repository_dispatch` event with type `image-pushed` to Proteus. The `cross-repo-dispatch.yml` workflow picks this up and triggers a Myrmidons apply against the appropriate host.

## Quick Start

```bash
# Build an image
just build IMAGE_NAME

# Run tests
just test IMAGE_NAME

# Promote an image from staging to production
just promote ghcr.io/homeric-intelligence/myapp:staging ghcr.io/homeric-intelligence/myapp:latest

# Full pipeline: build → test → promote → dispatch
just pipeline IMAGE_NAME

# Trigger Myrmidons apply
just dispatch-apply hermes
```

## Releases

Release notes are auto-generated from commits and published on GitHub:
https://github.com/HomericIntelligence/Proteus/releases

See [docs/releases.md](docs/releases.md) for the versioning and release-cutting policy.

## Integration Points

| Repo | Role |
|------|------|
| **AchaeanFleet** | Calls Proteus for image builds and promotion after each push |
| **Myrmidons** | Receives `repository_dispatch` on image push; runs `just apply` |
| **Proteus** | Owns all shared pipeline logic, Dagger modules, and dispatch scripts |

## Repository Structure

```
Proteus/
├── dagger/
│   └── src/
│       └── index.ts        # Dagger TypeScript pipeline module
├── scripts/
│   ├── promote-image.sh    # Skopeo image copy helper
│   ├── dispatch-apply.sh   # GitHub API dispatch trigger
│   └── check-symlinks.sh   # Verify all repo symlinks resolve
├── configs/
│   └── pipelines/
│       └── achaean-fleet.yaml  # Per-repo pipeline config
├── .github/
│   └── workflows/
│       ├── ci.yml                   # Validate pipeline configs on push/PR
│       ├── cross-repo-dispatch.yml  # Receives AchaeanFleet events, triggers Myrmidons
│       └── promote.yml              # Manual image promotion workflow
├── justfile
├── pixi.toml
├── CLAUDE.md
└── README.md
```

## Scripts

The `scripts/` directory contains helper utilities used by `just` recipes and CI:

- **`promote-image.sh`** — Copies an OCI image between registries using Skopeo. Invoked by `just promote SRC DEST`. Honors `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` for auth.
- **`dispatch-apply.sh`** — Sends a `repository_dispatch` event to Myrmidons to trigger an apply against a host. Invoked by `just dispatch-apply HOST`.
- **`check-symlinks.sh`** — Walks the repo (excluding `.git/`) and fails if any symlink points to a missing target. Run manually or wired into CI to catch broken submodule/config links early.

## Prerequisites

- [Dagger CLI](https://docs.dagger.io/install) installed
- [Skopeo](https://github.com/containers/skopeo) for image promotion
- `GITHUB_TOKEN` with `repo` scope for cross-repo dispatch
- [pixi](https://prefix.dev/) for environment management

## Adding Pipeline Configurations

Pipeline configurations live in `configs/pipelines/`. Each config is a YAML file describing a service's CI/CD pipeline: when to trigger it (on push, dispatch, etc.), which stages to run (build, test, promote, dispatch), and how to coordinate them.

### Schema

Each pipeline config follows this structure:

```yaml
# configs/pipelines/<service-name>.yaml
name: <service-name>                    # Identifier for the pipeline
description: >
  Description of what this pipeline does.

triggers:                               # Trigger events
  - event: image-pushed                 # Event type (image-pushed, repository_dispatch, etc.)
    repo: HomericIntelligence/<RepoName> # Source repository

registry:
  base: ghcr.io/homeric-intelligence    # Base registry path
  staging_suffix: "-staging"            # Suffix for staging images

stages:
  - name: build                         # Stage identifier
    type: dagger                        # Type: dagger, skopeo, or dispatch
    function: build                     # Function to call (for dagger type)
    args:
      context: "."                      # Build context directory
      tag: "staging"                    # Image tag
    depends_on: []                      # Stages that must complete first

  - name: promote
    type: skopeo                        # Use Skopeo for image promotion
    script: scripts/promote-image.sh    # Script to invoke
    args:                               # Positional args as ordered list (not dict)
      - "ghcr.io/homeric-intelligence/<service>:staging"
      - "ghcr.io/homeric-intelligence/<service>:latest"
    depends_on: [test]

notifications:
  on_failure:
    - channel: "#ci-alerts"
  on_success:
    - channel: "#deployments"
```

See `configs/pipelines/achaean-fleet.yaml` for a complete example.

### Adding a New Pipeline

1. **Create the config file:**
   ```bash
   touch configs/pipelines/<service-name>.yaml
   ```

2. **Write the pipeline definition** following the schema above, adapting the registry paths, stages, and triggers for your service.

3. **Schema-validate the config:**
   ```bash
   just validate
   ```
   Validates every file in `configs/pipelines/` against the committed
   JSON Schema (`configs/pipelines/schema.json`) — not just YAML syntax.
   See `KNOWN_LIMITATIONS.md` for the `notifications:` follow-up.

4. **Test the pipeline locally** (requires Dagger and Skopeo):
   ```bash
   just build <service-name>      # Build the OCI image
   just test <service-name>       # Run tests inside container
   just promote <staging-ref> <prod-ref>  # Promote staging → production
   ```

5. **Run the full pipeline** in one step:
   ```bash
   just pipeline <service-name>
   ```

6. **Commit and push:**
   ```bash
   git add configs/pipelines/<service-name>.yaml
   git commit -m "feat(pipelines): add <service-name> pipeline config"
   git push
   ```

The CI workflow (`ci.yml`) will validate your config on push. Once merged to `main`, the `cross-repo-dispatch.yml` workflow will receive events from the configured source repository and execute the pipeline stages in order.
