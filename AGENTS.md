# AGENTS.md — Proteus

This document specifies the multi-agent coordination protocols for
Proteus within the HomericIntelligence distributed agent mesh.

## Role

Proteus is the **CI/CD hub**: it owns the Dagger TypeScript
module used to build, test, and lint workloads, and it owns the
GitHub Actions workflows that wire those Dagger pipelines to the rest
of the ecosystem (notably AchaeanFleet for image pushes and
Myrmidons for cluster apply via `repository_dispatch`).

```
AchaeanFleet ──(image-pushed event)──► Proteus ──(dispatch)──► Myrmidons
                                            │
                                            ├─► Dagger build / test / lint
                                            └─► skopeo promote
```

## Role boundaries

| Agent | Owns | Must not do |
|---|---|---|
| Proteus | Dagger module, CI workflows, promote/dispatch glue | apply cluster state directly |
| ProjectAchaeanFleet | container image build and push | call Dagger functions |
| Myrmidons | declarative cluster apply | dispatch its own work |
| ProjectAgamemnon | agent orchestration | drive CI |

## Inbound handoff (Achaeans → Proteus)

AchaeanFleet (or any upstream) sends a `repository_dispatch` event:

```
event_type: image-pushed
client_payload:
  host: <hostname>
  image: <registry/image>     # advisory; not yet consumed
  tag:   <tag>                 # advisory; not yet consumed
```

Proteus reads `client_payload.host` in
`.github/workflows/cross-repo-dispatch.yml` and invokes
`scripts/dispatch-apply.sh` to forward the apply request to Myrmidons.
`host` is REQUIRED — the workflow fails closed with `::error::` if it is
absent (issue #84). The full payload contract lives in
`docs/dispatch-contract.md`. Upstream emitter alignment is tracked in #15.

## Outbound handoff (Proteus → Myrmidons)

`scripts/dispatch-apply.sh` issues a Myrmidons `repository_dispatch`
with the host argument so Myrmidons can apply the declarative state for
that host.

## Inter-agent message contracts

- GitHub `repository_dispatch` events are the transport.
- The cross-repo schema is not formally versioned yet; payload
  evolution is handled in lockstep PRs across the affected repos.

## Coordination invariants

1. **No direct cluster mutation.** Proteus never SSHes; it only
   dispatches to Myrmidons.
2. **Idempotent dispatches.** Re-issuing the same `image-pushed` event
   should not produce side effects beyond a second Myrmidons apply.
3. **Required CI green before merge.** All workflows pinned by SHA;
   see `docs/branch-protection.md`.

## See also

- `CLAUDE.md`
- `docs/runbooks/cross-repo-dispatch-failure.md`
- `docs/backwards-compat.md`
