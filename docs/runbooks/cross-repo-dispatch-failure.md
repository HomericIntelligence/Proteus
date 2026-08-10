# Runbook: Cross-repo dispatch failure

This runbook covers the steps to diagnose and recover when Proteus
fails to deliver an apply event to Myrmidons after AchaeanFleet (or another
upstream) emits `repository_dispatch: image-pushed`.

## Symptoms

- AchaeanFleet shows a successful image push, but Myrmidons does not
  receive a corresponding apply.
- The `Cross-Repo Dispatch` workflow on Proteus shows a failed run.
- Hosts referenced in the payload remain at the previous declarative
  state for longer than the expected reconciliation window.

## Pre-flight: confirm event reception

1. Open the Proteus Actions tab → `Cross-Repo Dispatch` workflow.
2. Confirm a run was created for the suspect time window. If no run
   exists, the inbound `repository_dispatch` was never accepted —
   skip to "Inbound event missing" below.

## Step 1 — Inspect the failed run logs

1. Click the failed run.
2. Open the `Log inbound event payload` step. Verify:
   - `Event type` is `image-pushed`.
   - `Client payload` contains a `host` field.
3. If `host` is empty or missing, the `Require client_payload.host` step
   will have failed with an `::error title=dispatch-contract::` annotation
   (issue #84). This is intentional fail-closed behavior — no apply is
   dispatched. Mitigation: re-issue the upstream dispatch with `host` set,
   per `docs/dispatch-contract.md`.

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

## Step 5 — Re-trigger from dead-letter artifact

When `scripts/dispatch-apply.sh` exhausts its retry budget
(`DISPATCH_MAX_ATTEMPTS`, default 5), it writes the unsent payload to
`${GITHUB_WORKSPACE}/.dispatch-dlq/<ts>-<host>.json` and `cross-repo-dispatch.yml`
uploads that directory as the `dispatch-dlq-<run_id>` artifact (90-day
retention). `dispatch-failure-alert.yml` then opens (or comments on) a
per-host tracking issue labelled `cross-repo-dispatch, incident,
severity:major`.

1. Open the auto-filed issue. Confirm `host` matches the failure you
   are investigating.
2. From the failed run page → Artifacts → download
   `dispatch-dlq-<run_id>.zip`; unzip; inspect:
   `jq . dispatch-dlq-<run_id>/*.json` shows `host`, `last_code`,
   `last_body`, and the full original `payload`.
3. Once the underlying cause is fixed (token rotated per Step 2,
   Myrmidons recovered per Step 3, etc.), re-trigger by either:
   - Re-running the failed workflow ("Re-run all jobs") — preserves
     audit trail end-to-end. Recommended.
   - Re-emitting the upstream `image-pushed` dispatch from AchaeanFleet
     with the same payload.
   - Locally:
     `MYRMIDONS_DISPATCH_TOKEN=<token> just dispatch-apply <host>`
     using the `host` from the DLQ JSON. Bypasses the workflow audit
     trail; use only when the first two options are unavailable.
4. After a successful retry, close the tracking issue with a comment
   linking the recovery action (PR, re-run URL, or local shell session).

### Tuning during an incident

If transient failures are widespread (e.g., GitHub API degraded),
operators can temporarily bump retry budget without editing code by
setting workflow-level env vars before re-running:

- `DISPATCH_MAX_ATTEMPTS` (default 5)
- `DISPATCH_BASE_DELAY_MS` (default 1000)
- `DISPATCH_MAX_DELAY_MS` (default 30000)

Document any temporary bump in the tracking issue.

## Inbound event missing

If no Proteus `Cross-Repo Dispatch` run exists at all:

1. Check the upstream (AchaeanFleet) workflow logs to confirm it
   actually called `repository_dispatch` against Proteus.
2. If the call was made and rejected, GitHub's audit log will show a
   401/403; check whether the AchaeanFleet-side token has access.
3. If the call was made and accepted but no run started, GitHub may
   be lagging — wait 5 minutes, then retry.

## Manual recovery

Once the cause is identified, see Step 5 for the audited recovery procedure
(download DLQ artifact, then re-run workflow).

## Post-incident

- File an issue documenting the root cause (token expiry, payload
  contract drift, GitHub outage, etc.).
- If a fix lands, link the issue and update this runbook with the
  new diagnostic step.
- Update `AGENTS.md` "known critical defects" list if a new class of
  failure was uncovered.
