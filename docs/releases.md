# Release Policy

Proteus releases are auto-generated from commits and published on GitHub.

## Versioning

We follow Semantic Versioning (SemVer): `MAJOR.MINOR.PATCH`. Git tags are formatted as `vX.Y.Z` (e.g., `v0.1.0`, `v1.2.3`).

## Release Notes

Release notes are auto-generated from Conventional Commit messages by `.github/workflows/release.yml` when a version tag is pushed to GitHub. The automation uses `gh release create --generate-notes`, which parses commit subjects in the `feat:`, `fix:`, `docs:`, `test:`, and `chore:` format to group and categorize changes.

To keep generated notes readable, always use these subject prefixes:
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation only
- `test:` — test changes only
- `chore:` — maintenance (dependencies, config, refactoring without public API change)

## Cutting a Release

1. Update `dagger/package.json` and `pixi.toml` with the new version number (must match the tag you'll push, e.g., `0.1.0` for tag `v0.1.0`).
2. Commit these changes with a descriptive message (e.g., `chore: bump version to 0.1.0`).
3. Tag the commit: `git tag -s v0.1.0 -m "Release v0.1.0"`. (The `-s` flag signs the tag; `tag.gpgsign=true` is assumed to be configured.)
4. Push the tag: `git push --tags`.
5. The release workflow (`.github/workflows/release.yml`) automatically triggers and creates a GitHub Release with auto-generated notes.

## Viewing Releases

Browse releases at: https://github.com/HomericIntelligence/Proteus/releases

## Related Work

- **Versioning and baseline tag:** See issue #101 — covers cutting the initial v0.1.0 tag to establish release history.
- **Backwards-compatibility policy:** See issue #112 and docs/backwards-compat.md — covers API stability guarantees across versions.
- **Release notification:** Release events are auto-published to GitHub Releases; distribution (emails, Slack, RSS) is coordinated by the HomericIntelligence DevOps team.
