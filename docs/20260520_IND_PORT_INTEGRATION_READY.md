# IND Port — Integration Readiness Sign-Off Doc

**Date:** 2026-05-20
**Sandbox:** `frontend/sandbox/ind-port/`
**Production target:** `frontend/client/src/{styles, lib, components/ind-report, pages}/`

This doc certifies the sandbox port has converged. Production move is gated on the four sign-off items below.

---

## Test coverage

| Suite | Tests | Status |
|---|---|---|
| `e2e.test.ts` (the IND-N suite, mirrors cryo merged pattern) | 34 | 34/34 ✅ |
| `smoke.test.ts` (round-0 baseline) | 7 | 7/7 ✅ |
| `screenshot.test.ts` (6 captures) | 6 | 6/6 ✅ |
| `structural.test.ts` (CSS coverage) | 4 | 4/4 ✅ |
| `responsive.test.ts` (1024/1280/1440) | 4 | 4/4 ✅ |
| `tiptap.test.ts` (edit capture wiring) | 3 | 3/3 ✅ |
| **Total** | **58** | **58/58** |

`tsc --noEmit -p sandbox/ind-port/tsconfig.json` → exit 0.

---

## Visual coverage

| Snapshot | What it proves |
|---|---|
| `IND-1-01_empty_state.png` | Onboarding renders, 3 reference compound chips |
| `IND-2-01_topbar.png` | Topbar landmarks |
| `IND-3-01_leftnav.png` + `02_after_switch.png` | Project switching updates active highlight + topbar |
| `IND-4-01_pipeline.png` | 5 step cards, demo-state all complete |
| `IND-5-01_doc_panel.png` | Version chip, region selector, section tabs, footer |
| `IND-7-01_step1_expanded.png` | Project Setup kv list |
| `IND-8-01_table_open.png` + `02_wetlab_open.png` | ADMET table + wet-lab upload panel |
| `IND-9-01_running.png` | Step 2 running state with progress bar |
| `IND-10-01_imported.png` | Step 2 imported-from-chat banner |
| `IND-11-01_pbpk_passed.png` | Step 3 passed state |
| `IND-12-01_pbpk_failed.png` | Step 3 failed state, red criterion box |
| `IND-13-01_leads_table.png` | Step 4 top-5 ranking |
| `IND-14-01_step5.png` | Step 5 with MAJOR warn row |
| `IND-15-01_inline_chips.png` + `02_chip_closeup.png` | ⚠ MAJOR chip inline with §2.6.1.2 paragraph |
| `IND-22-01_overlay_open.png` + `02_filter_major.png` | Audit overlay open + severity filter working |
| `IND-23-01_picker_selected.png` | 4-option dismissal picker |
| `IND-24-01_critical_present.png` | CRITICAL audit injected |
| `IND-26-01_overlay.png` | Sign overlay (Electronic Signature, 21 CFR Part 11) |
| `IND-27-01_totp_complete.png` | Sign button enabled after 6 TOTP digits |
| `IND-28-01_success.png` | Signed success card with sig ID + download buttons |
| `IND-29-01_narrow.png` | Responsive 1024 — doc panel hidden, FAB visible |
| `IND-HAPPY-{01..05}.png` | Super-merged flow: onboarding → main → audit → edit → sign |

Plus 6 baseline screenshots from earlier rounds (`main.png`, `main-full.png`, `all-steps-expanded.png`, `sign-overlay.png`, `audit-overlay.png`, `onboarding.png`).

**Total: ~30 PNG artifacts at 1280×900 covering every prototype state.**

---

## Feedback-loop wiring (Appendix B)

All 4 surfaces wired to `lib/ind-report-api.ts` and verified to POST via `page.route()` interception:

| Surface | Wired via | Test ID | Payload validated |
|---|---|---|---|
| B2 paragraph edit | `EditableParagraph` onBlur → `captureEdit` | IND-16, IND-17, IND-32, IND-HAPPY | ✅ paragraph_id, original, edited, section_type |
| B3 audit dismissal | `IndAuditOverlay` picker → `captureDismissal` | IND-23, IND-HAPPY | ✅ rule_id, section_type, reason enum |
| B4 cite suggest | `CitePopover` submit → `suggestCitation` | IND-18, IND-19, IND-HAPPY | ✅ guideline_id, rationale, document_only |
| B5 regenerate-with-instruction | `RegenerateModal` submit → `regenerateSection` | IND-20, IND-HAPPY | ✅ instruction text |

Total captured in audit JSON: **10 POSTs** across the 34-test super-merged run.

---

## Bugs caught + fixed during the audit-fix loop

| Round | Defect | Fix |
|---|---|---|
| 1 | Missing `.ind-topbar` (breadcrumb + region chips + tutorial + user) | Added `TopBar` component matching prototype markup |
| 1 | Missing `.ind-center-head` Audit button | Added small shield-icon button wired to `showAudit` state |
| 1 | Screenshot Sign-button selector too narrow (`.primary` only) | Match both `.primary` and `.warn` |
| 2 | 12 CSS classes flagged unused (overlay-only / state-triggered / paid-tier) | Documented in SKIP_CLASSES (no port bugs) |
| 3 | `.ind-doc-panel { display: flex }` overrode the 1024px hide rule | Appended `!important` overrides at end of CSS (prototype CSS bug) |
| 4 (this) | `.regen-btn` never rendered because demo had no `subs` | Enriched `DEMO_DOC_FOR_PANEL` with 11 sub-paragraphs |
| 4 (this) | Sign success card flashed for 100ms | Page-level `onSigned` no-op; user dismisses via Close |
| 4 (this) | IND-9/10/12 blocked on URL knobs | Added `readKnobs()` for `?state=running\|pbpk-fail`, `?imported=1`, `?audit=critical` |
| 5 (visual audit) | Audit overlay captured mid-animation (opacity 0) | `shot()` waits 250ms before screenshotting |
| 5 (visual audit) | Inline chips rendered as block, not inline with paragraph | CSS override flattens TipTap render tree to inline |

**10 fixes over 5 audit rounds.** Each round caught real defects the prior round's "green tests" missed.

---

## Sign-off items before integration

The migration script `frontend/sandbox/ind-port/integrate-to-production.sh` is ready. It will not run unless `--apply` is passed. Before applying:

- [ ] **Visual sign-off** — review the 30 PNGs in `frontend/sandbox/ind-port/.snapshots/e2e/` and confirm visual parity with the Claude Design prototype.
- [ ] **Live-backend smoke** — start Galaxy on `:8080`, run sandbox e2e against the live backend (set `captureFeedback(page, audit, { stub: false })` for a one-off check), confirm the 4 feedback endpoints actually receive POSTs and persist to JSONL.
- [ ] **Browser test** — open `http://localhost:7791/?onboarding=1` in a real browser (Chrome / Firefox / Safari) and click through onboarding → main → audit → edit → cite → regenerate → sign. Confirm no console errors and the experience matches the prototype's `BioMate IND Report.html`.
- [ ] **Confirm latest commit on `integration/next-phase`** — `git log -1 --stat frontend/sandbox/ind-port/` shows the audit-fix commit `667e30fd6` (or later).

Once all 4 are checked:

```bash
bash frontend/sandbox/ind-port/integrate-to-production.sh --apply
# Then:
git diff frontend/client/src/                     # review
git add frontend/client/src/                       # stage
git commit -m "frontend: integrate IND port from sandbox"
git push origin integration/next-phase
# Optional cleanup:
git rm -r frontend/sandbox/ind-port/.test-output frontend/sandbox/ind-port/.vite-cache
```

The migration script:
- Copies 8 files (CSS + API client + 5 components + page)
- Rewrites 7 import patterns (`../` → `@/`-aliases)
- Replaces the legacy 1,984-line `ind-report.tsx`
- Runs `tsc --noEmit` and reverts on failure

---

## Files that will move on integration

| Sandbox path | Production path |
|---|---|
| `styles/ind-report.css` | `frontend/client/src/styles/ind-report.css` |
| `lib/ind-report-api.ts` | `frontend/client/src/lib/ind-report-api.ts` |
| `components/IndLeftNav.tsx` | `frontend/client/src/components/ind-report/IndLeftNav.tsx` |
| `components/IndSteps.tsx` | `frontend/client/src/components/ind-report/IndSteps.tsx` |
| `components/IndDocPanel.tsx` | `frontend/client/src/components/ind-report/IndDocPanel.tsx` |
| `components/IndOverlays.tsx` | `frontend/client/src/components/ind-report/IndOverlays.tsx` |
| `components/EditableParagraph.tsx` | `frontend/client/src/components/ind-report/EditableParagraph.tsx` |
| `pages/IndReportPage.tsx` | `frontend/client/src/pages/ind-report.tsx` (replaces legacy) |

Sandbox-only files that stay in sandbox: `e2e.test.ts`, `smoke.test.ts`, etc. — these are the test suite, kept as the regression layer.

---

## Known limitations carried forward (acceptable)

1. **`contentEditable` → TipTap swap loses the chip's exact inline position** when the paragraph fills the column width — chip wraps to the next line. Prototype's `<p contentEditable>` rendered the chip on the same line. Acceptable per inline-flow semantics.
2. **DocPanel header is hardcoded** to "BM-0042 · Acme Therapeutics · NSCLC" — demo wiring artifact. Production will pull from `activeProject` props.
3. **`.ind-doc-fab` click is a stub `alert()`** — narrow-viewport doc modal not yet implemented. Production needs to wire it to open the DocPanel in a modal.
4. **One latent prototype CSS bug** — `@media (max-width: 1024px)` ordering issue, hotfixed with `!important` in sandbox CSS. Claude Design should lift the fix upstream.
