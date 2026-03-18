# 2026-03-05 12:04 Confusion Triage Admin UI Wiring and E2E

## Scope

- Continued implementation from the next-step queue.
- Kept dataset-search route work on hold.
- Implemented internal confusion-triage visibility in admin UX dashboard.

## Changes made

### 1) Admin dashboard: confusion triage section wired

Updated:
- `frontend/client/src/pages/admin/feedback-dashboard.tsx`

What was added:
- New state/models for confusion triage response rows.
- Data fetch call to:
  - `GET /api/telemetry/confusion-triage?from=<date>&to=<date>&limit=10`
- Defensive client-side ordering:
  - sort by `totalSignals` desc
  - tie-break by `latestSignalAt` desc
- New UI card:
  - title: `Confusion Triage`
  - grouped cluster count
  - table columns: Root Run / Signals / Signal Types / Latest Severity / Latest Signal
- Added stable test ids:
  - `confusion-triage-card`
  - `confusion-triage-row-<index>`
  - `confusion-triage-total-<index>`

### 2) Route wiring fix for admin dashboard

Updated:
- `frontend/client/src/App.tsx`

What was added:
- Explicit route:
  - `/admin/feedback-dashboard` -> `AdminFeedbackDashboardPage`

Why:
- `SiteHeader` already links to this path; explicit router wiring ensures the page resolves directly.

### 3) Deterministic UI/E2E verification

Added:
- `frontend/e2e/admin-confusion-triage-dashboard.e2e.ts`

Test behavior:
- Mocks auth (`/api/auth/me`) as authenticated admin-like user context.
- Mocks summary/issues/telemetry endpoints to keep dashboard stable.
- Mocks confusion-triage endpoint with intentionally unsorted rows.
- Verifies UI renders and sorts correctly:
  - top row shows higher `totalSignals`
  - expected cluster counts and values visible via test ids.

## Validation evidence

Build:
- `npm run build` (success)

E2E:
- `BIOMATE_URL=http://localhost:5412 npx playwright test e2e/admin-confusion-triage-dashboard.e2e.ts`
- Result: 1 passed, 0 failed

Lints/diagnostics:
- Updated files checked; no linter errors.

## Outcome

- PM/ops now have direct in-product visibility into confusion clusters by run lineage.
- Rendering and sorting semantics are locked by deterministic Playwright coverage.
- Dataset-search behavior remains unchanged in this pass.
