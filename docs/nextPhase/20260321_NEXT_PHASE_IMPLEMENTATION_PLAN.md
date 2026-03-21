# BioMate Next Phase — Implementation Plan & Team Assignment

**Date:** 2026-03-21
**Branch:** `next-phase-planning`
**Status:** Ready for team review
**Source documents:**
- `docs/nextPhase/20260209_BIOMATE_ARCHITECTURE_REVIEW.md` — current system state
- `docs/nextPhase/20260321_DEEPAGENTS_AGENTHARNESS_ANALYSIS.md` — DeepAgents analysis + domain profile design

---

## Overview

Four parallel workstreams. Each is independent and can be developed, tested, and merged separately without blocking others.

| Workstream | Owner | Branch | Priority |
|---|---|---|---|
| **A — LangGraph State Machine** | Backend engineer | `feature/langgraph-stategraph` | P1 |
| **B — User Domain Profile** | Full-stack engineer | `feature/user-domain-profile` | P1 |
| **C — LTM Activation** | Backend engineer | `feature/ltm-activation` | P2 |
| **D — Index Maintenance** | DevOps / any | `feature/nfcore-reindex` | P2 |

---

## Workstream A — LangGraph StateGraph

**Goal:** Replace direct Python method calls in `ai_assistant.py` with a formal LangGraph state machine. No logic changes — pure observability and resilience upgrade.

**Why:** Long Nextflow jobs on AWS Batch (30–90 min) currently have no checkpoint/resume. If the backend restarts mid-job, state is lost. LangGraph gives us resumability and LangSmith tracing for free.

**What does NOT change:** UnifiedWorkflowSearch LLM logic, ToolKnowledgeProvider, AutoFix3, QC gate, SSE streaming, frontend — all untouched.

### Deliverables

#### A1 — Define `BioMateQueryState`
**File:** `backend/lib/galaxy/ai/langgraph_state.py` (new file)

```python
from typing import TypedDict, Optional, List
from langgraph.graph import StateGraph

class BioMateQueryState(TypedDict):
    query: str
    session_id: str
    user_id: str
    intent: Optional[str]           # from UnifiedIntentRouter
    confidence: Optional[float]
    clarification_needed: bool
    workflow_candidates: List[dict]  # from UnifiedWorkflowSearch
    selected_workflow: Optional[dict]
    parameters: Optional[dict]
    execution_run_id: Optional[str]
    autofix_attempts: int
    error: Optional[str]
    final_response: Optional[dict]
```

#### A2 — Wire Existing Agents as Nodes
**File:** `backend/lib/galaxy/ai/langgraph_pipeline.py` (new file)

Nodes (all call existing code, no logic changes):
- `classify_intent` → calls `UnifiedIntentRouter.classify()`
- `check_clarification` → conditional, calls existing ambiguity check
- `search_workflows` → calls `UnifiedWorkflowSearch.search()`
- `generate_workflow` → calls `GalaxyWorkflowGenerator` / `NextflowComposer`
- `dispatch_execution` → calls existing execution dispatcher
- `monitor_qc` → calls `QCGateHandler`
- `run_autofix` → calls `AutoFix3Orchestrator` (conditional, on error only)

Edges:
```
classify → (research_question → research_node | else → check_clarification)
check_clarification → (needed → clarify_node | else → search_workflows)
search_workflows → generate_workflow → dispatch_execution
dispatch_execution → (error → run_autofix | success → END)
run_autofix → (max_attempts → END | retry → dispatch_execution)
```

#### A3 — Enable LangSmith Tracing (optional, requires decision on data policy)
**File:** `backend/config/ai_config.py`
- Add `LANGSMITH_API_KEY` env var support
- Add `LANGCHAIN_TRACING_V2=true` toggle
- Gate behind feature flag so it can be disabled

#### A4 — Checkpoint for Long Batch Jobs
- Use LangGraph `MemorySaver` checkpointer keyed by `run_id`
- Store checkpoint in Redis (already installed) with TTL = 24h
- On Nextflow job resume (`resume_from_run_id`), restore state from checkpoint

### Files to Create/Modify
| File | Action |
|---|---|
| `backend/lib/galaxy/ai/langgraph_state.py` | Create |
| `backend/lib/galaxy/ai/langgraph_pipeline.py` | Create |
| `backend/lib/galaxy/ai/ai_assistant.py` | Modify — call pipeline instead of direct methods |
| `backend/config/ai_config.py` | Modify — add LangSmith config |
| `backend/requirements.txt` | Verify — langgraph 1.1.2 already present |

### Testing
- Unit test each node in isolation (existing tests still pass)
- Integration test: full query → response via StateGraph
- Verify checkpoint save/restore with a mock long-running job
- No E2E test changes needed (API surface unchanged)

---

## Workstream B — User Domain Profile

**Goal:** Two-tier domain + topic selection at registration and in settings. Stored in LTM, injected as starting context bias into `_classify_intent_with_llm()` and `galaxy-assistant.ts` system prompt.

**Why:** Eliminates cold-start LLM guessing on early queries. Users who select `genomics → variant calling` immediately get sarek/mutect ranked correctly on query 1.

**What this does NOT change:** LLM is still called for every intent — no keyword-first shortcuts. Profile is injected as structured context, not a rule override.

### Deliverables

#### B1 — Domain + Topic Taxonomy
**File:** `backend/lib/galaxy/ai/domain_taxonomy.py` (new file)

```python
DOMAIN_TAXONOMY = {
    "genomics": ["variant calling", "WGS", "WES", "copy number", "structural variants", "population genetics"],
    "transcriptomics": ["bulk RNA-seq", "spatial transcriptomics", "long-read RNA-seq", "ATAC-seq"],
    "single_cell": ["scRNA-seq", "scATAC-seq", "multiome", "cell typing", "trajectory analysis"],
    "epigenomics": ["ChIP-seq", "ATAC-seq", "bisulfite-seq", "CUT&RUN", "Hi-C"],
    "proteomics": ["DDA", "DIA", "phosphoproteomics", "protein-protein interaction", "structural proteomics"],
    "metabolomics": ["LC-MS", "GC-MS", "NMR", "lipidomics", "metabolic flux"],
    "metagenomics": ["16S amplicon", "shotgun metagenomics", "metatranscriptomics", "binning/MAGs"],
    "structural_biology": ["AlphaFold", "molecular docking", "MD simulation", "cryo-EM", "X-ray crystallography"],
    "drug_discovery": ["ADMET prediction", "lead optimization", "target identification", "virtual screening"],
    "cryo_em": ["SPA", "cryo-ET", "subtomogram averaging", "helical reconstruction"],
    "pharmacology": ["PK/PD modeling", "IVIVE", "dose-response", "clinical pharmacology"],
    "systems_biology": ["ODE modeling", "network analysis", "flux balance analysis", "gene regulatory networks"],
    "synthetic_biology": ["genetic circuit design", "metabolic engineering", "CRISPR design"],
    "bioimaging": ["cell segmentation", "fluorescence microscopy", "spatial omics imaging", "flow cytometry"],
}
```

#### B2 — Backend: Store Profile in LTM
**File:** `backend/lib/galaxy/ai/memory/agentic_memory.py`
- Add `user_domain_profile` field to `LtmUser` table: `domains: List[str]`, `topics: List[str]`
- Add `update_domain_profile(user_id, domains, topics)` method
- Add `get_domain_profile(user_id)` method

**File:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
- Add `POST /api/user/domain-profile` endpoint
- Add `GET /api/user/domain-profile` endpoint

#### B3 — Backend: Inject Profile into Search
**File:** `backend/lib/galaxy/ai/unified_workflow_search.py`
- `_classify_intent_with_llm(query, user_profile=None)` — add optional param
- If `user_profile` provided: prepend to Haiku system prompt:
  ```
  User research profile: domains=[genomics], topics=[variant calling, WGS]
  Use this as a starting bias. Current query context takes precedence.
  ```

**File:** `backend/lib/galaxy/ai/ai_assistant.py`
- Load `user_domain_profile` from LTM at session start
- Pass to `UnifiedWorkflowSearch.search(user_profile=profile)`

#### B4 — Frontend: Registration Step 2
**File:** `frontend/client/src/components/domain-profile-selector.tsx` (new component)
- Tier 1: checkbox grid of 14 domains (2-column layout)
- Tier 2: tag cloud of topics, appears after Tier 1 selection, domain-filtered
- "Skip for now" button — stores empty profile, uses no prior
- "Save" calls `POST /api/user/domain-profile`

**File:** `frontend/client/src/components/register-form.tsx` (or equivalent)
- After successful registration → navigate to domain profile step before home

#### B5 — Frontend: Settings Panel
**File:** `frontend/client/src/components/settings/research-profile.tsx` (new component)
- Same `DomainProfileSelector` component reused
- Accessible from user settings menu
- Shows current selection, allows update any time
- Note text: *"BioMate uses this as your starting context for workflow recommendations. Your current conversation always takes precedence."*

#### B6 — Frontend: Inject into galaxy-assistant.ts
**File:** `frontend/server/galaxy-assistant.ts`
- Load user domain profile from DB at session init
- If profile set: prepend structured context to system prompt
- If no profile: current behavior unchanged (no prior)

### Files to Create/Modify
| File | Action |
|---|---|
| `backend/lib/galaxy/ai/domain_taxonomy.py` | Create |
| `backend/lib/galaxy/ai/memory/agentic_memory.py` | Modify — add profile fields |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Modify — add 2 endpoints |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Modify — add `user_profile` param |
| `backend/lib/galaxy/ai/ai_assistant.py` | Modify — load + pass profile |
| `frontend/client/src/components/domain-profile-selector.tsx` | Create |
| `frontend/client/src/components/settings/research-profile.tsx` | Create |
| `frontend/client/src/components/register-form.tsx` | Modify — add step 2 |
| `frontend/server/galaxy-assistant.ts` | Modify — inject profile context |
| `frontend/server/routes.ts` | Modify — proxy new profile endpoints |

### Open Questions (needs decision before B3)
- [ ] Override threshold: Option A (hard cutoff at N turns) vs B (decay weight) vs C (user toggle)?
- [ ] Tier 2 topic lists: curated static per domain (as above) vs dynamically generated from workflow index tags?

### Testing
- Unit: `get_domain_profile` / `update_domain_profile` round-trip
- Unit: Haiku prompt includes profile context when profile is set, not when absent
- E2E: Register → select domains → send first query → verify ranked workflow matches profile domain
- E2E: User with no profile → same behavior as before

---

## Workstream C — LTM Activation

**Goal:** Wire the existing `agentic_memory.py` PostgreSQL schema into the active request path so correction logs feed back into model improvement, and cross-session knowledge persists properly.

**Why:** Schema and tables exist. CorrectionLog, ProjectEpisode, and UserPreference are populated but never read back into recommendations.

### Deliverables

#### C1 — Read Correction Logs into Context
**File:** `backend/lib/galaxy/ai/memory/agentic_memory.py`
- `get_recent_corrections(user_id, limit=5)` — fetch recent user corrections for this user
- Returns: `[(original_suggestion, user_correction, tool_id, timestamp)]`

**File:** `backend/lib/galaxy/ai/ai_assistant.py`
- Before workflow generation: fetch recent corrections for user
- Append to Haiku/Sonnet prompt: *"This user previously corrected: [corrections]. Avoid repeating these."*

#### C2 — Record Workflow Outcomes
**File:** `backend/lib/galaxy/ai/memory/agentic_memory.py`
- `record_episode(user_id, query, workflow_id, outcome)` — called on workflow success/failure
- `outcome`: `{status, run_duration_s, autofix_count, error_type}`

**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- On job terminal state (success/failure): call `record_episode()`

#### C3 — Session Summary on Compression
**File:** `frontend/server/galaxy-assistant.ts`
- When context compression triggers (70% token threshold): call `POST /api/memory/session-summary`
- Backend stores summary in `LtmSession` table
- Next session start: load last session summary as context prefix

### Files to Modify
| File | Action |
|---|---|
| `backend/lib/galaxy/ai/memory/agentic_memory.py` | Modify — add 3 methods |
| `backend/lib/galaxy/ai/ai_assistant.py` | Modify — inject corrections |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Modify — record episodes |
| `frontend/server/galaxy-assistant.ts` | Modify — session summary on compress |

---

## Workstream D — Index Maintenance

**Goal:** Re-index nf-core pipelines (currently 100/405 indexed, stale since 2026-02-19) and set up automated periodic re-indexing.

### Deliverables

#### D1 — Re-run Index
```bash
cd /home/yzhang/biomate
python backend/scripts/index_all_workflows.py
```
Verify counts after:
```sql
SELECT source, COUNT(*) FROM workflows GROUP BY source;
```
Expected: nfcore should grow from 100 toward 405.

#### D2 — Cron / CI Scheduled Job
**File:** `.github/workflows/reindex-workflows.yml` (new, if using GitHub Actions)
OR add to existing deployment cron:
```bash
# Weekly re-index, Sunday 2am
0 2 * * 0 cd /home/yzhang/biomate && python backend/scripts/index_all_workflows.py >> /tmp/reindex.log 2>&1
```

#### D3 — Index Health Check Endpoint
**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` or new admin endpoint
- `GET /api/admin/index-health` → returns counts by source + last_indexed timestamps
- Flag stale sources (last_indexed > 7 days)

---

## Summary: What Each Team Member Gets

### Backend Engineer 1 → Workstream A (LangGraph)
- **Files:** `langgraph_state.py` (new), `langgraph_pipeline.py` (new), minor changes to `ai_assistant.py` and `ai_config.py`
- **Key skill:** Python, LangGraph StateGraph API
- **Dependency:** None — fully isolated new files
- **Risk:** Low — all existing logic unchanged

### Backend Engineer 2 → Workstream C (LTM)
- **Files:** `agentic_memory.py`, `ai_assistant.py`, `nextflow_executor.py`
- **Key skill:** Python, SQLAlchemy, PostgreSQL
- **Dependency:** None — independent of A and B
- **Risk:** Low — additive changes only

### Full-Stack Engineer → Workstream B (Domain Profile)
- **Files:** New frontend components, `domain_taxonomy.py`, `unified_workflow_search.py` changes, `galaxy-assistant.ts`, `routes.ts`
- **Key skill:** React/TypeScript + Python
- **Dependency:** B3 (backend) should be done before B6 (frontend injection)
- **Risk:** Medium — touches registration flow; needs careful UX review

### DevOps / Any Engineer → Workstream D (Index)
- **Files:** `index_all_workflows.py` (run, not modify), optional CI yml
- **Key skill:** Shell, SQLite
- **Dependency:** None
- **Risk:** None — read-only to production, just updates DB

---

## Branch Strategy

```
stronger_backend (main)
    └── next-phase-planning          ← this doc lives here
        ├── feature/langgraph-stategraph    (Workstream A)
        ├── feature/user-domain-profile     (Workstream B)
        ├── feature/ltm-activation          (Workstream C)
        └── feature/nfcore-reindex          (Workstream D)
```

All feature branches cut from `next-phase-planning`. PRs merge back to `next-phase-planning` first for integration testing, then to `stronger_backend`.

---

## Open Questions (requires product decision)

- [ ] **LangSmith:** Is it acceptable for trace data to leave BioMate infrastructure? If not, use self-hosted LangSmith or skip A3 entirely.
- [ ] **Domain profile override:** Option A (hard cutoff at N turns) / B (decay weight) / C (user toggle) — pick before B3
- [ ] **Topic lists:** Curated static per domain vs dynamically generated from workflow index tags — pick before B1
- [ ] **Phase 2 AutoFix subagent (from DeepAgents analysis):** Defer until A is stable. Pilot on staging only.

---

## References

- Architecture review: `docs/nextPhase/20260209_BIOMATE_ARCHITECTURE_REVIEW.md`
- DeepAgents analysis: `docs/nextPhase/20260321_DEEPAGENTS_AGENTHARNESS_ANALYSIS.md`
- Current branch: `connection_formal`
- LangGraph version installed: `1.1.2`
- Workflow DB: `backend/database/galaxy_ai_tools.db` — 2,285 workflows, 12,274 tools
