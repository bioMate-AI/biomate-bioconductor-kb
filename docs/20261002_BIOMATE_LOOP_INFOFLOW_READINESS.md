# BioMate Info-Flow Readiness for Two Closed Loops (A: external results → model; B: user feedback → model)

**Date:** 2026-10-02 · **Scope:** architecture-readiness audit of the *plumbing*, not of any specific training script. Read against live code in `/Users/kky/biomate-review` and `/Users/kky/biomate-connector`.

**Loop A** = external experimental results (CRO wet-lab KD/synthesis/PK CSV) → back into BioMate → usable by a model/retrain.
**Loop B** = user feedback on generated outputs/structures (via chat / instruction UI) → stored → usable by a model/loop.

---

## Headline verdict

- **Loop A — PARTIALLY-READY.** A genuine, provenance-tagged external-result → ingest → refit-model → propose-next-round loop exists **end to end — but only inside the drug-discovery "campaign" vertical.** It does not generalize to arbitrary workflow runs, and the connector auto-push seam is simulation-only (the live CRO/LIMS poll is stubbed).
- **Loop B — PARTIALLY-READY.** A real feedback → labeled-pair → retrain path exists, **but only for IND / regulatory *document text*** (customer edits of generated narrative → DPO pairs → tracked retrain). General chat feedback on outputs/structures is **UX-sentiment only** (thumbs / survey), not model-consumable corrections, and the richer structured feedback table that *could* carry them is **unwired**.

Neither loop is "not ready" — the hard mechanics (ingest endpoint, Bayesian surrogate + acquisition, auto-retrain daemon, DPO-pair store, retrain job submitter, inbound instrument parsers) are built and tested. What's missing is **generalization and unification**: these capabilities live in one vertical each, on their own silo stores, and don't cover the general design/run/output surface.

---

## FOUND / PARTIAL / MISSING table

| # | Dimension | Status | Key evidence |
|---|-----------|--------|--------------|
| 1 | **Results capture + provenance; external-result linkage** | **PARTIAL** | Provenance store for BioMate runs is **FOUND** (`executionRuns.inputBindings` = which dataset bound to each input; `parameters`, `steps`, `metrics`, `executionJson`, `nextflowOutputDir`, `galaxyInvocationId`). Findings parsed from S3 outputs. External-CSV → prior-design linkage exists **only** campaign-scoped (`/ingest-assay` + `wetlab_report_ingester`); no generic "attach external result to an executionRun" edge. |
| 2 | **Structured feedback capture (model-usable)** | **PARTIAL** | Model-usable feedback is **FOUND** only for IND/regulatory text (customer edits → DPO pairs). General chat feedback is UX-sentiment (thumbs/survey/confusion) in a separate SQLite store; the richer `ux_feedback` PG table + `feedback-service.ts` are **unwired** (no route imports them). No accept/reject/correct/annotate on generated structures/molecules. |
| 3 | **Loop orchestration / inter-round trigger** | **PARTIAL** | Inter-round DBTL is **FOUND** in drug-discovery (`auto_retrain.py` daemon: INGEST_ASSAY → refit GP → propose round N+1; `bayesian_optimizer.py` acquisition; `/model-tracks/adapt/retrain` → real retrain job). Physical Make/Test step is **stubbed** (SimAssay). PIVOT (switch-workflow-on-failure) is future work. Intra-run QC auto-loop exists separately. |
| 4 | **Connector return-path (inbound results)** | **PARTIAL** | Inbound capture code **FOUND**: most connectors read/scan instrument result files (qPCR, flow, plate-reader, LC-MS, Illumina, Nanopore, Benchling LIMS). The seam connector→`/ingest-assay` is demonstrated by `campaign_dbtl_bridge.py` — but as a **sim** (`SimAssaySource`); no live auto-push wired. |
| 5 | **Data-source / results unification** | **MISSING** | At least 6 disjoint stores for results+feedback; no single registry all surfaces read+write. This is the core blocker to generalizing either loop. |

---

## Evidence by dimension

### 1. Results capture + provenance store — PARTIAL

**Provenance of BioMate-produced runs: FOUND.**
- `frontend/shared/schema.ts:1255` `executionRuns` PG table persists run lineage: `inputBindings` ("provenance of which dataset was bound to each data-input step at launch", line 1270–1272), `parameters` (versioned), `steps`, `metrics`, `executionJson` (full Nextflow metadata blob), `nextflowOutputDir`, `nextflowRunId`, `galaxyInvocationId/HistoryId/WorkflowId`, `parentRunId`+`runSequence` (iteration lineage). This is a queryable, provenance-tagged run record.
- Output access + storage: `output_access_log` (`schema.ts:706`), S3 outputs; findings are computed by parsing S3 result files — `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:331 _parse_deseq2_results_from_s3`, `:370 _parse_enrichgo_results_from_s3`, `s3_output_files` lists per run. Findings/analysis prose path is in `ai_assistant.py`.
- In-flight cross-worker run state: `RunStateStore` / Redis (`nextflow_executor.py:54–113`, `docs/20260615_RUNS_PERSISTENCE_DESIGN.md`).

**External result (CRO CSV not produced by a BioMate workflow) ingested + linked to a prior design: PARTIAL — campaign-scoped only.**
- `POST /api/drug-discovery/{campaign_id}/ingest-assay` (`backend/lib/galaxy/webapps/galaxy/api/drug_discovery.py:7`, impl in `ai/drug_discovery/api_router.py`) ingests an external assay CSV and attaches it to a **campaign**, recording an `INGEST_ASSAY` audit event.
- `backend/lib/galaxy/ai/drug_discovery/wetlab_report_ingester.py` parses CRO CSV/JSON/PDF (and FDA NDA / EMA EPAR) into measured PK/safety fields and **tags provenance per field** (`source="measured_wetlab"` vs `"predicted_computational"`, with `reference`, `species`, `study_type`, `confidence`) — exactly the "predicted-vs-measured" signal `docs/20261001_CRO_DBTL_LOOP_DATA_SPEC.md` requires.
- **Gap:** linkage is to a drug-discovery *campaign*, not to the general `executionRuns` lineage. There is **no generic endpoint** to ingest an arbitrary external result and bind it as a provenance edge to a prior `executionRun`/design outside the drug-discovery vertical.

### 2. Feedback capture — PARTIAL

**Model-usable corrections: FOUND, but only IND/regulatory document text.**
- `backend/lib/galaxy/ai/drug_discovery/feedback_router.py` exposes customer-facing endpoints: `POST /api/ind-report/projects/{id}/edit`, `.../audit/{finding_id}/dismiss`, `.../citations/suggest`, `.../sections/{id}/regenerate`, `GET /api/regulatory/feedback/queue`, `.../active_adapter`.
- These persist to JSONL training stores — `backend/lib/galaxy/ai/drug_discovery/feedback_io.py:27` `CUSTOMER_PAIRS = data/regulatory_training/dpo/customer_pairs.jsonl`, plus `checker_feedback.jsonl`, `citation_extensions.jsonl`, `prompt_tuning_signals.jsonl`; `read_feedback_queue()` makes them retrievable.
- Consumed by `models_inference.py` `/api/model-tracks/adapt` ("learned edit pairs", `:556`) and `/api/model-tracks/adapt/retrain` (`:649`) → `regulatory_training_jobs.submit` (a real tracked retrain). So: **user correction → stored labeled pair → retrievable → retrain** is real for regulatory narrative.

**General chat/output feedback: PARTIAL — sentiment only, and the structured table is orphaned.**
- Chat UI mounts `PostRunMicroSurvey`, `ReportConfusionButton`, `SessionEndPulse` (`frontend/client/src/components/chat-with-artifacts.tsx:29–31`). These POST to `/api/feedback` (`routes.ts:1847`) which writes to a **SQLite `pilot_feedback`** table in `galaxy_ai_tools.db` (`routes.ts:916–931`). Feedback types are UX-centric (`pilot_exit_survey`, `post_run`).
- A **richer structured table exists but is unwired**: `ux_feedback` PG table (`schema.ts:1350`) carries `rating`, `reasonTags`, `runId`, `workflowId`, `messageId`, `outputUsefulnessScore`, `outputActionabilityScore`; `frontend/server/feedback-service.ts` implements create/summary/issues over it. **No route imports `feedbackService`** (grep: only its own file/test) — it is dead plumbing today.
- **Gap:** no structured accept/reject/correct/annotate on a *generated structure/molecule/output* that lands in a model-consumable store. Feedback is "was the UX clear / useful (1–5)", not "this predicted structure is wrong, here is the correction."

### 3. Loop orchestration / inter-round trigger — PARTIAL

- **Inter-round DBTL (drug-discovery): FOUND.** `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py` — a daemon per campaign that polls the audit log for new `INGEST_ASSAY` events and automatically refits the Bayesian surrogate (GP), re-scores the cached virtual library, and writes a fresh proposal round to `auto_proposals` (campaign DB). `bayesian_optimizer.py` supplies the acquisition/DECIDE step (the gap flagged in `docs/20260719_WETLAB_CLOSED_LOOP_DBTL_INTEGRATION.md §4` is now filled). `cro_order_export.py` emits the next-round CRO order.
- **Retrain trigger (regulatory): FOUND.** `/api/model-tracks/adapt/retrain` → `regulatory_training_jobs.submit`.
- **Stubbed:** the physical Make/Test hop in `campaign_dbtl_bridge.py` uses `SimAssaySource`; live CRO/LIMS poll is a swap-in, not wired.
- **Future work:** PIVOT (switch workflow on repeated failure) is a deferred third branch (project memory `project_future_work_pivot`). The intra-run QC/remediation auto-loop is a separate, existing mechanism and does not cross rounds.

### 4. Connector return-path — PARTIAL (most are inbound-capable)

Inbound (instrument/CRO → BioMate) capture code is present in nearly every connector; they read/scan result artifacts, not just push commands:

| Connector | Inbound evidence |
|---|---|
| **qPCR** | `read_biorad_pcrd`, `read_quantstudio_eds`, `scan_for_qpcr_files` |
| **Flow cytometer** | `read_fcs_header`, `scan_for_fcs_files` |
| **Plate reader** | `scan_for_plate_reader_files` (permeability readout) |
| **LC-MS** | `scan_for_lcms_files` |
| **Illumina BaseSpace** | `get_file_download_url`, `runs_to_biomate_inputs` |
| **Nanopore MinKNOW** | `run_to_biomate_params` |
| **Benchling (LIMS)** | `pull_workflow_inputs`, `push_workflow_outputs` |
| **instrument_watcher** | `scan_directory` (generic new-file watcher) |
| **CryoEM** | instrument result capture |

- The seam connector-captured-result → `POST /ingest-assay` → campaign GP is demonstrated by `/Users/kky/biomate-connector/lab_instruments/campaign_dbtl_bridge.py` (`run_bridge_sim_demo()` asserts "SEAM CLOSED").
- **Gap:** the bridge's Make/Test is **sim-only** (`SimAssaySource`; "This module never fabricates assay numbers... Wiring a live CRO/LIMS just means swapping that source"). So inbound *parsers* are FOUND; a live, automatic instrument → ingest → store push is not wired in production. Outbound-only connectors: Opentrons/robot actuation (BUILD) and SiLA2 control are command-side.

### 5. Data-source / results unification — MISSING (fragmented)

No single registry that all surfaces read+write. Results and feedback are scattered across at least six stores:

1. `executionRuns` (Postgres) — general run lineage.
2. Drug-discovery **campaign DB** (SQLite) — `auto_proposals`, `virtual_library_cache`, `INGEST_ASSAY` audit (the only place external results + proposals live).
3. Regulatory feedback **JSONL** files — `data/regulatory_training/dpo/*.jsonl` (the only model-consumable feedback store).
4. `pilot_feedback` (SQLite in `galaxy_ai_tools.db`) — general UX sentiment.
5. `ux_feedback` (Postgres) — structured, **unwired**.
6. Evidence/data sources — `backend/reference_data_complete.json` (read-only catalog).

This matches the known 3-siloed-registries fragmentation (project memory `project_data_source_fragmentation`: 30 Galaxy + 20 federation + 14 MCP sources; chat sees only ~20). **Consequence:** the drug-discovery vertical has a genuinely closed loop *because* it owns one store (the campaign DB). A general loop cannot see results/feedback uniformly, so neither loop A nor loop B generalizes beyond the vertical that owns its silo.

---

## Verdict and ranked missing plumbing

**Loop A (external results → model): PARTIALLY-READY.** Real and tested inside the drug-discovery campaign vertical (`ingest-assay` + `wetlab_report_ingester` provenance tagging + `auto_retrain` GP refit + `bayesian_optimizer` acquisition + `cro_order_export`). Not ready generally: no external-result → `executionRun` lineage edge; connector auto-push is sim-only.

**Loop B (feedback on outputs/structures → model): PARTIALLY-READY.** Real and tested for IND/regulatory document text (`feedback_router` → `customer_pairs.jsonl` → `model-tracks/adapt/retrain`). Not ready generally: chat feedback on structures/outputs is sentiment-only; the structured `ux_feedback` table is unwired; no accept/reject/correct on generated structures.

### Missing plumbing, ranked

1. **Unified results+feedback provenance registry (one store, all surfaces).** Collapse the 6 silos (campaign SQLite, regulatory JSONL, `pilot_feedback`, orphaned `ux_feedback`, `executionRuns`, evidence catalog) into one queryable store keyed by design/run id, so any result or feedback row links to the design that produced it. Without this, both loops stay trapped in their vertical. *(Fixes dim 5; unblocks 1 & 2.)*

2. **Generic external-result ingestion + lineage edge, and a live connector auto-push.** Generalize `/ingest-assay` to "attach arbitrary external CSV/result to a prior `executionRun`/design" (reusing `wetlab_report_ingester`'s measured-vs-predicted provenance tagging), and replace `SimAssaySource` in `campaign_dbtl_bridge` with a live LIMS/CRO poll so inbound connectors (qPCR/flow/plate-reader/LC-MS/Benchling) auto-land results in the registry. *(Fixes dims 1 & 4.)*

3. **Structured output/structure feedback in the general chat UI → model-consumable pairs → retrain trigger.** Add accept/reject/correct/annotate on generated structures/molecules/outputs, wire it to the orphaned `ux_feedback` service (or the unified registry), and generalize the regulatory DPO-pair → `regulatory_training_jobs.submit` retrain path so general feedback reaches a model. *(Fixes dims 2 & 3.)*
