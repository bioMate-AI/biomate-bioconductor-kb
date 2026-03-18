# Workflow Generation Correctness & Speed Plan

**Date:** 2026-03-10  
**Status:** Implementation in progress

---

## Problem Statement

Three gaps in the current workflow generation pipeline:

1. **SubworkflowLibrary is disconnected** — built as a runtime cache for generated workflows, but never wired into `NextflowComposer`. Repeated identical/similar requests re-run the full LLM stack every time.

2. **No correctness audit before full .nf generation** — `NextflowComposer` asks the LLM to generate a complete DSL2 workflow in a single pass. The LLM may hallucinate process names or `include{}` paths for tools that don't exist. This is caught only *after* the file is written (syntax check), not *before*, meaning the workflow may fail at runtime.

3. **Auto-fix was broken** — `workflow_ops` source files were missing (restored in previous commit).

---

## Architecture Decision: Speed First

The user's constraint is explicit: **workflow generation must not be slow**.

The naive fix (add ProposeValidateWorkflowGenerator as a separate LLM loop) would add 1–3 extra LLM calls. This is unacceptable.

**Solution: two no-extra-LLM-call layers before touching the generator LLM:**

```
User query
    │
    ▼
L0: SubworkflowLibrary cache lookup          ← instant (JSON file read)
    │  hit → return cached .nf path (0 LLM calls)
    │  miss ↓
    ▼
L1: Tool retrieval from tools table          ← fast (SQLite FTS)
    │
    ▼
L2: Tool-plan validation (DB-only)           ← fast (SQLite lookup, no LLM)
    │  Checks: which retrieved tools have wrapper_path on disk?
    │  Sorts: composable (NF-WRAPPER) tools first, ad-hoc last
    │  Drops: tools with MISSING status if good alternatives exist
    │
    ▼
L3: Single LLM call: generate full .nf      ← only LLM call (same as before)
    │  Prompt now includes ONLY validated tools
    │  No hallucinated include{} paths → fewer runtime failures
    │
    ▼
L4: Syntax validation + write to disk       ← fast (regex checks)
    │
    ▼
Store result in SubworkflowLibrary          ← async (non-blocking)
```

**Key design choices:**
- **L2 validation uses only DB lookups** — no LLM, no benchmark_knowledge.db, no network. Typical latency: 5–20 ms.
- **No refinement LLM call** — instead of asking the LLM to "fix" a bad tool list, we substitute bad tools with the best available alternative from the already-retrieved list. Pure code, instant.
- **SubworkflowLibrary cache key** = SHA-256 of (normalised user intent + sorted top-5 tool IDs). Cache hit → 0 LLM calls, ~1 ms response.
- **Async library write** — storing a result in the SubworkflowLibrary happens after returning to the caller, so it never adds latency to the user-facing response.

---

## Implementation Plan

### 1. SubworkflowLibrary cache (L0) — in `NextflowComposer`

**Changes to `nextflow_composer.py`:**
- Add `_library: SubworkflowLibrary` attribute (lazy-loaded from `database/subworkflow_library/`)
- Add `_cache_key(user_intent, tools)` → SHA-256 hash
- At the start of `compose_workflow()`: check library for structural match (Jaccard ≥ 0.8, quality ≥ 70)
- At the end (after writing the file): call `_store_in_library()` in a try/except (never block on failure)
- Cache hit returns: `{"success": True, "source": "subworkflow_library_cache", "cache_hit": True, ...}`

### 2. Tool-plan validation (L2) — in `NextflowComposer`

**New method `_validate_and_filter_tools(tools)`:**
- For each `_ToolContext`: check if `wrapper_path` resolves to a file on disk
  - If yes → `status = "NF-WRAPPER"` (preferred, include{} will work)
  - If no wrapper_path → `status = "GENERATE"` (LLM must write process block)
  - If `wrapper_path` set but file missing → `status = "BAD-PATH"` → substitute with next-best tool
- Substitution rule: if a BAD-PATH tool exists, look for another tool in the retrieved list with the same `category`, demote the bad one, promote the substitute
- Log a clear summary: `N composable (verified on disk), M ad-hoc, K bad paths substituted`
- Pass only verified tools to `_build_prompt()`

**This replaces the current post-generation `missing_includes` warning with a pre-generation filter.**

### 3. Medium/Low confidence routing — in `ai_assistant.py`

No new LLM calls added. The change is:
- **Medium confidence (Galaxy .ga format)**: instead of `EnhancedWorkflowGenerator` (Galaxy output), route through `NextflowComposer` with the `best_match` as `reference_match`. The medium-confidence Galaxy template provides structural context while `NextflowComposer` produces valid Nextflow output.
- **Low confidence**: no change — already uses `NextflowComposer`.

### 4. ProposeValidateWorkflowGenerator — deferred

The full propose-validate-refine loop (`propose_validate_workflow_generator.py`) is architecturally sound but adds at minimum 1 extra LLM call (proposal) + optional refinement call. It is **not wired in at this time** to meet the speed constraint.

It will be activated as a background "quality improvement" pass that runs *after* the workflow is returned to the user, improving the SubworkflowLibrary cache entry for next time.

---

## What Changes Per File

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/nextflow_composer.py` | Add L0 cache check + L2 tool validation + cache store |
| `backend/lib/galaxy/ai/ai_assistant.py` | Route medium-confidence Galaxy .ga matches through `NextflowComposer` |
| `backend/lib/galaxy/ai/subworkflow_library.py` | No changes — used as-is |

---

## Expected Outcome

| Scenario | Before | After |
|----------|--------|-------|
| Repeated query (cache hit) | 1 LLM call (~3–8 s) | 0 LLM calls (~1 ms) |
| New query, all tools composable | 1 LLM call, some bad includes | 1 LLM call, 0 bad includes |
| New query, mixed tools | 1 LLM call, warnings at end | 1 LLM call, bad tools substituted before prompt |
| Medium confidence Galaxy match | Galaxy .ga output (wrong format) | Nextflow .nf via composer |
| Auto-fix during execution | Broken (source files missing) | Functional (restored) |
