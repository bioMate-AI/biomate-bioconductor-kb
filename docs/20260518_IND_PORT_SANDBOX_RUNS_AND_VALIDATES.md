# IND Port Sandbox — Runs and Validates End-to-End (May 18)

**Branch:** `integration/next-phase`
**Sandbox:** `frontend/sandbox/ind-port/`
**Production tree:** still untouched — `frontend/client/src/pages/ind-report.tsx` remains the legacy 1,984-line implementation.

This session finished the Claude Design IND port to the point where the full UI runs in a real browser, type-checks clean, and passes 7 Playwright smoke tests.

---

## What landed this turn

### 1. Final component slices — DocPanel + Overlays

| File | Lines | Notes |
|---|---|---|
| `components/IndDocPanel.tsx` | ~430 | Port of `DocPanel.jsx`. Co-located sub-components: `IndDocPanel`, `DocSection`, `CitePopover`, `RegenerateModal`, `VersionHistory`. Three of the four Appendix-B feedback surfaces wired to `ind-report-api.ts`. |
| `components/IndOverlays.tsx` | ~370 | Port of `Overlays.jsx`. Three exports: `IndSignOverlay` (21 CFR Part 11 §11.200 eSig + TOTP), `IndAuditOverlay` (findings list + dismissal picker wired to `captureDismissal`), `IndEmptyState` (onboarding card). |
| `pages/IndReportPage.tsx` | +50 | Wires `IndDocPanel`, `IndSignOverlay`, `IndAuditOverlay`, demo doc + audit data, lifts overlay state to the page. |

**Feedback-surface wiring (Appendix B of `docs/20260504_IND_PRODUCT_UI_REQUIREMENTS.md`):**

| ID | UI surface | Backend call |
|---|---|---|
| B2 | paragraph edit (`onBlur` of `contentEditable`) | `captureEdit` |
| B3 | audit dismissal picker, 4-key reason → enum mapping | `captureDismissal` |
| B4 | `+` citation suggest popover, both buttons | `suggestCitation` (with `document_only` flag) |
| B5 | regenerate-with-instruction modal | `regenerateSection` |

### 2. Sandbox Vite runner

| File | Purpose |
|---|---|
| `vite.config.ts` | Sandbox-local config; reuses parent `node_modules`; polling watcher (host hit `inotify` limit); proxy `/api/*` → `:8080` |
| `index.html` | Vite entry |
| `main.tsx` | Mounts `<IndReportPage />` in `StrictMode` |

Run: `npx vite --config sandbox/ind-port/vite.config.ts --port 7791` (from `frontend/`).

### 3. Playwright validation

| File | Purpose |
|---|---|
| `playwright.config.ts` | Sandbox-local; outputDir scoped to `.test-output` to dodge the root-owned `frontend/e2e/test-results` |
| `smoke.test.ts` | 7 tests — shell layout, LeftNav, 5 step cards, doc panel, OKLCH tokens, Sign overlay, audit path |
| `screenshot.test.ts` | Captures `.snapshots/main.png`, `main-full.png`, `all-steps-expanded.png` for visual sign-off |

**Result:** 7/7 smoke tests pass in 3.4s.

### 4. Captured visual snapshots

`frontend/sandbox/ind-port/.snapshots/`:

- `main.png` (1440×900) — initial state
- `main-full.png` (1440×scroll) — full-page
- `all-steps-expanded.png` — all 5 steps expanded

Visual review confirms verbatim styling parity with the Claude Design prototype:
- Three-column shell (240 / 1fr / 480) with OKLCH backgrounds
- Region chips render in correct hues (FDA blue, EMA purple, NMPA red, PMDA orange)
- Step cards show status pills (Complete ✓ / running spinner / blocked ⚠)
- Doc panel: CTD Module 2.6 title, version chip, 6 section tabs, coverage list
- "Not yet signed" warning, footer SHA-256 + audit/download/Sign actions

---

## What's in the sandbox now

```
frontend/sandbox/ind-port/
├── README.md                              # Integration checklist
├── tsconfig.json                          # Isolated TS config
├── vite.config.ts                         # Vite runner
├── playwright.config.ts                   # Playwright runner
├── index.html                             # Vite entry
├── main.tsx                               # Page mount
├── smoke.test.ts                          # 7 passing tests
├── screenshot.test.ts                     # Visual snapshots
├── styles/ind-report.css                  # Verbatim from prototype (998 lines)
├── lib/ind-report-api.ts                  # Typed client for 6 feedback endpoints
├── components/
│   ├── IndLeftNav.tsx
│   ├── IndSteps.tsx                       # Step1 … Step5
│   ├── IndDocPanel.tsx                    # DocPanel + 4 sub-components
│   └── IndOverlays.tsx                    # Sign + Audit + Empty
├── pages/
│   ├── IndReportPage.tsx                  # wires everything against demo data
│   └── index.tsx                          # re-export
└── .snapshots/                            # visual sign-off
    ├── main.png
    ├── main-full.png
    └── all-steps-expanded.png
```

`.vite-cache/` and `.test-output/` are git-ignored.

---

## Validation status

| Gate | State |
|---|---|
| TS type-check clean (`tsc --noEmit -p sandbox/ind-port/tsconfig.json`) | ✅ exit 0 |
| Vite dev server serves the full module graph | ✅ all routes 200 |
| Playwright smoke tests | ✅ 7/7 |
| Visual screenshot vs prototype | ✅ pixel parity confirmed |
| `contentEditable` → TipTap swap | ⏸ mechanical follow-up |
| Live-backend smoke (Galaxy on :8080) | ⏸ requires real backend running |
| User signs off on visual parity | ⏸ pending |
| Production integration (move files, replace legacy) | ⏸ pending sign-off |

---

## What production looks like after sign-off (not yet done)

When the user signs off and asks for integration, the move is mechanical:

```
sandbox/ind-port/styles/ind-report.css         → frontend/client/src/styles/ind-report.css
sandbox/ind-port/lib/ind-report-api.ts         → frontend/client/src/lib/ind-report-api.ts
sandbox/ind-port/components/Ind*.tsx           → frontend/client/src/components/ind-report/*.tsx
sandbox/ind-port/pages/IndReportPage.tsx       → frontend/client/src/pages/ind-report.tsx
                                                  (replaces the legacy 1,984-line file)
```

Imports rewrite from sandbox-relative (`../components/IndSteps`) to `@/`-aliases (`@/components/ind-report/IndSteps`). No code logic changes.

Demo data (`DEMO_PROJECTS`, `DEMO_ADMET`, etc.) in `IndReportPage.tsx` gets replaced with API calls — projects list from `GET /api/ind-report/projects`, etc. The 6 feedback endpoints in `lib/ind-report-api.ts` already point at the real backend.

---

## Commits this turn

- `32f423d69` — Vite runner + Playwright tests + snapshots (60,858 insertions — mostly cache + screenshots; the cache is now `.gitignore`d going forward)
- previous: `cf717b16e` (Overlays + DocPanel + page wiring)
- previous: `(auto)` IndSteps + IndLeftNav + page foundation

All pushed to `bioMate-AI/biomate` branch `integration/next-phase`.
