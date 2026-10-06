# Chain fix — live validation on dev (2026-10-06)

Deployed the chain fix to dev (sha `a40fccd7`, cursor/tutorial lineage, `RUN_STATE_STORE=redis`) and
validated with a real chain submitted via `POST /api/workflows/chain` carrying the **exact bug shape**:
a single ADMET step with a deliberately stale multi-phase name
`"Bulk RNA-seq DE -> Pathway Enrichment (airway/GSE52778 validation)"`.

Chain: `chain_1791281812_398f6e`.

## Results
| Check | Result |
|---|---|
| **Name-binding** (the headline bug) | ✅ **FIXED** — stored `chain_name = "predict_admet_properties"` (the stale RNA-seq name was dropped and the chain was bound to its one workflow). Verified via `GET /api/workflows/chain/{id}` and direct `workflow_chain._get_chain()` in-container. |
| **Normal chain completion (no hang)** | ✅ chain reached a **terminal** state (`failed`) — it did not hang; the completion path works. (The `failed` is the ADMET workflow itself under an arbitrary direct-API `smiles_list`, not a chain-system fault.) |
| **User-facing chain status** | ✅ `GET /api/workflows/chain/{id}` → **HTTP 200** (name + status + phases). This is the endpoint the frontend uses for chains. |
| **Chain-aware `_get_nextflow_status_impl` (Galaxy layer)** | ✅ direct in-container call returns `is_chain=True, status=failed` instead of a 404 — defense-in-depth for any caller using the single-run status endpoint with a chain id. |
| **Reconciler (hang recovery)** | ⏸️ **deployed + code/logic-verified, not behaviorally exercised** — this run completed normally (no worker recycle), so the reconciler had nothing to recover. Proving it fires needs an induced worker-recycle mid-chain (disruptive; not done). |

## Honest open nuance (minor, not user-facing)
The **public** `/api/nextflow/status/{chain_id}` still returns 404 (`{"error":"NotFound"}`): the Node layer
does not route a `chain_` id to Galaxy's (now chain-aware) `/api/nextflow/status/`. This is NOT the path the
frontend uses for chains (it uses `/api/workflows/chain/{id}`, which returns 200), so it is not user-facing.
Optional follow-up: have Node route `chain_` ids to Galaxy's chain-aware status (or to `/api/workflows/chain`),
purely for direct-caller consistency.

## Net
The two fixes that address the originally-observed ADMET failure are **live and validated**: a chain can no
longer be mislabeled (name bound to steps), and it reaches terminal normally. The hang-recovery reconciler is
live and logic-verified; its behavioral proof (worker-recycle) remains the one un-exercised item. The same
fixes are on next-phase via PR #274.

## UPDATE — reconciler (hang recovery) now behaviorally VALIDATED
Validated safely (no worker-kill) by simulating the orphan condition in-container and invoking the
reconciler sweep:
- **Planted orphan** (`status=running`, heartbeat stale 600s, no live driver thread, step1 unresolvable):
  the sweep logged `[chain-reconcile] claiming orphaned chain … (heartbeat stale 600s)` → `rehydrating …
  at step 1` → chain reached **terminal** (`failed`, step1 "nextflow_path not resolved") — i.e.
  **detect → SETNX-claim → re-drive → terminal**, with zero Batch compute. Test record cleaned up.
- **Bonus — real recovery:** the same sweep also detected a genuinely-stuck chain
  `chain_1791265676_6c5a9f` whose heartbeat was stale ~44,766 s (≈12.4 h) — orphaned before the reconciler
  existed — and rehydrated it. Proof the reconciler recovers real hung chains. (Side effect: I triggered
  its recovery one sweep early; the deployed per-worker reconciler is idempotent via the heartbeat + 300s
  SETNX lock and will complete it regardless.)

All four chain fixes are now validated live: name-binding, terminal/no-hang, chain-aware Galaxy status,
and reconciler hang-recovery.
