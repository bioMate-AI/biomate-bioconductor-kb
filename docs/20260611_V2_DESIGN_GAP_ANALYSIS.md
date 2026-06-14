# v2 ↔ design gap analysis — 2026-06-11

Audit of the v2 BioMate UI / information flow against the Bioconductor
handoff design (`reference/claude_design/bioconductor-handoff/`).

## Snapshot

| Bucket | Ported | Backend gap | Architectural gap |
|---|---|---|---|
| Workflow panel (3 tabs, phase cards, hide-when-empty) | ✅ | — | — |
| After-run report (7 tabs) | ✅ structure | Some tabs await backend data | — |
| Chat surface | Speaker pill only | — | Missing section signposts / progress folds / reasoning blocks / (why?) anchors |
| Disambig card | ✅ component (v1) + v2 strict-TS port ready | — | **Not wired into chat-message.tsx — dead code** |
| Findings figures | ✅ FigBars / FigComposition / FigQc | Backend doesn't emit `figures[]` | — |
| QC audit | ✅ 4-stat + audit log + chain-of-custody + e-sig | Backend doesn't ship e-signature | — |
| Information flow | SSE per-component | — | No `__wfPin` equivalent — chat + panel don't share scenario state |
| Bioc curated chains | ✅ 3 chains in DB | `workflow_chains.citations` empty for all 3 | — |

---

## §1 — Information flow (handoff §1)

**Design**: one tape → engine (`window.__wfPin`) → chat + panel + report. Three surfaces in lockstep.

**Production**: two independent SSE subscriptions (chat-with-artifacts, nextflow-workflow-viewer). They share `invocationId` but not the narrative arc.

**Gap**:
- No "pipeline committed" signal — production panel reveals phases immediately when a workflow card lands; design holds at `.wf-unselected` until disambig resolves.
- No `section { n, total, title }` events for the 4-act arc (Understanding → Choosing → Running → Found).
- No engine-driven panel coupling.

**Fix scope**: backend SSE schema add (`section`, `pipeline_committed`, structured `phaseUpdate`). Frontend coordinator hook subscribing once and forking to chat + panel via context.

---

## §3 — Chat surface

### §3.1 Speaker pills

- Design: 6 fixed roles (PLAN/WF/QC/LOOP/AGENT/FIND), colour contract enforced.
- Production: `chat-message.tsx:238` renders `speaker-pill` with `data-speaker`, but backend can emit any string. No taxonomy.

### §3.2 Section signposts

- ❌ Not emitted by backend; chat is a flat log.

### §3.3 Progress folds vs reasoning blocks

- ❌ Every chat line renders inline. Design folds `wf/qc/plan/loop` consecutive lines into a `WF — 5 updates` caret; `agent/find` lines never fold.

### §3.4 `(why?)` anchor backed by `RESEARCH_PHASE_TRACE`

- ❌ No `RESEARCH_PHASE_TRACE` table or endpoint. v1 has `WorkflowRationale` as a separate one-off, not the hover pattern.
- **Biggest piece**: needs a backend `workflow_phase_rationale` DB table, an endpoint, a frontend `<WhyAnchor>` component, and curated content for all chains.

### §3.5 Disambig card

- ✅ Component: v1 `WorkflowDisambiguationCard` + v2 strict-TS port (`v2/DisambigCard.tsx`).
- ✅ Backend: emits `workflow_type:'disambiguation'`.
- ❌ **chat-message.tsx does not render it.** Dead code. Highest-ROI single fix.

### §3.5 Findings chat card

- ✅ `components/findings-card.tsx` is functionally the design's `FindingsChatCard`.

---

## §4 — Workflow panel

### §4.1 Layout

- ✅ Three section tabs (Workflow settings / Phases / After run) integrated in commit `924138d00a`.
- ✅ Status-aware default tab; action bar with run/pause/resume/stop/run-again.

### §4.2 Engine-driven coupling

- ❌ Production uses raw SSE, no `__wfPin`. Pre-disambig empty state isn't enforced.

---

## §5 — After-run report

| Tab | Component state | Data state |
|---|---|---|
| Findings | ✅ FindingsCard + FindingsFiguresPanel (FigBars/FigComp/FigQc) ported in commits `06b7165ca` + `2decdaa00` (A1 hoist of manifest-contract note) | ❌ Backend doesn't yet emit `figures[]` |
| Outputs | ✅ Per-file rows + view/download + Download all (JobButton kind `download_all_zip`) | ✅ |
| Methods | ✅ IMRaD prose | ❌ Backend doesn't differentiate manifest-vs-inferred values — design wants italic on inferred |
| Parameters | ✅ Phase/step/parameter/value rows | ❌ Missing `default/edited/user/autoloop` tag column |
| Software | ✅ component, hide-when-empty | ❌ Backend stub returns `{}` |
| Citations | ✅ wired to `/api/workflows/:name/citations` | ❌ Bioc chains have empty citations in DB |
| QC audit | ✅ 4-stat + audit log + chain-of-custody + hide-when-empty e-signature | Backend contract documented in `docs/20260611_QC_EVENTS_MEASURED_FIELD_CONTRACT.md`. E-signature record not yet emitted. |

---

## §6 — Backend endpoints inventory

| Endpoint | v2 consumer | State |
|---|---|---|
| `GET /api/invocations/:id/qc-events` | `useFetchQcEvents` | ✅ 200, single-token measured per A2 contract |
| `POST /api/jobs` (`kind:findings_analysis`) → `GET /api/jobs/:id/artifact` | `useFetchFindings` | ✅ 200; missing `figures[]` |
| `GET /api/invocations/:id/methods-report` | `useFetchMethods` | ✅; needs `source` tagging extension |
| `GET /api/invocations/:id/software` | `useFetchSoftware` | ❌ stub `{}` |
| `GET /api/workflows/:name/citations` | `useFetchCitations` | ✅ 200; empty for bioc chains until DB populated |

---

## Production cutover priority

| # | Fix | Effort | Visible impact |
|---|---|---|---|
| 1 | **Wire `DisambigCard` into chat-message.tsx** | 10 lines | bioc_kb tutorial centerpiece works |
| 2 | **Populate `workflow_chains.citations` rows for 3 bioc chains** | 12 SQL inserts | Citations tab non-empty |
| 3 | **Backend SSE `section` events at known markers** | 1-2 backend days | 4-act narrative arc in chat |
| 4 | **Backend `findings_analysis.figures[]`** | 1 backend day | FigBars/FigComp/FigQc actually render |
| 5 | **Frontend progress-fold + reasoning-block render in chat-message.tsx** | 2-3 days | Long runs read as narrative |
| 6 | **Methods + Parameters source-tagging** | 1 backend day | Italics + tag column |
| 7 | **Software endpoint + `pipeline_info/software_versions.yml` ingest** | 2 days | Software tab renders |
| 8 | **`workflow_phase_rationale` table + `(why?)` UI + curated content** | 1 week | "Every Why is citable" contract |
| 9 | **Engine refactor — `__wfPin` equivalent** | 1-2 weeks | Pipeline-committed gate + chat/panel lock-step |

Items 1-2 ship this week. 3-4 define a sprint. 5-7 the next. 8-9 are quarter-scope.

---

## What's already on `bioc/v2-qc-audit-panel`

| Commit | Surface |
|---|---|
| `924138d00a` | Workflow panel tabs (settings / phases / after run) |
| `8050e6c3d` | Rich QcAuditTab |
| `06b7165ca` | FindingsFiguresPanel (FigBars/Comp/Qc) |
| `5224fcafd` | v2 DisambigCard (strict-TS) |
| `2decdaa00` | A1 hoist of manifest-contract note + A2 harness cleanup |
| `712492acd` | Run-button hard gate on requiredUnfilled |
| `c8fb39b42` | bioc voiceover TTS pipeline integration |
| `<HEAD>` | v2 visual-audit harness + 1440p screen recorder upgrade + ~3-min narrative rewrite |

None of the above is on `integration/next-phase` yet — per the "don't merge until tested" rule.
