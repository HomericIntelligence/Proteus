# ProjectProteus — CLAUDE.md

## Project Overview

ProjectProteus is the CI/CD pipeline automation hub for the HomericIntelligence ecosystem. It centralizes all pipeline logic using Dagger (TypeScript SDK), manages OCI image builds, runs test suites, promotes images via Skopeo, and orchestrates cross-repo GitHub Actions dispatch events.

- Images are built and pushed to registries managed by **AchaeanFleet**.
- Deployments are triggered in **Myrmidons** via `repository_dispatch`.
- All pipeline logic is reusable across HomericIntelligence repos via Dagger modules.

## Key Principles

- Pipelines are code: all logic lives in `dagger/src/index.ts`, not in sprawling shell scripts.
- Cross-repo coordination uses GitHub's `repository_dispatch` API — no polling.
- Image promotion (staging → production) is explicit and auditable via `scripts/promote-image.sh`.
- Environment management uses pixi; task running uses justfile. Never use Makefiles.
- New features go into new repos; do not modify existing HomericIntelligence repos.

## Repository Structure

```
ProjectProteus/
├── dagger/
│   ├── src/
│   │   └── index.ts        # Dagger TypeScript module (Proteus class)
│   ├── package.json
│   └── tsconfig.json
├── scripts/
│   ├── promote-image.sh    # skopeo copy wrapper
│   ├── dispatch-apply.sh   # GitHub API repository_dispatch sender
│   └── check-symlinks.sh   # verify all repo symlinks resolve (run in CI symlink-check job)
├── configs/
│   └── pipelines/
│       └── achaean-fleet.yaml  # Pipeline config for AchaeanFleet
├── .github/
│   └── workflows/
│       ├── ci.yml                   # Validate on push/PR
│       ├── cross-repo-dispatch.yml  # AchaeanFleet → Myrmidons bridge
│       └── promote.yml              # Manual promotion workflow
├── justfile
├── pixi.toml
├── CLAUDE.md
└── README.md
```

## Pipeline Architecture

### Dagger Module (`dagger/src/index.ts`)

The `Proteus` class exposes three core pipeline functions:

| Function | Description |
|----------|-------------|
| `build(context, name, tag)` | Builds OCI image from Dockerfile, returns digest |
| `test(source, command)` | Runs test command inside container, returns output |
| `lint(source)` | Runs lint checks, returns output |

Dagger calls are made via `dagger call <function> --<args>` from the justfile.

### Cross-Repo Dispatch Flow

1. AchaeanFleet pushes an image and sends `repository_dispatch` (type: `image-pushed`) to ProjectProteus.
2. `cross-repo-dispatch.yml` receives the event and calls `scripts/dispatch-apply.sh`.
3. `dispatch-apply.sh` sends a `repository_dispatch` (type: `agamemnon-apply`) to Myrmidons.
4. Myrmidons runs `just apply` on the target host.

### Image Promotion Flow

```
Build (dagger call build) → Test (dagger call test) → Promote (skopeo copy) → Dispatch apply
```

This full pipeline is invoked with `just pipeline NAME`.

## Known Critical Defects

The following defects are open and **load-bearing** — agents working in
this repo should know about them before changing behaviour in the
affected areas. Always check the linked issue for the current status
before assuming the defect is unfixed.

- **Cross-repo dispatch payload contract.** `cross-repo-dispatch.yml`
  treats `client_payload.host` as REQUIRED and the workflow fails closed
  with `::error::` if it is absent (#84). It also forwards `image_name`,
  `image_tag`, `image_digest`, and `source` to Myrmidons when present
  (#6). Upstream alignment so AchaeanFleet actually emits `host` is
  tracked in #15; this entry stays until that lands. Canonical schema:
  `docs/dispatch-contract.md`.
- **Build/promote tag arithmetic — FIXED.** `dagger call build --publish`
  now pushes to `${registry}/${name}:${tag}-staging` (via the
  `stagingRef` helper in `dagger/src/tag.ts`). `scripts/promote-image.sh`
  copies that staging ref to `${registry}/${name}:${tag}` as a separate
  step. `just build` remains non-publishing by default (see #91); use
  `just publish NAME` to push, or `just pipeline NAME` for the full
  build→test→promote→dispatch flow.
- ~~**Pipeline YAML configs are not consumed.**~~ Resolved in #82 — configs
  drive `just pipeline <NAME>` via `proteus run`, and `just validate`
  schema-validates them via `proteus validate`. See `KNOWN_LIMITATIONS.md`
  for the `notifications` follow-up. (Refs #1, #82.) The `proteus.pipeline`
  subpackage additionally validates `configs/pipelines/*.yaml` against
  `schemas/pipeline.schema.json` (Draft-07), parses them into a `Pipeline`
  dataclass, topologically sorts stages by `depends_on`, and runs them via
  `just pipeline-config <CONFIG>`. See #1 (closed), #82.
- **CI unit/integration "jobs" are YAML parsers, not tests.** On `main`
  the `unit-tests` / `integration-tests` jobs in
  `.github/workflows/_required.yml` still only YAML-parse pipeline
  configs (#5 OPEN). Real-test work is staged in PRs #173 and #187;
  do not rely on the green CI badge as evidence of Dagger function
  correctness until those land. A `pipeline-test-suite` pre-push hook
  (`.pre-commit-config.yaml`) now runs `just test-all` locally so
  untested code is blocked before push even while CI catches up.
  Flip this entry to "resolved" only after #5 closes.
- **GitHub Actions security gaps.** Gitleaks runs with `--exit-code 0` (#86);
  treat absence of a Gitleaks failure as inconclusive. (Trivy gate restored — #85 closed.)
- **Branch protection is enforced** via `.github/branch-protection.main.json`.
  The `.github/workflows/apply-branch-protection.yml` workflow re-applies the
  ruleset on every change to that file using the `BRANCH_PROTECTION_PAT`
  secret. `just verify-branch-protection` (read-only) detects drift;
  `tests/branch-protection.test.sh` runs offline in CI as the
  `branch-protection-test` required check. (Closes #95. Partially closes
  #102 — `require_code_owner_reviews=true` flips here; the CODEOWNERS
  coverage audit tracked in #102 remains open.)
- **Releases.** Cut releases by pushing a `v<semver>` tag to `main`; never
  edit `package.json` / `pixi.toml` versions via a bot commit. The
  `release.yml` workflow fails closed if the tag does not match both
  manifests AND a dated `CHANGELOG.md` section. Strict `vX.Y.Z` only —
  no pre-release or build suffixes. See #101.
- **Cross-repo dispatch graceful degradation.** `scripts/dispatch-apply.sh`
  retries 408/429/5xx and curl transport errors with jittered exponential
  backoff (env-tunable via `DISPATCH_MAX_ATTEMPTS`, `DISPATCH_BASE_DELAY_MS`,
  `DISPATCH_MAX_DELAY_MS`), persists unsent payloads to
  `${GITHUB_WORKSPACE}/.dispatch-dlq/`, and the workflow uploads them as
  `dispatch-dlq-<run_id>` artifacts. `dispatch-failure-alert.yml` opens or
  comments on a per-host tracking issue labelled `cross-repo-dispatch,
  incident, severity:major`. See #98 and `docs/dispatch-contract.md`
  §Retry & Dead-Letter Behaviour.

Agents must not silently work around these defects; instead, link the
relevant issue from any PR that touches the affected code.

## Audit Remediation Tracking

The 2026-04-28 STRICT audit (#81) is being remediated in three waves.
See `docs/audit-2026-04-28/remediation-plan.md` for current status of
all 33 child issues, target dates, the wave dependency graph, and the
pre-batched Wave 3 PR map.

Agents picking up an audit child issue MUST:
1. Read the audit context in #81 and the relevant child issue.
2. Confirm the file target listed in `remediation-plan.md` matches the
   actual file — security-scan jobs live in `.github/workflows/_required.yml`,
   NOT in `.github/workflows/ci.yml`.
3. Link the child in the PR body via `Refs #81`.
4. Add a regression test under `tests/` (created in #88) for any bug fix.
5. Tick the matching checkbox in `docs/audit-2026-04-28/remediation-plan.md`.

## Development Guidelines

- All Dagger functions must be tested locally with `dagger call` before committing.
- Pipeline configs in `configs/pipelines/` must be valid YAML; `just validate` checks them.
- Scripts in `scripts/` must be executable and pass `shellcheck`.
- Keep the Dagger module typed — no `any` in TypeScript.
- Use `set -euo pipefail` in all bash scripts.
- Do not add a `CHANGELOG.md`; release notes are auto-generated by `.github/workflows/release.yml`. See `docs/releases.md`.

## Common Commands

```bash
# List all available tasks
just

# Build an OCI image
just build myapp

# Run tests
just test myapp

# Promote image from staging to production
just promote ghcr.io/homeric-intelligence/myapp:staging ghcr.io/homeric-intelligence/myapp:latest

# Trigger Myrmidons apply on a host
just dispatch-apply hermes

# Full pipeline
just pipeline myapp

# Lint check via Dagger
just lint

# Validate pipeline configs
just validate

# Enter pixi environment
pixi shell
```
