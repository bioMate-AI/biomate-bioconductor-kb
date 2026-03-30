# Session Summary — Next Phase Launch
**Date:** 2026-03-18  
**Branch context:** `next-phase-planning` (docs) + 4 feature branches (code)  
**Author:** AI Engineer session

---

## What Was Done This Session

### 0. Pre-work: Audit of connection_formal

Before starting new work, audited `connection_formal` against the next-phase plan to avoid re-implementing already-done work.

**Found already complete (from previous sessions):**
- `realtime/status` + `error-summary` proxy routes in `routes.ts`
- `workflow_chain.py` — chain execution backend (B2+B3 from Phase 1 plan)
- `pipeline-list-view.tsx` — multi-step pipeline UI component
- `pilot-run-panel.tsx` + `/api/nextflow/preflight` endpoint
- `estimate_workflow_cost` + `parse_workflow_error` in `nextflow_executor.py`
- `estimate_cost`, `parse_error`, `reproducibility`, `provenance` proxy routes
- `langgraph` 1.1.2 installed in `.venv`
- `research_domain` column in LTM schema
- `agentic_memory.py` core methods (`record_episode`, `record_correction`, `load_user_context`)
- `index_all_workflows.py` (1149-line script, 2285 workflows indexed)

**Confirmed missing (gaps to fill):**
- `langgraph_state.py`, `langgraph_pipeline.py` — StateGraph not wired
- `domain_taxonomy.py`, `domain-profile-selector.tsx`, `research-profile.tsx` — domain profile UI/backend
- Correction logs not injected back into prompts
- Workflow outcomes not recorded from `nextflow_executor.py`
- Session summary on compression missing
- Only 100/230 nf-core pipelines indexed (7 hardcoded, not filesystem scan)
- No CI cron for re-indexing

---

### 1. Four Feature Branches Created

All cut from `next-phase-planning`:

| Branch | Workstream | Priority |
|--------|-----------|----------|
| `feature/langgraph-stategraph` | A — LangGraph StateGraph | P1 |
| `feature/user-domain-profile` | B — User Domain Profile | P1 |
| `feature/ltm-activation` | C — LTM Activation | P2 |
| `feature/nfcore-reindex` | D — Index Maintenance | P2 |

---

### 2. Workstream A — LangGraph StateGraph (`feature/langgraph-stategraph`)

**Commit:** `c72b66b5d`

**Files created:**

`backend/lib/galaxy/ai/langgraph_state.py`
- Defines `BioMateQueryState` TypedDict with all query lifecycle fields: `query`, `session_id`, `user_id`, `intent`, `confidence`, `clarification_needed`, `workflow_candidates`, `selected_workflow`, `parameters`, `execution_run_id`, `autofix_attempts`, `error`, `final_response`

`backend/lib/galaxy/ai/langgraph_pipeline.py`
- Full StateGraph wrapping existing agents as thin nodes (no logic changes):
  - `classify_intent` → existing intent router
  - `check_clarification` → conditional: clarification needed → `END`, else → `search_workflows`
  - `search_workflows` → `UnifiedWorkflowSearch.search()`
  - `generate_workflow` → existing workflow generator
  - `dispatch_execution` → existing executor
  - `run_autofix` → `AutoFix3Orchestrator` (on error, max 3 retries)
- `MemorySaver` checkpointing keyed by `session_id`
- `build_biomate_pipeline(ai_assistant=None)` factory — works in tests without real AI

`backend/lib/galaxy/config/ai_config.py` (modified)
- LangSmith tracing config gated behind `LANGSMITH_API_KEY` env var (off by default)
- `configure_langsmith()` no-op unless key is set

`backend/lib/galaxy/ai/tests/test_langgraph_pipeline.py`
- **13/13 unit tests pass** — state instantiation, graph compilation, happy path, clarification early-exit, autofix retry loop

**Not yet done (future):** Wire `build_biomate_pipeline()` into `ai_assistant.py`'s main request path (currently parallel module, not yet active).

---

### 3. Workstream B — User Domain Profile (`feature/user-domain-profile`)

**Commit:** `3433a8e2c`

**Files created/modified:**

`backend/lib/galaxy/ai/domain_taxonomy.py` (new)
- Static 14-domain taxonomy: genomics, transcriptomics, single_cell, epigenomics, proteomics, metabolomics, metagenomics, structural_biology, drug_discovery, cryo_em, pharmacology, systems_biology, synthetic_biology, bioimaging
- `DOMAIN_LABELS` display names dict
- `get_topics_for_domains(domains)` helper

`backend/lib/galaxy/ai/memory/agentic_memory.py` (modified)
- `update_domain_profile(user_id, domains, topics)` — stores as `UserPreference` row with key `"domain_profile"`, no schema migration needed
- `get_domain_profile(user_id)` — returns `{domains: [], topics: []}` if unset

`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` (modified)
- `POST /api/user/domain-profile` — save profile
- `GET /api/user/domain-profile` — retrieve profile
- `GET /api/user/domain-taxonomy` — serve taxonomy to frontend

`backend/lib/galaxy/ai/unified_workflow_search.py` (modified)
- `search(user_profile=None)` — optional param threaded through
- Domain match gives **+2.0 score bonus** in `_calculate_score()`, only when query inference doesn't already signal a domain (query context always takes precedence)

`frontend/client/src/components/domain-profile-selector.tsx` (new)
- 2-step React component: Tier 1 = 14-domain checkbox grid (2 columns), Tier 2 = topic pills filtered to selected domains
- "Skip for now" and "Save" buttons
- Taxonomy hardcoded in component (avoids extra API round-trip)

`frontend/client/src/components/settings/research-profile.tsx` (new)
- Settings panel: fetches current profile, embeds `DomainProfileSelector`, shows save confirmation
- Explanatory note: "BioMate uses this as your starting context... your current conversation always takes precedence"

`frontend/server/routes.ts` (modified)
- Proxy routes for `POST/GET /api/user/domain-profile` and `GET /api/user/domain-taxonomy`

**Not yet done:** Registration flow Step 2 integration (navigating to domain selection after successful signup). `galaxy-assistant.ts` profile injection into system prompt.

---

### 4. Workstream C — LTM Activation (`feature/ltm-activation`)

**Commits:** `6b62376e8` (B as dep) + `74c69eb21` (C)

**Files modified:**

`backend/lib/galaxy/ai/memory/agentic_memory.py`
- `get_recent_corrections(user_id, limit=5)` — queries `CorrectionLog` table, returns `[(original_suggestion, user_correction, tool_id, timestamp)]`
- `record_workflow_outcome(user_id, session_id, query, workflow_id, outcome, ...)` — convenience wrapper over existing `record_episode()`

`backend/lib/galaxy/ai/ai_assistant.py`
- Before `generate_workflow_unified()`: fetches `get_recent_corrections()` and appends `[Memory context]` annotation to `user_intent` — influences BM25 search, template matching, and LLM generation
- Gated behind `MEMORY_AVAILABLE and self.agentic_memory`

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- At Nextflow job terminal state (success/failure): calls `record_workflow_outcome()`
- Fully wrapped in `try/except` — LTM failure never affects job flow

`frontend/server/galaxy-assistant.ts`
- Compression detection at `.slice(-6)` threshold
- Fires `_triggerSessionSummary()` (fire-and-forget) — calls Claude Haiku for 2-3 sentence summary, POSTs to `/api/memory/session-summary`

`frontend/server/routes.ts`
- `POST /api/memory/session-summary` proxy route

`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
- `POST /api/ai_assistant/memory/session-summary` — stores summary in `LtmSession` table

---

### 5. Workstream D — Index Maintenance (`feature/nfcore-reindex`)

**Commits:** `199f05c56`, `f0c19abb1`, `ba5945ef7`, `67a045fe6`, `ff6d73893`

**nf-core registry pull (major):**
- Sparse-cloned all 153 missing pipelines from `github.com/nf-core` into `backend/nf-core-workflows/`
- Only `main.nf` + `nextflow_schema.json` fetched per repo (`--depth=1 --sparse`) — efficient, no full history
- 153/153 succeeded, 0 failures
- 23 directories without `main.nf` confirmed as infrastructure repos (slackbot, logos, ops), not pipelines

**Indexer fix (`backend/scripts/index_all_workflows.py`):**
- `index_nfcore_pipelines()` was hardcoded to 7-entry dict — now dynamically scans entire `nf-core-workflows/` directory
- New `_parse_nfcore_schema()` helper extracts description and param names from `nextflow_schema.json` for auto-generation
- Curated metadata for 7 known pipelines unchanged; all others auto-generated
- **Result: nfcore count 100 → 230; total workflows 2,306 → 2,436**

**CI cron (`.github/workflows/reindex-workflows.yml`):**
- Weekly schedule: Sunday 2am UTC
- `workflow_dispatch` for manual trigger
- Self-hosted crontab equivalent documented as comment

**Index health endpoint (`/api/admin/index-health`):**
- Returns counts by source + `last_indexed` timestamps + staleness flag (>7 days)
- Proxy route added to `frontend/server/routes.ts`

---

## Current Branch State

```
next-phase-planning (docs base)
├── feature/langgraph-stategraph   ← 1 commit: A only (independent files)
├── feature/user-domain-profile    ← 1 commit: B only
├── feature/ltm-activation         ← 2 commits: B (dep) + C
└── feature/nfcore-reindex         ← 5 commits: B + C + A + D + indexer fix
```

---

## What's Next

### Immediate (P1 — unblock production value)

**N1 — Wire LangGraph pipeline into active request path (A → production)**
- `ai_assistant.py`: call `build_biomate_pipeline(self)` at session init
- Replace direct `_classify_intent_with_llm()` / `_search_workflows_two_pass()` calls with `pipeline.invoke(state, config={"configurable": {"thread_id": session_id}})`
- Enable LangSmith tracing in staging: `LANGSMITH_API_KEY=<key> LANGCHAIN_TRACING_V2=true`
- Test: verify SSE streaming still works end-to-end with pipeline wrapper active

**N2 — Registration Step 2: domain profile onboarding (B → UX)**
- `frontend/client/src/components/register-form.tsx`: after successful registration, navigate to `DomainProfileSelector` before home page
- On "Skip": store empty profile, proceed to home
- On "Save": `POST /api/user/domain-profile`, then home
- E2E test: register → select genomics → first query returns genomics-ranked results

**N3 — galaxy-assistant.ts profile injection (B → cold-start improvement)**
- At session init: `GET /api/user/domain-profile`
- If domains set: prepend to system prompt — `"User research profile: domains=[genomics], topics=[variant calling, WGS]. Use as starting bias."`
- Test: user with genomics profile + query "run my samples" → sarek/rnaseq ranked over drug-discovery workflows

### Near-term (P1 — Phase 1 pm/ plan gaps)

**N4 — WorkflowSession Redis model (A3 from pm/ plan)**
- `backend/lib/galaxy/ai/workflow_session.py`: Redis-backed session with `steps[], user_intent, data_format, output_types_by_step`
- Thread `session_id` through chat stream → search → generate
- Enables multi-turn context persistence (currently stateless per request)

**N5 — Two-tier catalog LLM wiring (A2 from pm/ plan)**
- Fix `_browse_catalog_with_llm()` as real Pass 0 — LLM returns `selected_names, confidence, clarification_question`
- Use LLM-extracted `search_terms` (not raw query) in FTS Pass 1
- Add `difflib.get_close_matches` fuzzy fallback in `_fetch_workflows_by_names()`

**N6 — input_types / output_types columns (A1 from pm/ plan)**
- Add `input_types TEXT, output_types TEXT` to `workflows` table
- Populate from `nextflow_schema.json` for nf-core, `take:` block for bioconductor
- Required for pipeline step auto-wiring (Phase 2 P2.2)

### Merge sequence (when branches are ready)

```
feature/langgraph-stategraph  ──► next-phase-planning (PR #A)
feature/user-domain-profile   ──► next-phase-planning (PR #B)
feature/ltm-activation        ──► next-phase-planning (after B merges, PR #C)
feature/nfcore-reindex        ──► next-phase-planning (PR #D, independent)
next-phase-planning           ──► connection_formal (integration PR, after all 4 green)
```

**Pre-merge checklist for each:**
- [ ] TypeScript `tsc --noEmit` passes (frontend branches)
- [ ] Python imports verified (backend branches — no circular imports)
- [ ] Unit tests pass (A: 13/13 confirmed; B/C/D: add unit tests before merge)
- [ ] Smoke test: start backend + frontend, send one query, verify no regression

### Deferred (Phase 2 — not in scope yet)

- Full Pipeline View UI with DAG (P2.1)
- Data Type System + Auto-wiring compatibility matrix (P2.2)
- Parameter Sweep full integration (P2.3)
- Parallel Branch Execution — LangGraph → Celery fan-out (P2.4)
- Tool Substitution with type validation (P2.5)
- Domain Profile override behavior (decay / hard cutoff)
- Dynamic topic lists from workflow index tags
