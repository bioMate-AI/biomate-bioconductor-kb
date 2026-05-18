# Integration Plan — research_agent_v2 → BioMate production

**Date:** 2026-05-18
**Sandbox:** `frontend/research_agent_v2/src/` (do not import yet)
**Production target:** `frontend/client/src/`
**Companion docs:** `docs/20260516_RESEARCH_AGENT_CHAT_UX_5_SURFACES_DESIGN_SPEC.md`
(the design spec) and `docs/20260515_RESEARCH_AGENT_CHAT_UX_ENGINEERING_AUDIT_AND_PLAN.md`
(the engineering audit).

---

## 0. Scope decisions (locked)

| Question | Decision |
|---|---|
| Bring over `ResearchTweaks.jsx`? | **No.** It's a Claude-Design dev tool for previewing the design, not a BioMate product feature. |
| Drop existing chat-progress 🔹 italic lines (commit `2bd9570cf`)? | **No.** They map directly onto the new `ChatStream` speaker-pill concept. Keep the SSE pipeline; add the speaker pill rendering. |
| Drop the existing `TaskList` component (LangGraph generation tasks)? | **No.** It is still important. Merge its concept with the new `PlanChecklist` so the user sees one unified plan, not two stacked task boxes. |
| Drop the existing workflow viewer (`nextflow-workflow-viewer.tsx`)? | **No.** Extend it with the new `PhaseCard` enhancements (auto-loop toggle, rationale pointer). The new `WorkflowPanel.jsx` in the sandbox is reference-level structure; the diff vs. our shipping viewer is mostly the QcBlock auto-loop toggle and a panel resizer. |
| Adopt `ResearchApp.jsx` wholesale? | **No.** It's structurally aligned with our existing `chat-with-artifacts.tsx` shell, but uses a tape-engine that we don't need (we have a real SSE event stream). Use ResearchApp as a **reference for the layout + state shape**, not as a drop-in replacement. |
| Adopt the sandbox `Tour.jsx` (1558 lines)? | **Selective.** The new demos (`rnaseq-chat`, `drugscreen-compare`, `variant-retry`, `cryosparc-main`, `outputs-findings-report`) are worth porting one by one; the engine wiring is sandbox-specific. |

---

## 1. Component-by-component mapping

Three categories: **KEEP** the existing BioMate file unchanged, **PORT** the
new sandbox file as a new component in production, **MERGE** (rewire the
existing file to subsume the new concept).

### NEW components (sandbox-only → port one at a time)

| Sandbox file | Production target | Action | Notes |
|---|---|---|---|
| `PlanChecklist.jsx` | `frontend/client/src/components/PlanChecklist.tsx` | **PORT + MERGE with existing `TaskList`** | Existing `TaskList` (LangGraph generation tasks) and the new `PlanChecklist` (decomposed sub-tasks with edit / parallel grouping / failure inline actions) are the same conceptual surface. Merge: have a single component that handles both lifecycle stages (intent → workflow generation tasks, then execution sub-tasks). Status state machine must cover both. |
| `ChatStream.jsx` | (extend `chat-message.tsx` + `chat-interface.tsx`) | **MERGE** | The sandbox `ChatStream` introduces speaker pills (`SPEAKERS` map: plan/wf/qc/loop/agent/find) and the `(why?)` rationale anchor. We already have the `🔹` italic line render (commit `2bd9570cf`) for `metadata.type === 'workflow_progress'`. Extend that render branch to also show a speaker pill before the italic message. Don't rewrite the message pipeline; just decorate. |
| `ChatCards.jsx` | `frontend/client/src/components/chat-cards/` (new dir) | **PORT** as 4 new components | `PilotPromptCard`, `PilotPromotionCard`, `ComparisonCard`, `FindingsChatCard`. None exist in production today. Each is a new `metadata.type` value in chat messages. |
| `ResearchApp.jsx` | (do not port the file) | **REFERENCE ONLY** | Use as the canonical layout/state-shape reference when adding the new surfaces to `chat-with-artifacts.tsx`. Do not import. The tape engine is replaced by our existing SSE stream. |
| `research-data.js` | (sandbox only) | **DELETE before any prod merge** | Static fixture data for the demo. Production reads from the real SSE event stream. Keep in the sandbox folder so the sandbox can render a demo locally. |
| `research-layout.css` | merge selectively into `frontend/client/src/styles/` | **MERGE** | Pull only the class blocks needed for surfaces being ported: `.plan-checklist`, `.chat-line` speaker-pill styles, `.compare-card`, `.compare-side-panel`, `.pilot-promotion`, `.findings-chat-card`, `.countdown-ring`. Skip global resets. |
| `research-tokens.css` | merge into existing `tokens.css` | **MERGE** | Add 6 speaker color tokens (`--bm-plan`, `--bm-wf`, `--bm-qc`, `--bm-loop`, `--bm-agent`, `--bm-find`) and 3 delta colors (`--delta-up`, `--delta-dn`, `--delta-neu`). Don't override existing tokens. |

### MODIFIED components in the sandbox (vs prior Claude-Design biomate)

For each modified file, decide whether the change in the sandbox is something
we want to adopt or skip:

| Sandbox file | Diff vs old design | Production action |
|---|---|---|
| `WorkflowPanel.jsx` (22 KB, +5 KB) | Adds `onResize` prop, auto-loop toggle wiring, ties to `AfterRunReport`. | **MERGE** into existing `nextflow-workflow-viewer.tsx`. We already have the live viewer; pull the auto-loop toggle on QC blocks and the panel resizer. Skip the `AfterRunReport` tab structure for now (separate workstream — see Surface 6 below). |
| `PhaseCard.jsx` (+0.8 KB) | Skip-step / skip-phase buttons commented out (pending dependency-graph alignment); adds auto-loop toggle on QcBlock with citation footer. | **MERGE** into existing phase card. Adopt the auto-loop toggle. Leave skip-step / skip-phase as-is (we already have them; don't disable). |
| `AutoLoop.jsx` (+0.2 KB) | Adds `autoloop` prop variant ("review proposed fix" vs "auto-loop attempting"). | **MERGE**. We have the existing auto-loop UI; this is a small refinement. |
| `Modals.jsx` (+288 lines) | Adds `AfterRunReport` (7-tab tabbed view: Findings, Outputs, Methods, Params, Software, Citations, QC audit). Replaces the old modal stack with inline tabs in the panel. Includes 21 CFR Part 11 chain-of-custody + e-signature blocks. | **PORT** the new `AfterRunReport` as a separate surface (Surface 6 below). Don't replace the existing modals yet. |
| `Chrome.jsx` (−7 lines) | Brand chip → logo-only `.brand-full`. Three new research-scenario chips in the sidebar "Chat" history. | **SKIP** — Chrome is a sandbox shell; our production sidebar already exists. |
| `Tour.jsx` (+225 lines) | Three new tours (`rnaseq-chat`, `drugscreen-compare`, `variant-retry`) + tour engine wiring. | **PORT SELECTIVELY** — the 5 use-case tutorials listed in `02_TUTORIAL_USE_CASE_COVERAGE.md`. Skip the engine hooks (`window.__tourFFTo`, etc.). |
| `layout.css` (+122 lines) | New CSS for `.after-run-report`, `.panel-resizer`, `.tweaks-reopen`, brand logo. | **MERGE** the `.after-run-report` and `.panel-resizer` blocks. Skip the rest. |
| `tokens.css` (unchanged) | Identical to old. | **SKIP** — already match. |
| `tour.css` (+2 lines) | Whitespace only. | **SKIP**. |

### NEW or NET-NEW Surfaces requiring NEW work in production

| Surface | Existing analog in prod? | What to build |
|---|---|---|
| **Surface 1 — Plan checklist (sticky)** | `TaskList` (LangGraph generation only) | Merge `PlanChecklist` semantics into `TaskList`. Single component now covers (a) generation-phase tasks (current behavior) AND (b) execution sub-tasks from `TaskDecomposer`. Plan-edit mode with 10s auto-lock. Parallel-group glyph. Failure inline actions. |
| **Surface 2 — Speaker pills on 🔹 lines** | Italic 🔹 chat-progress lines exist (commit `2bd9570cf`) | Add speaker pill render to `chat-message.tsx`. Backend narrator extends each event with a `speaker` field. Same-speaker collapse after 3 consecutive lines. |
| **Surface 3 — `(why?)` rationale tooltip** | None | Add a hover anchor on chat lines that carry a `rationaleId`. New endpoint `/api/research/rationale/{phase_id}` returns the rationale text + citation. |
| **Surface 4 — Run-vs-Run comparison card** | Nothing in chat. `compareExecutionRuns` API exists but `parameterDifferences` is missing. | Build `ComparisonCard` component. Fix the backend gap (WC-7). Two render variants: inline chat card OR side panel (pick inline as default per design spec). |
| **Surface 5 — Pilot toggle + promotion card** | `is_pilot` + `dataScope` schema present; `PilotExperimentPanel` written but never imported. | Port `PilotPromptCard` + `PilotPromotionCard`. Add chat-progress events: `workflow.pilot_started`, `workflow.pilot_completed`, `workflow.pilot_failed_qc`, `workflow.pilot_promoted`. Pilot promotion defaults to "Stop here" (not auto-proceed to full). |
| **Surface 6 — After-run report (NEW, was not in design spec)** | We have a `methods-report` download path. | **NEW** workstream. Adopt the 7-tab `AfterRunReport` pattern (Findings / Outputs / Methods / Parameters / Software / Citations / QC audit). 21 CFR Part 11 e-sig block is regulatory — coordinate with the CRO/IND track. |

---

## 2. What to KEEP from current BioMate

Explicitly preserve (don't let the port erase these):

1. **Chat-progress 🔹 italic lines** (commit `2bd9570cf`) — the entire
   backend narrator (`workflow_chat_narrator.py`), the SSE inject path,
   the React render branch for `metadata.type === 'workflow_progress'`,
   and the engineer-channel `[WORKFLOW]` logging. These map onto the
   new ChatStream concept by adding speaker pills, NOT by replacing.
2. **The TaskList task-management box** — keep the existing component;
   merge the `PlanChecklist` concept into it (one box, not two).
3. **Real cancel / pause / resume + 10s auto-proceed** (commit `3614b43dc`)
   — keep the backend endpoints + the frontend countdowns. The
   `Auto-Proceed Conventions` table in the design spec is already
   honored by this code.
4. **DeepAnalysisAgent** (commit `4ec1d56b8` + downstream) — keep the
   in-process Deep Agent and the `/api/autofix3/run` endpoint. The
   sandbox doesn't have a Deep Agent integration; that's our addition.
5. **Existing phase-step rerun**, **Skip step**, **Skip phase** — the
   sandbox `PhaseCard.jsx` comments these out pending dependency-graph
   work; we already have them. Keep them.
6. **Reference design alignment work** — the oklch tokens in
   `workflow-panel.css` we already match in the sandbox `tokens.css`.

---

## 3. Promotion order (one surface per merge)

Smallest-risk, highest-visibility first. Each PR gets a feature flag.

1. **Speaker pills (Surface 2)** — purely cosmetic; reuses existing
   chat-progress pipeline. Adds 6 tokens + 1 render branch. **Half day.**
2. **Plan checklist merge (Surface 1)** — replaces (well, evolves)
   `TaskList`. Status state machine extends. Backend exposes
   `TaskDecomposer` output via a new `/api/research/plan` endpoint.
   **2 days.**
3. **Pilot toggle + promotion (Surface 5)** — the `is_pilot` plumbing
   already works; the missing piece is the chat-side UI + 4 new
   narrator event kinds. **1 day.**
4. **Run-vs-Run comparison card (Surface 4)** — backend gap (WC-7 +
   `parameterDifferences` populate) + inline chat card. **1 day.**
5. **`(why?)` rationale tooltip (Surface 3)** — small UI but needs a
   new endpoint that produces rationale text per phase. **1 day.**
6. **After-run report tabs (Surface 6, new)** — separate work; large
   surface. **2-3 days.** Coordinate with CRO/IND track for the e-sig
   block.

Total: ~7-8 days. Each lands on its own dev-EC2 sync.

---

## 4. Backend contracts to write (none exist yet)

Per the design spec section "API Endpoints Needed":

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/research/plan` | POST | Decompose query into plan items (wraps `TaskDecomposer`) |
| `/api/research/plan/{plan_id}/events` | SSE | Plan-level status updates |
| `/api/research/rationale/{phase_id}` | GET | (why?) rationale text + citation |
| `/api/workflows/{inv}/phases/{name}/trace` | GET | Phase rationale + events + params + cost (heavy variant, deferred) |
| `/api/workflows/runs/{a}/compare?with={b}` | GET | **Fix** missing `parameterDifferences` field |
| `/api/research/cost_estimate` | POST | Pilot vs full cost preview (optional, can defer) |

---

## 5. Test plan per surface

Each surface's PR must include:

1. **Unit tests** — narrator templates for any new event kinds.
2. **Playwright render test** — seed a chat session via localStorage,
   verify the surface renders with the correct testid + data attributes.
3. **Real-case E2E** — for surfaces tied to a workflow event
   (Pilot, Comparison, Plan), trigger a real Nextflow run and verify
   the surface fires correctly via real SSE.
4. **Visual audit** — fullPage screenshot + video (where applicable),
   persisted under `docs/screenshots/`.
5. **Tutorial coverage** — the relevant tutorial scenario(s) from
   `02_TUTORIAL_USE_CASE_COVERAGE.md` must still pass.

---

## 6. Decision gates before merging

Before any surface lands in production:

- ✅ All 5 sandbox tutorial scenarios (cryo, output, drug screen,
  Bulk seq, variants) play correctly against the new surface
- ✅ Existing chat-progress 🔹 lines still render (no regression)
- ✅ Existing TaskList still works for LangGraph generation phase (it
  is now merged into PlanChecklist, but the LangGraph path must still
  succeed)
- ✅ Existing pause / resume / cancel controls work (no regression)
- ✅ TypeScript clean repo-wide (`tsc --noEmit` returns 0 errors)
- ✅ Playwright suite green for the new surface
- ✅ Dev EC2 smoke test verifies the surface against live data
- ✅ Audit doc written + committed

---

## 7. Open questions for this integration round

(Different from the design-spec open questions — those are for design
review; these are for implementation.)

1. **Plan persistence** — when the user reloads, should the plan
   re-fetch from the server, or restore from local cache? The current
   `TaskList` restores from localStorage; the new `PlanChecklist`
   expects server-driven. Recommend: server source of truth, local
   cache for offline read-only fallback.
2. **Speaker pill placement** — design spec recommends "after `🔹`,
   before the text". The sandbox `pillPlacement: 'after-marker'`
   default agrees. Lock this and don't expose as a user preference.
3. **TaskList → PlanChecklist migration path** — drop-in or
   side-by-side feature flag? Recommend: feature-flag the new component
   so the old `TaskList` is the fallback for one release; remove
   afterward.
4. **`(why?)` tooltip authoring** — who writes the rationale text?
   The design spec says "from `RESEARCH_PHASE_TRACE` knowledge base";
   we'd need a rationale-KB seed. Recommend: pull from the existing
   workflow descriptions in our workflow DB; supplement per phase
   via a CSV that maps `phase_id → rationale + citation`.
5. **After-run report** — adopt the 21 CFR Part 11 e-sig block on
   non-regulated workflows? Probably overkill for an RNA-seq run.
   Recommend: only render the e-sig section for workflows tagged
   `requires_signature: true` (CRO compliance).

---

## 8. Reference reading order

When this lands on a new engineer, read in this order:

1. `frontend/research_agent_v2/README.md` — what's in the sandbox + why
2. (this doc) `02_INTEGRATION_PLAN.md` — the component mapping + promotion order
3. `frontend/research_agent_v2/docs/02_TUTORIAL_USE_CASE_COVERAGE.md` — tutorial scenarios per surface
4. `frontend/research_agent_v2/docs/00_HANDOFF_FROM_CLAUDE_DESIGN.md` — original handoff
5. `docs/20260516_RESEARCH_AGENT_CHAT_UX_5_SURFACES_DESIGN_SPEC.md` — surface spec + Design Notes
6. `docs/20260515_RESEARCH_AGENT_CHAT_UX_ENGINEERING_AUDIT_AND_PLAN.md` — latent-capability inventory
7. `docs/20260517_SESSION_SUMMARY_CHAT_PROGRESS_AND_RESEARCH_AGENT_UX.md` — what's already shipped
