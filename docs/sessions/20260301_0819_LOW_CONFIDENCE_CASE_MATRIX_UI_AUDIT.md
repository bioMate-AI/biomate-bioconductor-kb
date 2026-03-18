# Low-Confidence Case Matrix UI Audit (2026-03-01 08:19)

## Scope
- Expanded low-confidence policy regression from 1 scenario to a strict 3-case matrix in UI E2E.
- Goal: verify execution gating behavior and override contract across confidence shapes.

## Cases Added
1. **Domain guard block path**
   - Input includes `domainGuard.blocked = true` and low confidence.
   - Expected: `Run Workflow` disabled, override button visible.
   - Expected on override: `/api/workflows/execute` payload has `executionConfig.allowLowConfidence = true`.

2. **Feedback-only low-confidence path**
   - No domain guard block, but `needs_user_feedback = true` + `feedback_prompt`.
   - Expected: blocked run state still surfaced in UI.
   - Expected on override: same low-confidence override payload contract as above.

3. **High-confidence path**
   - `needs_user_feedback = false`, high confidence.
   - Expected: `Run Workflow` enabled, no override button.
   - Expected execute payload: no low-confidence override flag.

## Evidence
- Test file: `frontend/e2e/low-confidence-override.e2e.ts`
- Command:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/low-confidence-override.e2e.ts --project chromium --retries=0`
- Result:
  - **3 passed / 0 failed**

## Notes
- This matrix is pure UI-driven and deterministic (no fallback manual feedback POSTs).
- It also guards the metadata-shape issue that previously caused low-confidence UI signals to be dropped.
