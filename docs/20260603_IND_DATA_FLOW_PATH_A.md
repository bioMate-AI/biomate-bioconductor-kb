# IND Module Data Flow — Path A Design (workflows → IND)

**Status:** Design proposal. Path B (manual upload) is in production (commit `69f9b6fac`); Path A is what we build next.

**Context:** The audit doc (`docs/20260603_IND_MODULE_HONEST_AUDIT.md`) found that the IND module's Step 1–5 pipeline view reads from canned per-project JSON. The user asked: "do they need to call the workflows in BioMate, or just directly use their results? are the results manually provided?" Today: manually provided. Path A makes the workflow run in BioMate the source of truth.

---

## Path A — natural flow

```
   ┌─────────────────────────────────────────────────────────────────┐
   │  Customer in BioMate chat                                       │
   │                                                                 │
   │  "Screen 12 compounds for ADMET — hERG, DILI, Ames, Ro5"        │
   │                                                                 │
   │  → BioMate routes to predict_admet_properties (AWS Batch)       │
   │  → Workflow run completes                                       │
   │  → AI: "Done. 8/12 passed all gates. Ready to roll into IND?"  │
   │                                                                 │
   │  [Roll into IND project ▾]  BM-0042 ▼  Step 2 ─────────► [Add]  │
   └─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │  Backend: workflow_completion_hook                              │
   │  - Read run outputs from S3                                     │
   │  - Map to pipeline_data sidecar (admet / pbpk / leads block)    │
   │  - Append a row to pipeline_data_audit.jsonl                    │
   │  - Push an SSE event "pipeline_data:updated" to any subscriber  │
   └─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │  /ind-report page                                               │
   │  - SSE listener bumps pipelineRefreshKey                        │
   │  - Step 2 re-renders with the real 8/12 + the real compound rows│
   │  - §2.6 prose generation now has real data to cite              │
   └─────────────────────────────────────────────────────────────────┘
```

The point: **the customer never copies values between systems.** They run their workflow in chat (already real today); BioMate routes the outputs into the matching IND project automatically.

---

## What's already real

| Layer | Status | File |
|---|---|---|
| ADMET workflow (`predict_admet_properties`) | runs on AWS Batch, real outputs in S3 | `backend/nf-core-workflows/modules/.../predict_admet_properties.nf` |
| PBPK validation against 107 reference drugs | computes real AFE/AAFE/within-2-fold | `backend/lib/galaxy/ai/drug_discovery/model_validation.py` |
| Bayesian lead optimization | real ranking with EHVI acquisition | `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py` |
| Chat → workflow routing | real (BioMate chat resolves intent → workflow + params) | `backend/lib/galaxy/ai/ai_assistant.py` |
| §2.6 prose generation (GPT-5) | real per-paragraph, streamed via SSE | `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py::_llm_narrative` |
| pipeline_data sidecar fetch | real (`GET /api/ind-report/projects/{id}/pipeline_data`) | `ind_actions_router.py` |
| Pipeline-data-driven UI | real (Steps 1–5 read pipelineData per project) | `pages/ind-report.tsx` + `IndSteps.tsx` |

## What's missing (the actual Path A work)

### A.1 — Workflow → pipeline_data writer

**File to add:** `backend/lib/galaxy/ai/drug_discovery/pipeline_data_writer.py`

```python
def write_admet_block(project_id: str, workflow_run_id: str, output_paths: dict) -> dict:
    """Read predict_admet_properties outputs from S3, project them into the
    AdmetData TS-type shape, write to pipeline_data/<project_id>.json.

    Inputs:
      project_id: IND project to update
      workflow_run_id: which run this came from (for audit)
      output_paths: dict of S3 paths the workflow produced
        {
          "admet_csv": "s3://.../admet_predictions.csv",
          "ro5_csv":   "s3://.../ro5_violations.csv",
          ...
        }

    Side effects:
      - Updates pipeline_data/<project_id>.json::admet
      - Appends pipeline_data_audit.jsonl with {ts, project_id, step="admet",
        workflow_run_id, prev_summary, new_summary}
      - Emits SSE event "pipeline_data:updated" with payload {project_id, step}
    """
```

Mirror functions: `write_pbpk_block`, `write_leads_block`, `write_compounds_block`.

### A.2 — Workflow completion hook

**File to extend:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

Add an opt-in `ind_target` parameter to workflow submission. When set, the executor's completion callback calls `pipeline_data_writer.write_X_block(...)` automatically. The chat-side router (`ai_assistant.py`) populates `ind_target` when the user has an active IND project + the workflow is one of the recognized "feeds-IND" workflows.

Recognized mappings (the registry of which workflow feeds which step):

| Workflow | Feeds | pipeline_data field |
|---|---|---|
| `predict_admet_properties` | Step 2 ADMET | `admet` |
| `pbpk_simulation` (single-compound qualification) | Step 3 PBPK | `pbpk` |
| `bayesian_lead_optimization` | Step 4 Leads | `leads` |
| `import_smiles` | Step 1 Compounds + Lead | `compounds`, `lead_smiles` |

The mapping is a YAML file (`backend/config/ind_workflow_targets.yml`) so reg-science can add new mappings without code changes.

### A.3 — SSE channel for pipeline updates

**File to add:** `backend/lib/galaxy/ai/drug_discovery/ind_sse.py`

A FastAPI `EventSourceResponse` mounted at `GET /api/ind-report/projects/{id}/events`. The frontend subscribes when the IND page is open; on receiving `pipeline_data:updated`, it bumps `pipelineRefreshKey` to trigger the existing fetch.

This is the same SSE pattern already used for `regenerateSection`, so the wiring cost is low. The challenge: an in-memory pub-sub (one process) is fine for dev; Redis pub-sub is needed for the dev/prod multi-worker gunicorn deployment.

### A.4 — "Roll into IND project" chat affordance

**File to extend:** `frontend/client/src/components/chat-message.tsx`

When the chat message contains a workflow completion (existing convention: a `workflow_completion` payload), append a small footer:

```
Done. 8/12 passed all gates.
[Roll into IND project ▾  BM-0042 ▼  Step 2 ────► Add]
```

The dropdown lists the user's IND projects (from the existing `/api/ind-report/projects` GET). On click: POSTs to a new endpoint `POST /api/ind-report/projects/{id}/ingest_workflow` with `{workflow_run_id, target_step}`, which calls the same `pipeline_data_writer` functions as the auto-hook. Manual confirmation is the safe default; the auto-hook is opt-in per project.

### A.5 — pipeline_data_audit chain

**File to add:** `data/ind_demo/registry/pipeline_data_audit.jsonl`

Every write goes through here:

```jsonl
{"ts":"2026-06-03T20:15:33Z","project_id":"p-bm0042","step":"admet","source":"workflow_run","workflow_run_id":"af3-run-9182","prev_summary":{"pass":8,"total":12},"new_summary":{"pass":10,"total":12},"actor":"ai-router","attestation":"automatic"}
{"ts":"2026-06-03T20:42:11Z","project_id":"p-bm0042","step":"admet","source":"rerun_endpoint","rerun_params":{...},"prev_summary":{"pass":10,"total":12},"new_summary":{"pass":7,"total":12},"actor":"u-jane","attestation":"manual_rerun"}
```

Three reasons this matters:

1. **Audit trail PDF (already real) extends naturally** — list every data update beneath the signature section so the FDA reviewer sees not just "signed at 2026-06-03 with doc-sha X" but also "ADMET data ingested from workflow af3-run-9182 at 14:22".
2. **Roll-back path** — at any point we can replay the chain to a prior state.
3. **Honesty** — the user can see whether a given pipeline_data block came from a real workflow, a re-run with new params, or a manual upload (Path B).

---

## Decision points

### D.1 — Auto-feed or always-confirm?

The natural-feeling path is **always-confirm by default, opt-in auto-feed per project**. Customers should see the suggestion in chat ("Roll into BM-0042 Step 2?") and click Add, rather than discovering their IND project changed without them asking.

Implementation: a per-project flag `auto_ingest_workflows: bool` (default false). When false, the chat affordance fires; when true, `pipeline_data_writer` runs on workflow completion without UI confirmation.

### D.2 — How does the workflow know which IND project?

Three approaches, in order of preference:

1. **Chat context carries it.** When the user has `/ind-report?project=p-bm0042` open in another tab and starts a workflow in chat, the chat client passes `ind_project_id` to the workflow submission. The completion hook reads it back. Most natural.
2. **AI guesses + asks.** If the chat session doesn't have an explicit project, the AI asks: "Which IND project should this go into?" Lists the user's projects.
3. **Drop into a holding pen.** If no clear project, results land in a "Recent workflow runs" tray on the IND page. User drags them onto a project. More clicks but never silently misroutes.

Recommend (1) + fallback to (2).

### D.3 — What if the customer uploaded a PDF via Path B AND a workflow auto-fed via Path A?

Path B (upload) and Path A (auto-feed) coexist. The display rule: **measured (PDF/CSV upload) always wins over computed (workflow)**. This is the existing principle in `IndSteps.tsx:284` ("Upload GLP assay results to override computational predictions. Measured values always take precedence."). The pipeline_data sidecar gets a `_provenance` field per block: `{ source: "workflow"|"upload"|"manual_rerun", attached_at, attestation }`. The §2.6 narrative cites whichever block won — and explicitly says so in prose, because that's what an FDA reviewer expects.

### D.4 — What about the §2.6 prose itself?

The prose is generated by GPT-5 against whatever pipeline_data is current at draft time. **No change needed.** It already reads the latest pipeline_data block.

The interesting follow-on: when pipeline_data updates (workflow or rerun), should we automatically regenerate §2.6.x? Default: **no, but surface a "Section is stale: data updated since this draft" badge** so the user clicks Regenerate when ready. Auto-regen is a worse UX (paragraphs change under the user's reading cursor).

---

## Effort sizing

| Item | Effort |
|---|---|
| A.1 pipeline_data_writer (4 funcs) | 2 days |
| A.2 workflow completion hook + workflow_targets.yml | 1.5 days |
| A.3 SSE channel (in-memory; Redis later) | 0.5 day |
| A.4 chat "Roll into IND" affordance | 1 day |
| A.5 pipeline_data_audit chain + extend audit PDF | 1 day |
| Tests + dev-box smoke + ind-report E2E that runs a real workflow | 2 days |

Total: **~8 person-days** to make a customer able to run a workflow in chat and watch their IND module update without copy-paste.

This is the next major lift after the A1 / A2/A3 / S2 / C1 items in the audit doc.

## What ships before this is built

Path B (manual upload, just landed): customer uploads ADMET CSV / PBPK PDF / lead-ranking export → backend stores → wetlab list shows the files. The IND module doesn't yet *use* the contents of those uploads to populate the canned pipeline_data; that's a half-step on the way to Path A.

The half-step option: after Path B is real but before Path A is built, add CSV → pipeline_data extraction. The customer uploads `admet_predictions.csv` and the backend parses the columns it recognizes (`compound_id, hERG_IC50, DILI_score, ames_flag, ...`) into the AdmetData shape. This is ~1 person-day of work and gives customers something useful without waiting for the full chat-roll-in.
