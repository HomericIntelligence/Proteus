# Audit 2026-04-28 — Remediation Plan

Epic: #81 | Milestone: "Audit 2026-04-28 Remediation" | Target close: 2026-07-31

## External co-blockers (referenced by CLAUDE.md:92, not children of #81)
- #89 — external test infra dependency
- #5  — external test infra dependency

## Wave 1 — Foundation (target 2026-05-31; parallel PRs)
- [ ] #88 Test harness — adds `tests/`, `just test-suite`, vitest+bats — PR: TBD
- [ ] #86 Gitleaks gate — `_required.yml:193,196` `--exit-code 0` → `--exit-code 1` — PR: TBD
- [ ] #87 Action SHA pinning — VERIFY-AND-CLOSE: grep confirms all actions SHA-pinned — PR: none ✅ CLOSED
- [ ] #94 Required status checks — branch protection API: add `typescript`, `lint-scripts`, `validate-configs`, `unit-tests` — PR: TBD
- [ ] #95 CODEOWNERS review required — branch protection API: `required_approving_review_count=1` — PR: TBD
- [ ] #99 Milestone created — gh API — PR: none ✅ DONE
- [ ] #100 CLAUDE.md defect doc — covered by this PR — PR: TBD
- [ ] #102 CODEOWNERS in branch protection — branch protection API: `require_code_owner_reviews=true` — PR: TBD

## Wave 2 — Critical bugs (target 2026-06-30, gated on Wave 1 #88 merged)
- [ ] #83 Tag arithmetic — `justfile:33` — regression test under `tests/integration/` — PR: TBD
- [ ] #84 Dispatch payload contract — `scripts/dispatch-apply.sh` + `.github/workflows/cross-repo-dispatch.yml` — PR: TBD
- [ ] #82 Pipeline config consumption — `dagger/src/index.ts` reads `configs/pipelines/*.yaml` — PR: TBD
- [ ] #97 Payload `host` validation — `scripts/dispatch-apply.sh` regex check — PR: TBD
- [ ] #93 Dagger error handling — `dagger/src/index.ts` — PR: TBD
- [ ] #92 lint() caching — `dagger/src/index.ts` — PR: TBD

## Wave 3 — Hygiene (target 2026-07-31; pre-batched PRs)
- [ ] PR-A (`dagger/package.json`): #96, #107, #108
- [ ] PR-B (`_required.yml`): #106
- [ ] PR-C (`scripts/dispatch-apply.sh`): #104, #105, #98
- [ ] PR-D (`scripts/promote-image.sh`): #109
- [ ] PR-E (`CHANGELOG.md`): #101, #103, #112
- [ ] PR-F (`.github/`): #110, #111, #119
- [ ] PR-G (docs): #117, #116, #114, #121
- [ ] PR-H (root): #113, #115, #120, #118
- [ ] Re-audit via /hephaestus:repo-analyze-strict-full
- [ ] Close #81 when grade ≥ B AND #82–#88 all CLOSED

## Rollback policy
Any Wave 1/2 PR that turns main CI red is reverted within 24h via `git revert`. Wave 1 #88 MUST go green on `_required.yml` before merge.
