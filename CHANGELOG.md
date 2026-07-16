# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-03

Initial versioned release of the Proteus CI/CD pipeline-automation hub
for the HomericIntelligence ecosystem. Downstream consumers (AchaeanFleet,
Myrmidons) may pin to git tag `v0.1.0`.

### Added
- Dagger TypeScript module (`dagger/src/index.ts`) exposing `build`, `test`,
  `lint` pipeline functions.
- Cross-repo dispatch bridge: `.github/workflows/cross-repo-dispatch.yml` +
  `scripts/dispatch-apply.sh` for AchaeanFleet → Myrmidons coordination.
- Image promotion via `scripts/promote-image.sh` (skopeo copy wrapper) and
  `.github/workflows/promote.yml` manual workflow.
- Pixi environment + justfile task runner; pipeline configs in
  `configs/pipelines/`.
- Required CI checks in `.github/workflows/_required.yml`: shellcheck,
  yamllint, gitleaks, Trivy SAST, TypeScript typecheck, signed-commit gate.
- SAST + npm audit security scanning (#152).
- CodeQL workflow (`.github/workflows/codeql.yml`).
- Fail-closed `host` validation on cross-repo dispatch payload (#84, #158).
- Audit 2026-04-28 remediation plan tracker (`docs/audit-2026-04-28/`, #154).
- Structural regression check for issue #92 (#160).

### Fixed
- Gitleaks no longer suppresses exit code on secret detection (#86, #156).

### Security
- Branch protection enforces signed commits, SHA-pinned GitHub Actions (#87),
  and a Trivy filesystem scan gate.

[Unreleased]: https://github.com/HomericIntelligence/Proteus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/HomericIntelligence/Proteus/releases/tag/v0.1.0
