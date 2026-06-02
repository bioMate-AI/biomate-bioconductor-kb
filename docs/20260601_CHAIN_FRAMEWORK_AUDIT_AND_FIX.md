# Chain Framework — Audit Findings & Fix Record

**Date:** 2026-06-01
**Branch:** `integration/next-phase`

---

## What the chain framework does

A "chain" is a pre-curated or LLM-assembled sequence of Nextflow workflows where each step's outputs are automatically wired into the next step's inputs. Examples seeded in the DB:

- `rare_disease_multimodal_workup` — sarek → VEP → rnaseq → DROP → case_report (5 steps)
- `bulk_rnaseq_de_analysis` — rnaseq → differentialabundance → GSEA (3 steps)
- `drug_discovery_screening` — ADMET → docking → binding_affinity (3 steps)

The LLM matches a user request to a curated chain first; if none match, it assembles steps ad-hoc. The user sees step-by-step progress and can approve each step before the next one starts ("pipeline" mode).

---

## Three bugs found — all critical

### Bug 1 — Frontend calls non-existent endpoints (404 on first click)

`chain-execution.ts` and `chain-pipeline-sync.ts` were written calling:

| Frontend call | Correct endpoint (from routes.ts) |
|---|---|
| `POST /api/chain/submit` | `POST /api/workflows/chain` |
| `POST /api/chain/resume` | `POST /api/workflows/chain` (with `chain_run_id` set) |
| `GET /api/chain/:id/status` | `GET /api/workflows/chain/:id` |

No alias routes exist in `frontend/server/routes.ts`. Result: every "Run Pipeline" or "Run Chain" click returns a 404 and shows a red error banner. The chain never starts.

**Fix:** Updated both frontend lib files to call the correct endpoints, and to transform the payload into the shape the proxy expects (`steps[]` + `connections[]` extracted from the workflow artifact before sending).

### Bug 2 — Missing Python module causes silent thread crash after step 1

`workflow_chain.py` lines 167 and 215 import:
```python
from galaxy.chain.artifact_contracts import artifact_value, pick_artifact_file
```

The directory `backend/lib/galaxy/chain/` does not exist. Result: when the chain executor finishes step 0 and tries to wire its outputs into step 1's inputs (`_apply_connection_handoffs`), the background thread crashes with `ModuleNotFoundError`. The user sees an infinite "running…" spinner with no error message — the worst kind of failure.

**Fix:** Created `backend/lib/galaxy/chain/__init__.py` and `backend/lib/galaxy/chain/artifact_contracts.py` implementing the two functions.

### Bug 3 — Submit payload shape mismatch (would 400 even after Bug 1 fixed)

The old `submitWorkflowFromArtifact` sent:
```json
{ "workflow": { ...full artifact... }, "chatSessionId": "...", "endAtStep": 0 }
```

The proxy at `routes.ts:9388` reads:
```js
const rawSteps = req.body?.steps || req.body?.workflow_steps || [];
```

With the old shape, `rawSteps` would always be `[]` — the steps were buried inside `workflow.*`. The backend would receive an empty steps array and either reject or create a no-op chain.

**Fix:** `submitWorkflowFromArtifact` now extracts `chain_steps` / `pipeline_steps` from the artifact and sends them as top-level `steps`, plus `connections` built from the step sequence.

---

## Files changed

| File | Change |
|---|---|
| `frontend/client/src/lib/chain-execution.ts` | Fixed endpoint `/api/chain/submit` → `/api/workflows/chain`; fixed payload shape to send `steps[]` + `connections[]` directly; fixed resume to call same endpoint with `chain_run_id` |
| `frontend/client/src/lib/chain-pipeline-sync.ts` | Fixed endpoint `/api/chain/:id/status` → `/api/workflows/chain/:id` |
| `backend/lib/galaxy/chain/__init__.py` | Created (empty, makes it a package) |
| `backend/lib/galaxy/chain/artifact_contracts.py` | Created — implements `pick_artifact_file()` and `artifact_value()` |

---

## What was already working (not touched)

- `frontend/server/routes.ts` — proxy routes for `POST /api/workflows/chain`, `GET /api/workflows/chain/:id`, `/outputs`, `/manifest` are all correct and complete
- `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` — 1118-line backend implementation is solid: sequential executor, polling, auto-wiring, type compatibility, curated chain DB
- `frontend/client/src/components/chat-with-artifacts.tsx` — `handleRunChain`, `handleRunPipeline`, `handleApprovePipelineStep`, polling loop — all correct; they call the lib functions which are now fixed
- `buildChainSubmitSteps`, `buildChainConnections`, `syncPipelineStepsFromChain` — all correct helper functions

---

## Known remaining gaps (not fixed here)

- **Three seeded chains reference missing workflows**: `DROP` (rare disease), `SEACR` (CUT&TAG), `PolyAMiner-Bulk` (APA) — no Nextflow wrappers exist. These chains will fail at the step that references them. Fix: implement workflow stubs for these three, or remove those chains from the seed data.
- **No E2E test** — the fix should be validated by submitting a 2-step chain (e.g., `bulk_rnaseq_de_analysis` steps 1+2) against the dev backend and verifying step sequencing, status polling, and the "Run again" path.
- **`_apply_connection_handoffs` uses 1-based step indexing** — `target_step = step_index + 1` on line 173 of workflow_chain.py, but the connections array uses 0-based `to_step`. This off-by-one should be verified with a chain that has explicit connections wired.
