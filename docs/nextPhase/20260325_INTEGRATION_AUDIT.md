# Next Phase Integration Audit — 2026-03-25

**Integration branch:** `integration/next-phase` (pushed to GitHub)  
**PR:** https://github.com/bioMate-AI/biomate/pull/new/integration/next-phase  
**Source branches merged:** feature/langgraph-stategraph, feature/ltm-activation, feature/user-domain-profile, feature/nfcore-reindex-clean

---

## What Was Planned vs What's Now Integrated

### Workstream A — LangGraph StateGraph (from `feature/langgraph-stategraph`)

| Task | Status | File |
|------|--------|------|
| A1: `BioMateQueryState` TypedDict | ✅ Done | `backend/lib/galaxy/ai/langgraph_state.py` |
| A2: `build_biomate_pipeline()` wrapping existing nodes | ✅ Done | `backend/lib/galaxy/ai/langgraph_pipeline.py` |
| A3: LangSmith config / toggle | ✅ Done | `backend/lib/galaxy/config/ai_config.py` |
| A4 (plan): Checkpoint for long Batch jobs (MemorySaver) | ✅ Done | `langgraph_pipeline.py` uses `MemorySaver` |
| A4 (pm): Expert knowledge UI (param rationale/citation badge) | ✅ Done | `nextflow-workflow-viewer.tsx`, `parameter-group.tsx` |
| A5 (pm): FTS scoring unit tests | ✅ Done | `test_langgraph_pipeline.py` (13 unit tests) |
| A2 (pm): Search quality — FTS, scoring, pipeline intent | ✅ Done | `unified_workflow_search.py` |

**Not yet done:**
- A1 (pm): `input_types`/`output_types` columns in `workflows` table (database migration + indexer fix for 953 missing workflows)
- A3 (pm): WorkflowSession Redis model for output-type chain propagation

---

### Workstream B — User Domain Profile (from `feature/user-domain-profile`)

| Task | Status | File |
|------|--------|------|
| B1: `domain_taxonomy.py` — 14-domain DOMAIN_TAXONOMY | ✅ Done | `backend/lib/galaxy/ai/domain_taxonomy.py` |
| B2: `update_domain_profile()` / `get_domain_profile()` in AgenticMemoryService | ✅ Done | `backend/lib/galaxy/ai/memory/agentic_memory.py` |
| B3: POST/GET `/api/user/domain-profile` endpoints | ✅ Done | `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` |
| B4: `user_profile` param in `UnifiedWorkflowSearch.search()` with +2.0 domain bias | ✅ Done | `unified_workflow_search.py` |
| B5: `DomainProfileSelector` React component | ✅ Done | `frontend/client/src/components/domain-profile-selector.tsx` |
| B6: Frontend proxy for domain-profile/domain-taxonomy | ✅ Done | `frontend/server/routes.ts` |
| B7: `ResearchProfilePanel` settings component | ✅ Done | `frontend/client/src/components/settings/research-profile.tsx` |

**Not yet done:**
- B (registration step): Wire DomainProfileSelector into registration flow after signup (B4 in plan doc)
- B (settings entry point): Wire ResearchProfilePanel into Settings page navigation

---

### Workstream C — LTM Activation (from `feature/ltm-activation`)

| Task | Status | File |
|------|--------|------|
| C1: `get_recent_corrections()` in AgenticMemoryService | ✅ Done | `agentic_memory.py` |
| C1b: Inject corrections into `generate_workflow_unified()` | ✅ Done | `ai_assistant.py` |
| C2: `record_workflow_outcome()` wrapper | ✅ Done | `agentic_memory.py` |
| C2b: Hook `record_workflow_outcome()` at Nextflow terminal states | ✅ Done | `nextflow_executor.py` |
| C3: Session summary on context compression in `galaxy-assistant.ts` | ✅ Done | `galaxy-assistant.ts` |
| C3 (pm): nf-core test profile runner — `POST /api/workflows/validate_profile` | ✅ Done | `nextflow_executor.py`, `routes.ts`, `nextflow-workflow-viewer.tsx` |

**Not yet done:**
- C2 (pm): Data-dependent param auto-fill from decision trees
- C4 (pm): Parameter sweep `POST /api/workflows/sweep`
- C5 (pm): `SweepResultsPanel` comparison table

---

### Workstream D — Index Maintenance + Extras (from `feature/nfcore-reindex`)

| Task | Status | File |
|------|--------|------|
| D1 (plan): CI cron + health check endpoint | ✅ Done | `index_all_workflows.py`, `nextflow_executor.py` |
| D1 (pm): Cost estimation `POST /api/workflows/estimate_cost` | ✅ Done | `nextflow_executor.py`, `routes.ts` |
| D2 (pm): Async job notifications via `WorkflowNotificationService` | ✅ Done | `routes.ts` |
| D2 (plan): Dynamic nf-core pipeline discovery in indexer | ✅ Done | `index_all_workflows.py` |

**Not yet done:**
- D3 (pm): Reproducibility export (zip: methods.txt + params.json + nf script)
- D4 (pm): Error recovery UX (LLM error parser + "Fix & Resume" button)
- D5 (pm): Data provenance / lineage (`input_s3_uris`/`output_s3_uris` per task)

---

### Multi-task Sequencing (Workstream B from pm/)

| Task | Status |
|------|--------|
| B1 (pm): `PipelineListView` numbered recipe component | ✅ Done — `pipeline-list-view.tsx` + wired in `chat-message.tsx` |
| B2 (pm): Output-as-input wiring (`POST /api/workflows/runs/:id/resolve-outputs`) | ❌ Not done |
| B3 (pm): Sequential chain execution (`POST /api/workflows/chain`) | ❌ Not done |
| B4 (pm): LangGraph wiring for multi-task decomposition in `galaxy-assistant.ts` | ❌ Not done — **blocks B1 from rendering** |
| B5 (pm): Tests for multi-task flow | ❌ Not done |

---

## Summary Status

| Workstream | Done | Partial | Not Started |
|---|---|---|---|
| A — LangGraph + Search | 7/8 | 0 | 1 (input_types columns) |
| B — Domain Profile | 7/8 | 1 (reg wiring) | 0 |
| C — LTM | 6/9 | 0 | 3 (auto-fill, sweep, sweep panel) |
| D — Index + Extras | 4/7 | 0 | 3 (repro, error UX, provenance) |
| Multi-task (pm/B) | 1/5 | 0 | 4 (B2-B5) |

**Overall: ~25/37 planned items complete (~67%)**

---

## Top Remaining Gaps (by user impact)

### P0 — Must Fix for Pipeline Multi-task to Work
**B4: `galaxy-assistant.ts` multi-task decomposition**  
When user says "RNA-seq then DE then pathway", the AI must detect multi-step intent and return `{workflow_type: 'pipeline', pipeline_steps: [...]}`. Until this is done, `PipelineListView` (B1, already built) will never render for real multi-step requests.

### P1 — High Value, Moderate Effort
1. **B4 (pm): Sequential chain execution** (`POST /api/workflows/chain`) — needed to actually execute the pipeline list
2. **D4 (pm): Error recovery UX** — users currently see raw Nextflow stacktraces with no guidance
3. **A1 (pm): `input_types`/`output_types` DB columns** — needed for type-safe multi-step wiring

### P2 — Medium Value
4. **C2 (pm): Data-dependent param auto-fill** — walk decision trees from pilot analysis results
5. **D3 (pm): Reproducibility export** — "Export for reproducibility" button + zip generation
6. **B (registration wiring)** — wire DomainProfileSelector into the registration flow

### P3 — Nice to Have
7. **C4/C5 (pm): Parameter sweep + results panel**
8. **D5 (pm): Data provenance / lineage**

---

## Integration Branch Contents (26 files)

```
backend/
  lib/galaxy/ai/
    ai_assistant.py              — LTM correction injection, domain profile endpoints
    domain_taxonomy.py           — 14-domain DOMAIN_TAXONOMY (new)
    langgraph_pipeline.py        — LangGraph StateGraph nodes (new)
    langgraph_state.py           — BioMateQueryState TypedDict (new)
    unified_workflow_search.py   — FTS quality, pipeline intent, user_profile bias
    config/ai_config.py          — LangSmith config
    memory/agentic_memory.py     — get_recent_corrections, record_workflow_outcome
    tests/test_langgraph_pipeline.py — 13 unit tests
    jobs/qc_trace_monitor.py     — QC trace improvements
  webapps/galaxy/api/
    ai_assistant.py              — domain-profile API endpoints
    nextflow_executor.py         — preflight, cost estimate, validate profile, LTM hooks
  scripts/
    index_all_workflows.py       — dynamic nf-core discovery, CI health check

frontend/
  client/src/components/
    chat-message.tsx             — pipeline workflow_type rendering
    domain-profile-selector.tsx  — 2-step domain/topic picker (new)
    nextflow-workflow-viewer.tsx — validate environment button, param tooltips, auto-expand
    parameter-group.tsx          — defaultOpen, KnowledgeBadge, EditableParamRow
    phase-card.tsx               — phase card improvements
    settings/research-profile.tsx — ResearchProfilePanel (new)
  server/
    galaxy-assistant.ts          — session summary on compression, domain profile injection
    memory-repository.ts         — memory service improvements
    routes.ts                    — preflight, cost, validate, domain-profile proxy routes
    vite.ts                      — build improvements
  e2e/
    post-session-audit.e2e.ts    — 11 live E2E tests (all pass)

docs/nextPhase/
  20260322_AUDIT_AND_TEST_REPORT.md
  20260322_USER_PERSPECTIVE_AUDIT.md
  20260324_E2E_AUDIT_REPORT.md
  20260325_INTEGRATION_AUDIT.md   ← this file
```
