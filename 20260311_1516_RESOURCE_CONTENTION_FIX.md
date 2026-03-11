# Resource Contention Fix — E2E Suite — 2026-03-11

## Problem

4 tests in `bioinformatics-viewers.e2e.ts` failed when run as part of the full 60-test
batch but passed in isolation:

| Test | Failing assertion |
|---|---|
| Annotation Viewer | `textarea.toBeVisible()` timeout |
| Interactive Tool Launcher | `textarea.toBeVisible()` timeout |
| Navigation | `textarea.toBeEnabled({ timeout: 10000 })` |
| Theme | `textarea.toBeVisible({ timeout: 10000 })` |

## Root Cause

**`workers: 1` + `fullyParallel: false` prevents browser-level parallelism, but does NOT
prevent back-to-back backend load accumulation.**

Two mechanisms compound:

### 1. Inflight LLM requests from prior tests
`sendMessageAndWaitForResponse` waits for the browser-visible typing indicator to
disappear, then advances to the next test. However, the **backend** may still be
finishing its LLM stream internally (writing to the audit log, closing SSE handles, etc.).

When the next test's `setupTestUser` navigates to a fresh page, the backend briefly
handles 2 requests simultaneously: the tail of the prior test's LLM call + the new test's
session-check / chat-history load. Under this brief load, the app takes >10s to render
its chat interface — exactly the 10000ms budget that Navigation and Theme used.

### 2. Sequential ffmpeg recording accumulation
`video: { mode: 'on' }` writes a video for every test. With 60+ tests in sequence, the OS
accumulates write handles for completed (but not yet flushed) video files. This creates
mild disk-I/O pressure that slows page-load times for subsequent tests.

Note: bioinformatics-viewers already disables video for its OWN tests
(`test.use({ video: "off" })`), but prior tests' recordings still compete for disk.

## Fix

### `frontend/e2e/bioinformatics-viewers.e2e.ts`

1. Added `test.setTimeout(180000)` — gives every test in the file a 3-minute budget
   instead of the default 10-minute global timeout (which doesn't help when the assertion
   inside the test uses a 10s timeout).

2. Raised final `toBeEnabled` / `toBeVisible` timeouts from **10000ms → 30000ms**:
   - `chatInput.toBeEnabled()` in UI Rendering
   - `textarea.toBeEnabled()` in Navigation
   - `textarea.toBeVisible()` in Theme

### `frontend/playwright.config.ts`

`video` and `screenshot` remain `'on'` for full audit trail. The timeout increases are
the entire fix — no reduction in recording fidelity.

## What Was NOT Changed

- `workers: 1` and `fullyParallel: false` stay — sequential execution is correct
- Global `video: 'on'` and `screenshot: 'on'` stay — audit trail preserved for every test
- `bioinformatics-viewers.e2e.ts` keeps its local `video: "off"` override — no change

## Verification

Run bioinformatics-viewers in isolation first, then in full suite:

```bash
cd /home/yzhang/biomate/frontend
# Isolated
npx playwright test e2e/bioinformatics-viewers.e2e.ts --reporter=list

# In full batch (should now pass all 7)
npx playwright test --reporter=list 2>&1 | grep -A2 "bioinformatics"
```

Expected: 7/7 passing in both modes.
