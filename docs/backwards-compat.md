# Backwards Compatibility Policy — Dagger Module API

This document defines what backwards compatibility means for the
TypeScript Dagger module shipped from `dagger/src/index.ts`.

## Public surface area (governed by SemVer)

1. **The `Proteus` class methods** and their parameter signatures:
   - `build()`
   - `test()`
   - `lint()`
   - Any additional method exported in `index.ts`.
2. **Method parameter names, types, defaults, and required/optional status.**
3. **Return-shape contracts** documented in JSDoc.
4. **Module name** (`@homeric-intelligence/proteus` once published) and
   the export structure of the npm package.

## Not public

- Internal helper functions and `_`-prefixed members.
- The exact text of log output or error messages (structure and exit
  codes only).
- Workflow YAML files under `.github/workflows/` (these are this
  repo's CI, not a downstream contract).
- Pipeline config schemas under `configs/` (consumed only by Proteus
  itself for now).

## What counts as breaking

A change is **breaking** if it:

- Removes or renames a public method.
- Adds a required parameter to a public method.
- Removes a parameter or tightens its allowed values.
- Changes a default value in a way that changes runtime behaviour.
- Changes the return shape in a way that breaks `tsc --noEmit` on a
  conforming downstream caller.
- Removes a documented environment variable read by the module.

A change is **non-breaking** if it:

- Adds a new public method.
- Adds an optional parameter with a sensible default.
- Widens an allowed-values enum.
- Adds new properties to a return-shape object.

## Deprecation policy

Before removing or renaming a public surface:

1. Mark it with a `@deprecated` JSDoc tag and document the replacement.
2. Add a `### Deprecated` entry in `CHANGELOG.md` and reference the
   replacement.
3. Keep the deprecated surface working for **at least one minor
   release** before removal.
4. Remove in the next `MAJOR` release (or pre-1.0 `MINOR` release).

## Versioning policy

Proteus follows [Semantic Versioning 2.0.0](https://semver.org/).

Pre-1.0 caveat: while the version remains `0.y.z` the Dagger module
API may receive breaking changes in any `MINOR` bump. Downstream
consumers should pin a specific `MINOR` until v1.0.0.

## Cross-repo dispatch contract

The cross-repo `repository_dispatch` payload shape (consumed in
`cross-repo-dispatch.yml`) is **a separate contract** versioned in
lockstep with AchaeanFleet and Myrmidons. Changes there require
coordinated PRs across all three repos; this document does not
govern that surface.

## See also

- `dagger/src/index.ts` — public surface.
- `AGENTS.md` — cross-repo contracts.
- `CHANGELOG.md` (once created) — release history.
