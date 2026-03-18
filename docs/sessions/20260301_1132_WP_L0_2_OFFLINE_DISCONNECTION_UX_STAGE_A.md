# WP-L0-2 Offline/Disconnection UX (Stage-A)

Timestamp: 2026-03-01 11:32

## Scope delivered

Implemented Stage-A offline/disconnection UX with a non-disruptive rollout:

1. Added a browser network status hook based on `navigator.onLine` and browser `online` / `offline` events.
2. Surfaced an explicit offline banner in the main chat shell.
3. Added retry guidance copy to reduce user confusion during transient disconnects.
4. Added UI E2E coverage for offline -> online transition behavior.
5. Re-ran strict release feedback matrix to confirm no regressions.

## Files changed

- `frontend/client/src/lib/network-status.ts` (new)
  - Added `useNetworkStatus()` hook.
  - Uses event listeners for online/offline transitions.
  - Returns `{ isOnline }`.

- `frontend/client/src/components/chat-with-artifacts.tsx`
  - Integrated `useNetworkStatus()`.
  - Added offline warning strip:
    - `data-testid="offline-banner"`
    - `data-testid="offline-retry-guidance"`
  - Offline banner message:
    - "You appear to be offline."
    - "Reconnect to continue chat and workflow operations. Your current session remains available locally."

- `frontend/e2e/ux-offline-recovery.e2e.ts` (new)
  - Added deterministic UX test for network transitions:
    - online baseline: no banner
    - `context.setOffline(true)`: banner visible
    - `context.setOffline(false)`: banner clears

## Why this Stage-A design

- Adds high-signal user guidance without changing backend execution semantics.
- Keeps existing execution and confidence gate behavior stable.
- Avoids introducing retry side-effects before standardizing async guidance and retry handlers (WP-L0-3 dependency).

## Test evidence

### 1) New offline UX suite

Command:
- `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/ux-offline-recovery.e2e.ts --project chromium --retries=0`

Result:
- `1 passed`

### 2) Regression gate (release matrix)

Command:
- `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`

Result:
- `feedback-real-ui-strict.e2e.ts` PASS
- `pm-user-stories-comprehensive.e2e.ts` PASS
- Matrix result: `SUCCESS`

Artifact:
- `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_112704.txt`

## Current limitations (intentional for Stage-A)

- Banner is currently keyed to browser online/offline state only.
- Does not yet classify "backend reachable but stream disconnected" separately.
- Does not yet include auto-retry buttons or resumable action chips.

## Stage-B follow-up (planned)

1. Add tri-state connectivity model:
   - `online+live`, `online+degraded`, `offline`.
2. Integrate execution error copy with connectivity-aware remediation.
3. Add explicit `Try again` action contracts in chat and execution failure panels.
4. Add telemetry:
   - `network.offline_banner_shown`
   - `network.offline_banner_cleared`
   - `network.retry_clicked`

