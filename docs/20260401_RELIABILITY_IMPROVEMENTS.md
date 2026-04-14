# Reliability Improvements — Claude Code Inspired

**Date:** 2026-04-01  
**Branch:** integration/next-phase  
**Based on:** `docs/20260401_CLAUDE_CODE_OPTIMIZATION_GAPS.md` + `docs/20260401_WORKFLOW_GENERATION_AGENTIC_LOOP.md`

Six targeted improvements implemented in parallel. All are contained to individual files with no pipeline restructuring.

---

## 1. SSE Disconnect + Heartbeat (`routes.ts`)

**Problem:** Client disconnects did not stop the LLM from generating tokens. No heartbeat meant proxy/load-balancer idle timeouts closed connections after ~15s silence.

**Fix:**
- `AbortController` created at handler entry; `req.on('close')` calls `abort()` immediately
- `safeSend(event, data)` replaces all `res.write()` calls — guards every write with `res.writableEnded || aborted` check
- Heartbeat timer fires every 10s (`': heartbeat\n\n'` SSE comment); started after headers sent, cleared in `finally`
- `finally` block ensures timer is always cleared

**Files:** `frontend/server/routes.ts` — `/api/chat/stream` handler only

---

## 2. Context Compressor — Orphan Tool-Pair Fix (`context-compressor.ts`)

**Problem:** After compression, `tool_result` blocks in recent messages could reference `tool_use` IDs that were in compressed (discarded) old messages. The Anthropic API rejects such orphaned pairs.

**Fix:** Added `sanitizeToolPairs(messages)` — collects all `tool_use` IDs present in the array, then filters out any `tool_result` whose `tool_use_id` is absent. Called on the final combined array (summary + recent) before return.

Also added `// TODO: replace with actual usage.input_tokens from Anthropic response when plumbed through` above the `chars * 0.25` token estimate.

**Files:** `frontend/server/context-compressor.ts`

---

## 3. Prereq Validator — Schema Cache + LLM Timeout (`workflow-prerequisites-validator.ts`)

**Problem 1:** Tool schemas were fetched from Galaxy API on every `validate()` call — typically 3–8 network calls each time.

**Problem 2:** The Anthropic `messages.create()` call in `llmAnalyze()` had no timeout — could hang indefinitely with extended thinking budget.

**Fix:**
- `schemaCache: Map<string, { schema; fetchedAt }>` + `getCachedToolSchema(toolId)` with 1-hour TTL — all `getToolSchema()` calls now go through cache
- `AbortController` with 15s `setTimeout` wraps the Anthropic call; `AbortError` falls back to `ruleBasedFallbackValidation()` (returns `fulfilled: false` conservatively)
- `clearTimeout()` in `finally` prevents timer leaks

**Files:** `frontend/server/workflow-prerequisites-validator.ts`

---

## 4. Domain Specialist — Timeout + Retry (`domain_specialist.py`)

**Problem:** `future.result()` in `_consult_parallel()` blocked indefinitely. No retry on transient LLM errors.

**Fix:**
- `as_completed(futures, timeout=30)` — outer 30s wall-clock limit for all specialists
- `future.result(timeout=25)` — per-specialist 25s cap; `TimeoutError` produces fallback recommendation
- `for attempt in range(3)` retry loop in `_consult_single()` — exponential backoff (1s, 2s) on transient errors (`rate_limit`, `overloaded`, `5xx`, `timeout`); non-transient errors bail immediately

**Added imports:** `import time`, `import concurrent.futures`

**Files:** `backend/lib/galaxy/ai/agents/domain_specialist.py`

---

## 5. Workflow Generator — Validation Retry Loop (`galaxy_workflow_generator.py`)

**Problem:** If the LLM generated invalid tool IDs, the workflow was returned with `validation_errors` attached and the LLM never got a correction opportunity.

**Fix:** `_generate_workflow_structure()` now runs a `for attempt in range(2)` loop:
- Attempt 0: if validation passes → return immediately (no extra cost)
- Validation failure on attempt 0: extracts invalid IDs, appends `CORRECTION REQUIRED` block listing invalid IDs and valid alternatives, loops to attempt 1
- Attempt 1: returns best-effort result with `validation_errors` if still failing
- Parse/exception on attempt 0: one free retry; on attempt 1: return immediately

**Cost:** +1 LLM call only when validation fails (rare). Zero extra cost on normal requests.

**Files:** `backend/lib/galaxy/ai/galaxy_workflow_generator.py`

---

## 6. Session Datasets Wiring — Concerns A + B Activated

**Problem:** `WorkflowDatasetSelector` and domain specialist format context were implemented but dormant — `uploaded_datasets=None` because the data source was incorrectly set to BioMNI catalog datasets (reverted earlier).

**Fix:** Wired `req.session.uploadedDatasets` (actual user uploads) through the full stack as a separate `session_datasets` field, keeping it strictly separate from `available_datasets` (BioMNI RAG catalog).

Full chain:
```
req.session.uploadedDatasets
  → enrichedContext.sessionDatasets  (routes.ts — both /api/chat endpoints)
  → ChatContext.sessionDatasets      (galaxy-assistant.ts)
  → generateWorkflow(sessionDatasets)
  → backendRequest.session_datasets  (galaxy-api-proxy.ts)
  → AIRequestModel.session_datasets  (api/ai_assistant.py)
  → uploaded_datasets = request.session_datasets or None
  → WorkflowDatasetSelector (Concern A) + DomainSpecialistPool (Concern B)
```

When no session uploads exist, `sessionDatasets` is `undefined` (not `[]`), so `uploaded_datasets` resolves to `None` and both concerns remain dormant — correct behavior.

**Files:**
- `frontend/shared/galaxy-types.ts`
- `frontend/server/galaxy-assistant.ts`
- `frontend/server/galaxy-api-proxy.ts`
- `frontend/server/routes.ts`
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

---

## Summary

| # | Fix | Severity | Files | Status |
|---|---|---|---|---|
| 1 | SSE disconnect + heartbeat | High | `routes.ts` | Done |
| 2 | Context compressor orphan pairs | High | `context-compressor.ts` | Done |
| 3 | Prereq validator cache + timeout | Medium | `workflow-prerequisites-validator.ts` | Done |
| 4 | Domain specialist timeout + retry | Medium | `domain_specialist.py` | Done |
| 5 | Workflow generator validation retry | Low-Medium | `galaxy_workflow_generator.py` | Done |
| 6 | Session datasets wiring (A+B) | Feature | 5 files | Done |

All 6 changes are backward-compatible. No pipeline restructuring. No new external dependencies.
