# Branch Protection Policy

This document captures the branch-protection and merge-queue policy for
Proteus's default branch (`main`). The legacy branch-protection payload is
stored in `.github/branch-protection.main.json`. The live repository rulesets
remain authoritative for required status checks; inspect them before every
administrative change because committed documentation can drift from GitHub.

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
| Merge queue | **staged; activate after workflow smoke check** | #214 |
| Require signed commits | **on** | live ruleset `15556490` |
| Queue merge method | **squash** | #214 |

### Merge queue policy

The staged, GitHub-compatible rule fragment is
`.github/rulesets/main-merge-queue.json`. It is intentionally not applied by
CI. Post-merge activation requires an administrator after the representative
workflow smoke check is ready.

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
queued group. Every workflow that supplies a required context therefore keeps
its existing `push` and `pull_request` triggers and also subscribes to that
event:

- `.github/workflows/_required.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

### Required status checks

The authoritative required set is the union of the active repository
rulesets returned by
`gh api repos/HomericIntelligence/Proteus/rules/branches/main`. The live
baseline inspected for #214 on 2026-07-16 contained these contexts:

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
rules. The regression test `tests/unit/test_merge_queue_readiness.py` locks the
required-context-to-workflow mapping used for this rollout and verifies that
all three workflows handle merge groups.

Whenever a required job is added, renamed, or removed, update the applicable
ruleset only after enumerating all effective rules and confirming the posting
workflow runs for both pull requests and merge groups. The
`tests/test-required-checks-ruleset.sh` regression test checks live baseline
contexts in CI; `tests/unit/test_merge_queue_readiness.py` provides the
offline merge-queue guard.

## Staged activation after #214 merges

Do not run these commands from the implementation PR. After the workflow
changes are on `main` and the repository smoke check is ready, an administrator
may add the queue rule to the existing `homeric-main-baseline` ruleset without
reconstructing or weakening any sibling rule.

```bash
set -euo pipefail
repo=HomericIntelligence/Proteus
ruleset_id=15556490
before=/tmp/proteus-ruleset-before.json
rollback=/tmp/proteus-ruleset-rollback.json
after=/tmp/proteus-ruleset-with-queue.json
live=/tmp/proteus-ruleset-live.json

gh api "repos/${repo}/rulesets/${ruleset_id}" > "$before"
jq -e '.name == "homeric-main-baseline" and .enforcement == "active"' \
  "$before" >/dev/null
jq -e '[.rules[] | select(.type == "merge_queue")] | length == 0' \
  "$before" >/dev/null

jq '{
  name,
  target,
  enforcement,
  bypass_actors: (.bypass_actors // []),
  conditions,
  rules
}' "$before" > "$rollback"

jq --slurpfile queue .github/rulesets/main-merge-queue.json '{
  name,
  target,
  enforcement,
  bypass_actors: (.bypass_actors // []),
  conditions,
  rules: (.rules + [$queue[0]])
}' "$before" > "$after"

before_checks=$(jq -c '[.rules[] | select(.type == "required_status_checks")
  | .parameters.required_status_checks]' "$before")
after_checks=$(jq -c '[.rules[] | select(.type == "required_status_checks")
  | .parameters.required_status_checks]' "$after")
test "$before_checks" = "$after_checks"

gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" --input "$after" >/dev/null
gh api "repos/${repo}/rulesets/${ruleset_id}" > "$live"

if ! jq -e --slurpfile queue .github/rulesets/main-merge-queue.json \
  '[.rules[] | select(.type == "merge_queue")] == $queue' "$live" >/dev/null
then
  gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
    --input "$rollback" >/dev/null
  echo "Activation verification failed; restored the pre-activation ruleset." >&2
  exit 1
fi

live_checks=$(jq -c '[.rules[] | select(.type == "required_status_checks")
  | .parameters.required_status_checks]' "$live")
if test "$live_checks" != "$before_checks"; then
  gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
    --input "$rollback" >/dev/null
  echo "Required checks changed; restored the pre-activation ruleset." >&2
  exit 1
fi
```

After activation, enqueue one representative PR and record the
`merge_group/checks_requested` run, all 13 required check results, and the
queued squash merge on issue #214. If the smoke cycle fails, remove the queue
rule by re-applying `$rollback` and preserve the failure output verbatim.

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
# → either the required-context list above, or 404 if deleted.
```

## See also

- `docs/milestones.md` — milestone targeting this change set
- `CLAUDE.md` "Known Critical Defects"
- `AGENTS.md` — cross-repo guarantees that depend on this ruleset
- [GitHub merge queue documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- [GitHub rulesets REST API](https://docs.github.com/en/rest/repos/rules)
