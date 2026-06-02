# BioMate Research-Agent UI — Engineering Handoff for Claude Code

This document is the porting brief for the Research-Agent UI prototype. It extends BioMate's
existing workflow-panel redesign with five new chat-side surfaces and a comprehensive
after-run report, all loaded as inline-Babel React in a single HTML page.

**Goal of this document:** give Claude Code (or any senior frontend engineer) enough
structure, contracts, and pitfall-awareness to port this to a real BioMate codebase without
guessing at intent. Read end-to-end before touching code.

---

## 0. TL;DR · what this prototype is

- **Entry:** `Research Agent UI.html` — a single HTML page that loads CSS + JSX via
  `<script type="text/babel">`. No build step. React 18.3.1, Babel standalone 7.29.0.
- **Two compatible scenario systems** live in parallel:
  - **v1 workflow panel** (`SCENARIOS` in `data.js`) — phases / steps / QC gates / outputs.
    Drives the right-side panel.
  - **Research-Agent engine** (`RESEARCH_SCENARIOS` in `research-data.js`) — event tapes
    that drive the new chat-side surfaces (plan checklist, speaker pills, decision cards,
    findings card).
- **Five new chat-side surfaces** added on top of the unchanged v1 panel:
  1. **Plan checklist** (sticky, top of chat thread)
  2. **Speaker-pilled chat lines** (`PLAN`, `WF`, `QC`, `LOOP`, `AGENT`, `FIND`)
  3. **(why?) rationale tooltip** (lightweight; replaces a heavy phase-card expansion)
  4. **Run-vs-Run comparison card** (inline in chat)
  5. **Pilot prompt + Pilot promotion cards** (inline in chat)
- **After-run report** (in panel, replaces v1's link row + modals): a 7-tab inline view —
  Findings · Outputs · Methods · Parameters · Software · Citations · QC audit — with a
  single "Download report" link to bundle all tabs as DOCX / Markdown / LaTeX.
- **Tutorial engine** (`Tour.jsx`) drives the engine + clicks tab buttons + opens modals
  programmatically. Three "new" demos (R01/R02/R03) plus an extended set of v1 demos.
- **Tweaks panel** exposes scenario alternatives + UX recommendations; persists via
  localStorage + `__edit_mode_set_keys` host messages.

---

## 1. Files and responsibilities

| File | Role |
|---|---|
| `Research Agent UI.html` | App entry. Loads everything; defines no logic itself. |
| `src/tokens.css` | v1 design tokens — colors, radii, shadows, type scale. |
| `src/layout.css` | v1 layout — app grid, sidebar, chat column, workflow panel, phase/step rows, modals, toast, **plus** new sections for `after-run-report`, `panel-resizer`, `tweaks-reopen`, brand-full logo. |
| `src/research-tokens.css` | Research-Agent extension tokens — speaker palette (`--bm-plan/wf/qc/loop/agent/find`), dark mode, density mode. |
| `src/research-layout.css` | Layout for the new surfaces — plan checklist, chat stream, speaker pills, chat cards, rationale tooltip, comparison card, pilot prompt, findings chat card, tweaks panel chrome. |
| `src/tour.css` | Tour callout chrome — both regular and "cartoon" speech-bubble styles. |
| `src/Icon.jsx` | Inline SVG icon set. `<Icon name="..." size={N}/>`. |
| `src/data.js` | v1 SCENARIOS: `CRYOSPARC`, `GATK`, `ADMET`, `NFCORE`, **`DRUGSCREEN`** (new). Exposed as `window.SCENARIOS`. |
| `src/research-data.js` | `RESEARCH_SCENARIOS` (7 entries) + `RESEARCH_PHASE_TRACE` (rationale lookups). Each scenario has a `tape: []` of typed events the engine walks. |
| `src/Chrome.jsx` | `Sidebar` (brand logo, 7 chat threads, user) + legacy v1 `ChatColumn` (kept for tour script compatibility, not used by the new app entry). |
| `src/PhaseCard.jsx` | v1 `PhaseCard`, `Step`, `QcBlock`, `StatusChip`. **Note: skip-step + skip-phase commented out for this release.** |
| `src/AutoLoop.jsx` | `AutoLoopCard` — QC HALT card. Behaviour switches by `autoloop` prop: off → "review the proposed fix" with Accept/Edit/Dismiss; on → "auto-loop attempting remediation" with cancel-now option. |
| `src/Modals.jsx` | `SkipConfirmModal`, `AdjustModal`, `PreviewModal`, `ReportModal` (legacy, still callable), `QcAuditModal` (legacy). Plus exported **sub-components** used both by the legacy modals and by the new inline `AfterRunReport`: `ReportFindings`, `ReportOutputs`, `ReportMethodsImrad`, `ReportParams`, `ReportSoftware`, `ReportCitations`, `QcAuditPanel`. |
| `src/WorkflowPanel.jsx` | The right-side panel. Workflow settings strip → phase list → After-run report (inline tabs) → footer. **Owns** the simulated SSE run loop, the drag-handle resizer, the `AfterRunReport` component, and the local toast. |
| `src/PlanChecklist.jsx` | Surface 1: sticky plan strip above the chat thread. |
| `src/ChatStream.jsx` | Surface 2: speaker-pilled chat lines + `(why?)` rationale tooltip + same-speaker collapse. |
| `src/ChatCards.jsx` | Surfaces 4 + 5: `PilotPromptCard`, `PilotPromotionCard`, `ComparisonCard`, `FindingsChatCard`, plus the shared `CountdownRing`. |
| `src/ResearchApp.jsx` | App root. Loads tweaks from localStorage, drives the scenario engine, exposes window hooks for the tour (`__tourFFTo`, `__tourAction`, `__tourSetScenario`, `__openTourModal`, etc.), renders sidebar + chat + workflow panel + tweaks panel. |
| `src/ResearchTweaks.jsx` | The Tweaks panel UI (`ResearchTweaks`). Surfaces every spec open-question + recommendation. |
| `src/Tour.jsx` | `DEMO_TOURS` registry + `WFTour` callout + `WFSpotlight` + `TourPicker` + `useWFTour` hook. **Read the tour-step contract carefully** — it has setup hooks, auto-advance timers, modal openers, and engine fast-forward. |

`HANDOFF.md` (root) is the v1 handoff (still relevant for the v1 panel — phase cards, QC,
auto-loop). This file is the extension brief; consult both.

---

## 2. The two engines (most important section)

### 2.1 v1 panel engine (`WorkflowPanel.jsx`)

The right-side panel runs a **simulated SSE loop** when `runState === 'running'`:

- Every `tweaks.speed` ms (~900ms default), find the currently-running step, mark it
  `completed`, find the next `pending` step in the same phase, mark it `running`.
- If no more pending steps in this phase, advance to the next phase's first pending step
  and set `openPhaseId` to it.
- When no pending steps remain anywhere, set `runState = 'completed'`.

This is intentionally simple. **In a real backend**, replace this loop with an SSE
subscription to `/api/workflows/{inv}/events`. Keep the state shape — the rest of the
panel reads from it.

### 2.2 Research-Agent engine (`ResearchApp.jsx` + `research-data.js`)

Each scenario in `RESEARCH_SCENARIOS` declares a `tape: Event[]`. The engine walks the
tape at `speed`-scaled real time, applying each event to a small state machine, halting at
`await` events until a user action (or countdown auto-fire) advances past it.

**Tape event kinds** (`research-data.js` top-of-file comment is the canonical list):

| Kind | Effect |
|---|---|
| `chatLine { s, m, k?, ts?, rationaleId? }` | Append a speaker-pilled line to chat. `s` is the speaker code (`plan/wf/qc/qc-err/loop/agent/find`). `k` overrides speaker for severity. `rationaleId` is a key into `RESEARCH_PHASE_TRACE` and renders the `(why?)` anchor. |
| `planShow { editing? }` | Show the plan checklist, optionally in edit mode. |
| `planUpdate { id, status, meta? }` | Update a single plan item's status. |
| `planFail { id, reason }` | Mark item failed + inline failure block with reason. |
| `planUnfail { id, status }` | Collapse the failure block back into a status. |
| `planLock` | Leave edit mode. |
| `phaseUpdate { id, status }` | Recolour a phase card. Auto-opens the phase if `running`. |
| `runState { value }` | Flip the panel-level run state (idle/running/completed/failed). |
| `showCard { card, data }` | Inline a chat card (`pilotPrompt`, `pilotPromotion`, `comparison`, `findings`). |
| `dismissCard { card }` | Mark a card dismissed. **Critical** — without this, cards stack visually. |
| `startCountdown { label, seconds }` | Start a real countdown. Fires `label` when it hits zero. |
| `await { label }` | Halt until a matching user action arrives (`AWAIT_ACCEPTS` map in `ResearchApp.jsx`). |
| `marker { id }` | A no-op during playback. **Used by tutorials only**: `window.__tourFFTo(markerId)` walks the tape instantly to a named state, skipping `await`s and `startCountdown`s. |

**Why two engines?** The v1 panel was the existing prototype. The new chat surfaces tell a
deeper, narrated story — pilot prompts, auto-loop, comparison decisions — that can't be
synthesized from just step status. So the chat side has its own scripted event stream that
*coexists* with whatever the v1 panel is doing. In production, both should listen to the
same backend SSE stream; the tape is the prototype's stand-in for that stream.

### 2.3 Engine ↔ panel mapping

| Research scenario | v1 panel scenario | Notes |
|---|---|---|
| `rnaseq` | `nfcore` | nf-core is the closest v1 stand-in for an RNA-seq pipeline. |
| `drugscreen` | `drugscreen` | New v1 scenario added in `data.js` to align panel + chat. |
| `variant` | `gatk` | gatk's WGS Germline scenario is the closest panel match. |
| `cryosparc` | `cryosparc` | Identity. |
| `gatk` | `gatk` | Identity. |
| `admet` | `admet` | Identity. |
| `nfcore` | `nfcore` | Identity. |

Mapping lives in `V1_SCENARIO_MAP` (top of `ResearchApp.jsx`).

---

## 3. The five new surfaces

### Surface 1 · Plan checklist (`PlanChecklist.jsx`)

Sticky strip above the chat thread, **auto-appears when the engine fires `planShow`**.

Props: `items`, `editing`, `collapsed`, `onToggleCollapsed`, `onEditDone`, `onRemoveItem`,
`onAddItem`, `onItemAction`, `editLockCountdown`.

Item shape: `{id, title, status, est_s?, meta?, parent?, parallel?, failReason?}`.
Statuses: `pending | running | done | warn | failed | skipped`.

Parallel groups: items with the same `parallel: 'p1'` value render together with a
connector line.

**Plan items are phase-level across every scenario.** Step-level granularity lives in the
panel's phase cards. (This is a non-obvious invariant — was a bug we fixed mid-build.)

### Surface 2 · Speaker-pilled chat lines (`ChatStream.jsx`)

Each line carries a speaker pill: PLAN, WF, QC, LOOP, AGENT, FIND. Color tokens are in
`research-tokens.css`. Same-speaker collapse triggers after `collapseThreshold` consecutive
lines (default 3). Hover pill = tooltip with role name (`SPEAKERS` map at top of file).

**`(why?)` rationale tooltip:** if a chat line carries `rationaleId: 'scenarioId:phaseId'`,
a small `(why?)` anchor is appended. Hover → tooltip with the rationale text + citation
from `RESEARCH_PHASE_TRACE`. **This replaces the heavier inline phase-card expansion that
the spec originally proposed.**

### Surface 3 · The (why?) anchor (above)

Implemented inline in `ChatStream.jsx`. Data source: `RESEARCH_PHASE_TRACE[scenario:phase]`
in `research-data.js`.

### Surface 4 · Run-vs-Run comparison card (`ChatCards.jsx > ComparisonCard`)

Posted inline in chat by `showCard { card: 'comparison', data }`. Shape:

```ts
{
  runA: {label, sub},
  runB: {label, sub},
  metrics: [{name, a, b, delta, dir, aQc?, bQc?}],
  params:  [{name, a, b, origin: 'autoloop'|'user'}],
  recommendation: {preferred, confidence, reason, pvalue?, test?, autoProceed?},
}
```

When `confidence === 'high'` and the tape fires `startCountdown('compare_use_b_auto', 10)`,
the recommended button gets a 10s auto-pick countdown. Other confidences sit indefinitely.

### Surface 5 · Pilot prompt + Pilot promotion (`ChatCards.jsx`)

- **`PilotPromptCard`** — posted when the engine recommends a pilot. Inline radio (Pilot vs
  Full) + sampling strategy + Run/Skip buttons. Currently shows minute estimates only —
  **cost references are commented out**, see section 7.
- **`PilotPromotionCard`** — posted when a pilot completes. Has `result: 'pass' | 'fail'`
  variants. The fail variant carries an inline auto-loop suggestion (`changes:
  [[param,was,now]]`) plus an "Apply fixes and re-pilot" action.

---

## 4. After-run report (`WorkflowPanel.jsx > AfterRunReport`)

Lives at the bottom of the panel body when `runState === 'completed'`. Replaces the v1
"After run" link row + AI Analysis modal + Methods Report modal stack.

**Header:** "After run" label on the left + "Download report" link on the right. The
download stub flashes a toast for now; in production it should build a DOCX/MD/LaTeX
covering all tabs below.

**Tabs (in order):** Findings · Outputs · Methods · Parameters · Software · Citations ·
QC audit. The QC audit tab only appears if the scenario has any QC gates.

**Tab content** is rendered by the sub-components exported from `Modals.jsx`:

| Tab | Component | Data source |
|---|---|---|
| Findings | `ReportFindings` | Per-scenario `findings` map inside `AfterRunReport`. |
| Outputs | `ReportOutputs` | Flattened from `phases[].steps[].outputs[]` at render time. |
| Methods | `ReportMethodsImrad` | Static cryo-EM example prose (port should generate from manifest). |
| Parameters | `ReportParams` | Static example table (same). |
| Software | `ReportSoftware` | Static list (same). |
| Citations | `ReportCitations` | Static list (same). |
| QC audit | `QcAuditPanel` | Built dynamically from `scenario.phases[].qc[]`. |

**Tab data-tour aliases:** for backwards-compat with tutorials written against the old
modal stack, the Findings tab also carries `data-tour="link-report"`, Outputs has
`data-tour="link-view-results"`, QC audit has `data-tour="link-qc"`. Other tabs use
`data-tour="after-tab-<kind>"`. Tour `setup()`s click these to switch the active tab —
**this is how the tour drives content changes**, see section 5.

---

## 5. Tour engine (`Tour.jsx`)

Read this section carefully. The tour has more wiring than usual because it drives the
scenario engine, switches tabs in the after-run report, and opens/closes modals.

### 5.1 Step shape

```ts
{
  target: string | null,          // CSS selector, or null for centered modal
  placement: 'top'|'right'|'bottom'|'left'|'center',
  title: string,
  body: ReactNode,                // typically <>…<div className="hint">…</div></>
  icon?: string,                  // single emoji, shown floating on cartoon callouts
  setup?: (tweaks) => Partial<tweaks> | null,  // runs before measure
  autoAdvance?: number,           // ms before firing onNext automatically
  cta?: string,                   // override for the last-step button label
}
```

A demo is `{ id, label, group, scenario, cartoon?, steps: Step[] }`. Listed in
`DEMO_TOURS`. Picker reads `group` to organize.

### 5.2 Setup() — engine control surface

Setup is the key extension over the v1 tour. It runs **before** the spotlight measures
its target rect, so it can mutate engine state to ensure the target exists.

Common patterns:
- Return an object → merges into the tour-tweaks state (drives the v1 panel via
  `setTourTweak` in `ResearchApp.jsx`). E.g. `{ runState: 'completed' }`.
- `window.__tourFFTo('marker_id')` → research-engine fast-forward to a tape marker.
- `window.__tourAction('label')` → fire a user action into the engine (the old way; FF is
  preferred for drug-screen tour because it skips awaits).
- `window.__tourSetScenario('id')` → switch active scenario.
- `window.__tourReset()` → restart the active scenario from tape head 0.
- `window.__openTourModal(kind, payload)` / `__closeTourModal()` → open `preview` modal
  or any other Modal kind.
- DOM clicks → `document.querySelector('[data-tour="..."]').click()` is how tab-switching
  works (for after-run-report tabs).
- `scrollIntoView({behavior:'smooth', block:'start'|'center'|'end'})` on targets that need
  to be brought into view inside the panel body.

`onResize` callback on `<WorkflowPanel>` exists; the panel has a left-edge drag handle
that calls `setTweak({ panelWidth: N })`.

### 5.3 Auto-advance

If a step declares `autoAdvance: N`, `WFTour` fires `onNext` after N ms. The drug-screen
tour (R02) uses this end-to-end so it plays hands-off in ~90s. The cryo and output tours
advance on click.

**Critical:** `onNext` is held in a ref inside `WFTour` so re-renders don't reschedule
overlapping timeouts. If you refactor `WFTour`, keep this pattern.

### 5.4 Tutorial inventory

**Research-side (new):**

- `rnaseq-chat` — R01 — Bulk RNA-seq · chat surfaces (4 steps, cartoon)
- `drugscreen-compare` — R02 — Drug screen · auto-loop + comparison (13 steps, cartoon,
  fully auto-advanced)
- `variant-retry` — R03 — Variant calling · plan edit + retry (5 steps, cartoon)

**v1-side (legacy demos, lightly extended):**

- `overview` — General full walkthrough (9 steps)
- `nfcore-normal` / `nfcore-qcloop` / `nfcore-blocked` / `nfcore-disambig`
- `nfcore-idle` / `nfcore-failed`
- `gatk-idle` / `gatk-running` / `gatk-completed`
- `cryosparc-main` — **09d — CryoSPARC SPA · 3-minute deep dive** (20 steps, cartoon)
- `outputs-findings-report` — **09f — After run · all tabs** (13 steps, cartoon) — major
  rewrite for the new inline-tabbed after-run report
- `admet-main`

The previously-listed `nfcore-watcher` demo is **removed** because the watcher feature is
commented out for this release.

### 5.5 Tutorial narratives

Voiceover scripts for the three primary demos live in:

- `Demo Narratives.md` — English
- `Demo Narratives ZH.md` — Simplified Chinese (for China-market marketing)

Each script is keyed to the tour step, with pacing + diction notes at the bottom.

---

## 6. Tweaks panel (`ResearchTweaks.jsx`)

### 6.1 Tweaks that are exposed

| Group | Keys | Purpose |
|---|---|---|
| Scenario | `scenarioId` | Switch active research scenario. |
| Replay | `speed` | Engine playback speed multiplier. |
| Theme | `theme` | `light` / `dark`. |
| Density | `density` | `comfortable` / `compact`. |
| Q1 · Plan editability | `planEditDefault` | Recommend: yes, with 10s auto-lock. |
| Q2 · Collapse threshold | `collapseThreshold` | Recommend: ≥3. |
| Q3 · Comparison placement | `comparePlacement` | Recommend: inline (alternative: side panel). |
| Q4 · Pilot default | `pilotDefaultOn` | Recommend: auto-ON for heavy runs. |
| Q5 · Phase rationale | (text only) | Recommend: `(why?)` hover anchor. |
| Q6 · Pill placement | `pillPlacement` | Recommend: after the ◆ marker. |
| Q7 · Countdown seconds | `countdownSeconds` | Recommend: 10s. |
| Misc | `showTs`, `panelWidth`, `sidebarMode` | Chat options, layout. |

### 6.2 Persistence

State lives in `localStorage['biomate-research-tweaks']` AND in the
`/*EDITMODE-BEGIN*/{...}/*EDITMODE-END*/` block at the top of `ResearchApp.jsx`. On user
edit, `ResearchApp` posts `{type: '__edit_mode_set_keys', edits: patch}` to the host so
the host (the design tool) can rewrite the EDITMODE block on disk.

**For production:** drop the EDITMODE block entirely. Tweaks become a developer-only flag
panel. The seven recommended values become the production defaults.

### 6.3 Reopen pill

`tweaks-reopen` (bottom-LEFT, fixed) appears whenever the Tweaks panel is closed. Anchored
left so it never overlaps the workflow panel's Confirm-and-Run button (panel is on the
right).

---

## 7. Things deliberately commented out · "leaving for future work"

These are wrapped in comments with the marker "leaving for future work" so they're easy to
re-enable.

### 7.1 Cost / pricing

Every dollar amount and "cost" reference is commented:
- `research-data.js` — every scenario's `cost: { full_usd, pilot_usd }`, every findings-card
  `cost:`, every phase-trace `cost: { used, est, vcpuh }`.
- `data.js` — every v1 scenario's `max_cpus` and `max_memory` global params.
- `ChatCards.jsx` — pilot prompt cost badge + meta cost text; pilot promotion meta cost
  text; pilot promotion "Ready for full run" sub-cost; findings card cost line.
- `Modals.jsx ReportFindings` — `Compute cost` row in the cryosparc findings table.
- `Tour.jsx` — every tour hint mentioning cost.

**Search the codebase for `leaving for future work`** to find them all.

### 7.2 Skip step / Skip phase

In `PhaseCard.jsx` — both step-level Skip and phase-level Skip Phase buttons are commented
with a note: needs dependency-graph alignment before re-enabling.

### 7.3 Watcher (detach / reconnect)

In `WorkflowPanel.jsx` — the watcher-attached row in the panel footer is commented out.
The `nfcore-watcher` tour demo is also removed. Re-enable both together once the live SSE
work lands.

### 7.4 Phase-card inline trace expansion

Originally specced (Surface 3 in the requirements doc) as a heavy inline expansion under
each phase card with rationale, live events, params, cost. **Replaced with the lightweight
`(why?)` hover anchor on chat lines.** The data structure (`RESEARCH_PHASE_TRACE`) still
supports the heavier form if you want to restore it.

---

## 8. Critical contracts · don't break these

1. **`window.SCENARIOS`** has 5 keys: `cryosparc`, `gatk`, `admet`, `nfcore`, `drugscreen`.
   The first 4 are v1; the 5th is a new chat-aligned scenario.
2. **`window.RESEARCH_SCENARIOS`** has 7 keys: 3 new (`rnaseq`, `drugscreen`, `variant`)
   plus 4 v1 adapters (`cryosparc`, `gatk`, `admet`, `nfcore`).
3. **Plan items must be phase-level**, not step-level. Step-level granularity lives in the
   workflow panel.
4. **`AWAIT_ACCEPTS`** map in `ResearchApp.jsx` defines which user actions satisfy each
   await label. If you add a new `await` to a tape, add its accepted actions here.
5. **`AfterRunReport`** depends on `window.ReportFindings`, `window.ReportOutputs`,
   `window.ReportMethodsImrad`, `window.ReportParams`, `window.ReportSoftware`,
   `window.ReportCitations`, `window.QcAuditPanel` — all exported by `Modals.jsx`.
6. **Dismiss key alignment.** The tape dismisses a card via `dismissCard { card: 'X' }`;
   the render checks `dismissedCards['X']`. Keys must match. (We had this bug; the keys
   are now `pilotPrompt`, `pilotPromotion`, `comparison`.)
7. **Tour `setup()` is sync.** Return either a tweak-patch object or `null` (for side
   effects). Don't return a promise — the spotlight measures right after.
8. **Brand logo** is at `images/biomate-logo.png`. Sized full-width via `object-fit:
   cover` in `.brand.brand-full`.

---

## 9. Recommended port order

1. **Copy `tokens.css`, `layout.css`, `research-tokens.css`, `research-layout.css`,
   `tour.css` as-is.** They're framework-agnostic.
2. **Port `Icon.jsx`** — trivial, just SVG.
3. **Port `data.js` + `research-data.js`** — or replace with real API calls.
   - `data.js` → `GET /api/scenarios/:id`
   - `research-data.js` tapes → SSE stream from the backend
   - `RESEARCH_PHASE_TRACE` → `GET /api/workflows/{inv}/phases/{name}/trace`
4. **Port the leaf components first:** `PlanChecklist`, `ChatStream`, `ChatCards`,
   `Modals`, `AutoLoop`, `PhaseCard`. They're pure presentation.
5. **Port `WorkflowPanel.jsx`** — replace the fake `setInterval` run loop with a real SSE
   subscription. Keep `AfterRunReport` intact; the tab data plumbing is already correct.
6. **Port `ResearchApp.jsx`** — this is the engine. Replace the tape walker with an SSE
   subscription that maps backend events to the same internal state shape.
7. **Port `Chrome.jsx > Sidebar`** — make the chat list a real session list.
8. **Tweaks panel and Tour** — keep for QA / internal demos; ship `Tweaks` off-by-default
   in production. Optionally keep the Tour for in-product onboarding.

---

## 10. Known caveats

1. **React setState-in-render warnings** sometimes emit from `WorkflowPanel.jsx`'s
   simulated run loop. Not a crash; will go away when the loop is replaced with SSE.
2. **In-browser Babel** transpiles JSX at load. Production port should precompile.
3. **`AfterRunReport`'s Methods/Parameters/Software/Citations tabs** show static cryo-EM
   example text regardless of scenario. Wire to `manifest.methods / manifest.params /
   manifest.software / manifest.citations` when porting.
4. **The `Workflow Panel Redesign.html`** (root, not extended) is the v1 starting point.
   Kept side-by-side for reference; the active app is `Research Agent UI.html`.
5. **Skip dependency graph.** When you re-enable skip-step / skip-phase, you'll need to
   re-evaluate the dependency graph to mark downstream steps as needing-input.
6. **Live SSE for the drug-screen Run-vs-Run comparison** — the backend endpoint
   `/api/workflows/runs/{a}/compare?with={b}` was specced as needing
   `parameterDifferences` populated. Check that's done before wiring.

---

## 11. Smoke test checklist

After porting, verify:

- [ ] Sidebar shows all 7 chat threads; clicking each switches the active scenario.
- [ ] Active-scenario tour group floats to the top of the Tutorial picker.
- [ ] Drug screen tour runs end-to-end hands-off in ~90s without crashing.
- [ ] After-run report appears when runState becomes completed; all 7 tabs switch cleanly.
- [ ] Download report link in the After-run header is wired (currently fires a toast).
- [ ] Tweaks panel close button posts `__edit_mode_dismissed`; pill at bottom-left.
- [ ] Tweaks panel reopens via the pill in bottom-left when closed.
- [ ] Panel resize drag-handle on left edge of the panel resizes between 380–800px.
- [ ] `(why?)` rationale tooltip appears on chat lines with `rationaleId` set.
- [ ] No browser console errors when each scenario plays through.

---

## 12. Quick reference · file dependencies

```
Research Agent UI.html
├── tokens.css
├── layout.css
├── research-tokens.css
├── research-layout.css
├── tour.css
│
├── data.js                  # window.SCENARIOS
├── research-data.js         # window.RESEARCH_SCENARIOS, window.RESEARCH_PHASE_TRACE
│
├── Icon.jsx
├── Chrome.jsx               # Sidebar (used), ChatColumn (legacy)
├── PhaseCard.jsx            # PhaseCard, Step, QcBlock, StatusChip
├── AutoLoop.jsx             # AutoLoopCard
├── Modals.jsx               # All modals + Report sub-components + QcAuditPanel
├── WorkflowPanel.jsx        # WorkflowPanel + AfterRunReport
├── Tour.jsx                 # DEMO_TOURS, WFTour, useWFTour
│
├── PlanChecklist.jsx        # New surface 1
├── ChatStream.jsx           # New surface 2 + (why?) anchor
├── ChatCards.jsx            # New surfaces 4 + 5
├── ResearchTweaks.jsx       # Tweaks panel UI
└── ResearchApp.jsx          # Root component + scenario engine
```

---

## 13. Final notes

- This prototype prioritizes **demoability** over production-readiness. The simulated
  run loop, the tape engine, the static report tabs, and the inline Babel are all in
  service of that.
- Read **`Demo Narratives.md`** before you watch the tutorials; the narration explains
  what each step is showing.
- The Chinese subtitle script (`Demo Narratives ZH.md`) was authored for marketing in
  China and follows the same step structure.
- When in doubt about a behaviour, **run the tutorial for that scenario** in the live UI.
  The tutorial reflects the intended user-facing model end-to-end.

Good luck with the port — most of the moving parts are deliberately separated so each
file is portable on its own. The two engines + the tour are the only places where the
glue gets dense; everything else is presentational React.
