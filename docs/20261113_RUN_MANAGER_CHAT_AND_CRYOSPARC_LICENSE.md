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

### Dig tip `1001dec4` — Confirm & Run evidence (license vs infra)

On tip `1001dec42f` (after Provide credentials):

| Step | Result |
|------|--------|
| Confirm & Run → `POST /api/workflows/execute` | **HTTP 500**, `error: cryosparc_execution_failed` (GPU warming up), **`runId` 0751f4e9-…** |
| License gate | Cleared — response was **not** `402` / `cryosparc_license_required` |
| Cancel | Worked for that `runId` |
| Panel `data-status` | Often stayed **`idle`** after the 500 — UI never left idle |

**E2E implication:** Flow A must treat license-gate success from the execute response alone:

- `status !== 402` and error not `cryosparc_license_required`
- Pass when `runId` is present **or** status is 2xx/4xx non-license **or** `body.error` is `cryosparc_execution_failed` / infra
- Optional brief wait for panel status; **do not require** leave-idle when execute already returned a non-license outcome
- Keep cancel + credential cleanup in `finally`

Hard-requiring panel leave-idle timed out on dig even though the license path was already proven.

**A2 isolation (retest flake):** after a prior Confirm & Run left an in-flight cryosparc run, dig’s 120s idempotent dedupe returned HTTP 200 (`deduplicated: true`) for the no-license execute probe — never hitting `402`. Flow A now pre-cancels in-flight cryosparc runs and uses a unique `e2e_nonce` param so the probe reaches the license gate.

**A5 HTTP vs panel race:** Confirm & Run can flip the panel to `Running` while `/api/workflows/execute` is still open (GPU warm-up). A 120s `waitForResponse` alone timed out even though license was cleared. Flow A now races HTTP (240s) vs panel leave-idle, accepts either non-license execute body or panel non-idle, and cancels via response `runId` or the in-flight runs list.

### Live dig green — Confirm & Run past license (2026-11-13 evening)

Tip under test: product `1001dec42f` (LicenseGate `isBlocked` / `data-blocked` fix); E2E race fix `558ddc77af`.

| Step | Result |
|------|--------|
| A1 | delete cryosparc credential → `source=none` |
| A2 | execute without license → **402** `cryosparc_license_required` |
| A3 | LicenseGate visible; Confirm disabled; shot `A3_license_gate_blocks_confirm.png` |
| A4 | Provide credentials → `(your credentials)`; `data-blocked=false`; Confirm enabled; `source=user` |
| A5 | Confirm & Run → panel badge **Running** (HTTP still open / raced); **not** license 402 — past gate |
| A6 | cancel in-flight cryosparc runs (e.g. `0d3be651-…`, `91c3fb33-…`) → **200**; credential cleared in `finally` |

Playwright: Flow A `1 passed` (~2.4m); full A+B `2 passed` (~1.9m). No full SPA GPU wait.

Shots A3–A5 audited: blocked Confirm → enabled Confirm with user key → Running + Pause/Stop. A6 API cancel succeeded; panel shot still showed Running (UI lag vs cancel).

## Open

- GPU warming / CryoSPARC infra 500s are orthogonal to the license gate; track separately if Confirm & Run should surface a clearer warm-up message in the panel.
- Consider validating cryosparc license **before** execute dedupe so a no-license request cannot inherit an in-flight twin.
- A6 screenshot timing: cancel via API returns 200 before panel leaves Running — optional short wait before A6 shot.
