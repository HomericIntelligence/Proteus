# ProjectProteus Tests

This directory contains the automated test suite for the pipeline logic and scripts.

| Layer | Tool | Run |
|-------|------|-----|
| Unit (Dagger TS) | Jest | `just test-unit` |
| Integration (shell) | bats-core | `just test-integration` |
| E2E (real Dagger + registry) | bats + Dagger | `JUST_RUN_E2E=1 just test-e2e` |
| Everything | — | `just test-all` |

## Running Tests Locally

```bash
# Unit tests
just test-unit

# Integration tests (mocked skopeo/curl)
just test-integration

# All automated tests
just test-all

# E2E tests (requires Docker + Dagger CLI)
JUST_RUN_E2E=1 just test-e2e
```

## Test Structure

- **`dagger/tests/unit/`** — Jest tests for the Proteus class (mocked Dagger SDK)
- **`tests/integration/`** — Bats tests for shell scripts (mocked external tools)
- **`tests/e2e/`** — Bats tests using real Dagger engine (opt-in via `JUST_RUN_E2E=1`)

## Notes

- The pre-commit hook `pipeline-test-suite` runs `just test-all` before push.
- Integration tests use PATH shims to mock `skopeo` and `curl` — no real registry or GitHub API calls.
- E2E tests require a running Docker daemon and the Dagger CLI installed.
