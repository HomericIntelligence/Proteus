# Milestones

This document defines the **canonical milestone set** for Proteus.
Maintainers should create matching GitHub milestones in the UI and assign
every open issue to the appropriate one. The list here is the source of
truth; the GitHub UI mirrors it.

Once the GitHub milestones exist, this file should be kept in sync as
milestones close.

## Active milestones

### v0.1.x — pipeline correctness (target: 2026-06-30)

Goal: make the currently-broken pipeline glue **actually work**. No new
features — only fix the load-bearing defects identified in the
2026-04-28 strict audit.

Tracked priorities:

- Fix cross-repo dispatch payload contract mismatch (#15, #84).
- Fix build/promote tag arithmetic (#2, #83).
- Wire the unused pipeline YAML configs into runtime code (#1, #82).
- Replace YAML-parser "tests" with real unit and integration tests
  (#88, #89, #5).
- Stop suppressing security scanner failures (#85, #86).
- Pin GitHub Actions to commit SHAs — landed.

### v0.2.0 — security and reviewability (target: 2026-08-15)

Goal: make Proteus safe to operate as the ecosystem's CI/CD hub.

Tracked priorities:

- Branch protection: require approvals (#95), enforce CODEOWNERS (#102).
- TS error handling in Dagger module (#93).
- Cache-aware `lint()` that doesn't `npm ci` per call (#92).
- Dagger SDK version range tightened (#96).
- SAST / SCA / secrets scanning truly enforcing (#23).

### v0.3.0 — release engineering (target: 2026-10-15)

Goal: make Proteus itself releasable.

Tracked priorities:

- Create `CHANGELOG.md` with a real release process (#103).
- Versioned releases (#101).
- Devcontainer for first-time contributors — landed.
- Operational runbooks (#116 — landed; more to follow).

## Backlog (no milestone yet)

Anything not in the lists above belongs in the backlog. The triage
process (see #62) moves backlog items into a milestone once they have
enough context.

## Process

- Milestones use the `v<MAJOR>.<MINOR>` naming convention.
- A milestone is **closed** when every linked issue is closed and CI is
  green on the matching release tag.
- New milestones are added here by PR before being created in the
  GitHub UI.

## See also

- `docs/runbooks/cross-repo-dispatch-failure.md`
- `docs/branch-protection.md`
- `docs/backwards-compat.md`
- `AGENTS.md` "Known Critical Defects"
