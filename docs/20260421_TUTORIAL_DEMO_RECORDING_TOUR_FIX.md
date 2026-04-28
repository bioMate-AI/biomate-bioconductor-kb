# Tutorial Demo Recording — Built-in Tour Fix

**Date**: 2026-04-21  
**Branch**: integration/next-phase

---

## Summary

Rewrote all 12 reference-design tutorial demo files to use the reference design's own built-in tour system (`.tut-btn` → `.tour-callout` with SVG spotlight overlay) instead of a custom injected `#__ref-tip` div that was fixed at `bottom: 28px; left: 28px` and had no visual connection to the UI element being described.

---

## Problem

The previous implementation of `demo-ref-helpers.ts` injected a custom `#__ref-tip` element into the page:

```typescript
// WRONG — custom div injected at bottom-left
el.innerHTML = `<span class="tip-label">Tutorial</span>${text}`;
el.style = 'position:fixed; bottom:28px; left:28px; ...';
document.body.appendChild(el);
```

This:
1. Always appeared at the bottom-left regardless of what was being demonstrated
2. Had no visual connection (spotlight, pointer, positioning) to the element it described
3. Did not use the reference design's own tour system, which was already fully implemented

The reference design (`reference/claude_design/cro/src/Tour.jsx`) has a complete 10-step tour with:
- SVG spotlight overlay (`WFSpotlight`) that cutouts around the target element
- `.tour-callout` positioned dynamically next to `[data-tour="..."]` targets (left/right/top/bottom/center)
- Auto-placement fallback when the preferred side doesn't have room
- Step counter (`Step N of 10`), back/next buttons, skip button
- Per-step `setup()` callbacks that apply tweaks to drive the UI into the right state
- Triggered by `.tut-btn` in Chrome.jsx

---

## Fix

### `frontend/e2e/demo-ref-helpers.ts`

- Removed `tip()` function entirely
- Removed `TIP_INIT_SCRIPT` CSS injection
- Removed tip CSS injection calls from `loadRef()` and `switchTweaks()`
- Added `runTour(page, demo)` helper:

```typescript
export async function runTour(page: Page, demo: string): Promise<void> {
  const tutBtn = page.locator('.tut-btn').first();
  await tutBtn.waitFor({ state: 'visible', timeout: 15_000 });
  await tutBtn.hover();
  await page.waitForTimeout(600);
  await tutBtn.click();
  await page.waitForTimeout(800);

  for (let i = 0; i < TOUR_TOTAL_STEPS; i++) {
    await page.locator('.tour-callout').waitFor({ state: 'visible', timeout: 10_000 });
    await page.waitForTimeout(500);
    await shot(page, demo, `tour_step_${String(i + 1).padStart(2, '0')}`);
    await page.waitForTimeout((TOUR_STEP_PAUSE[i] ?? 5_500) - 500);
    const nextBtn = page.locator('.tour-callout .btn.primary').first();
    await nextBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await nextBtn.click();
    await page.waitForTimeout(700);
  }

  await page.locator('.tour-callout').waitFor({ state: 'hidden', timeout: 8_000 });
  await page.waitForTimeout(1_500);
}
```

- Added `TOUR_STEP_PAUSE` record (0–9) with per-step hold times (5500–6500 ms)
- Added `TOUR_TOTAL_STEPS = 10`

### Tour system (reference, not modified)

The built-in tour in `src/Tour.jsx` has 10 steps with these tweaks auto-applied:

| Step | ID | Target | Tweaks applied |
|------|----|--------|----------------|
| 0 | welcome | center | nfcore, running, qcHalt=false, blocked=false, disambig=false |
| 1 | chat-handoff | `[data-tour="chat-handoff"]` | nfcore, disambig=false |
| 2 | panel-header | `[data-tour="panel-header"]` | — |
| 3 | phase-list | `[data-tour="phase-list"]` | — |
| 4 | running-phase | `[data-tour="phase-list"] .phase.open` | — |
| 5 | qc-halt | `[data-tour="phase-list"]` | qcHalt=true, running |
| 6 | blocked | `[data-tour="panel-body"]` | qcHalt=false, blocked=true, licenseGate=true |
| 7 | run-button | `[data-tour="run-footer"]` | blocked=false, licenseGate=false, running |
| 8 | watcher | `[data-tour="watcher"]` | — |
| 9 | tweaks (done) | center | — |

The tour therefore covers every major edge case: qcHalt auto-loop (step 5), blocking errors (step 6), run button states (step 7), watcher detach (step 8) — without any custom overlay code.

### All 12 demo-ref-*.demo.ts files

Each demo was rewritten to follow this pattern:

```
1. loadRef() with scenario-specific initial tweaks
2. shot() of the initial scenario state (1–3 pre-tour screenshots)
3. switchTweaks({ runState: 'running' })  // tour step 0 expects running state
4. runTour(page, DEMO)                    // all 10 tour steps with spotlight
5. shot() of final done state
```

Scenario-specific initial screenshots (before tour):

| Demo | Initial tweaks | Pre-tour screenshots |
|------|---------------|---------------------|
| 09a | nfcore/running → completed | `00_nfcore_running`, `01_nfcore_completed` |
| 09b | nfcore/running/qcHalt=true | `00_qc_halt_initial` |
| 09c | nfcore/running/blocked+licenseGate | `00_blocked_license_gate` |
| 09d | cryosparc/running → completed | `00_cryosparc_running`, `01_cryosparc_completed` |
| 09e | nfcore/idle/disambig=true | `00_disambiguation_card` |
| A01 | nfcore/idle | `00_nfcore_idle` |
| A04 | nfcore/failed | `00_nfcore_failed` |
| A08 | nfcore/running/watcherAttached | `00_watcher_attached` |
| B01 | gatk/idle | `00_gatk_idle` |
| B02 | gatk/running | `00_gatk_running` |
| B03 | gatk/completed | `00_gatk_completed` |
| C01 | admet/idle → running → completed | `00_admet_idle`, `01_admet_running`, `02_admet_completed` |

Each demo produces `tour_step_01.png` through `tour_step_10.png` in `e2e/screenshots/<demo>/`, plus a `done.png`.

---

## Other fixes in this session

### Demo-10 blank screenshot (CSP)

`demo-10-workflow-panel-reference.demo.ts` was loading the reference design through the Express server, which had a CSP `script-src` that did not include `https://unpkg.com` (where React/Babel are loaded from in the reference design HTML).

**Fix**:
1. Changed `WP_URL` in demo-10 to `http://localhost:7779/...` (Python HTTP server, no CSP)
2. Added `'https://unpkg.com'` to `scriptSrc` in `server/security-config.ts` for long-term fix

### Video finalization timing

Short demos (< 30s) sometimes didn't finalize their `.webm` before the script copied it.

**Fix** in `run-ref-demos.sh`: replaced `sleep 4` with a polling loop that checks for `*.webm` every second for up to 15 seconds.

---

## Output

All videos written to `frontend/e2e/demo-videos-ref/` as `.webm` files.  
Screenshots written to `frontend/e2e/screenshots/<demo>/`.

Run command:
```bash
cd frontend
bash e2e/run-ref-demos.sh              # all 12
bash e2e/run-ref-demos.sh 09a B02      # specific demos by key
bash e2e/run-ref-demos.sh --no-video   # screenshots only
```
