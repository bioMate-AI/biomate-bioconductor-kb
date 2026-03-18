# 2026-02-26 12:22 Progress: Policy Alignment + Session-End Pulse Feedback

## Clarification addressed

Yes — the website already had policy pages. This update reviewed and revised those existing pages directly, rather than creating separate standalone policy docs.

## Policy review and revision completed

### Existing website policy pages reviewed
- `frontend/client/src/pages/privacy.tsx`
- `frontend/client/src/pages/terms.tsx`

### Privacy policy revised
- Updated last-updated date to `February 26, 2026`.
- Added explicit disclosure of:
  - product telemetry event collection
  - user-submitted feedback collection (inline, post-run, confusion, download outcome)
- Clarified telemetry/feedback identifiers (`sessionId`, `runId`, `workflowId`, `invocationId`) and diagnostic purpose.
- Added use purpose for improving workflow clarity, output usability, and download reliability.
- Added rights text for requesting deletion of account-associated feedback records (subject to legal/security obligations).
- Added explicit retention statement (retain only as reasonably necessary for operations, security, support, contracts, and legal obligations).

### Terms revised
- Updated last-updated date to `February 26, 2026`.
- Added explicit data/privacy disclosure:
  - telemetry and feedback may be collected for UX/reliability improvement
  - users should avoid placing sensitive personal data in free-text feedback unless needed for support

## Session-end pulse feedback implemented

### Backend mapping support
- `frontend/shared/schema.ts`
  - Extended `feedbackTypeEnum` with `session_pulse`.
- `frontend/server/routes.ts`
  - Added `session_pulse` mapping in `/api/feedback` type translation.

### New UI component
- Added `frontend/client/src/components/feedback/session-end-pulse.tsx`
  - Two quick yes/no pulse questions
  - Optional comment
  - Submits through existing `/api/feedback` endpoint with `feedback_type: "session_pulse"`

### Integration
- `frontend/client/src/components/chat-with-artifacts.tsx`
  - Mounted `SessionEndPulse`
  - Triggered once per session after terminal run state and after post-run survey is dismissed
  - Passes session/run/invocation context for correlation

## Regression found and fixed

### Issue
- Initial session-pulse rollout caused stacked dialogs with post-run survey in some runs.
- Result: feedback regression E2E failed at post-run survey Yes button interaction.

### Fix
- Sequenced pulse trigger to open only after:
  - terminal status reached,
  - post-run survey context exists for the same run,
  - post-run survey is closed.
- Stabilized E2E survey interactions by asserting survey question text visibility before clicking Yes buttons.

## Validation

- Build: `cd frontend && npm run build` -> **PASS**
- Lint diagnostics on edited files -> **No linter errors**
- Feedback regression: `BIOMATE_URL=http://localhost:5310 npx playwright test feedback-regression.e2e.ts` -> **PASS**

## Current status

Policy text is now aligned with implemented telemetry/feedback behavior, and session-end pulse feedback is live without breaking mandatory feedback regression flow.
