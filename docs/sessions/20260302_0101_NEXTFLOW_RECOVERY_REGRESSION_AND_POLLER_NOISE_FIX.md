## 2026-03-02 01:01 - Nextflow Recovery Regression + Poller Noise Fix

### What happened
- After introducing stricter Nextflow runnable acceptance in `frontend/server/galaxy-api-proxy.ts`, `complete-workflow.e2e.ts` regressed.
- Real-user symptom in UI/E2E:
  - assistant text suggested clicking Run,
  - but no executable workflow artifact was actually returned,
  - no execution run ID was captured,
  - test failed with `Execution did not complete successfully`.

### Root cause
- Recovery trial loop in `generateWorkflow()` was too fragile:
  - strict local inspectability could reject valid Nextflow candidates too early,
  - later trial request failure (`503`) aborted selection path and ended with no runnable workflow.
- This created a mismatch between assistant messaging and real execution capability.

### Fixes applied
1. **Made trial loops error-tolerant**
   - Wrapped per-trial calls in `try/catch` for both:
     - `/api/ai_assistant/search_nextflow_workflow`
     - `/api/ai_assistant/generate_workflow`
   - A single trial failure no longer collapses the whole recovery attempt.

2. **Adjusted runnable acceptance fallback**
   - Keep strict checks when script is locally inspectable (workflow signatures parsed).
   - If script path is not locally inspectable from frontend process, keep candidate as potentially runnable and defer final entry/run validation to backend executor.

3. **Removed Nextflow-only poller noise**
   - In `frontend/server/routes.ts`, prevented `galaxyPoller.startPolling(...)` for Nextflow-direct runs without a Galaxy workflow ID.
   - This avoids repeated `/api/workflows//invocations/...` 404 log noise.

### Validation evidence
- Rebuilt/restarted frontend server on `:5310`.
- Ran:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
- Result: **PASS**
  - execution run captured: `e72898c0-8d08-48b6-a786-3818dd415916`
  - invocation tracked: `1215842d-45bd-451a-9350-8b7242e42335`
  - output indicators present: visualization + download

### Log audit result
- No new `GET /api/workflows//invocations/...` entries appeared for the latest run after poller guard.
- Historical 404 entries remain in logs from prior runs (expected).

### Current status
- Real-user flow restored: workflow generated -> runnable -> executed -> artifacts visible/downloadable.
- Recovery path is now more resilient to intermittent backend trial errors.
