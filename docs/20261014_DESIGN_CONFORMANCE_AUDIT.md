# Design-Conformance Audit — implementation vs. `data_centroid_design_v2` specs

**Date:** 2026-10-14. **Scope:** interaction-pattern + layout/IA conformance (modal-vs-panel, slide-over-vs-popup, missing/extra affordances) — NOT visual style. **Source of truth:** `reference/claude_design/data_centroid_design_v2/spec/00–14 *.html` + `dataui/*.jsx`.

## Why the prior audit missed this class
The earlier "screenshot committee" audit scored **static captured images** for content quality (right values, no clipping, no fixture pollution). A static crop **cannot reveal an interaction/presentation pattern**: a screenshot of the full step view looks identical whether it's a centered modal or a side panel — the modal-ness (overlay, dismissal, that it floats over the app instead of being a panel/pane) is invisible in a still. So an entire class — *how a surface is presented vs. what the spec says it should be* (pane/page/inline/drawer vs. modal) — was **never checked**. This audit checks it by reading the design's React (`dataui/*.jsx`) against the implementation components.

## Counts
- **Deviations found: 4** — **2 high** (modal where spec wants a pane), **1 medium**, **1 low**.
- By category: interaction-pattern **3**, layout/IA **1**, visual-style **0** (out of scope).
- **1 of the 2 high already fixed this session** (full step view).
- **Systemic observation (not a single row):** the design uses **panes/panels/inline/rails almost exclusively** — across ALL of `dataui/*.jsx` there are only **2 "modal/dialog" mentions, both narrative** (a toast string; the word "modality"). The implementation renders **~30 surfaces as `<Dialog>` modals**. Most are legitimately modal (settings, create-project, credentials, QC-gate, e-signature, confirmations, the attach/browse picker). The deviations are the **detail/object views** the spec intends as panes but the impl made modals.

## Deviations

| # | Spec | Surface | Intended (spec) | Actual (code) | Category | Severity | Fix |
|---|---|---|---|---|---|---|---|
| 1 | **08 The full step view** | Full step view (`StepDetail`) | Pane / drawer (`StepDeep.jsx` = inline panel + drawer; no modal) | Was a centered `max-w-3xl` modal `Dialog` (`nextflow-workflow-viewer.tsx:3753`) | interaction-pattern | **HIGH** | ✅ **FIXED** `6bb43c7ad` — now a full-height side panel (anchored right) |
| 2 | **12 Reports as editable files** / **09 Reports** | Comprehensive report viewer (`workflow-report-viewer.tsx`) | An **editable file / pane** (`DocEditor.jsx`; spec 12 "reports as editable files") | Centered `max-w-4xl max-h-[85vh]` modal `Dialog` (`workflow-report-viewer.tsx:123`) | interaction-pattern | **HIGH** | Convert to a pane/editable-file surface (same pattern as the full-step-view fix), or route report-view into the after-run Results pane rather than a popup |
| 3 | **07 workflow panel** | Overall progress bar vs. the design's run header | RunSurface header pattern (panels/rails) | (minor) progress + status chrome differs in placement; not a modal issue | layout/IA | MED | Lower priority; align the panel header to RunSurface once #1–2 land |
| 4 | **14 Panes & output previews** | Output preview overlay | Inline panes (`Viewers.jsx`) | AfterRunReport outputs are inline (OK); verify no step-output overlay opens as a modal elsewhere | interaction-pattern | LOW | Spot-check `step-output-preview.tsx` open-in-overlay path |

## Confirmed NON-deviations (checked, design-conformant)
- **Connectors** (spec 11/12): the primary nav ("Connectors", `app-sidebar.tsx:398`) opens **`/settings/connections` — a page**, matching `Connectors.jsx` (`mainpane`). The `ConnectorsDialog` modal is a secondary/legacy path, not the primary surface.
- **Dataset object** (spec 04): shown as a **pane in `/files`** (the data-hub two-pane), matching `DataHub.jsx` — not a modal.
- **After-run Results** (spec 09): the merged Results view (`AfterRunReport.tsx`) is a **pane**, conformant.
- **Cold start / composer** (spec 00/06): inline, conformant.

## Coverage honesty
This is a **focused first pass on the modal-vs-pane / interaction-pattern class** (the one the screenshot audit missed), spot-checked across the 15 specs via `dataui/*.jsx` + the key implementation components. It is **not an exhaustive element-by-element pass** of every spec's affordances; a full pass (every button/field/IA detail per spec) remains open and would likely surface more low/medium layout items. The high-severity structural deviations (modal-where-pane) are the ones that matter most and are enumerated above.

---

## Full element-by-element pass (2026-10-14)

Extended the audit beyond the modal-vs-pane class to element presence / affordances / IA / states, spec-by-spec against the implementation.

### Result: NO new structural deviations — total stays **4**.
The first pass had already caught the real structural (interaction-pattern) deviations. The element-level pass finds the implementation **largely conformant on element presence**, and **rules out** two suspected modals as non-deviations.

### Per-spec verification
| Spec | Impl component | Verdict |
|---|---|---|
| 00 Foundations / cold start | cold-start page, composer | Conformant — thin launcher + two-lane (Instant/Cloud) concept + goal-seed present (lane *rendering* polish is live-ref-only, not pixel-verified) |
| 01 Search & evidence | search/answer components | Conformant — source reader + inline anchors + empty/failure states present (spot-checked) |
| 02 Data analysis | ChatView/composer | Conformant (inline) |
| 03 Models | /models | Model object opens as a pane/page, not a modal — conformant |
| 04 Files / dataset object | `/files` DataHub | Conformant — dataset object is a **pane** with Preview / Lineage / Versions / Quality tabs + "Open in"; `dataset-dialog.tsx` is a dataset **selector** (`onDatasetsSelected`), not the object view, and has no active usages |
| 05 / 11 Design & generate | design-generate/* | Conformant (pane) |
| 06 Composer | chat composer | Conformant (inline) |
| 07 Workflow panel | `nextflow-workflow-viewer.tsx` | Conformant anatomy (domain kicker · name · project; section tabs Workflow-settings/Phases/After-run; footer blocker + primary action); **#3 (MED)** header/progress *placement* vs RunSurface stands |
| 08 Full step view | `step-detail.tsx` | **#1 (HIGH) — FIXED** (now a pane) |
| 09/10 Worked examples | search/model-case | Conformant (inline/pane) |
| 12 Reports as editable files | `workflow-report-viewer.tsx` | **#2 (HIGH) — OPEN** (modal; should be an editable file/pane) |
| 13 Run cards by domain | dashboard/run cards | Conformant (cards; panel-is-a-sandbox/preview-consistency honored) |
| 14 Panes & output previews | `chat-with-artifacts.tsx`, `step-output-preview.tsx` | Conformant — 380px chat clamp present (`maxPanelWidth = max(320, min(860, splitWidth-380))`), panel open-state persists/restores; collapse-to-rail behavior is live-ref-only, not pixel-verified; **#4 (LOW)** output-overlay spot-check stands |

### Ruled out as non-deviations (suspected modals that are legitimate/legacy)
- `dataset-dialog.tsx` — dataset selector, not the object view; no active usages.
- `parameter-preview-dialog.tsx` — no active usages (legacy).
- The ~30 other `<Dialog>` surfaces are legitimately modal (settings, create-project, credentials, QC-gate, e-signature, confirmations, attach/browse picker, interactive-tool launcher).

### Coverage honesty (unchanged intent)
This pass verified **element presence + the detail-view-modal class** across all 15 specs via `dataui/*.jsx` + the implementation components. It did **not** pixel-compare every label's exact copy or every state's rendering against the live reference (`:7779`) — a few behaviors (cold-start lane rendering, panel collapse-to-rail) are marked **live-ref-only, not pixel-verified** and could surface minor low-severity copy/spacing items on a dedicated visual pass. **No new high/medium structural deviations were found** — the actionable list remains: fix **#2 Report viewer → editable pane** (HIGH), then **#3** (MED) and **#4** (LOW).
