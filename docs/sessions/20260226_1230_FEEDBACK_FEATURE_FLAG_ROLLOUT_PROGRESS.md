# 2026-02-26 12:30 Progress: Feedback Feature-Flag Rollout Control

## Scope completed

Implemented staged rollout controls for UX feedback modules across frontend and backend, with default local behavior remaining enabled.

## Feature flags added

### Frontend flags
- File: `frontend/client/src/lib/feature-flags.ts`
- Added:
  - `VITE_ENABLE_UX_FEEDBACK` (default ON unless explicitly `"false"`)
  - `VITE_ENABLE_UX_FEEDBACK_ADMIN` (default ON when UX feedback is ON)

### Backend flags
- File: `frontend/server/routes.ts`
- Added:
  - `ENABLE_UX_FEEDBACK` (default ON unless explicitly `"false"`)
  - `ENABLE_UX_FEEDBACK_ADMIN` (default ON when UX feedback is ON)

## Frontend gating implemented

- `frontend/client/src/lib/feedback.ts`
  - `submitFeedback()` short-circuits with success when feedback feature is disabled.
- Feedback UI modules now return `null` when disabled:
  - `inline-feedback-widget.tsx`
  - `post-run-micro-survey.tsx`
  - `download-outcome-prompt.tsx`
  - `report-confusion-button.tsx`
  - `session-end-pulse.tsx`
- Admin access visibility gating:
  - `site-header.tsx` (hide UX Feedback nav item when admin flag is off)
  - `pages/admin/feedback-dashboard.tsx` (show disabled-message view when off)

## Backend gating implemented

- `POST /api/telemetry/events`:
  - returns `204` immediately when feedback feature disabled.
- `POST /api/feedback`:
  - returns `404` when feedback feature disabled.
- Admin endpoints gated by admin flag:
  - `GET /api/feedback/summary`
  - `GET /api/feedback/issues`
  - `GET /api/telemetry/summary`
  - return `404` when admin flag disabled.

## Validation

- Build: `cd frontend && npm run build` -> **PASS**
- Lint diagnostics on edited files -> **No linter errors**
- Regression: `BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts` -> **PASS**

## Verification caveat and note

- I attempted a disabled-mode check by setting env vars per command while querying the running local server.
- Result showed default behavior because server-side env flags are evaluated at server startup.
- To validate disabled mode end-to-end, restart the frontend server with:
  - `ENABLE_UX_FEEDBACK=false` and/or `ENABLE_UX_FEEDBACK_ADMIN=false`
  - plus optional client flags: `VITE_ENABLE_UX_FEEDBACK=false`, `VITE_ENABLE_UX_FEEDBACK_ADMIN=false`

## Outcome

Feedback modules are now rollout-controllable for phased deployment without changing default local behavior.
