# Cross-Repo Dispatch Contract

This document specifies the contract for `repository_dispatch` events flowing between homericintelligence repos and Proteus.

## Inbound: AchaeanFleet → Proteus (`image-pushed`)

AchaeanFleet sends `image-pushed` events to Proteus when a new OCI image is built and pushed to a registry.

| Field | Type | Required | Consumed At | Notes |
|-------|------|----------|-------------|-------|
| `host` | string | **REQUIRED** | `.github/workflows/cross-repo-dispatch.yml` | Target host for `agamemnon-apply` dispatch. If absent, missing, or empty, the `Require client_payload.host` step fails the workflow with `::error::` — see issue #84. Additionally validated for RFC 1123 format and allowlist membership — see "Host validation" below (#97). |
| `image` | string | No | Not consumed | Advisory field; documented in `AGENTS.md:38-40`. Future consumers should normalize via `docs/dispatch-contract.md`. |
| `tag` | string | No | Not consumed | Advisory field; documented in `AGENTS.md:38-40`. Future consumers should normalize via `docs/dispatch-contract.md`. |
| `image_tag` | string | No | Not consumed | Advisory field; documented in `AGENTS.md:38-40`. Future consumers should normalize via `docs/dispatch-contract.md`. |
| `source` | string | No | Not consumed | Advisory field; documented in `AGENTS.md:38-40`. Future consumers should normalize via `docs/dispatch-contract.md`. |

**Source of truth**: AchaeanFleet's `notify-proteus.sh` script.

### Host validation (issue #97)

Beyond the presence check (#84), `client_payload.host` is validated in two layers:

1. **Format**: must match RFC 1123 hostname grammar
   `^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$`. Any control
   character, whitespace, or shell metacharacter fails the check.
2. **Allowlist**: must appear as an exact-match line in
   `configs/allowed-hosts.txt`. To add a host, open a PR amending that
   file with a justification linked to a tracking issue.

Both checks run in `.github/workflows/cross-repo-dispatch.yml` (primary
trust boundary, the `Validate client_payload.host against allowlist` step)
and again in `scripts/dispatch-apply.sh` (defence in depth, also covers
local `just dispatch-apply` invocations). Both layers delegate to
`scripts/validate-host.sh::validate_host`.

## Outbound: Proteus → Myrmidons (`agamemnon-apply`)

Proteus forwards the dispatch to Myrmidons with the following event:

```json
{
  "event_type": "agamemnon-apply",
  "client_payload": {
    "host": "<validated-host-from-inbound>"
  }
}
```

**Sent by**: `scripts/dispatch-apply.sh`.

## Fail-Closed Behavior

If `host` is absent, missing, empty, not RFC 1123-compliant, or not in the
allowlist, Proteus **fails closed**:

1. `.github/workflows/cross-repo-dispatch.yml` — the `Require client_payload.host`
   step rejects an absent/empty host and logs `::error title=dispatch-contract::`;
   the `Validate client_payload.host against allowlist` step then rejects a
   malformed or non-allowlisted host (#97).
2. The failing step exits with code 1, halting the workflow.
3. No `agamemnon-apply` dispatch is sent to Myrmidons.

**Rationale**: In multi-host deployments, a silent default to any host (e.g., `hermes`) would misroute applies and corrupt cluster state. Failing closed ensures operators must explicitly provide an explicitly-allowlisted `host`; see issues #84 and #97.

## Retry & Dead-Letter Behaviour

`scripts/dispatch-apply.sh` retries the outbound POST under classified
failure conditions. **Retryable** classes — exponential backoff with
0.5–1.5× jitter between attempts:

| Class | Codes | Reason |
|-------|-------|--------|
| HTTP transient | 408, 429, 500, 502, 503, 504 | Server overload / rate limit |
| curl transport | 6 (DNS), 7 (connect), 28 (timeout), 35 (SSL connect), 52 (empty reply), 56 (recv) | Network transient |

**Non-retryable** — failure persisted to DLQ immediately, exit 1:

| Codes | Reason |
|-------|--------|
| 401, 403 | Token revoked / scope wrong — see runbook Step 2 |
| 404 | Myrmidons repo renamed — see runbook Step 3 |
| 422 | Malformed payload — fix upstream emitter |

**Configuration** (env vars, all optional):

| Var | Default | Purpose |
|-----|---------|---------|
| `DISPATCH_MAX_ATTEMPTS` | `5` | Total attempts including the first |
| `DISPATCH_BASE_DELAY_MS` | `1000` | Initial backoff (ms) |
| `DISPATCH_MAX_DELAY_MS` | `30000` | Cap for a single backoff (ms) |
| `DISPATCH_DLQ_DIR` | `${GITHUB_WORKSPACE:-$PWD}/.dispatch-dlq` | Where DLQ JSON is written |

**Dead-letter format**: one JSON file per exhausted dispatch,
`<ts>-<host>.json`, fields: `ts`, `host`, `repo`, `last_code`,
`payload` (full original outbound JSON), `last_body` (response body
from last attempt, JSON-encoded by `jq -R -s '.'` so binary/quoted
bytes are preserved).

See `docs/runbooks/cross-repo-dispatch-failure.md` Step 5 for the
operator recovery procedure.

## Local Verification

To verify the inbound contract with a test dispatch:

```bash
# Send a known-good payload (with an allowlisted host):
gh api repos/HomericIntelligence/Proteus/dispatches \
  -f event_type=image-pushed \
  -f client_payload='{"host":"hermes","image":"myapp","tag":"1.0.0"}'

# Send a failing payload (missing host):
gh api repos/HomericIntelligence/Proteus/dispatches \
  -f event_type=image-pushed \
  -f client_payload='{"image":"myapp","tag":"1.0.0"}'
# Expected: workflow run fails with ::error title=dispatch-contract:: annotation.
```

## Related Issues & Documents

- **Issue #98**: Graceful degradation in cross-repo dispatch chain (implemented via this PR).
- **Issue #84**: Fail-closed on absent/empty `host`.
- **Issue #97**: Payload validation — RFC 1123 format + allowlist enforcement.
- **Issue #15**: Coordinate AchaeanFleet emitter to ensure `host` is always sent.
- **`AGENTS.md:38-40`**: Advisory fields and future normalization.
- **`configs/allowed-hosts.txt`**: Audited allowlist of dispatch target hosts.
- **`scripts/validate-host.sh`**: Shared format + allowlist validator.
- **`.github/workflows/cross-repo-dispatch.yml`**: Inbound validation and dispatch.
- **`scripts/dispatch-apply.sh`**: Outbound dispatch to Myrmidons with retry logic.
- **`docs/runbooks/cross-repo-dispatch-failure.md`**: Troubleshooting guide.
