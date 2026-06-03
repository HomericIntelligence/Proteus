# Runbook: no silent failures in CI

CI must surface real failures. Suppression patterns that hide failure
exit codes are forbidden. The `forbid-suppressions` job in
`.github/workflows/_required.yml` enforces this in CI.

## Forbidden idioms

- `<cmd> || true` at end of line (Bucket A — shell suppression).
- `continue-on-error: true` on a workflow step or job (Bucket E —
  workflow opt-out).
- Tool-level zero-exit flags such as `--exit-code 0`, `--exit-zero`,
  `--no-fail`, or `set +e` around a single command (Bucket F — tool
  opt-out; same effect as Bucket E, different layer).

## What to do instead

- If the finding is real but you cannot fix it now, add the tool's
  native allowlist (e.g. `.gitleaks.toml`, `pip-audit --ignore-vuln`,
  `trivy --ignore-policy`) with a tracking issue and a review date.
- If the tool is broken (wrong flag, wrong invocation), fix the
  invocation.
- If the step is genuinely advisory, gate it behind an explicit
  `if`-check and emit `::warning::`, never silently exit zero.

## Gitleaks specifics

- Run `gitleaks detect --source . [--config .gitleaks.toml]` with no
  `--exit-code` flag so the default exit code 1 fails the job on any
  finding.
- Continue to upload the SARIF artifact with `if: always()` so the
  report is preserved even when the scan step fails.
- For known false positives, add `[[allowlists]]` entries to
  `.gitleaks.toml` (double-bracket array-of-tables for v8+); never
  reintroduce `--exit-code 0`.
