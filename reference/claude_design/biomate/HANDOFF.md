# BioMate Workflow Panel — Design Handoff

This prototype implements the phase-first workflow console redesign for BioMate's bioinformatics workflow runner. It ships as a single HTML file plus a set of React/JSX component files, with no build step — everything loads via inline Babel.

The goal of this document is to give an engineer (or Claude Code) enough structure to port this to a real codebase without guessing at intent.

---

## 1. Files and responsibilities

| File | Responsibility |
|---|---|
| `Workflow Panel Redesign.html` | App entry. Defines `App`, the scenario/run-state machine, `openModal` router, `setTweak` persistence, and the Tweaks panel. |
| `src/tokens.css` | Design tokens: colors (`--bg`, `--surface-*`, `--text-*`, `--border`, `--accent`, `--err`, `--ok`), radii, shadows, type scale. |
| `src/layout.css` | All layout, component, and state styles. Organized top-down: app grid → sidebar → chat column → workflow panel → phase/step → QC/autoloop → modals → tweaks → toast. |
| `src/data.js` | Four hardcoded workflow scenarios (`CRYOSPARC`, `GATK`, `ADMET`, `NFCORE`), exposed as `window.SCENARIOS`. |
| `src/Icon.jsx` | Inline SVG icon set (one `<Icon name="..." size={N}/>` component). |
| `src/Chrome.jsx` | `Sidebar` (threads + rail mode) and `ChatColumn` (chat messages, input, disambiguation card). |
| `src/PhaseCard.jsx` | `PhaseCard`, `Step`, `QcBlock`, `StatusChip`. |
| `src/AutoLoop.jsx` | `AutoLoopCard` — the inline QC-halt-with-proposed-fix card. |
| `src/Modals.jsx` | `SkipConfirmModal`, `AdjustModal`, `PreviewModal`. |
| `src/WorkflowPanel.jsx` | The panel itself: scenario → phase list → settings strip → post-run results → run footer. Owns the simulated SSE run loop and the local toast. |

Scripts are cache-busted with `?v=N` — bump when porting to avoid stale browser caches.

---

## 2. Information architecture

The redesign's core move is to make **phases** the primary unit of the panel. Phases collapse to one row each and expand to reveal their steps, QC gates, and phase-level run/skip actions. Individual steps never own the vertical scroll.

```
App (3-column grid)
├── Sidebar
│   ├── Brand
│   ├── Home / Threads / Files / Tools nav
│   └── Current history list (scenario picker)
├── ChatColumn
│   ├── Messages
│   │   ├── User query
│   │   ├── BioMate response (pre-exec summary) w/ WorkflowRef card
│   │   ├── [optional] Disambiguation card (two close matches)
│   │   └── [optional] Findings / run-complete summary
│   └── Chat input (textarea + Suggest button)
└── WorkflowPanel
    ├── Panel header (scenario name + subtitle + close)
    ├── [optional] License gate alert
    ├── [optional] Blocked alert
    ├── Phase list
    │   └── PhaseCard (repeated)
    │       ├── Phase head (chevron, letter badge, titles, status chip, progress)
    │       └── Phase body (when open)
    │           ├── Step rows (name, chip, actions)
    │           ├── QcBlock (QC gates + auto-loop toggle)
    │           ├── [optional] AutoLoopCard (QC halt with proposed fix)
    │           └── Phase-action row (Run phase / Skip phase)
    ├── "Suggest a new step via chat" link
    ├── Capability hint tip
    ├── Workflow settings strip (collapsed; expands to show global params)
    ├── [run complete] After-run links + Findings card
    └── Run footer
        ├── Progress bar
        ├── Confirm & Run / Stop / Run again button
        └── Watcher bar (attached · live SSE // detached · AWS Batch)
└── Modals (rendered at app level)
    ├── SkipConfirmModal (step or phase)
    ├── AdjustModal
    └── PreviewModal
```

---

## 3. Data model

### Scenario shape (`window.SCENARIOS[id]`)

```ts
type Scenario = {
  id: string;
  name: string;
  subtitle: string;
  domain: string;
  query: string;              // the chat query that "produced" this workflow
  globalParams: Param[];
  phases: Phase[];
};

type Phase = {
  id: 'A' | 'B' | 'C' | ...;  // letter label in the UI
  name: string;
  summary: string;
  steps: Step[];
  qc: QcGate[];
  autoloop: boolean;          // whether this phase has auto-loop on QC fail
};

type Step = {
  id: string;
  name: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'skipped';
  params: { k: string; v: string }[];
  outputs: { name: string; type: 'table'|'image'|'folder' }[];
  runCount?: number;          // added at mount, incremented by rerun
};

type QcGate = { metric: string; op: '>'|'<'|'='|'between'; threshold: string };
type Param  = { key: string; label: string; value: string };
```

### Four scenarios included

| ID | Name | Phases | Steps | Notable |
|---|---|---|---|---|
| `cryosparc` | CryoSPARC SPA | 5 (A–E) | 23 | Has mid-run steps (`running` + `completed` mix), 3 QC gates with auto-loop |
| `gatk` | WGS Germline — GATK4 | 3 (A–C) | 8 | `mapping_rate > 95%` and `ts_tv_ratio between 2.0–2.1` gates |
| `admet` | ADMET Property Prediction | 1 | 1 | Degenerate case — tests 1-step / no-phases UI |
| `nfcore` | nf-core · fastp QC | 2 | 4 | Multi-accession QC pipeline |

---

## 4. State machine

### App-level state (in `Workflow Panel Redesign.html`)

| State | Type | Source of truth | Persisted? |
|---|---|---|---|
| `scenario` | string | `TWEAK_DEFAULTS` + localStorage | ✅ via Tweaks |
| `runState` | `'idle' \| 'running' \| 'completed' \| 'failed'` | Tweaks + simulated run loop | ✅ |
| `speed` | number (ms per step) | Tweaks | ✅ |
| `panelOpen` | boolean | Close button | ❌ (session only) |
| `panelWidth` | number (px) | Tweaks | ✅ |
| `sidebarMode` | `'auto' \| 'expanded' \| 'hidden'` | Tweaks | ✅ |
| `qcHalt` / `licenseGate` / `blocked` / `disambig` | boolean | Tweaks | ✅ |
| `watcherAttached` | boolean | Footer link + Tweaks | ✅ |
| `modal` | `{kind: 'skip'\|'adjust'\|'preview', ...} \| null` | `openModal(kind, payload)` | ❌ |
| `tweaksVisible` | boolean | Host toolbar toggle (postMessage) | ❌ |

### Panel-level state (in `WorkflowPanel`)

| State | Notes |
|---|---|
| `phases` | Cloned from scenario data; mutated by simulated run loop, rerun, skip. |
| `openPhaseId` | Which phase card is expanded. Defaults to running phase or first phase. Resets when scenario changes. |
| `settingsOpen` | Workflow-settings strip expanded. |
| `autoloopMap` | Per-phase `{[phaseId]: boolean}` overlay over the scenario's default. |
| `toast` | `{msg, id} \| null` — drives the 2.4s dismissible pill. |

### Run simulation

`WorkflowPanel` drives a 1-step-at-a-time simulation when `runState === 'running'`:

- Every `speed` ms, find the currently-running step; mark it `completed`; find the next `pending` step in the same phase and mark it `running`.
- If the current phase has no more `pending` steps, advance to the first `pending` step of the next phase, and `setOpenPhaseId` to that phase.
- When no pending steps remain anywhere, `setRunState('completed')`.

This is an intentionally simple stand-in for a real SSE stream. In a real impl, replace with a subscription to the backend's run events.

### Modal router

```js
const openModal = (kind, payload) => setModal({ ...payload, kind });
```

**Important**: the spread order matters. The outer `kind` must win; that's how the app distinguishes `'skip'` vs `'adjust'` vs `'preview'`. The payload uses `targetKind: 'step' | 'phase'` (NOT `kind`) to disambiguate step-skip vs phase-skip inside `SkipConfirmModal`.

---

## 5. Interaction inventory

### Working interactions

| Element | Trigger | Effect |
|---|---|---|
| Phase head | Click | Toggle open/collapsed |
| Step params button (⚙) | Click | Toggle inline-params editor |
| Step Rerun button (completed) | Click | Flip to `running`, bump `runCount` |
| Step Adjust button (failed) | Click | Open `AdjustModal` |
| Step Skip button (pending/failed) | Click | Open `SkipConfirmModal` w/ `targetKind:'step'` |
| Step output "view" | Click | Open `PreviewModal` |
| Step output "dl" | Click | Toast: "Download queued — …" |
| QC gate edit | Click | Toast (edit surface placeholder) |
| Auto-loop switch | Click | Toggle per-phase auto-loop |
| Run phase button | Click | Set first pending step of phase to `running`, flip `runState` if idle |
| Skip phase button | Click | Open `SkipConfirmModal` w/ `targetKind:'phase'` |
| Suggest a new step via chat | Click | Focus chat textarea + seed prompt + toast |
| Workflow settings strip | Click | Expand/collapse global params |
| Global param edit | Click | Toast (edit surface placeholder) |
| AutoLoopCard Accept | Click | Flip auto-loop on for phase + toast |
| AutoLoopCard Dismiss | Click | Toast |
| Confirm & Run / Stop / Run again | Click | Flip `runState` accordingly |
| Detach / Reconnect watcher | Click | Toggle watcher state + chip |
| Reopen panel button (when closed) | Click | Reopen panel |
| Sidebar reopen button (when hidden) | Click | Set sidebar to auto |

### Placeholder / toast-only interactions

These fire a toast to acknowledge the click but don't open a real panel yet. They're deliberate placeholders for future work:

- Output file "dl" — should call a real download endpoint
- QC gate "edit" — should open a threshold-editor modal
- Global param "edit" — should open the settings strip with that row in edit mode, or a dedicated modal
- "Suggest a new step via chat" — currently seeds the textarea; a fuller version would pre-construct an assistant message

### Edge cases (exposed as Tweaks)

| Flag | What it shows |
|---|---|
| `qcHalt` | `AutoLoopCard` inline under the first phase body, with proposed parameter adjustments + literature citation + Accept/Dismiss |
| `licenseGate` | Credential-required alert at the top of the panel with Configure action |
| `blocked` | Missing-param error alert with Fix now / Confirm anyway |
| `disambig` | In-chat disambiguation card showing two close workflow matches with similarity scores |
| `watcherAttached: false` | Footer swaps to "Watcher detached · job on AWS Batch" with Reconnect link |
| `panelOpen: false` | Chat column shows a "Panel" button top-left to reopen |

---

## 6. Responsive behavior

- **Sidebar auto-collapse**: when `sidebarMode === 'auto'` AND `panelOpen === true`, sidebar becomes a 56px icon rail. Hover reveals labels.
- **Chat padding**: uses `clamp()` to scale from 20px → 8% → 120px as viewport narrows.
- **Below 1100px**: panel shrinks.
- **Below 900px**: sidebar hides automatically; a floating reopen button appears.
- **Panel width**: live-adjustable via Tweaks (420–640px, persisted).

---

## 7. Design tokens (from `tokens.css`)

See `src/tokens.css` for the full list. Key tokens:

- **Surfaces**: `--bg`, `--surface`, `--surface-2`, `--surface-3`
- **Text**: `--text`, `--text-muted`, `--text-dim`
- **Borders**: `--border`, `--border-strong`
- **Accent**: `--accent` (primary action), `--accent-weak`
- **Status**: `--err`, `--ok`, `--warn`, `--run` (cyan for running)
- **Radii**: `--r-sm` (4px), `--r-md` (6px), `--r-lg` (10px)
- **Shadows**: `--shadow-sm`, `--shadow-md`, `--shadow-lg`
- **Fonts**: `--font-sans` (system stack), `--font-mono` (system mono)

---

## 8. What is NOT covered

Things a real implementation still needs to build, that this prototype only stubs:

1. **Real SSE / workflow backend** — the run simulation is a fake loop driven by `setTimeout`.
2. **Auth + license gate flow** — the `licenseGate` alert points at a Configure action that's a no-op.
3. **Editable QC thresholds** — the edit affordance shows a toast; real flow needs an inline editor or modal.
4. **Editable global params** — same as QC.
5. **File preview content** — `PreviewModal` shows a static string placeholder.
6. **File download** — `dl` and Download-all are UI-only.
7. **Chat history / threads / tools** — Sidebar lists are static; only the "Current" list is interactive (acts as a scenario picker).
8. **Suggest-a-step chat flow** — seeds the textarea but doesn't produce a real assistant response.
9. **Accessibility audit** — focus rings are present on buttons but keyboard navigation of the phase list and modal trap are not exhaustively implemented.
10. **Methods report / AI analysis / QC audit log links** — shown in the After-run section as `.linkish` buttons; currently no-op.
11. **Empty / error states for individual scenarios** — the `blocked` and `licenseGate` tweaks demonstrate the intent but a real system needs them tied to actual validation results.

---

## 9. Known implementation notes

- **Babel in-browser**: the prototype ships with `@babel/standalone` transpiling JSX at load. A real port should precompile.
- **Global style objects**: each component uses CSS classes + scoped token variables — no shared JS `styles` objects that could collide.
- **Window globals**: components expose themselves via `Object.assign(window, {...})` since Babel-loaded scripts don't share scope. When porting to a bundler, convert to `import` / `export`.
- **localStorage key**: `biomate-tweaks` stores the full `TWEAK_DEFAULTS` shape.
- **Speaker-notes postMessage**: not used here (this isn't a deck).

---

## 10. Component prop contracts

### `WorkflowPanel`

```ts
{
  scenario: string;                    // id in SCENARIOS
  runState: RunState;
  setRunState: (s: RunState) => void;
  onOpenModal: (kind, payload) => void;
  onClosePanel: () => void;
  tweaks: { speed, qcHalt, licenseGate, blocked };
  watcherAttached: boolean;
  setWatcherAttached: (b: boolean | (prev) => boolean) => void;
}
```

### `PhaseCard`

```ts
{
  phase: Phase;
  open: boolean;
  onToggle: () => void;
  onRunPhase: () => void;
  onSkipPhase: () => void;
  onStepAction: (action: 'skip'|'rerun'|'adjust'|'preview'|'download', arg, phase) => void;
  onEditGate: (gate) => void;
  onToggleLoop: () => void;
  autoloopOn: boolean;
}
```

### `SkipConfirmModal`

```ts
{
  target: {
    targetKind: 'step' | 'phase';     // NOT `kind` — that's reserved for the router
    name: string;
    phaseId: string;
    stepId?: string;
    downstream: string[];             // e.g. ['Phase B', 'Phase C']
    confirm: () => void;              // runs on "Skip ... anyway"
  };
  onCancel: () => void;
  onConfirm: () => void;
}
```

### `AutoLoopCard`

```ts
{
  phase: Phase;
  attempt: number;                    // e.g. 2
  maxAttempts: number;                // e.g. 3
  onAccept: () => void;
  onDismiss: () => void;
}
```

---

## 11. Suggested porting order

1. Copy `tokens.css` + `layout.css` as-is.
2. Port `Icon.jsx` — trivial.
3. Port `data.js` — or replace with real scenario fetch.
4. Port `PhaseCard.jsx`, `Modals.jsx`, `AutoLoop.jsx` — pure presentational; wire handlers via props.
5. Port `Chrome.jsx` — Sidebar + ChatColumn; hook up real threads + chat messages.
6. Port `WorkflowPanel.jsx` — replace the fake run loop with a real SSE subscription; keep the state shape intact.
7. Replace `window.SCENARIOS` with a real API call.
8. Wire the Tweaks panel off for production, but keep the edge-case alerts (license gate, blocked, watcher detached, disambiguation) as real states tied to backend validation.
