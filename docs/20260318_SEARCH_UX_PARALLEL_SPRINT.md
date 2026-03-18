# Workflow Search Fix + UX Gaps Sprint

**Date:** 2026-03-18
**Branch:** connection_formal
**Trigger:** `client-demo.e2e.ts` RNA-seq scene failing — BioMate entered "Recovery Mode" with no workflow found

---

## Root Causes Identified

### RC1 — RNA-seq name tokenization (FIXED)
`nf-core/rnaseq` was tokenized as `{'nf', 'core/rnaseq'}` (slash not split).
"rnaseq" never overlapped with query words "rna" + "seq".
**Fix:** `.replace("/", " ")` + compound expansion `"rnaseq" → "rna seq"` in `_calculate_score()`.

### RC2 — Bioconductor FTS dominance (FIXED by two-pass)
Bioconductor R package docs are verbose → FTS scores 40–43 for bioconductor vs 8–36 for nf-core.
The `source_priority` bonus (nfcore=100/50 = 2.0 pts) was completely buried.
**Fix:** Two-pass SQL search skips bioconductor entirely in Pass 1 and 2.

### RC3 — `EnhancedToolSearch` 70% dormant (PARTIALLY FIXED)
4 of 5 scoring dimensions always return 0 because `user_context` was never passed.
**Fix:** `_extract_context_from_query()` infers organism/paired_end/replicates from query text
and passes as `user_context` — activates ~60% of dormant scoring without asking the user anything.

---

## Changes Made (Parallel Sprint)

### Agent 1 — Backend search (`unified_workflow_search.py`)

| Change | Description |
|--------|-------------|
| `_DOMAIN_KEYWORD_MAP` class var | Keyword→domain mapping for query-time domain inference (no LLM) |
| `_infer_domain_from_query()` | Returns ranked domain list from keyword counting |
| `_extract_context_from_query()` | Extracts organism, paired_end, num_replicates from query text |
| `_run_fts_sql()` helper | DRY wrapper for FTS JOIN query with optional WHERE clause |
| `_search_workflows_two_pass()` | **Core fix**: Pass1=format='nextflow'+domain, Pass2=format='nextflow', Pass3=fallback |
| `search()` updated | Invokes two-pass before falling back to bioconductor-inclusive search |
| Tags bonus (+4/+2 per tag) | nfcore curated tags (e.g. `["rnaseq","transcriptomics"]`) directly match query tokens |
| Category bonus (+3) | When workflow `domain` column matches inferred query domain |
| Removed `PIPELINE_INTENT_TOKENS` hack | The -8/+10 penalty was a band-aid; two-pass makes it unnecessary |

### Agent 2 — Frontend UX gaps (`workflow-artifact.tsx`, `useUnifiedExecution.ts`, `routes.ts`)

| Gap | Change | Files |
|-----|--------|-------|
| Gap 6: `progress_milestone` silently discarded | Added `ProgressMilestone` interface, milestone state, handler that appends to list, timeline JSX (`data-testid="milestone-timeline"`) | `useUnifiedExecution.ts`, `workflow-artifact.tsx` |
| Gap 3: Realtime status API never called | Added proxy route for `GET /api/workflows/:invocationId/realtime/status`, polling `useEffect` every 5s while running, AI analysis panel JSX (`data-testid="ai-realtime-panel"`) | `routes.ts`, `workflow-artifact.tsx` |

---

## Two-Pass Search Strategy (the key architectural decision)

```
Query: "RNA-seq differential expression analysis"
                │
                ▼
         infer_domain_from_query()
         → ['transcriptomics'] (6 keyword matches)
                │
                ▼
  Pass 1: SQL WHERE format='nextflow' AND domain IN ('transcriptomics')
          Results: nf-core/rnaseq (score ~14), biomni transcriptomic_biomarker (score ~11)
          Max score >= 6 → ✅ RETURN (bioconductor never seen)
                │
                (if Pass 1 fails or max < 6)
                ▼
  Pass 2: SQL WHERE format='nextflow'  (no domain filter)
          Results: nf-core pipelines from other domains that still match query
          Max score >= 4 → return
                │
                (if Pass 2 fails or max < 4)
                ▼
  Pass 3: Original full search (includes bioconductor_nf)
          Used for tool/function-level queries, not pipeline queries
```

---

## DB Metadata Usage

From the `20260318_WORKFLOW_ENGINE_OVERHAUL_UPDATE.md` overhaul, the `workflows` table has:
- `format`: `nextflow` / `bioconductor_nf` / `galaxy_ga` — used as Pass 1/2 hard filter
- `domain`: 100% populated for all sources — used as Pass 1 SQL pre-filter
- `tags`: curated JSON for nfcore (e.g. `["nf-core","rnaseq","transcriptomics"]`) — used for tags bonus
- `category`: well-populated — used for category bonus
- `tools_used`: 95%+ — available for future tool-intersection scoring

Previously only `format` was used. This sprint activates `domain`, `tags`, and `category`.

---

## EnhancedToolSearch Activation

From `20260310_TIERED_CLARIFICATION_PLAN.md`: 70% of `EnhancedToolSearch.search_with_context()` scoring
was permanently zero because `user_context` was never passed. Scoring weights:

| Weight | Dimension | Status before | Status after |
|--------|-----------|---------------|-------------|
| 25% | Omics applicability | ❌ Zero | ✅ Active when organism in query |
| 20% | Task suitability | ❌ Zero | ✅ Partial (via suitable_for) |
| 15% | Data requirements | ❌ Zero | ✅ Active when replicates in query |
| 10% | User expertise | ❌ Zero | 🟡 Active only when "expert"/"beginner" in query |
| 15% | nf-core validation | ✅ Active | ✅ Active |

**Remaining work** (Tier 2 clarification — Phase 3 of tiered plan):
Ask 1–3 bundled questions when context is ambiguous (organism/replicates/read-type).
Implement in `galaxy-assistant.ts` + `conversation-state.ts`.

---

## Test Run (Run 13)

- Started: 2026-03-18
- Log: `/tmp/client-demo-run13.log`
- Expected: All 3 scenes (ADMET, RNA-seq, CryoEM) execute successfully
- Key assertion: RNA-seq scene finds nf-core/rnaseq (not enters Recovery Mode)

---

## Open Work (from `20260310_EXECUTION_TRACING_UX_GAPS.md`)

| Gap | Status | Notes |
|-----|--------|-------|
| Gap 1: Raw Nextflow logs not surfaced | ❌ Open | Medium effort — add log tail SSE in NextflowMonitor |
| Gap 2: workflow-trace.txt task data not shown | ❌ Open | Medium effort — emit `task_trace` SSE event |
| Gap 3: Realtime status API never called | ✅ **DONE** | Added polling + AI panel in `workflow-artifact.tsx` |
| Gap 4: AutoFix results invisible | 🟡 Partial | Gap 3 fix surfaces autofix status when fixes_applied > 0 |
| Gap 5: CloudWatch container logs not surfaced | ❌ Open | High effort |
| Gap 6: progress_milestone silently discarded | ✅ **DONE** | Milestone timeline added to `workflow-artifact.tsx` |
| Gap 7: No trace display component | ❌ Open | High effort — Gantt + resource usage view |

---

## Related Documents
- `docs/20260318_WORKFLOW_ENGINE_OVERHAUL_UPDATE.md` — DB architecture (2284 workflows, 12274 tools)
- `docs/20260310_TIERED_CLARIFICATION_PLAN.md` — EnhancedToolSearch activation plan
- `docs/20260310_EXECUTION_TRACING_UX_GAPS.md` — 7 UX visibility gaps
- `docs/20260310_AUTOFIX_SYSTEM_REFERENCE.md` — AutoFix 9-fixer system
