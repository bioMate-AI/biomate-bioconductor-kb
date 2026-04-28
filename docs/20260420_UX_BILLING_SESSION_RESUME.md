# UX Panel Redesign + Billing Fix — Session Resume

**Date:** 2026-04-20  
**Branch:** integration/next-phase  
**Prior plan:** `docs/20260419_PANEL_REDESIGN_IMPL_PLAN.md`

---

## What Was Done This Session

### Billing Fix — Java Client Non-Blocking

**Problem:** Setting `JAVA_BILLING_ENABLED=true` caused the system to hang on every AI response.
The `JavaBillingClient._post()` used synchronous httpx with:
- `_TIMEOUT = 5.0s` × 3 retries with `time.sleep()` between = up to **18s per HTTP call**
- `emit_llm()` calls `_post()` twice → **36s hang** per LLM response
- This blocked FastAPI endpoint threads, making the backend unresponsive

**Root cause:** `emit_llm()`, `emit_batch_job()`, `emit_s3_put()` were documented as "fire-and-forget" but were actually synchronous blocking calls.

**Fix applied** (`backend/lib/galaxy/ai/billing/java_billing_client.py`):
1. `_TIMEOUT`: `5.0s` → `2.0s`
2. `_RETRY_DELAYS`: `(1.0, 2.0, 4.0)` → `(1.0,)` (one retry only)
3. All three emit methods now spawn **daemon threads** — they return `True` immediately and never block the caller. Max thread lifetime = 2×(2s timeout + 1s retry + 2s timeout) = 10s in background, invisible to the request.

Now `JAVA_BILLING_ENABLED=true` is safe even when the Java service at `35.86.137.71:8080` is unreachable.

---

### UX 3B — AutoLoopCard Accept Action ✅

**Before:** "Apply" button existed but only showed a toast.

**After:**
- Added `onAccept?: (paramChanges: Record<string, unknown>) => void` prop to `AutoLoopPanel`
- Renders "Apply N changes & Re-run" button (amber, `data-testid="autoloop-accept-btn"`) when `onAccept` is provided and remediations have `param_changes`
- Merges `param_changes` from ALL remediations (later entries win on key conflict)
- Viewer wires `onAcceptAutoloop`:
  1. Merges param_changes into `params` state via `setParams`
  2. Dismisses the autoloop panel
  3. Calls `handleExecute()` → triggers re-run with updated params
- `onAcceptAutoloop` added to `PhaseGroupSection` interface and call site

**Files changed:**
- `frontend/client/src/components/auto-loop-panel.tsx` — `onAccept` prop + button
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — `onAcceptAutoloop` prop + wiring

---

### UX 3C — ViewerPhase Type Completeness ✅

Added missing fields to `ViewerPhase`:
- `summary?: string` — phase-level summary text from backend `phases.summary`
- `autoloop?: boolean` — auto-loop flag from backend `phases.autoloop`

Both are now passed through in the `phases` useMemo when building from `stepsSource`.

---

## Remaining Work

| Item | Status |
|------|--------|
| SkipConfirmModal with downstream deps | Deferred — needs design review |
| EventBridge rule for compute billing | ✅ RESOLVED — rule `biomate-batch-job-state-change` ENABLED; Lambda 128+111 invocations Apr 18–20, 0 errors |
| Billing E2E assertions (llm calls, compute) | ✅ DONE — S1–S6 all have `expect(llm_cost_usd).toBeGreaterThan(0)` + compute warn |
| E2E auth fix (setupTestUser rate-limit) | ✅ DONE — `page.evaluate(fetch)` with bypass token; `playwright.config.ts` loads `.env` |
| Autoloop panel AL-0 to AL-8 | ✅ 9/9 PASSING |

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/billing/java_billing_client.py` | Thread-based emit, short timeout |
| `frontend/client/src/components/auto-loop-panel.tsx` | `onAccept` prop + Apply button |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | `onAcceptAutoloop` wiring + 3C type fields |
