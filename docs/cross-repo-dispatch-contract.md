# Cross-Repo Dispatch Contract

This document specifies the payload schema for the `image-pushed` → `agamemnon-apply`
dispatch chain that bridges AchaeanFleet, ProjectProteus, and Myrmidons.

## Inbound Payload (`image-pushed`)

**Sender**: AchaeanFleet (`scripts/notify-proteus.sh`)  
**Receiver**: ProjectProteus (`.github/workflows/cross-repo-dispatch.yml`)

### Required Fields

- **`host`** (string, non-empty)
  - Target host name on which Myrmidons will apply the configuration.
  - Example: `hermes`, `zephyr`, `ares`.
  - Status: **Required by this contract**. AchaeanFleet #21 tracks the upstream
    addition of this field.
  - If missing or empty, ProjectProteus workflow fails at the `Require client_payload.host` step (non-zero exit, #84).
  - See ProjectProteus #15 for the contract mismatch context.

### Forwarded Fields (Audit Context)

These fields are not required; missing fields default to empty string.

- **`image_tag`** (string)
  - OCI image tag pushed by AchaeanFleet.
  - Example: `v1.2.3`, `latest`, `sha-abc123f`.
  - Forwarded to Myrmidons for audit logging.

- **`source`** (string)
  - Emitter name. Example: `AchaeanFleet` (default), or a manual trigger name.
  - Forwarded to Myrmidons for audit logging.

### Example

```json
{
  "event_type": "image-pushed",
  "client_payload": {
    "host": "hermes",
    "image_tag": "v1.2.3",
    "source": "AchaeanFleet"
  }
}
```

## Outbound Payload (`agamemnon-apply`)

**Sender**: ProjectProteus (`scripts/dispatch-apply.sh`)  
**Receiver**: Myrmidons (`.github/workflows/agamemnon-apply.yml`)

### Contract

ProjectProteus forwards all received fields (`host`, `image_tag`, `source`) to
Myrmidons in the outbound `agamemnon-apply` event. The payload is JSON-encoded
via `jq --arg` to ensure safe handling of all characters (quotes, newlines,
backslashes, control chars).

### Required Fields

- **`host`** (string, non-empty)
  - Target host for apply. Relayed from inbound payload.
  - Myrmidons uses this to route to the appropriate apply workflow.

### Audit Context Fields

- **`image_tag`** (string)
  - Relayed from inbound payload (or empty if missing).

- **`source`** (string)
  - Relayed from inbound payload (or empty if missing).

### Example

```json
{
  "event_type": "agamemnon-apply",
  "client_payload": {
    "host": "hermes",
    "image_tag": "v1.2.3",
    "source": "AchaeanFleet"
  }
}
```

## Validation Rules

1. **Inbound validation** (ProjectProteus `cross-repo-dispatch.yml` `Require client_payload.host` step):
   - Fail non-zero (fail-closed, #84) if `host` is missing or empty.
   - Log the error message for debugging.
   - See ProjectProteus #15 for context.

2. **Outbound encoding** (ProjectProteus `scripts/dispatch-apply.sh`):
   - Use `jq -n --arg` to JSON-encode the payload. This eliminates manual
     escaping bugs and correctly handles all input characters.
   - Never interpolate user-controlled fields directly into the JSON string.

3. **Myrmidons acceptance** (Myrmidons `.github/workflows/agamemnon-apply.yml`):
   - Schema must accept `host`, `image_tag`, and `source` fields.
   - If schema does not accept the expanded payload, the Myrmidons maintainer
     must update before merging the ProjectProteus #15 change.
   - See Rollback section in `docs/runbooks/cross-repo-dispatch-failure.md`.

## Compatibility and Rollback

### Pre-Merge Verification

Before merging ProjectProteus #15, verify Myrmidons accepts the expanded payload:

```bash
gh api repos/HomericIntelligence/Myrmidons/dispatches \
  -f event_type=agamemnon-apply \
  -f 'client_payload[host]=test-host' \
  -f 'client_payload[image_tag]=test' \
  -f 'client_payload[source]=manual'
```

- **204 response** → Success. Myrmidons schema accepts all three fields.
- **4xx response** → Myrmidons schema does not accept the expanded payload.
  Do not merge #15 without updating Myrmidons first.

### If Myrmidons Rejects the Expanded Payload

See "Rollback — Myrmidons rejects expanded payload" in
`docs/runbooks/cross-repo-dispatch-failure.md`.

## Cross-References

- **ProjectProteus #15**: Cross-repo dispatch payload contract mismatch
- **ProjectProteus #13**: Validate client_payload (related, future schema-based validator)
- **ProjectProteus #84**: Related multi-host deployment issues
- **AchaeanFleet #21**: Add `host` to notify-proteus.sh
- **ADR-006**: Decouple from ai-maestro (architecture context for cross-repo dispatch)
