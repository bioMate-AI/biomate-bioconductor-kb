# Logs + UI Element Review (2026-03-05 06:55)

## Review Scope

- Runtime/server logs from recent strict UI test runs.
- UI behavior through PM-critical E2E suites.
- UI element coverage analysis based on declared `data-testid` in client components versus E2E references.

## Findings (Severity Ordered)

### 1) High: Dataset discovery path repeatedly fails (404), reducing assistant context quality

- **Observed in logs:** repeated `ERR_BAD_REQUEST` with 404 for dataset search requests.
- **Impact:** AI assistant can still return workflows, but dataset augmentation/context is degraded; this can reduce relevance quality in user-facing responses.
- **Code evidence:**
  - Proxy calls backend dataset route at:
    - `frontend/server/galaxy-api-proxy.ts` (`searchDatasets()` -> `POST /api/datasets/search`)
  - Local route exposed to client is:
    - `frontend/server/routes.ts` (`POST /api/galaxy/datasets/search`)
- **Risk to tomorrow demo:** medium-high for prompts that rely on dataset recommendations/context.

### 2) Medium: Accessibility warnings for feedback dialogs

- **Observed in browser console logs:** warnings about missing `Description` / `aria-describedby` on dialog content.
- **Likely sources:**
  - `frontend/client/src/components/feedback/post-run-micro-survey.tsx`
  - `frontend/client/src/components/feedback/session-end-pulse.tsx`
- **Impact:** non-blocking for core function, but can affect accessibility quality and may create noisy logs in demos.

### 3) Medium: Redis URL misconfiguration causes fallback to MemoryStore

- **Observed in startup logs:** Redis init fails with invalid URL and app falls back to MemoryStore.
- **Code location:**
  - `frontend/server/redis-session.ts`
- **Impact:** functional for demo, but session behavior is less production-like and state resilience is weaker.

### 4) Medium: UI element coverage is broad but not exhaustive

- **Computed coverage snapshot:**
  - Declared client `data-testid` elements: **162**
  - Explicitly covered via E2E `getByTestId`/`[data-testid*]`: **42**
  - Not explicitly testid-covered: **120**
- **Impact:** core user journey is covered and passing, but many secondary UI surfaces (settings, project forms, tool dialogs, data-entry controls) are not fully exercised in the latest strict demo gate.
- **Representative un-covered groups (by explicit testid):**
  - Settings tabs and toggles (`tab-*`, `switch-*`, `select-*`)
  - Project/dataset forms (`input-*`, `textarea-*`, `button-create-project`, `button-save-dataset`)
  - Sidebar utility actions (`button-settings`, `button-billing`, `button-starred-workflows`, etc.)

### 5) Low: Occasional Playwright artifact `ENOENT` flake in mixed runs

- **Observed in previous run history:** artifact write race causing test flake despite successful functional retries.
- **Impact:** CI/test signal noise, not direct product behavior failure.
- **Mitigation used:** serial runs (`--workers=1`) for critical gate checks.

## UI Critical Path Status (Current)

PM-critical scenarios were re-run and passed:

- Complete user workflow journey:
  - `frontend/e2e/complete-workflow.e2e.ts` -> pass
- 4 direction real UI coverage:
  - `frontend/e2e/survey-directions-real.e2e.ts` -> all pass
- Multi-run/run-manager clarity and stability:
  - `frontend/e2e/run-manager-*.e2e.ts` selected suite -> pass
- Visual user evaluation:
  - `frontend/e2e/real-user-visual-evaluation.e2e.ts` -> pass

## Recommendation Before User Demo

1. Keep current verified runtime environment unchanged (same healthy port/session).
2. Treat dataset search degradation as a known limitation during demo Q&A (workflow execution itself still passing).
3. If time allows before demo:
   - patch dialog accessibility descriptions,
   - verify/fix dataset search route mismatch upstream.
