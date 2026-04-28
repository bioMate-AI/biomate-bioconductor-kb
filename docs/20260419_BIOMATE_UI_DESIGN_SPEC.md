# BioMate Platform — UI/UX Design Specification
**Date:** 2026-04-19  
**Purpose:** Design brief for the workflow execution interface  
**Audience:** Design team  
**Status:** Ready for redesign review

---

## 1. Product Overview

BioMate is an AI-powered bioinformatics assistant that:
- Accepts natural-language queries ("Run ADMET prediction for aspirin", "Call variants on SRR123456 with GATK4")
- Routes the query to the correct scientific workflow (400+ Nextflow pipelines)
- Pre-fills workflow parameters from the query using AI
- Executes on AWS Batch or locally via Nextflow
- Streams real-time execution status via SSE (Server-Sent Events)
- Produces structured scientific outputs (VCF files, CSV tables, QC reports, 3D maps)

**Primary users:** Biologists, bioinformaticians, drug discovery scientists, cryo-EM operators  
**Scale of workflows:** 1–25 sequential steps (processes) grouped into 2–6 logical phases  

---

## 2. Current Page Layout

### 2.1 Overall 3-Column Layout

```
┌──────────────┬─────────────────────────────┬─────────────────────┐
│  Left sidebar│  Center: Chat               │  Right: Workflow    │
│  (200px)     │  (fluid, ~60% of remaining) │  Panel (420px)      │
│              │                             │                     │
│  Navigation: │  AI conversation thread     │  Workflow viewer    │
│  - Projects  │  with markdown rendering    │  (opens auto when   │
│  - Chats     │                             │  AI returns a       │
│  - Tools     │  Chat input at bottom       │  workflow)          │
│  - Quick     │                             │                     │
│    Actions   │                             │                     │
└──────────────┴─────────────────────────────┴─────────────────────┘
```

The right panel **auto-opens** when the AI generates a workflow response. It can be dismissed and reopened from the chat message. Width is currently hardcoded at `420px`.

### 2.2 Chat Area — Message Types

1. **User message** — right-aligned bubble, teal background
2. **AI assistant message** — left-aligned, markdown text
   - Currently includes a verbose pre-execution summary block (being simplified)
   - Contains inline workflow artifact card (open-in-panel button)
3. **Workflow artifact card** — compact card below the AI message text with workflow name, status badge, "Open in panel" button
4. **Typing/streaming indicator** — animated dots while AI responds

### 2.3 Right Panel — Workflow Viewer (Current State)

The panel header shows: `Workflow Panel | [WorkflowName] [status badge] [×]`

**Current panel scroll order (top → bottom):**

```
1. Parameters section (collapsible, OPEN by default)
   └─ Parameter group(s) with Input/Select fields
   └─ Input Data Analysis (collapsible sub-section)

2. Run controls
   ├─ LicenseGate (if needed)
   ├─ Validate Environment button
   ├─ [Confirm and Run Workflow] — primary CTA
   ├─ [Pause/Detach] [Resume/Reconnect] row
   ├─ [Restart] [Cancel] row
   └─ Usage meter

3. QC Settings section (collapsible, ALWAYS shown even when not applicable)
   ├─ Pause-at-QC-fail toggle
   ├─ Quality threshold sliders
   └─ QC profile selector

4. Autofix status panel (shown if autofix active)
5. Prereq checklist (shown if execution blocked)
6. Blocked reason alert + "Confirm Anyway" button

7. Results action buttons (full-width, stacked)
   ├─ [View Results] toggle
   ├─ [Analyze Results] (AI analysis)
   ├─ [Download All]
   ├─ [Download QC Audit Log] (if QC active)
   └─ [Download Methods Report]

8. Run metrics strip (wall time, started, ended, per-step costs)

9. Live Nextflow process list (if trace data available)

10. Capability hint (small text)
    "You can edit parameters · adjust QC thresholds · skip steps · preview outputs"

11. Step-controls hint (small text)
    "Run single steps for targeted checks..."

12. Phase-grouped step cards (PhaseGroupSection → PhaseCard per step)
    └─ [+ Suggest step] button at bottom

13. Preview modal (StepOutputPreview)
14. Adjust modal (StepAdjustModal)
15. Logs panel (monospace, 12rem height)
16. Report confusion button

17. Auto-loop panel (if autoloop SSE events received)
18. AI Analysis Panel (if analysis run)
19. Output Results section (if showResults=true)
    ├─ Runtime artifacts list
    ├─ ChatOutputAttachments (file cards)
    └─ FindingsCard (AI findings with citations)
```

---

## 3. Component Inventory

### Core Components (all in `frontend/client/src/components/`)

| File | Lines | Purpose |
|------|-------|---------|
| `chat-with-artifacts.tsx` | 1403 | Main page layout; manages panel open/close state, session, run state |
| `nextflow-workflow-viewer.tsx` | 2761 | Entire right panel content — parameters, run controls, step cards, outputs |
| `phase-card.tsx` | 385 | Individual step card — status, run/skip controls, param overrides, output files |
| `chat-interface.tsx` | ~1750 | Chat thread rendering, message list, typing indicator, queue |
| `chat-input.tsx` | ~200 | Chat textarea with file attachment popover |
| `auto-loop-panel.tsx` | 361 | QC gate results table + remediation cards (drug discovery & cryo-EM) |
| `findings-card.tsx` | ~200 | AI-generated findings with citations (shown after run completes) |
| `parameter-group.tsx` | — | Collapsible group of parameter fields (Input, Select, Switch) |
| `step-output-preview.tsx` | — | Modal preview for step output files (image, CSV, JSON, FASTA) |
| `step-adjust-modal.tsx` | — | Modal to edit step parameters and rerun from that step |
| `license-gate.tsx` | — | Credential check (e.g., AlphaFold database path) |

### Server-side
| File | Lines | Purpose |
|------|-------|---------|
| `server/galaxy-assistant.ts` | ~2400 | AI routing, pre-execution summary, workflow intent decomposition |
| `server/routes.ts` | ~800 | API proxy — execute, status, findings, step-file, methods-report |

---

## 4. Current UX Screenshots

### Screenshot A — Initial state (idle, parameters open, ADMET 1-step workflow)
*Panel opens with Parameters expanded at top. Steps hidden below the fold.*

### Screenshot B — Multi-step workflow (WGS Germline GATK, many parameters)
*Complex workflow with groups: Input options, Reference genome, Variant caller, Sample metadata — all stacked vertically, very long scroll.*

### Screenshot C — Scrolled down to steps + suggest-step button
*Steps section at the bottom. Suggest-step = small dashed button that pre-fills chat input.*

### Screenshot D — Suggest step clicked
*Chat textarea pre-filled with: "Add a step after 'Admet Pred Workflow' that "*

### Screenshot E — After step skip
*Step card shows strikethrough/skipped state. QC Settings section visible even though no QC is active.*

---

## 5. Functional Description — All Features

### 5.1 Workflow Execution

**Trigger:** User sends natural-language query in chat  
**AI flow:**
1. Intent decomposition (single workflow vs. multi-step pipeline)
2. Workflow retrieval (BGE dense retrieval + FTS + LLM routing)
3. Parameter pre-fill from message (pixel size, accession IDs, SMILES strings, file paths)
4. Disambiguation card if multiple candidates score close
5. Pre-execution message in chat (currently being simplified)
6. Workflow panel auto-opens with pre-filled parameters

**Execution states:** `idle → running → completed/failed`  
**Execution engine:** Nextflow on AWS Batch (SSE streaming of status updates)

### 5.2 Phase / Step Structure

**Conceptual model:**
- A **workflow** = 1 to 23 processes (Nextflow processes)
- Processes are grouped into **phases** — semantic stages of the biological analysis
- **Example: CryoSPARC SPA (23 steps)**
  - Phase A: Motion Correction + CTF Estimation (steps 0–4)
  - Phase B: Particle Picking (steps 5–8)
  - Phase C: 2D Classification (steps 9–13)
  - Phase D: 3D Reconstruction / Ab-Initio (steps 14–18)
  - Phase E: FSC Validation (steps 19–22)
- **Example: WGS Germline GATK (8 steps)** — no phase grouping currently, all flat
- **Example: ADMET Prediction (1 step)** — single process

**Phase-level controls (proposed primary unit):**
- Run all steps in phase
- View all phase outputs
- Phase-level QC gate (if applicable)
- Auto-loop: rerun phase if QC fails

**Step-level controls (within each phase):**
- **Run step** — execute single process, useful for debugging
- **Rerun step** — after completion/failure, retry with same or modified params  
  *(Run count shown: "Rerun step (×2)")*
- **Skip step** ⚠️ — marks step as complete without running  
  **RISK:** Downstream steps expecting this step's output may fail  
  *Action: Comment out or add strong warning dialog before shipping*
- **Pause-after toggle** — workflow pauses after this step completes (for manual inspection)
- **Parameter override** — inline edit of step-specific params without affecting global settings
- **Adjust & Rerun** — opens modal: edit params → rerun from this step → creates new runId

### 5.3 Step Outputs (per PhaseCard)

Each completed step card shows its output files with:
- File type icon (image 🖼 / table 📊 / code 📄 / log)
- File name
- **View** link — opens `StepOutputPreview` modal (inline image, CSV table, JSON tree, FASTA viewer)
- **Download** link → `/api/workflows/runs/{runId}/step-file?path=...&download=1`

Supported preview formats: `.png`, `.jpg`, `.svg`, `.pdf`, `.csv`, `.tsv`, `.json`, `.vcf`, `.fasta`, `.fastq`, `.html`, `.log`

### 5.4 Global Parameters

Parameters that apply to the **entire workflow** (not per-step):
- **Input data** — primary input files or accessions (e.g., `input`, `reads`, `bam`)
- **Reference genome** — `genome: hg38` or explicit paths
- **Output directory** — `outdir`
- **Resources** — `max_cpus`, `max_memory`, `max_time`
- **Workflow-specific settings** — e.g., `aligner: bwa-mem2`, `variant_caller: gatk`

Currently shown in a collapsible section at the **top of the panel** before steps. 

**Proposed change:** Move global params below the run button, collapsed by default. Params that belong to specific steps should migrate into the PhaseCard inline param display.

### 5.5 QC System

**When active:** Drug discovery (ADMET, docking, CYP-DDI, NCA-PK), Cryo-EM (motion correction, particle picking, 2D classification, FSC validation)

**QC Gate model:**
- Thresholds per metric (e.g., `herg_ic50 > 10 µM`, `ctf_fit_quality > 0.2`)
- Gate outcomes: PASS / ADVISORY / HALT
- Overall level: GOLD / SILVER / BRONZE / FAIL

**Current implementation:**
- `AutoLoopPanel` component — shows gate results table + remediation suggestions
- Inline in workflow panel when backend emits `autoloop_gate_results` SSE event
- QC Settings section (threshold editor + profile selector) — shown even when QC not applicable

**Proposed change:**
- Hide QC Settings section entirely when `availableQcProfiles.length === 0 && qcGateData === null`
- QC gate results appear inline within the relevant **phase card** (not as a global panel)
- Per-phase auto-loop toggle: "Rerun this phase if QC fails (max 3 attempts)"

### 5.6 Auto-Loop (Automated Remediation)

**What it does:** When a QC gate HALTs execution, the system:
1. Analyzes which parameters caused the failure
2. Proposes adjusted parameters (with literature citations)
3. Re-runs the phase with adjusted params
4. Repeats up to N attempts

**Current scope:** Workflow-level (whole pipeline reruns)  
**Proposed scope:** Phase-level (only the failed phase reruns)

**Domains:** Drug discovery (ADMET, docking, CYP-DDI, NCA-PK), Cryo-EM (all 5 phases)

**Autofix:** Separate from auto-loop — when a step fails due to infrastructure/environment error (not QC), the system analyzes the error log and proposes a fix. Shown via `autofix` panel.

### 5.7 Results & Outputs

**After run completes:**
- `View Results` — toggles `ChatOutputAttachments` section (S3 output files, grouped by type)
- `Analyze Results` — runs AI analysis (Claude Haiku) to generate `FindingsCard` (summary, key results, citations, next steps)
- `Download All` → `/api/invocations/{invocationId}/download-all`
- `Download QC Audit Log` → `/api/invocations/{invocationId}/qc-audit-download`
- `Download Methods Report` → `/api/invocations/{invocationId}/methods-report`
- Per-step outputs: inline in each PhaseCard output section

**FindingsCard** shows:
- Summary paragraph (AI-generated)
- Key results table (metric, value, interpretation)
- Citations (PMID, title, year)
- Caveats
- Next steps (with "Continue in chat" button)

### 5.8 Detach / Reconnect (Nextflow-specific)

Nextflow jobs run as independent AWS Batch jobs. The frontend "watches" via SSE polling.  
- **Detach** — frontend stops SSE polling; job continues on Batch
- **Reconnect** — frontend resumes polling the same runId
- This is **NOT** a pause/resume of the actual computation  
- Label should be "Detach watcher" / "Reconnect watcher" to avoid confusion with biological "pause"

**True pause (per-step):** The `pause-after` toggle stops the workflow orchestrator after the current step finishes, allowing manual inspection of outputs before proceeding.

### 5.9 Suggest Step

Small affordance at the bottom of the step list. When clicked, pre-fills the chat textarea with:  
`"Add a step after '[last step name]' that "`

Allows users to extend the workflow via chat without re-describing full context. Currently a full-width dashed button — should be downgraded to a small text link.

---

## 6. Identified UX Problems (Current State)

| # | Problem | Severity | Location |
|---|---------|----------|----------|
| P1 | Steps buried at bottom — user must scroll past params + run controls + QC to reach steps | High | Right panel |
| P2 | Parameters shown at top but also need to be per-step — currently global only | High | Right panel |
| P3 | QC Settings section visible even for workflows with no QC | Medium | Right panel |
| P4 | Results are 4 full-width stacked buttons — heavy visual weight for post-run only actions | Medium | Right panel |
| P5 | "Skip step" is dangerous (breaks downstream dependencies) but no warning | High | PhaseCard |
| P6 | "Detach" button label confusing — users expect "Pause" | Medium | Run controls |
| P7 | Pre-execution AI message was verbose (verbose parameter dump) — now simplified but still needs testing | Medium | Chat area |
| P8 | Panel width 420px feels cramped for multi-param workflows | Medium | Right panel |
| P9 | "Suggest step" is a full dashed button — too prominent for minor feature | Low | Step list |
| P10 | No phase-level run/loop controls — only step-level and whole-workflow | High | Steps section |
| P11 | Long workflows (23 steps) shown flat — no visual phase grouping as primary unit | High | Steps section |
| P12 | Auto-loop is whole-workflow scope — should be per-phase | High | QC/loop controls |
| P13 | Capability hint ("You can edit parameters · adjust QC thresholds · skip steps · preview outputs") is vague text, not actionable | Low | Below steps |

---

## 7. Proposed Redesign

### 7.1 Overall Principles

1. **Phase-first, step-second** — phases are the primary interaction unit; steps expand within phases
2. **Execution context always visible** — Run button and status never require scrolling
3. **Per-phase everything** — parameters, QC, outputs, loop controls all scoped to phase
4. **Progressive disclosure** — global settings collapsed by default; per-step detail on demand
5. **Actions as links, not buttons** — post-run output actions are text links, not heavy buttons

### 7.2 New Panel Layout (500px width)

```
┌─ Workflow Panel ─────────────────────────── [status badge] [×] ┐
│  WorkflowName                                                    │
│  ──────────────────────────────────────────────────────────────  │
│  ● Updated 3:41 PM                  [⬛ Cancel]  [↩ Restart]    │
│  ████████░░░ 62%  (running state)                                │
│  ──────────────────────────────────────────────────────────────  │
│                                                                  │
│  ▾ Phase A — Motion Correction  ●●●● RUNNING  2/4 steps        │
│    ┌──────────────────────────────────────────────────────────┐ │
│    │ Step 1  MotionCorr2         ✓ completed  [Rerun] [⚙]    │ │
│    │   Outputs: micrographs_ctf.star  👁 View  ⬇ Download    │ │
│    ├──────────────────────────────────────────────────────────┤ │
│    │ Step 2  Gctf                ↻ running...                 │ │
│    ├──────────────────────────────────────────────────────────┤ │
│    │ Step 3  CTFFind4            ○ pending                    │ │
│    └──────────────────────────────────────────────────────────┘ │
│    QC Gate: ctf_fit_quality > 0.2  [threshold editor ▾]         │
│    ☐ Auto-loop this phase on QC fail (max 3×)                   │
│                                                                  │
│  ▸ Phase B — Particle Picking  ○ pending                        │
│  ▸ Phase C — 2D Classification  ○ pending                       │
│  ▸ Phase D — 3D Reconstruction  ○ pending                       │
│  ▸ Phase E — FSC Validation  ○ pending                          │
│                                                                  │
│  ──────────────────────────────────────────────────────────────  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ▶  Confirm and Run Workflow                             │   │
│  └──────────────────────────────────────────────────────────┘   │
│  [Detach watcher ↗]  (Nextflow: job continues on Batch)         │
│                                                                  │
│  ▸ Workflow settings  (output dir, genome, resources…)  [▾]     │
│                                                                  │
│  ──────────────────────────────────────────────────────────────  │
│  After run:  View results  ·  Download all  ·  Methods report   │
│             AI analysis  ·  QC audit log                         │
│  ──────────────────────────────────────────────────────────────  │
│  + Suggest a new step via chat                                   │
└──────────────────────────────────────────────────────────────── ┘
```

### 7.3 Phase Card Design (expanded state)

```
┌─ Phase A — Motion Correction  ████░░░ RUNNING  ─────────────┐
│  3 steps · QC: CTF quality gates                              │
│                                                               │
│  ① MotionCorr2          ✓ COMPLETED  [Rerun] [Params ▾]     │
│     Parameters:  patch_x: 5  patch_y: 5  max_shift: 20Å     │
│     Outputs:  📊 motion_trace.star  👁  ⬇                   │
│                                                               │
│  ② Gctf                 ↻ RUNNING  (est. 2 min)              │
│                                                               │
│  ③ CTFFind4              ○ PENDING                           │
│     Pause-after this step  [toggle]                          │
│                                                               │
│  ── QC Gate (fires after step ③) ──────────────────────     │
│  ctf_fit_quality  threshold: > 0.2   [edit]                 │
│  astigmatism      threshold: < 500Å  [edit]                 │
│  ☐ Auto-loop phase on fail (max 3×)                          │
│                                                               │
│  [Run Phase A]     [Skip Phase A ⚠]                          │
└───────────────────────────────────────────────────────────── ┘
```

**Skip phase** should show a modal:
> ⚠️ Skipping Phase A removes its output files. Downstream phases that use these outputs may fail.  
> [Skip anyway]  [Cancel]

### 7.4 Workflow Settings (global params, collapsed)

```
▸ Workflow settings  ────────────────────────────────────────
  Output directory:    results/run_2026-04-19/       [edit]
  Reference genome:    hg38                          [edit]
  Max CPUs:            16                            [edit]
  Max memory:          64 GB                         [edit]
  Email notification:  (none)                        [edit]
```

### 7.5 Chat Message — Pre-execution (simplified)

**Before (current verbose):**
```
Understood from your message
• Input: (no specific inputs detected...)
• smiles: CC(=O)Oc1ccccc1C(=O)O (auto-filled)
Running: workflow
1 run · local
ADMET Property Prediction — Predicts key drug...
```

**After (proposed):**
```
ADMET Property Prediction is ready in the panel — check the 
steps and parameters, then click Confirm & Run.
```
*(Workflow card appears below with Open in panel button)*

---

## 8. Open Questions for Design

1. **Phase collapse behavior:** When all steps in a phase are `pending`, should the phase be collapsed by default? Or expanded to show the step list?

2. **Skip step vs. Skip phase:** Should skip be per-step, per-phase, or only per-phase to reduce dependency risk?

3. **Auto-loop UI placement:** Should the auto-loop toggle be inside the phase card (per-phase), or a global setting?

4. **Parameter visibility:** For a 1-step workflow (ADMET), there's no meaningful distinction between "phase params" and "global params". Should the params section switch modes based on step count?

5. **Execution blocked state:** When prereqs are missing (no SMILES, no input file), should the Run button be hidden or disabled with inline explanation?

6. **Mobile/narrow viewport:** The 3-column layout breaks below ~1200px. Should the right panel become a slide-over drawer on narrow screens?

---

## 9. Relevant Files for Designer

### Frontend source (`frontend/client/src/components/`)
```
nextflow-workflow-viewer.tsx   — main panel, 2761 lines (PRIMARY)
phase-card.tsx                 — step card component, 385 lines (PRIMARY)
chat-with-artifacts.tsx        — layout shell, 1403 lines
chat-interface.tsx             — chat thread
chat-input.tsx                 — textarea + file upload
auto-loop-panel.tsx            — QC gate results table + remediation
findings-card.tsx              — AI findings after run
parameter-group.tsx            — collapsible param group
step-output-preview.tsx        — file preview modal
step-adjust-modal.tsx          — step param edit + rerun modal
```

### Design tokens / UI library
```
client/src/components/ui/      — shadcn/ui: Button, Card, Badge, Switch,
                                  Input, Select, Dialog, Alert, Tabs, etc.
client/src/index.css           — Tailwind CSS variables (colors, radius, etc.)
tailwind.config.ts             — theme configuration
```

### Screenshots (in `/tmp/s3-e2e-screenshots/`)
```
s3smoke-03-panel.png           — idle state, ADMET 1-step (panel open)
s3smoke-05-draft.png           — scrolled to bottom, suggest-step clicked
s3c9-02-skip-btn.png           — WGS workflow, skip button visible
s3c9-03-after-skip.png         — state after step skip + QC Settings visible
s3b4-02-panel-open.png         — ADMET panel open, parameters section
s3b5-02-viewer-in-panel.png    — WGS Germline GATK, many parameters
s3c10-02-suggest-btn.png       — suggest-step button location
```

---

## 10. Technical Notes for Implementation

- **State management:** All panel state is in `nextflow-workflow-viewer.tsx` as local React state. No global store.
- **Real-time updates:** SSE events update `updatedPhases` array via `useEffect`. Phase status is derived from `nextflowStatus.processes` array (keyed by process name).
- **Per-step params:** `PhaseCard` already accepts `parameters: Record<string, any>` prop. Backend enriches steps with `parameters` dict via `_enrich_steps_with_phase_info()` in `ai_assistant.py`.
- **Phase grouping:** `PhaseGroupSection` component groups `updatedPhases` by `phase_group` field. CryoSPARC uses index-based static mapping; other workflows use keyword matching.
- **Output files:** `PhaseCard` receives `taskFiles` (from Nextflow work_dir scan) and `outputFiles` (from S3/local). Both rendered in the output section.
- **Auto-loop:** Backend emits `autoloop_gate_results`, `autoloop_update`, `autoloop_phase_complete`, `autoloop_escalation` SSE events. `AutoLoopPanel` consumes these. Currently whole-workflow scope.
- **QC gate data:** `qcGateData` prop flows from SSE `qc_gate` events. `availableQcProfiles` from `/api/qc/profiles`.

---

*Document generated 2026-04-19 · BioMate integration/next-phase branch*
