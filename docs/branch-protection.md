# Branch Protection Policy

This document captures the branch-protection and merge-queue policy for
Proteus's default branch (`main`). The legacy branch-protection payload is
stored in `.github/branch-protection.main.json`. Live repository rulesets are
authoritative for effective status checks and must be inspected before every
administrative change because committed policy can drift from GitHub.

## Why this matters

Proteus is the CI/CD hub for the entire HomericIntelligence
ecosystem. A regression merged directly to `main` here can fan out to
AchaeanFleet image pushes, Myrmidons applies, and downstream agent
provisioning. Branch protection is the last guardrail.

## Target ruleset for `main`

| Setting | Target value | Tracked by |
| --- | --- | --- |
| Restrict deletions | **on** | — |
| Restrict pushes (no force-pushes, no direct commits) | **on** | — |
| Require pull request before merging | **on** | — |
| Required approving review count | **0** (organization automation policy) | Charybdis #279 |
| Dismiss stale approvals on new commits | **preserve live value** | — |
| Require review from code owners | **preserve live value** | #102 |
| Require status checks to pass | **on** | — |
| Required status checks | see below | #94 |
| Merge queue | **staged; activate after workflow smoke readiness** | #214 |
| Require signed commits | **on** | live ruleset `15556490` |
| Queue merge method | **squash** | #214 |

### Merge queue policy

The staged GitHub rule fragment is
`.github/rulesets/main-merge-queue.json`. It is intentionally not applied by
CI. Activation is a separate post-merge administrator operation after the
representative smoke check is ready.

| Queue setting | Value |
| --- | --- |
| Target branch | `main` |
| Grouping strategy | `ALLGREEN` |
| Maximum queue builds | `10` |
| Maximum merged entries per group | `5` |
| Minimum entries per group | `1` |
| Minimum wait | `5` minutes |
| Required-check timeout | `60` minutes |
| Merge method | `SQUASH` |

GitHub dispatches `merge_group` with activity type `checks_requested` for a
queued group. Every workflow that supplies a live required context therefore
preserves its existing `push` and `pull_request` triggers and also subscribes
to that event:

- `.github/workflows/_required.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

Because this rollout changes workflow event triggers, an independent human
reviewer must review those workflow changes before merge. Automated validation
does not replace that review requirement.

### Required status checks

The authoritative required set is the union of all active rulesets returned by
`gh api repos/HomericIntelligence/Proteus/rules/branches/main`. On 2026-07-16,
Proteus had two live repository rulesets: `homeric-main-baseline` (`15556490`)
and `homeric-main-extras` (`18221113`). Their 13 effective required contexts
were:

- `lint` — shellcheck, yamllint, mypy (when Python present),
  `tsc --noEmit`, `verify-issue-92-invariants.sh` (`_required.yml`)
- `unit-tests` (includes `tests/test-required-checks-ruleset.sh`)
- `integration-tests`
- `security/dependency-scan` — Trivy fs scan, fails on CRITICAL/HIGH
- `security/secrets-scan` — Gitleaks (see #86 for exit-code gap)
- `build`
- `schema-validation`
- `deps/version-sync`
- `test`
- `package`
- `install`
- `release` (`release.yml`)
- `Lint Shell Scripts` — shellcheck on `./scripts` + `verify-issue-92-invariants.sh` (`ci.yml`)

Other workflow jobs remain advisory unless they appear in the effective live
rules. `tests/unit/test_merge_queue_readiness.py` locks the required-context
mapping used for this rollout and confirms all three posting workflows support
merge groups.

Whenever a required job is added, renamed, or removed, enumerate the effective
rules first and patch only the applicable live ruleset while preserving every
sibling rule and repository-specific context. The live regression test
`tests/test-required-checks-ruleset.sh` checks the effective union;
`tests/merge-queue-activation.test.sh` covers offline preservation and rollback
with 18 numbered fail-safe cases. The activation implementation and its current
signed/DCO commit history are carried by
[PR #216](https://github.com/HomericIntelligence/Proteus/pull/216); review the
PR's current head instead of relying on a manually copied commit list.
Refs #214.

## Staged activation after #214 merges

Do not activate the queue from the implementation PR. Once the workflow changes
are on `main`, an administrator first reviews the exact preserving payload:

```bash
just merge-queue-plan
```

After the representative smoke check is ready, apply it explicitly:

```bash
just merge-queue-activate
```

`scripts/activate-merge-queue.sh` discovers the active repository ruleset by
name and reads the full target payload, complete ruleset inventory, and
effective `main` rules before mutation. List reads request 100 entries per page,
validate every page, and combine all pages before policy checks. It rejects any
applicable pre-existing merge queue, validates the exact Proteus target
identity, `main`-only scope, repository-role bypass, and 13-context contract,
then re-fetches and compares all three complete snapshots immediately before
PUT. It arms an EXIT-trap rollback before the PUT, retries every post-mutation
read, verifies the target read-back, confirms every live ruleset is still
present, compares the complete effective branch state against the pre-state
plus the one staged queue rule, and checks that all required contexts are
byte-for-byte equivalent after normalization. Rollback is disarmed only after
every postcondition passes. On failure, rollback first proves that the live
writable target still exactly equals the attempted desired payload; if another
writer has changed it, the script refuses to overwrite that state and preserves
the recovery snapshot.

Central rollout work in [Odysseus PR #417](https://github.com/HomericIntelligence/Odysseus/pull/417),
under umbrella [issue #386](https://github.com/HomericIntelligence/Odysseus/issues/386),
must follow the same contract: inspect and patch each repository's live
rulesets, preserve Proteus's exact two-ruleset, 13-context contract together
with every repository-specific rule and context, and verify effective branch
state. It must not apply a fixed generic ruleset payload across the fleet; this
staged fragment is one rule, not a complete Proteus ruleset.

After activation, enqueue one representative PR and record the
`merge_group/checks_requested` run, all 13 required check results, and the
queued squash merge on issue #214. If the smoke cycle fails, restore the
pre-activation payload and preserve the failure output verbatim.

## Enforcement

The legacy branch-protection settings are the literal body of
`.github/branch-protection.main.json`. They are applied automatically by
`.github/workflows/apply-branch-protection.yml` on every push to `main` that
modifies the JSON file, using the admin-scoped `BRANCH_PROTECTION_PAT`
repository secret. The staged merge-queue fragment is a repository-ruleset
rule and is not sent to the legacy branch-protection endpoint.

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

```bash
gh api -X PUT repos/HomericIntelligence/Proteus/branches/main/protection \
  --input docs/audit-2026-04-28/classic-protection-after-94.json
```

If the admin running the PR cannot PATCH classic protection, the
fallback is to delete it (Ruleset becomes the sole enforcer):

```bash
gh api -X DELETE repos/HomericIntelligence/Proteus/branches/main/protection
```

Verify with:

```bash
gh api repos/HomericIntelligence/Proteus/branches/main/protection
# Either the required-context list above, or 404 if deleted.
```

## See also

- `docs/milestones.md` — milestone targeting this change set
- `AGENTS.md` "Known Critical Defects" and cross-repo guarantees that depend on this ruleset
- [GitHub merge queue documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- [GitHub rulesets REST API](https://docs.github.com/en/rest/repos/rules)
