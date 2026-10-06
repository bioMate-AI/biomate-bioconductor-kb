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
