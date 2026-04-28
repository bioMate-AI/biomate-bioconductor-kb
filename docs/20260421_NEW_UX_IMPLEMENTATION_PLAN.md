# New UX Implementation Plan
*2026-04-21 — Reference design port: remaining work*

## What was done before this session

- `workflow-panel.css` created with all reference design tokens and component classes
- `panel-head` (sticky title + status chip + progress bar) implemented
- `panel-body` (scrollable body) implemented  
- `panel-foot` (sticky run button + watcher bar) implemented
- `PhaseGroupSection` ported to `.phase / .step / .chip / .btn` reference CSS
- Settings strip ported to `.strip / .strip-body`
- `WorkflowTour` component added (`workflow-tour.tsx`) — 9-step spotlight tour
- Tutorial button added to panel header

---

## P0 — Layout breaks (must fix first)

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| P0-1 | **Double header** — outer "Workflow Panel" bar + `panel-head` both visible | `chat-with-artifacts.tsx:1193–1205` | Collapse outer bar to a slim row (Tutorial + Close only); `panel-head` owns the title |
| P0-2 | **`min-height: 0` missing** — `panel-body` won't scroll in Firefox/Safari | `workflow-panel.css` | Add `min-height: 0` to `.wf-panel` and `.wf-panel .panel-body` |
| P0-3 | **`.strip` not full width** — settings toggle doesn't fill panel | `workflow-panel.css` | Add `width: 100%; text-align: left` to `.wf-panel .strip` |

---

## P1-A — Cut (remove entirely, no replacement needed)

| # | Section | testid | E2E impact |
|---|---------|--------|-----------|
| C1 | **Input analysis panel** — AI sanity-check; auto-filled params + AI chat handle this | `input-analysis-section`, `button-analyze-inputs` | No E2E assertion; safe to cut |
| C2 | **Session dataset panel** (inside settings strip) — files already accessible via param row "Browse" button | `session-dataset-panel` | `pilot-study-e2e.e2e.ts:405` — update to not assert this panel |
| C3 | **Validate environment button** — developer debug aid, 2+ min runtime | `button-validate-environment` | No E2E assertion; safe to cut |
| C4 | **Live process list** — duplicate of phase cards; shows raw internal names | `nf-process-list` | `cryoem-stepwise-and-output.e2e.ts` CS-3 — update assertion |
| C5 | **Autofix status panel** (state/attempts/source debug info) | `autofix-status-panel` | No E2E assertion; keep banner (`autofix-active-banner`) |
| C6 | **Reproducibility export button** — developer feature, 0 pilot users asked | — | No E2E assertion; safe to cut |
| C7 | **Runtime artifacts debug box** (blue S3 paths) | `nextflow-runtime-artifacts` | No E2E assertion; safe to cut |

---

## P1-B — Port (Tailwind → reference CSS)

| # | Section | Reference CSS | Notes |
|---|---------|--------------|-------|
| R1 | **Error recovery card** | `.alert.err` + `.act` buttons | Keep `button-error-fix-chat` testid |
| R2 | **Prereq checklist** | `.alert.err` + `.act` + `.linkish` | Keep `workflow-prereq-checklist` testid |
| R3 | **Post-run links row** | `.results-links` + `.linkish` | Keep all button testids |
| R4 | **Metrics strip** | `.metrics-strip` + `.cell .lbl/.val` | Keep `run-metrics-strip` testid |
| R5 | **Logs panel** | `.strip` (collapsible) + `pre.log-pre` | Collapsed by default; auto-expand on failure |
| R6 | **QC settings section** | `.strip/.strip-body` + `.param-row` + `.switch` | Collapse by default |
| R7 | **Autofix active banner** | `.alert.info` | Keep `autofix-active-banner` testid |
| R8 | **Download commands panel** | `.output-file` links | Keep `download-commands-panel` testid |
| R9 | **AI analysis panel** | `.findings-card` + `.f-h/.f-body/.f-table` | Keep `ai-analysis-panel` testid |
| R10 | **Completion banner** | already `.alert.ok` ✓ | Done |

---

## P2 — E2E test updates

| File | Line | Selector | Action |
|------|------|----------|--------|
| `pilot-study-e2e.e2e.ts` | 405–406 | `session-dataset-panel` | Remove assertion (panel cut) |
| `cryoem-stepwise-and-output.e2e.ts` | CS-3 block | `nf-process-list` | Remove/soften — redirect to phase card `data-status` |
| Any file | — | `run-metrics-strip` | Preserve testid on new `.metrics-strip` element |
| Any file | — | `download-commands-panel` | Preserve testid on new `.output-file` container |

---

## Reference CSS classes needed (not yet in workflow-panel.css)

```css
.wf-panel .results-links          /* post-run link row */
.wf-panel .metrics-strip          /* run metrics */
.wf-panel .metrics-strip .cell
.wf-panel .metrics-strip .lbl
.wf-panel .metrics-strip .val
.wf-panel .log-pre                /* monospace log block */
.wf-panel .output-file            /* download link row */
.wf-panel .findings-card          /* AI analysis card */
.wf-panel .f-h                    /* findings heading */
.wf-panel .f-body
.wf-panel .f-table
.wf-panel .f-row
.wf-panel .f-cite
```

---

## Implementation order

1. P0 fixes (CSS + double header)
2. P1-A cuts (remove 7 sections from TSX + state)
3. P1-B ports (Tailwind → reference CSS for 9 sections, add missing CSS classes)
4. P2 E2E updates
5. TypeScript check + Vite build
6. Visual review

---

## Net result

Removing 7 sections + porting 9 sections reduces the panel by ~22% of current content with zero loss of scientist-facing value.
