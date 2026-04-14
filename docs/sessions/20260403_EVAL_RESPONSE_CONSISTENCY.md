# 2026-04-03 — Evaluation Harness + Response Consistency

## Context

The evaluation harness (benchmarks in `evaluation/`) was connected to a running BioMate instance and producing unreliable scores. The root cause was two-fold:

1. **BioMate response inconsistency** — backend code applied ad hoc text mutations (drug development prefix, truthfulness guard) that made responses non-deterministic and made downstream parsing brittle.
2. **Evaluation adapter fragility** — the prereq recovery adapter inferred workflow generation from a hardcoded keyword list (`LAUNCH_INDICATORS`) rather than a structured signal.

This session fixes both ends so evaluation results are trustworthy.

---

## Problem 1 — Non-Streaming Endpoint (`/api/chat`) Inconsistencies

### What existed (removed)

**`shouldApplyTruthfulnessGuard` block** (`routes.ts` ~line 3273):
- Applied only when `isDrugDevelopmentQuery && unresolvedWorkflowState`
- Replaced phrases like "runnable workflow has been generated" with failure language
- Added a "Workflow generation is currently unavailable" prefix unconditionally
- Effect: AI-generated text was silently mutated; the final message contradicted what the AI actually said

**`workflowGenerationDiagnostics` suffix** (`routes.ts` ~line 3308):
- Appended "To unblock this quickly, please confirm:\n- ..." to every message whenever diagnostics were non-null
- Only checked `!assistantMessage.includes("To unblock this quickly")` to suppress duplicates
- Effect: unhelpful boilerplate appended to successful responses if diagnostics happened to be set

### What replaced them

A declarative `responseState` enum computed from the actual workflow payload:

```typescript
const responseState: "workflow_ready" | "needs_input" | "workflow_failed" | "chat_only" =
  runnableWorkflow ? "workflow_ready"
  : workflowGenerationFailed ? "workflow_failed"
  : (prerequisitesValidation && !prerequisitesValidation.canRun) ? "needs_input"
  : "chat_only";
```

`state: responseState` is now returned in the JSON response body, giving the frontend and evaluation harness a reliable field to switch on rather than parsing message text.

**File**: `frontend/server/routes.ts` lines 3273-3278, 3348.

---

## Problem 2 — Streaming Endpoint (`/api/chat/stream`) Inconsistencies

This endpoint was fixed in the previous session (removed `isDrugDevelopmentQuery` prefix and `shouldApplyTruthfulnessGuard` block). This session adds the same `responseState` computation and adds two dedicated SSE events emitted *before* the final payload.

### New SSE events

```typescript
// event: workflow_ready — emitted when runnableWorkflow is true
safeSend("workflow_ready", {
  workflow_name: ga.name || "",
  workflow_id:   ga.id || "",
  workflow_type: workflowPayload.workflow_type || workflowPayload.execution_engine || "",
  nextflow_path: workflowPayload.nextflow_path || "",
  source:        workflowPayload.source || "",
  confidence:    workflowPayload.confidence ?? null,
});

// event: needs_input — emitted when prereqValidation says canRun=false
safeSend("needs_input", {
  missing: prerequisitesValidation?.items
    ?.filter((i: any) => !i.satisfied)
    .map((i: any) => i.param || i.name || "") || [],
});
```

These events are authoritative — consumers should not infer state from response text. The `state` field in the final payload mirrors the same logic.

**File**: `frontend/server/routes.ts` lines 3583-3680.

---

## Problem 3 — Evaluation Adapter Using Keyword Matching

### `evaluation/adapters/prereq_recovery_adapter.py`

**Removed**: `LAUNCH_INDICATORS` list (27 strings like "confirm & run", "workflow is ready", "mapped your request", etc.)

**Why it was wrong**: Keyword matching on free-form LLM output is inherently unreliable. Phrases differ between model versions, query types, and domain contexts. The adapter was penalizing or missing correct responses based on whether the LLM happened to use one of the listed phrases.

**Replaced with**: `if resp.workflow_card:` — uses the structured `workflow_card` object populated from the `event: workflow_ready` SSE event (or the legacy `workflow` field in the final chunk). This is a machine-parseable signal that doesn't vary with phrasing.

**Also fixed**: The runner looked for `metadata["actual_outcome"]` but the adapter wrote `metadata["outcome"]`. Added `"actual_outcome": outcome` alongside `"outcome": outcome` so both keys are set.

---

## Problem 4 — Evaluation Client SSE Parsing

### `evaluation/core/biomate_client.py`

**Added**: Full SSE event type tracking using `current_event` variable. The SSE spec sends event lines separately from data lines:

```
event: workflow_ready
data: {"workflow_name": "nf-core/sarek", ...}
```

The client now parses `event:` lines and routes the subsequent `data:` payload to the appropriate handler. Blank lines reset `current_event` to `"message"` (per SSE spec).

**`event: workflow_ready`**: Populates `ChatResponse.workflow_card` with structured fields.  
**`event: needs_input`**: No-ops (workflow_card stays None — by design).  
**All other events**: Use legacy text accumulation path.

Legacy fallback (the `workflow` field in the final JSON chunk) is kept but only applied when `workflow_card is None`, so it doesn't overwrite the structured event.

---

## Consistency Matrix After Fixes

| Endpoint | State signal | Text mutations | Evaluation reads |
|---|---|---|---|
| `/api/chat` (non-streaming) | `state` field in JSON | None | Non-streaming adapters can read `state` |
| `/api/chat/stream` (streaming) | `event: workflow_ready` / `event: needs_input` + `state` in final payload | None | `biomate_client.py` reads `event:` lines |
| Evaluation adapter | `resp.workflow_card is not None` | N/A | Structured, not keyword-based |

---

## Smoke Test Results (2026-04-03)

```
cross_domain_routing:   n=3  mean=0.333  (routing working; 33% on 3 RNA-seq queries)
prereq_recovery:        n=2  mean=1.000  RESOLVED:2 (100%)
license_gating:         n=3  mean=0.667
```

All three adapters run without errors. The prereq_recovery outcome breakdown now correctly shows "RESOLVED" instead of "unknown".

---

## Files Changed

| File | Change |
|---|---|
| `frontend/server/routes.ts` | Removed `shouldApplyTruthfulnessGuard` + diagnostics suffix in non-streaming endpoint; added `responseState` + `state` field |
| `frontend/server/routes.ts` | (Streaming endpoint, prior session) Added `event: workflow_ready` / `event: needs_input` before final payload; added `state` to final payload |
| `evaluation/core/biomate_client.py` | Full SSE event type parsing; `event: workflow_ready` → `workflow_card`; legacy fallback kept |
| `evaluation/adapters/prereq_recovery_adapter.py` | Removed `LAUNCH_INDICATORS`; resolution detection uses `resp.workflow_card` only; added `actual_outcome` key to metadata |
