# Branch Protection Policy

This document captures the **target** branch protection ruleset for
ProjectProteus's default branch (`main`). The ruleset is configured in
the GitHub UI / API by a repository admin; this file is the
human-readable source of truth and is updated in a PR before any UI
change.

## Why this matters

ProjectProteus is the CI/CD hub for the entire HomericIntelligence
ecosystem. A regression merged directly to `main` here can fan out to
AchaeanFleet image pushes, Myrmidons applies, and downstream agent
provisioning. Branch protection is the last guardrail.

## Target ruleset for `main`

| Setting | Target value | Tracked by |
|---|---|---|
| Restrict deletions | **on** | — |
| Restrict pushes (no force-pushes, no direct commits) | **on** | — |
| Require pull request before merging | **on** | — |
| Required approving review count | **1** (minimum) | #95 (enforced) |
| Dismiss stale approvals on new commits | **on** | — |
| Require review from code owners | **on** | #102 (enforced via API; CODEOWNERS coverage audit remains open) |
| Require status checks to pass | **on** | — |
| Required status checks | see below | #94 |
| Require branches to be up to date before merging | **on** | — |
| Require signed commits | **off** (under review) | — |
| Allowed merge methods | **squash only** | — |

### Required status checks

The authoritative required set is enforced by the
`homeric-main-baseline` repository ruleset (see
`gh api repos/HomericIntelligence/ProjectProteus/rulesets`). Every job
in `.github/workflows/_required.yml` is a required context. After
#94, the full list is:

- `lint` — shellcheck, yamllint, mypy (when Python present),
  `tsc --noEmit`, `verify-issue-92-invariants.sh` (`_required.yml`)
- `unit-tests` (includes `tests/test-required-checks-ruleset.sh`)
- `integration-tests`
- `security/dependency-scan` — Trivy fs scan, fails on CRITICAL/HIGH
- `security/secrets-scan` — Gitleaks (see #86 for exit-code gap)
- `build`
- `schema-validation`
- `deps/version-sync`
- `Lint Shell Scripts` — shellcheck on `./scripts` + `verify-issue-92-invariants.sh` (`ci.yml`)
- `branch-protection-test` (offline branch protection verification)

The following `_required.yml` jobs also run on every PR and remain
required contexts in the ruleset, but are not part of the minimal
gating set above: `forbid-suppressions`, `markdownlint`, `pixi-check`,
`justfile-check`, `symlink-check`.

Whenever a job is added, renamed, or removed in `_required.yml`, the
ruleset must be updated in the same PR via `gh api -X PUT
repos/HomericIntelligence/ProjectProteus/rulesets/15556490`. The
`tests/test-required-checks-ruleset.sh` regression test enforces this
invariant in CI.

## Enforcement

The ruleset above is the **literal** body of `.github/branch-protection.main.json`.
It is applied automatically by `.github/workflows/apply-branch-protection.yml`
on every push to `main` that modifies the JSON file, using the admin-scoped
`BRANCH_PROTECTION_PAT` repository secret.

Manual operations (admin token required):

- Apply / re-apply: `GITHUB_TOKEN=<admin-pat> just apply-branch-protection`
- Detect drift:    `GITHUB_TOKEN=<admin-pat> just verify-branch-protection`

Offline regression coverage runs on every PR via `_required.yml` →
`branch-protection-test`; no token is required.

## Migration note — 2026-06 (#94)

`#94` adds a TypeScript type check (`tsc --noEmit`) and the
`verify-issue-92-invariants.sh` static guard to the `lint` job in
`.github/workflows/_required.yml`, and adds a
`tests/test-required-checks-ruleset.sh` regression step to
`unit-tests`. `.github/workflows/ci.yml` is **retained**: its
`Lint Shell Scripts` job remains a required context (shellcheck on
`./scripts` plus `verify-issue-92-invariants.sh`), alongside the
`TypeScript Type Check` job. The `validate` job that was removed
earlier (#106) is documented here for the historical record.

Because `ci.yml` (and therefore the `"Lint Shell Scripts"` context) is
retained, the classic branch-protection record on `main` keeps that
context. The same #94 PR aligns the classic record with the ruleset
contexts using:

    gh api -X PUT repos/HomericIntelligence/ProjectProteus/branches/main/protection \
      --input docs/audit-2026-04-28/classic-protection-after-94.json

If the admin running the PR cannot PATCH classic protection, the
fallback is to delete it (Ruleset becomes the sole enforcer):

    gh api -X DELETE repos/HomericIntelligence/ProjectProteus/branches/main/protection

Verify with:

    gh api repos/HomericIntelligence/ProjectProteus/branches/main/protection
    # → either the required-context list above, or 404 if deleted.

## See also

- `docs/milestones.md` — milestone targeting this change set
- `CLAUDE.md` "Known Critical Defects"
- `AGENTS.md` — cross-repo guarantees that depend on this ruleset
