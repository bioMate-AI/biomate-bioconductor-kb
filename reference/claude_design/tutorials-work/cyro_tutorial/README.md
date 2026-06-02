# Handoff: BioMate Research-Agent UI — Tutorial / Tour System (deterministic drive)

## Overview

This package hands off the **BioMate Research-Agent UI** prototype, with particular focus
on its **guided-tutorial ("tour") system** — the in-product walkthroughs that narrate a
workflow run, step by step, while highlighting parts of the UI.

The prototype is a single HTML page that loads React (18.3.1) + Babel-standalone via
`<script type="text/babel">`, with no build step. It renders a chat column (left) and a
workflow panel (right), both narrating the same bioinformatics run from two angles.

> **These files are design references, not production code.** They are HTML/JSX prototypes
> showing the intended look and behaviour. The task is to **recreate them in the target
> codebase's environment** (React, Vue, Svelte, native, etc.) using its established
> patterns — or, if no app exists yet, to pick the most appropriate framework and implement
> there. Do not ship the inline-Babel HTML as-is.

A complete, broader engineering brief for the whole app already exists at
**`HANDOFF_RESEARCH_AGENT_UI.md`** (included in this bundle). Read that for the full app;
**read this document for the tutorial system specifically**, which was recently reworked
and has a subtle contract that is easy to get wrong.

## Fidelity

**High-fidelity.** Colours, typography, spacing, motion, and interaction are final. Recreate
the UI pixel-accurately using the design tokens in `src/tokens.css` /
`src/research-tokens.css`. Tour callout chrome lives in `src/tour.css`.

---

## 1. Why the tutorial system needed reworking (the core problem)

A tour is a list of **steps**. Each step shows a callout ("tip") with title + body, and
highlights a target element. The run being narrated is animated by **two independent
engines**:

- **Workflow panel** (`WorkflowPanel.jsx`) — a simulated SSE loop that, while
  `runState === 'running'`, ticks every ~900ms: completes the running step, starts the next,
  advances phases, and auto-expands whichever phase is running.
- **Chat / progress stream** (`ResearchApp.jsx` + `research-data.js`) — walks a scripted
  `tape` of timed events (chat lines, plan updates, cards) on its own timer.

**The bug:** the CryoSPARC tutorial set `runState: 'running'` and let both engines free-run
on their timers. The user reads each tip at their own pace, but the engines kept ticking —
so by the time the user read *"Phase A is running,"* the panel had raced ahead to a later
phase or finished entirely, and the chat stream had blasted all the way to *"Reconstruction
converged at 3.21 Å"* within ~10 seconds. **The animation no longer matched the tip.**

**The fix (the contract this document is about):** a tutorial must **drive the UI
deterministically** — freeze the free-running engines and explicitly set the exact state
each step describes. The sibling Bioconductor / drug-screen tours already did this for the
chat stream via tape markers; the fix extended the same discipline to the workflow panel and
to the CryoSPARC tour.

---

## 2. The deterministic-drive mechanism

Three imperative APIs are exposed on `window` (registered/torn down by the React components)
so a tour step's `setup()` can pin both engines into an exact, frozen state.

### 2.1 Workflow-panel pin — `window.__wfPin(spec)` / `window.__wfUnpin()`

Registered by `WorkflowPanel.jsx`. When a `pinSpec` is set, the panel's simulated-SSE tick
is **frozen** and the phase list is forced into an exact state. Spec forms:

| Spec | Meaning |
|---|---|
| `{ idle: true }` | All steps `pending` (a not-yet-started preview). Phase A expanded. |
| `{ running: 'A', runningStepIdx: 2 }` | Phase A is the active/expanded phase; steps `0,1` completed, step `2` running, rest pending. Earlier phases none. |
| `{ done: ['A'], running: 'B', runningStepIdx: 0 }` | Phase A fully completed (outputs seeded), Phase B running at step 0, expanded. |
| `{ complete: true }` | All steps completed; last phase referenced; after-run report shows. |

`__wfUnpin()` clears the pin and the engine resumes normal behaviour. A manual "Run" click
also clears it. Implementation details:

- `pinSpec` is React state; an effect re-applies it whenever it changes **or the scenario
  resets** (`useEffect(..., [pinSpec, scenario])`), so a scenario reset can't clobber a pin.
- The tick effect early-returns while `pinSpec` is set (and lists `pinSpec` in its deps so it
  re-evaluates the moment a pin is applied).
- Completed steps are seeded with their `base.phases[].steps[].outputs` (or a synthetic
  `<id>_output.star`) so inline output chips and the after-run report have data.

### 2.2 Chat-stream pause — `window.__tourManual(on)`

Registered by `ResearchApp.jsx`. Sets a ref that makes the tape walker (`runStep`) and the
scenario kick-off effect **no-ops** while `on === true`. This is what stops the progress
stream from auto-playing to completion while the user reads an early tip. Flipped on by the
tour's first step and off by the tour teardown (`stop()` / `startDemo()` in `Tour.jsx`).

### 2.3 Chat-stream fast-forward — `window.__tourFFTo(markerId)`

Registered by `ResearchApp.jsx`. Walks the active scenario's `tape` from the current head
**forward** to a `{ kind: 'marker', id }` event, applying every non-control event instantly
(skipping `await` / `startCountdown`). Hardened behaviour:

- **If the marker is not ahead of the current head, it is a NO-OP.** This makes repeated /
  same-marker steps and backward navigation safe — they can never accidentally replay the
  whole tape to the end (which was a failure mode of the naive version).

### 2.4 Tape markers

The narrated state lives behind named markers in the scenario `tape` (`research-data.js`).
For CryoSPARC the markers are, in order:

```
cryo_plan → cryo_a_run → cryo_a_done → cryo_b_run → cryo_de_run → cryo_done
```

The `"Reconstruction converged at 3.21 Å"` line and the findings card sit **after**
`cryo_de_run`, behind `cryo_done` — so they only appear at the final completion beat, never
earlier.

---

## 3. How a tour step drives the UI (the authoring contract)

Each step has a `setup(tweaks)` that runs **before** the spotlight measures its target. To
keep the animation matched to the tip, `setup()` should, in this order:

1. (first step only) `window.__tourManual(true)` then `window.__tourReset()` — freeze + clear
   the stream.
2. `window.__tourFFTo('<marker>')` — advance the chat stream to the beat this tip describes
   (omit on steps that should leave the stream where it is).
3. `window.__wfPin({ ... })` — pin the workflow panel to the exact phase/step state.
4. `return { runState, qcHalt, ... }` — tweak-patch merged into tour state (drives the
   panel's status badge, QC halt card, etc.). Return `null` for pure side-effects.

`setup()` is **synchronous** — return a patch object or `null`, never a promise.

### Worked example (CryoSPARC "Gate cleared — Phase B kicks off")

```jsx
setup: () => {
  if (window.__tourFFTo) window.__tourFFTo('cryo_b_run');                       // stream → Phase B beat
  if (window.__wfPin)   window.__wfPin({ done: ['A'], running: 'B', runningStepIdx: 0 }); // panel → A done, B running
  return { qcHalt: false, runState: 'running' };                               // badge running, halt card gone
},
```

### Teardown

`Tour.jsx`'s `stop()` and `startDemo()` call `window.__wfUnpin()` and
`window.__tourManual(false)` so the UI is never left frozen after a tour ends or when
switching tours.

---

## 4. CryoSPARC tour ↔ state map (reference)

The `cryosparc-main` demo (`09d — CryoSPARC SPA · 3-minute deep dive`) maps its steps to
state as follows. This is the canonical example of an in-sync tour.

| Tip (step) | Stream marker | Panel pin | Run badge |
|---|---|---|---|
| Welcome (center) | reset → none | `{ idle:true }` | idle |
| Two views / Run header / 5 phases / Inside A / Confirm | `cryo_plan` (step 2) | `{ idle:true }` | idle |
| We're off! Phase A running | `cryo_a_run` | `{ running:'A', runningStepIdx:0 }` | running |
| Live progress per step | — | `{ running:'A', runningStepIdx:2 }` | running |
| QC gate tripped | `cryo_a_done` | `{ running:'A', runningStepIdx:4 }` | running + qcHalt |
| Halt card | — | `{ running:'A', runningStepIdx:4 }` | running + qcHalt |
| Gate cleared — Phase B kicks off | `cryo_b_run` | `{ done:['A'], running:'B', runningStepIdx:0 }` | running |
| Step outputs / Preview modal | — | `{ done:['A'], running:'B', runningStepIdx:1 }` | running |
| Phases B → E run through | `cryo_de_run` | `{ done:['A','B','C'], running:'D', runningStepIdx:1 }` | running |
| All 23 steps complete | `cryo_done` | `{ complete:true }` | completed |
| Outputs / After-run | — (stays at done) | `{ complete:true }` | completed |

---

## 5. State management

- **Two `runState`s coexist:** the research-engine `runState` (drives plan/stream) is set by
  tape `runState` events; the panel `v1RunState` is set by the tour's `setup()` return via
  `setTourTweak`. They are intentionally separate. `__tourReset()` resets only the research
  engine — it does **not** clear a `__wfPin`.
- **Refs vs state:** `tourManualRef` is a ref (read synchronously inside timers). `pinSpec`
  is React state (drives re-render of the frozen phase list). Keep this split if you refactor.
- **Auto-advance:** a step may set `autoAdvance: N` (ms) to fire `onNext` automatically;
  `WFTour` holds `onNext` in a ref so re-renders don't stack overlapping timers.

---

## 6. Design tokens (tour chrome)

Pull exact values from `src/tokens.css`, `src/research-tokens.css`, `src/tour.css`. Key ones:

- **Spotlight ring (cartoon):** dashed ring `oklch(0.55 0.18 250)` stroke 2.5,
  `stroke-dasharray: 6 5`, radius 14; outer glow `oklch(0.78 0.10 250 / 0.35)` stroke 10.
- **Speaker pill palette:** `--bm-plan / --bm-wf / --bm-qc / --bm-loop / --bm-agent / --bm-find`
  (in `research-tokens.css`) — stable across plan, chat, and tweaks.
- **Callout width:** 420px (center) / 360px (anchored); offset 14px; viewport margin 16px.

---

## 7. Files in this bundle

| File | Role |
|---|---|
| `Research Agent UI.html` | App entry — loads all CSS + JSX. |
| `HANDOFF_RESEARCH_AGENT_UI.md` | Full app engineering brief (read alongside this doc). |
| `src/Tour.jsx` | **Tour system** — `DEMO_TOURS` registry, `WFTour` callout, `WFSpotlight`, `TourPicker`, `useWFTour` hook. Drive/teardown wiring lives here. |
| `src/WorkflowPanel.jsx` | Right panel + simulated SSE tick + **`__wfPin` pin API** + `AfterRunReport`. |
| `src/ResearchApp.jsx` | Root + tape engine + **`__tourManual` / `__tourFFTo` / `__tourReset`** window hooks. |
| `src/research-data.js` | `RESEARCH_SCENARIOS` tapes (with markers) + `RESEARCH_PHASE_TRACE`. |
| `src/data.js` | v1 `SCENARIOS` (phases / steps / QC / outputs) → `window.SCENARIOS`. |
| `src/PlanChecklist.jsx` `src/ChatStream.jsx` `src/ChatCards.jsx` | Chat-side surfaces. |
| `src/PhaseCard.jsx` `src/AutoLoop.jsx` `src/Modals.jsx` | Panel-side presentation + after-run report sub-components. |
| `src/Chrome.jsx` `src/Icon.jsx` `src/ResearchTweaks.jsx` | Sidebar, icons, tweaks panel. |
| `src/*.css` | `tokens`, `layout`, `research-tokens`, `research-layout`, `research-readable`, `tour`. |

---

## 8. Production guidance for the tour system

- **Replace both simulated engines with the real SSE stream.** The `__wfPin` /
  `__tourFFTo` mechanism is a prototype stand-in for "jump the UI to a known state." In
  production, a tutorial should drive against **recorded fixture events** (or a replayable
  demo run) rather than scripted tapes — but the *contract* stays: a tutorial step must put
  the UI in a deterministic, frozen state, never let a live timer race the narration.
- **Keep the freeze.** Whatever the data source, a guided step must pause auto-progression
  while its tip is showing. The single most important lesson from this rework: **never narrate
  a moving target.**
- **Keep fast-forward idempotent / monotonic.** The "no-op if marker not ahead" guard is what
  makes Back/Next navigation safe. Preserve an equivalent guard.
- **Tours can ship as in-product onboarding**; the Tweaks panel should ship off by default
  (developer/QA only).

---

## 9. Smoke test (tour sync)

- [ ] Start `09d — CryoSPARC SPA · 3-minute deep dive`. Step through with Next/→.
- [ ] At every step the panel's expanded/highlighted phase matches the tip (Phase A while on
      A, Phase B after "gate cleared", etc.).
- [ ] The chat stream advances in lockstep; it never auto-plays to completion while a tip is
      showing.
- [ ] `"Reconstruction converged at 3.21 Å"` + findings card appear **only** at "All 23 steps
      complete," never earlier.
- [ ] Exiting the tour (Esc / Done) releases the freeze — a manual Run then animates normally.
- [ ] No console errors through a full playthrough.
