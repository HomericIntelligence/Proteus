# Runbook: Cross-repo dispatch failure

This runbook covers the steps to diagnose and recover when ProjectProteus
fails to deliver an apply event to Myrmidons after AchaeanFleet (or another
upstream) emits `repository_dispatch: image-pushed`.

## Symptoms

- AchaeanFleet shows a successful image push, but Myrmidons does not
  receive a corresponding apply.
- The `Cross-Repo Dispatch` workflow on ProjectProteus shows a failed run.
- Hosts referenced in the payload remain at the previous declarative
  state for longer than the expected reconciliation window.

## Pre-flight: confirm event reception

1. Open the ProjectProteus Actions tab → `Cross-Repo Dispatch` workflow.
2. Confirm a run was created for the suspect time window. If no run
   exists, the inbound `repository_dispatch` was never accepted —
   skip to "Inbound event missing" below.

## Step 1 — Inspect the failed run logs

1. Click the failed run.
2. Open the `Log inbound event payload` step. Verify:
   - `Event type` is `image-pushed`.
   - `Client payload` contains a `host` field (and, optionally, the advisory
     `image_tag` and `source` fields forwarded for the Myrmidons audit log, #15).
3. If `host` is empty or missing, the `Require client_payload.host` step
   will have failed with an `::error title=dispatch-contract::` annotation
   (issue #84). This is intentional fail-closed behavior — no apply is
   dispatched. The upstream emitter (AchaeanFleet) must send `host`; track via
   AchaeanFleet#21 and ProjectProteus#15. Mitigation: re-issue the upstream
   dispatch with `host` set, per `docs/dispatch-contract.md`.

## Step 2 — Verify the dispatch token

`scripts/dispatch-apply.sh` uses `secrets.MYRMIDONS_DISPATCH_TOKEN`.

1. In repository settings → Secrets and variables → Actions, confirm
   `MYRMIDONS_DISPATCH_TOKEN` exists and is non-expired.
2. The token must have `repo` scope (or fine-grained `contents:write` on
   Myrmidons). If expired, rotate via the documented secret-rotation
   procedure and re-run the failed workflow.

## Step 3 — Verify Myrmidons accepts the dispatch

```bash
gh api repos/HomericIntelligence/Myrmidons/dispatches \
  -f event_type=apply-from-proteus \
  -f client_payload[host]=<host>
```

(Run from a machine authenticated as the same identity backing
`MYRMIDONS_DISPATCH_TOKEN`.)

- 204 → Myrmidons accepted the event. Move on to Step 4.
- 401/403 → token revoked or scope wrong; rotate.
- 404 → Myrmidons repo renamed or moved; update `MYRMIDONS_REPO`
  default in `cross-repo-dispatch.yml`.

## Step 4 — Verify Myrmidons fired its Apply workflow

1. Open the Myrmidons Actions tab.
2. Look for an `Apply` run started shortly after Step 3.
3. If no run was created, the Myrmidons-side workflow trigger is
   misconfigured — escalate to the Myrmidons on-call.

## Inbound event missing

If no Proteus `Cross-Repo Dispatch` run exists at all:

1. Check the upstream (AchaeanFleet) workflow logs to confirm it
   actually called `repository_dispatch` against ProjectProteus.
2. If the call was made and rejected, GitHub's audit log will show a
   401/403; check whether the AchaeanFleet-side token has access.
3. If the call was made and accepted but no run started, GitHub may
   be lagging — wait 5 minutes, then retry.

## Manual recovery

Once the cause is identified, re-run by either:

- Re-running the failed Proteus workflow ("Re-run all jobs"), OR
- Re-emitting the upstream `image-pushed` dispatch from AchaeanFleet, OR
- Manually invoking `scripts/dispatch-apply.sh <host>` from a trusted
  shell with `MYRMIDONS_DISPATCH_TOKEN` exported (this bypasses the
  audit trail; prefer one of the prior options).

## Rollback — Myrmidons rejects expanded payload

If Myrmidons' `agamemnon-apply` handler starts rejecting dispatches after the
#15 change with a 4xx error citing unexpected `image_tag` or `source` fields:

1. Revert `scripts/dispatch-apply.sh` to send only `{"host": "..."}` by
   replacing the `jq` block with: `PAYLOAD=$(jq -n --arg host "${HOST}" '{event_type:"agamemnon-apply",client_payload:{host:$host}}')`
2. File a Myrmidons issue requesting the schema accept `image_tag` and
   `source` fields (see `docs/cross-repo-dispatch-contract.md`).
3. Do not merge #15 until Myrmidons schema is updated.

## Post-incident

- File an issue documenting the root cause (token expiry, payload
  contract drift, GitHub outage, etc.).
- If a fix lands, link the issue and update this runbook with the
  new diagnostic step.
- Update `CLAUDE.md` "known critical defects" list if a new class of
  failure was uncovered.
