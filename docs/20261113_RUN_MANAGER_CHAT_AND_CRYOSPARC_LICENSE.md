# Run Manager → owning chat + CryoSPARC license hard-block

**Date:** 2026-11-13

## Screenshots that drove the work

1. **Run Manager opened only the right workflow panel** — left chat stayed on an empty “New Chat (test)” while Cryosparc Standard Spa (Failed) loaded on the right.
2. **CryoSPARC ran with no license prompt** — Phases showed Running / Init Cryosparc Project with Movies Path blank and no Tool Credentials UI.

## Fixes

### Run Manager opens the owning chat

- `runManagerSwitchHref()` builds `/?session=<chatSessionId>&focusRun=<runId>` when the clicked run belongs to another session.
- `handleSwitchRun` navigates there (list `chatSessionId`, else restored run) instead of only `loadRun` + panel open.
- `?focusRun=` loads that exact run into the panel after session remount; session-restore skips when `focusRun` is present.
- `RunListItem.chatSessionId` typed to match `/api/workflows/runs` rows.

### CryoSPARC license must ask + block

Root causes:

- LicenseGate only mounted for `idle|pending_review` → Restart from Failed never re-checked.
- Gate fail-open on API error / empty scan; Confirm could race while loading (`isLicenseBlocked` still false).
- Nextflow executor silently injected `CRYOSPARC_LICENSE_ID` from env; Direct path fell back to `CRYOSPARC_LICENSE`.

Changes:

- `LicenseGate` fail-closed for BYOL paths while loading / on error; synthetic cryosparc path when only `workflow_type`/`name` is set.
- Gate moved under **Workflow settings**; mounts for idle / failed / completed (not only idle).
- Footer license hint for Restart/Run again; `handleExecute` hard-returns when blocked.
- Node execute: 402 without user cryosparc credential on Nextflow + Direct paths; shared env only if `BIOMATE_ALLOW_SHARED_CRYOSPARC_LICENSE=true`.
- Galaxy Nextflow launcher: same policy — no silent env license inject.

## Tests

- `client/src/components/run-manager-utils.test.ts` — switch href cases
- `client/src/components/license-gate.test.ts` — path helpers
- **Live dig E2E (2026-11-13):**
  `frontend/e2e/run-manager-chat-and-cryosparc-license.e2e.ts` + `chat-files-and-reports.e2e.ts`
  - **A (ask only, tip `ecf9fedc4d`):** delete credential → `source=none` → execute **402** → LicenseGate + Confirm disabled
  - **A (Confirm & Run E2E):** Provide credentials in panel → Confirm enabled → Confirm & Run past license gate (execute ≠ 402) → cancel run immediately (no GPU SPA wait). Also fixes `data-blocked` so a resolved user key clears the attribute (`hardPath || …` bug).
  - **B:** Run Manager → `?session=&focusRun=` → owning chat + panel
  - **chat-files:** MD sibling figures beside chat
  - Screenshots: `frontend/e2e/execshots/run-manager-cryosparc-license/` (A3–A6) · `frontend/e2e/screenshots/chat-files-and-reports/`

## Open

- Re-verify A Confirm & Run after frontend sync of `isBlocked` / credential-modal testids (this tip).
