# 2026-02-26 12:15 Progress: Website Policy Review and Revision

## What was reviewed

Confirmed the website already has user-facing legal pages:
- `frontend/client/src/pages/privacy.tsx`
- `frontend/client/src/pages/terms.tsx`

## Revisions completed

### Privacy Policy updates
- File: `frontend/client/src/pages/privacy.tsx`
- Updated "Last updated" date to `February 26, 2026`.
- Expanded "Information We Collect" to explicitly include:
  - product interaction telemetry events
  - user-submitted feedback (inline, post-run, confusion reports, download outcome checks)
- Added clarification that telemetry/feedback may include technical identifiers (`sessionId`, `runId`, `workflowId`, `invocationId`) used for diagnostics.
- Added usage purpose for UX and reliability improvements.
- Expanded rights section to mention deletion requests for account-associated feedback.
- Added explicit retention statement: retain data only as long as reasonably necessary for operations, security, support, contracts, and legal obligations.

### Terms of Service updates
- File: `frontend/client/src/pages/terms.tsx`
- Updated "Last updated" date to `February 26, 2026`.
- Expanded Data and Privacy section to disclose:
  - collection of telemetry and user feedback for quality/reliability improvement
  - guidance not to include sensitive personal information in free-text feedback unless required for support

## Validation

- Build: `cd frontend && npm run build` -> **PASS**
- Lint diagnostics on edited files -> **No linter errors**

## Note

These changes align policy text with the recently implemented UX feedback and telemetry capabilities without introducing new backend enforcement behavior claims.
