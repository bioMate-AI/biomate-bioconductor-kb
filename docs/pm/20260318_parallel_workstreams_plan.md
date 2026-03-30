# Parallel Workstreams Plan — Phase 1
**Date**: 2026-03-18
**Branch**: connection_formal
**Context**: Three major workstreams + two uncovered areas identified via architecture review

---

## Why These Three Can Run in Parallel

Each workstream owns a distinct set of files with minimal overlap. The only shared boundary is `nextflow_executor.py` (all three touch it, but at different methods). The touch-points are listed below so teammates can coordinate handoffs, not block each other.

```
Workstream A ──► WorkflowSession model (output_types) ──► B needs this to validate step connections
Workstream A ──► workflows table input_types/output_types ──► C needs this to identify pilot data format
Workstream B ──► execute_nextflow() chain calls ──► shares execution path with C (different params)
Workstream C ──► pilot-run-panel.tsx ──► viewer imports it (A/B don't touch viewer internals)
```

All three can start simultaneously. The only sequencing rule: **B's pipeline list view** should use A's `WorkflowSession.output_types` for connection validation; wire a stub first, replace when A lands.

---

## Workstream A — Workflow Selection & Generation

**Theme**: Right workflow selected every time; context persists across turns.

### Owned files
| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Wire `_browse_catalog_with_llm()` as real Pass 0; use `search_terms` (not raw query) in FTS; two-tier catalog; fuzzy name resolution |
| `backend/scripts/index_all_workflows.py` | Fix path format (add `subworkflows/`); re-index 953 missing; add `input_types` + `output_types` columns |
| `backend/database/` migrations | Add `input_types TEXT, output_types TEXT` to `workflows` table |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Propagate `analysis_type`, `data_format`, `clarification_question` from search result |
| `frontend/server/galaxy-assistant.ts` | Receive `clarification_question`; early-exit to ask user (like existing `workflowAmbiguity`) |
| **NEW**: `backend/lib/galaxy/ai/workflow_session.py` | `WorkflowSession` Redis model: `steps[], user_intent, data_format, session_id, output_types` |

### Tasks (in order)

**A1 — Indexer fix** (~2h)
1. Fix `index_all_workflows.py`: bioconductor paths → add `subworkflows/` prefix; nfcore → store canonical disk paths
2. Add `input_types TEXT, output_types TEXT` columns to `workflows` table
3. Populate `input_types`/`output_types`:
   - nfcore: parse `nextflow_schema.json` → extract `input`, `outdir` param schemas
   - bioconductor: parse `take:` block of each `.nf` file
   - biomni_nextflow: parse `params.*_file` declarations
4. Re-index 953 missing workflows

**A2 — Catalog two-tier + LLM wiring** (~3h)
1. Fix `_get_workflow_catalog()`: domain-summary tier (≤30 lines) + scoped workflow tier; include bioconductor via domain grouping
2. Wire `_browse_catalog_with_llm()` as Pass 0 in `_search_workflows_two_pass()` — LLM returns `selected_names, confidence, clarification_question`
3. Fix `_fetch_workflows_by_names()`: add `difflib.get_close_matches` fuzzy fallback
4. Use LLM-extracted `search_terms` (not raw query) in FTS Pass 1

**A3 — WorkflowSession** (~2h)
1. `WorkflowSession` dataclass stored in Redis: `session_id, steps[], user_intent, data_format, output_types_by_step`
2. `session_id` threaded through `/api/chat/stream` context → `search_nextflow_workflow()` → `generateWorkflow()`
3. Modification classifier: `value_change`, `skip_step`, `add_workflow` (sequential append) — replaces current `adjust-params`
4. Data type compatibility check when appending steps: `WorkflowSession.output_types[step_N]` must satisfy `workflows.input_types` for step N+1

**A4 — Expert knowledge UI** (~1h)
1. In `nextflow-workflow-viewer.tsx`: when a param was auto-filled from `tool_knowledge`, show `[info icon]` → tooltip with rationale + citation (PMID)
2. `[Override]` → inline editor → stored in `user_param_overrides` table per user+workflow

**A5 — Tests**
- FTS scoring unit tests: "GSE68086 lung adenocarcinoma RNA-seq" → nf-core/rnaseq ranked #1
- WorkflowSession round-trip: session persists intent across 3 chat turns
- Modification classifier: each of 3 modification types correctly classified

---

## Workstream B — Multi-Task Sequencing & Parallel

**Theme**: User says "and then do pathway enrichment" — system wires it. No DAG, just a numbered recipe.

### Context (from team share doc)
Already done (Phase A-C in `20260310_TEAM_SHARE_CHAT_QUEUE_AND_TASK_ORCHESTRATION.md`):
- Stop button, soft query queue, client-side TaskList, QC Gate inline, LangGraph foundation
- `pending_tasks` table with `depends_on UUID[]`
- `/api/pipelines/:id/events` SSE endpoint
- `_looks_like_multi_task()` heuristic

Gaps:
- LangGraph StateGraph not wired to actual Celery task dispatch
- TaskList is client-side only (doesn't survive page reload)
- No sequential hand-off: step N+1's inputs not auto-populated from step N's S3 outputs
- No real-time task list view showing pipeline as numbered recipe

### Owned files
| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | Wire `_handle_multi_task()` to LangGraph → real Celery dispatch |
| `frontend/server/routes.ts` | `POST /api/workflows/chain` — sequential N-step execution; `POST /api/workflows/runs/:id/resolve-outputs` — output-as-input wiring |
| **NEW**: `frontend/client/src/components/pipeline-list-view.tsx` | Numbered recipe list (no DAG): ① ② ③ with `← uses:` auto-inferred connection label |
| `frontend/client/src/components/chat-with-artifacts.tsx` | Render `PipelineListView` when chain detected; pass `onModifyStep` handler |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | No new methods needed; `execute_nextflow()` already supports `resume_from_run_id` |

### Tasks (in order)

**B1 — Pipeline list UI** (~3h)
Design and implement `pipeline-list-view.tsx` — the numbered recipe:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PIPELINE — 3 steps
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① nf-core/rnaseq                PENDING
  genome: GRCh38 | samples: 58
  → outputs: count matrix, QC report

② nf-core/differentialabundance PENDING
  padj: 0.05 | lfc: 1.0
  ← uses: ① count matrix

③ GSEA Pathway Enrichment       PENDING
  ← uses: ② DEG list

[Chat: "remove step 2" / "change padj to 0.01"]

         [Confirm & Run Pipeline]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
- No arrows, no node boxes — just numbered list
- `← uses: ①` is the only connection shown, always auto-inferred from data types
- Parallel branches: `② and ③ run in parallel` label
- Chat IS the editor

**B2 — Output-as-input wiring** (~2h)
`POST /api/workflows/runs/:id/resolve-outputs`: given completed run ID + candidate next-workflow path, match S3 output files to next workflow input params by extension + `workflows.output_types` (from A1).

**B3 — Sequential chain execution** (~2h)
`POST /api/workflows/chain`:
```json
{ "steps": [{"nextflow_path": "...", "params": {...}}, {...}] }
```
Executes sequentially: each step polls for completion before starting next. Step N+1's `input` param auto-filled from step N's S3 output via B2. Returns `chain_run_id` that aggregates status.

**B4 — LangGraph wiring** (~3h)
Wire `_handle_multi_task()` to actual Celery dispatch. When `_looks_like_multi_task()` returns true:
1. LLM decomposes into ordered list of workflow names
2. Each becomes a `pending_task` in DB with `depends_on` for sequential links
3. LangGraph StateGraph fan-out for parallel branches
4. TaskList persisted in `pending_tasks` table (survives reload)

**B5 — Tests**
- "RNA-seq then DE then pathway" → 3-step pipeline list rendered
- "run in parallel" → ② ③ shown with parallel label
- Chat "remove step 2" → list updates to 2 steps
- Sequential run: step 2 starts only after step 1 completes; input auto-filled

---

## Workstream C — Test Harness

**Theme**: User knows the pipeline will work before committing to a full run. Parameters validated, data characterized, pilot run on 10% sample.

### Context (what already exists)
- `pilot_analysis/registry.py`: 20 data characterization analyzers (run on raw input data, ~30s each)
- `test_harness/evaluators.py`: WorkflowEvaluator with data_flow dimension scoring
- `parameter_context_requirements.json`: `data_dependent` params with `pilot_analysis` field + decision_tree
- `POST /api/workflows/preflight`: already implemented (3-phase: parameters, S3 inputs, workflow structure)
- `pilot-run-panel.tsx`: has ValidationPhase state, configuration, progress, QC gate display
- `-resume` already in `nextflow_executor.py` (line 1317-1323)
- nf-core `-profile test` in workflow configs

### Owned files
| File | Change |
|------|--------|
| `frontend/client/src/components/pilot-run-panel.tsx` | Add data characterization phase; wire `data_dependent` param recommendations |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Parameter sweep: N execute calls sharing `-resume`; nf-core test profile runner |
| `frontend/server/routes.ts` | Sweep endpoint; comparison table endpoint |
| **NEW**: `frontend/client/src/components/sweep-results-panel.tsx` | Comparison table: padj=[0.01,0.05,0.1] × lfc=[0.5,1.0] → DEG counts per combination |
| `backend/lib/galaxy/ai/pilot_analysis/registry.py` | Already complete — wire into execution path |

### Tasks (in order)

**C1 — Wire pilot_analysis to preflight** (~2h)
When `POST /api/workflows/preflight` runs Phase 2 (input file check), also:
- Detect which `pilot_analysis` analyzers apply from `parameter_context_requirements.json` `data_dependent` entries
- Run matching analyzers (e.g. `estimate_fragment_size` for BAM inputs, ~30s)
- Return `data_characterization: {fragment_size: 180, protocol: "stranded_reverse", ...}`
- In `pilot-run-panel.tsx`: show data characterization results before pilot config

**C2 — Data-dependent param auto-fill** (~2h)
From `parameter_context_requirements.json` decision trees:
- After pilot_analysis runs, walk the decision tree for each `data_dependent` param
- E.g.: `scVI n_latent` → `estimate_scrnaseq_complexity` output → decision tree → recommend `n_latent: 20`
- Inject recommendations into `pilot-run-panel.tsx` "Parameter Recommendations" section alongside Apply/Apply All buttons

**C3 — nf-core test profile runner** (~1h)
Before pilot run on user data: "Validate pipeline environment first (5 min)" button.
`POST /api/workflows/validate_profile` → runs `nextflow run {nf_path} -profile test,docker` on smallest Batch instance → logs only → confirms environment works.
Show result: "✓ Environment validated — pipeline runs end-to-end" or error with log excerpt.

**C4 — Parameter sweep** (~3h)
`POST /api/workflows/sweep`:
```json
{
  "nextflow_path": "...",
  "base_params": {"genome": "GRCh38"},
  "sweep": {"padj_threshold": [0.01, 0.05, 0.1], "lfc": [0.5, 1.0]}
}
```
Backend: cartesian product → N `execute_nextflow()` calls, each with `resume_from_run_id = base_run_id` so upstream alignment is cached.
Returns `sweep_run_id`; status endpoint returns per-combination status + results.

**C5 — Sweep results panel** (~2h)
`SweepResultsPanel` below completion banner when `sweep_run_id` is set:
| padj | lfc | DEG count | Runtime | Status |
|------|-----|-----------|---------|--------|
| 0.01 | 0.5 | 234 | 2m14s | ✓ |
| 0.05 | 0.5 | 891 | 2m17s | ✓ |
| 0.1  | 1.0 | 1,204 | 2m19s | ✓ |

"Use these params" button on any row → fills workflow params with that combination.

**C6 — Tests**
- Preflight with BAM input: `estimate_fragment_size` runs, result in preflight response
- Data-dependent param: scVI `n_latent` recommended correctly from decision tree
- Sweep 3×2 combinations: 6 child runs all share upstream `-resume` cache; comparison table renders
- Environment validation: test profile runs, returns pass/fail

---

## What Else Is Not Covered

These are real gaps that none of the three workstreams above addresses. They are smaller scope — most are 1-2 day efforts.

### D1 — Pre-run Cost Estimation

**Gap**: No "this job will cost approximately $X" shown before the user clicks Run. Billing tracks costs after the fact. The pilot run panel shows "estimated full run cost" after pilot completes, but users need a static estimate before committing.

**What exists**: AWS Batch job definition has instance type costs. `pilot-run-panel.tsx` has "Estimated Full Run Cost" field (populated from pilot runtime extrapolation).

**Fix**:
- `POST /api/workflows/estimate_cost`: given `nextflow_path + params`, read `aws_batch_job_definition` instance type, estimate hours from `runtime_estimate` in `pilot_analysis/registry.py` or from historical runs in `pending_tasks` table, return `{min_usd, max_usd, assumptions}`.
- Show in AWAITING REVIEW panel before user confirms.

### D2 — Async Job Notification

**Gap**: Long Batch jobs (30-60 min) — user detaches, forgets, comes back to stale UI. Notification system exists in code (`workflow-notification-service` imported in `routes.ts`) but is not wired to anything.

**Fix**:
- Wire `WorkflowNotificationService` to emit when `status → completed/failed`
- Browser push notification via `ServiceWorkerRegistration.showNotification()` (already a standard browser API, no third-party needed)
- Optional: email via existing notification service if configured

### D3 — Reproducibility Export

**Gap**: After a successful run, no easy way for a bioinformatician to share/reproduce: "here is exactly what I ran."

**What exists**: `galaxy_workflow_generator.py` line 228 — methods section generation (`_generate_methods_section()`); already implemented but not exposed in UI.

**Fix**:
- "Export for reproducibility" button in DownloadCommandsPanel
- Generates a zip: `methods.txt` (prose methods section), `workflow.nf` (exact .nf used), `params.json` (exact params with applied user overrides), `software_versions.txt` (from `*_versions.yml` nf-core outputs), `aws s3 sync` command for data
- Stores in S3 alongside outputs

### D4 — Error Recovery UX

**Gap**: When a Batch job fails, user sees raw Nextflow error stack traces in the log viewer. No "what went wrong" summary, no suggested fix, no structured recovery.

**What exists**: `workflow_restarter.py` (`backend/lib/galaxy/ai/workflow_ops/`) — auto-retry logic. Not connected to UI.

**Fix**:
- LLM error parser: feed last 200 lines of failed log → Haiku → structured `{error_type, human_summary, suggested_fix, can_resume}`
- Display in red banner below failed status: "Step STAR_ALIGN failed: reference genome not found at s3://... → Check your genome param"
- If `can_resume=true`: show "Fix & Resume" button (pre-fills chat with suggested fix)

### D5 — Data Provenance / Lineage

**Gap**: No record of "this output file was produced by running workflow X on input file Y with params Z at time T." Users cannot trace outputs back to inputs across sessions.

**Fix** (minimal viable):
- Store in `pending_tasks` table: `input_s3_uris TEXT[], output_s3_uris TEXT[]` per completed task
- `GET /api/workflows/runs/:id/provenance` → returns full lineage chain (chain of runs for multi-step pipelines)
- Small "provenance" tab in DownloadCommandsPanel: input files → workflow → output files tree

---

## Dependency Map

```
A1 (indexer + columns)
  └── A2 (catalog + LLM wiring)
  └── A3 (WorkflowSession) ──────► B2 needs output_types per step
  └── C1 (uses input_types for pilot)

B1 (pipeline list UI)
  └── B2 (output-as-input wiring) ──► A1 must land first (uses output_types)
  └── B3 (chain execution) ──────────► B2 must land first
  └── B4 (LangGraph) ─────────────────► B3 must land first

C1 (pilot_analysis wired)
  └── C2 (data-dependent params)
  └── C3 (test profile runner)
  └── C4 (sweep) ─────────────────────► C3 should land first (validate env before sweep)
  └── C5 (sweep results panel) ────────► C4 must land first

D1–D5: independent, can be picked up by any teammate with bandwidth
```

## Suggested Parallelism

| Teammate | Week 1 | Week 2 |
|----------|--------|--------|
| **T1** | A1 (indexer fix + columns) → A2 (catalog + LLM) | A3 (WorkflowSession) → A4 (expert knowledge UI) |
| **T2** | B1 (pipeline list UI) → B2 (output-as-input) | B3 (chain execution) → B4 (LangGraph wiring) |
| **T3** | C1 (pilot_analysis wired) → C2 (data-dependent) | C3 (test profile) → C4 (sweep) → C5 (panel) |
| **T4** | D1 (cost estimate) + D4 (error recovery UX) | D2 (notifications) + D3 (reproducibility) + D5 (provenance) |

T4 work is independent and parallelizable with T1–T3 from day one.

## File Ownership Summary (Conflict Prevention)

| File | Owner |
|------|-------|
| `unified_workflow_search.py` | T1 (A) |
| `index_all_workflows.py` | T1 (A) |
| `workflow_session.py` (new) | T1 (A) |
| `ai_assistant.py` (propagation) | T1 (A) |
| `galaxy-assistant.ts` | T2 (B) |
| `pipeline-list-view.tsx` (new) | T2 (B) |
| `routes.ts` — chain endpoints | T2 (B) |
| `routes.ts` — sweep + cost endpoints | T3 (C) + T4 (D1) — **coordinate** |
| `nextflow_executor.py` — sweep | T3 (C) |
| `nextflow_executor.py` — resume | Already done, no change |
| `pilot-run-panel.tsx` | T3 (C) |
| `sweep-results-panel.tsx` (new) | T3 (C) |
| `pilot_analysis/registry.py` | T3 (C) — read-only wiring |
| `DownloadCommandsPanel` + provenance | T4 (D3+D5) |

`routes.ts` is touched by T2, T3, and T4. Coordinate by: T2 adds chain endpoints to a separate `routes/chain.ts`; T3 adds sweep/cost to `routes/sweep.ts`; T4 adds provenance to `routes/provenance.ts`; main `routes.ts` only imports these.
