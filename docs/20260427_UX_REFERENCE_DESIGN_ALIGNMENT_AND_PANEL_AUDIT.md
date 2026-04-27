# UX Reference Design Alignment + Workflow Panel Audit
**Date:** 2026-04-27  
**Branch:** integration/next-phase

---

## Overview

Full session dedicated to (1) aligning BioMate's UI to the Claude reference design at `localhost:7779`, (2) auditing every interactive element in the workflow panel for correctness, and (3) fixing all identified gaps.

---

## 1. TypeScript Fix — chat-message.tsx

**Problem:** TS1005 `')' expected` at line 666. Root cause: the previous session replaced `<Card>` with `<div>` but left behind an extra `</div>` (the old `flex-1 space-y-2` wrapper close tag).

**Fix:** Removed the orphan `</div>`. Also fixed `message.createdAt` → `message.timestamp` (correct field name from the Message type).

---

## 2. Reference Design CSS Alignment

### Global Tokens (`reference-design.css`)
- Added `.wf-chip` CSS — the compact workflow card shown in chat when workflow is open in panel
- Added `.disambig-card` CSS — disambiguation card when multiple workflows match
- Added `.bm-alert` CSS — alert banners (warn/err/info)
- All ported verbatim from reference `layout.css`

### Sidebar (`app-sidebar.tsx`)
Completely restructured JSX to match `Chrome.jsx` from reference design:

| Before | After |
|--------|-------|
| "bioMate AI / Bioinformatics Assistant" + document icon | "B" brand mark + "biomate / workflow console" |
| PROJECTS, RECENT CHATS, TOOL CATEGORIES, QUICK ACTIONS sections | WORKSPACE nav (New Chat, Workflows, Runs, CRO Library) + CURRENT chat history with colored status dots + ACTIONS |
| Card-based footer with Avatar component | Compact footer: initials circle + name + email |

Key behaviors kept: chat history dot colors (blue=running, red=failed, green=completed), all `data-testid` attributes preserved.

### Chat Messages (`chat-message.tsx`)
- Added **wf-chip** component shown when `isWorkflowMessage && isInPanel`: displays workflow name, subtitle/domain, "● In panel" green badge — exact match to reference design's `ChatColumn` component
- Added `ExternalLink` import for future use

---

## 3. Workflow Panel — All 15 Reference Tweak Scenarios

Audited all scenarios from the reference design's "Tweaks" panel. Fixed the 3 gaps found:

### Gap 1: Blocked execution alert
**Before:** Single "Confirm and Run Anyway" button  
**After:** Red error alert with `<strong>Execution blocked</strong>` + **"Fix now"** (opens Workflow Settings strip via `setGlobalParamsOpen`) + **"Confirm anyway"** buttons — matches reference exactly

### Gap 2: Footer button per-state
**Before:** Always showed "Confirm and Run Workflow"  
**After:**
- `idle` → "Confirm and run workflow"
- `running` → spinner + "Running…"
- `failed` → "Restart"
- `completed` → "Run again"

### Gap 3: Phase-level "Stop phase"
**Before:** Only workflow-level cancel existed (header icon)  
**After:** "Stop phase" button appears in `phase-actions` when `anyRunning && onStopPhase` — wired to `onCancel` via new `onStopPhase` prop on `PhaseGroupSection`

### Additional fixes in same pass:
- **Watcher bar text** updated to match reference exactly: "Watcher attached · live SSE" / "Watcher detached · job on AWS Batch" / "Detach watcher" / "Reconnect watcher"

---

## 4. Workflow Panel — Deep Element Audit

Full audit of all 23 interactive elements. Findings:

### Placeholder fixed
- **"View phase outputs"** (line 640): Was a button with no `onClick`. Now expands the phase and scrolls to its `step-outputs` div via `querySelector('[data-testid="phase-group-{key}"] .step-outputs')`.

### Commented out (no backend)
- **Skip phase button** — UI-only, marks phase done locally but no Nextflow API to actually skip a running AWS Batch job. Commented out with note: "hidden until backend skip endpoint added"
- **Skip step button** — same reason
- **Skip confirmation dialog** — same

### Commented out (purpose unclear)
- **Watcher attach/detach** — "Detach watcher" / "Reconnect watcher" buttons + watcher status bar. The concept (SSE stream pausing) is not exposed meaningfully to users. Commented out pending product definition.
- **"Batch job continues running after detach."** text — orphaned note from the watcher removal, deleted.

---

## 5. QC Gate + Parameter Editor Connections

### QC gate "edit" button
**Before:** Called `setGlobalParamsOpen(true)` (wrong — opened workflow params strip, not QC thresholds)  
**After:** Calls `setQcSettingsOpen(true)` + scrolls to `[data-qc-key="{paramId}"]` in the QC threshold editor. Added `data-qc-key` attribute to each threshold row.

The QC threshold editor (already fully built at lines ~2011–2060) provides:
- Per-metric number inputs with direction label (`≥` or `≤`) + unit
- Blue accent border + blue background when modified
- × reset button when modified
- Rationale text per metric
- "Reset all" button when any overrides exist

### Auto-loop panel — gate value colors
**Before:** All gate values rendered in gray (`text-gray-600`) regardless of pass/fail  
**After:**
- `action === "halt"` → `text-red-600` (bold) — failing gate
- `action === "advisory"` → `text-amber-600` (bold) — warning
- `action === "pass"` → `text-green-600` (bold) — passing gate

### Auto-loop panel — remediation was→now
**Before:** Showed only new parameter value as `key → new_value` chips  
**After:** Shows `key | old_value (red strikethrough) → new_value (green)` using current `params` passed as `currentParams` prop down through `PhaseGroupSection` → `AutoLoopPanel` → `RemediationCard`

### ParameterGroup (already working)
Confirmed `ParameterGroup` correctly renders all types:
- `boolean` → Switch
- `select` → dropdown with options
- `file` ending in `_csv/_tsv/_fasta` → Textarea (multiline)
- `file` ending in `_path/_dir/_file` → Input + Browse button
- `number` → Input with `Range: min–max` hint when min/max set
- secret params → password Input
- default → text Input with optional KnowledgeBadge for AI-recommended values

Grouped by schema `group` field, required params shown first with `*` marker.

---

## 6. API Endpoints Verified

All endpoints referenced by workflow panel buttons exist in `routes.ts`:

| Button | Endpoint |
|--------|----------|
| Step "view" | `GET /api/workflows/runs/:id/step-file` |
| Step "dl" | `GET /api/workflows/runs/:id/step-file?download=1` |
| Adjust & rerun | `POST /api/workflows/runs/:id/rerun` |
| Step param adjust | `POST /api/workflows/runs/:id/rerun-from-step` |
| Download all | `GET /api/invocations/:id/download-all` |
| Methods report | `GET /api/invocations/:id/methods-report` |
| AI analysis | `POST /api/workflows/runs/:id/ai/analyze` |
| QC audit log | `GET /api/invocations/:id/qc-audit-download` |

---

## 7. Test Results

All smoke tests pass after changes:
- Billing smoke: 4/4 ✅
- Auth flows: 2/3 (1 skip) ✅
- Chat history: 3/4 (1 skip) ✅
- Full workflow E2E: 8/8 ✅

Visual verification via Playwright screenshots confirmed:
- Sidebar matches reference design (B brand mark, workspace nav, chat history dots)
- wf-chip appears in chat when workflow is in panel
- Workflow panel running state renders correctly with real AWS Batch data
- Step outputs "view dl" links render for completed steps
- QC gates block shows with "edit" link + auto-loop toggle
- Workflow settings strip expands with ParameterGroup (typed params)
- QC Settings strip expands with numeric threshold editor

---

## 8. Known Open Issues

1. **Skip phase/step** — No backend API. When needed, implement `POST /api/workflows/runs/:id/skip-phase` in `nextflow_executor.py` and re-enable.

2. **Watcher detach** — No clear product definition. The SSE stream pausing (`pauseRun`/`resumeRun`) exists in `chat-with-artifacts.tsx` but the UX purpose is unclear.

3. **QC gate "edit" inline editor** — Currently scrolls to the QC Settings threshold editor. A true inline editor (edit threshold directly in the gate row) would be better UX but requires a separate inline editing widget.

4. **Auto-loop toggle persistence** — The per-phase auto-loop toggle is UI state only; resets on page reload. This is acceptable — backend runs QC logic independently, toggle just controls whether the remediation card shows.

5. **ADMET workflow QC gates display** — The SMILES input parameter appears in the QC gates block because `groupRenderedParams` includes all phase params. This is a data classification issue; ADMET's Nextflow `.nf` file should tag QC-specific params separately.

---

## 9. Files Changed

- `frontend/client/src/components/app-sidebar.tsx` — full sidebar redesign
- `frontend/client/src/components/chat-message.tsx` — wf-chip + TS fix
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — panel audit fixes
- `frontend/client/src/components/auto-loop-panel.tsx` — gate colors + was→now params
- `frontend/client/src/styles/reference-design.css` — wf-chip/disambig/alert CSS
- `frontend/client/src/styles/workflow-panel.css` — `.alert .body strong` + `.act` alignment
