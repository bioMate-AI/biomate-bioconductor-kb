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

The interface uses a three-column layout: a left navigation sidebar (~200px), a fluid center chat area (~60% of remaining width), and a fixed-width right workflow panel (currently 420px, proposed 500px).

The right panel **auto-opens** when the AI generates a workflow response. It can be dismissed and reopened from the chat message.

### 2.2 Screenshot A — Full page, idle state (ADMET 1-step workflow)

*Panel opens automatically. Parameters section is expanded at the top. Steps are hidden below the fold. The chat message shows the AI response with a verbose pre-execution summary (being simplified).*

![Full page layout — idle state, ADMET workflow, panel open](/tmp/s3-e2e-screenshots/s3smoke-03-panel.png)

### 2.3 Screenshot B — Multi-step workflow (WGS Germline GATK)

*A complex genomics workflow with many parameter groups: Input options, Reference genome, Variant caller, Sample metadata — all stacked vertically in the right panel.*

![Multi-step WGS Germline GATK workflow in panel](/tmp/s3-e2e-screenshots/s3b5-02-viewer-in-panel.png)

### 2.4 Screenshot C — Panel scrolled to bottom: steps section visible

*After scrolling past Parameters, Run controls, and QC Settings, the phase-grouped step cards appear. The "Suggest step" dashed button is at the bottom.*

![Panel scrolled to bottom — steps and suggest-step button](/tmp/s3-e2e-screenshots/s3smoke-05-draft.png)

### 2.5 Screenshot D — Step skip button visible, QC Settings always shown

*The skip button appears on each step card. QC Settings section is always present even when the workflow has no QC profiles.*

![Step skip button and QC Settings always visible](/tmp/s3-e2e-screenshots/s3c9-02-skip-btn.png)

### 2.6 Screenshot E — After step skip

*Step marked as skipped. QC Settings section still visible even though this workflow has no active QC.*

![State after step skip — QC settings still visible](/tmp/s3-e2e-screenshots/s3c9-03-after-skip.png)

### 2.7 Screenshot F — Suggest step: button location

*The "Suggest step" button is located at the very bottom of the step list.*

![Suggest step button location](/tmp/s3-e2e-screenshots/s3c10-02-suggest-btn.png)

### 2.8 Screenshot G — Suggest step: chat pre-filled

*After clicking "Suggest step", the chat input is pre-filled with "Add a step after 'Admet Pred Workflow' that ". User types what they want to add.*

![Chat input pre-filled after suggest-step click](/tmp/s3-e2e-screenshots/s3c10-03-prefilled-input.png)

### 2.9 Screenshot H — Pre-execution summary in chat (current verbose version)

*The AI response before showing the workflow panel. Currently shows interpreted inputs, parameter values, and a long description — overlapping with what's already in the panel.*

![Current verbose pre-execution summary in chat](/tmp/s3-e2e-screenshots/s3a1-01-response.png)

### 2.10 Screenshot I — Multi-accession workflow (nf-core QC, 2 SRR accessions)

*When a user provides multiple SRR accessions, the AI detects multi-run intent and shows the panel with both inputs. QC Settings and the full step list are visible.*

![Multi-accession workflow — nf-core fastp QC](/tmp/s3-e2e-screenshots/s3a3-01-response.png)

---

## 3. Component Inventory

### Frontend Components (all in `frontend/client/src/components/`)

| File | Lines | Purpose |
|---|---|---|
| `nextflow-workflow-viewer.tsx` | 2,761 | Entire right panel — parameters, run controls, step cards, outputs |
| `phase-card.tsx` | 385 | Individual step card — status, run/skip/rerun, param overrides, output files |
| `chat-with-artifacts.tsx` | 1,403 | Main page layout — panel open/close, session, run state |
| `chat-interface.tsx` | ~1,750 | Chat thread, message list, typing indicator, queue management |
| `chat-input.tsx` | ~200 | Chat textarea with file attachment popover |
| `auto-loop-panel.tsx` | 361 | QC gate results table + remediation cards (drug discovery & cryo-EM) |
| `findings-card.tsx` | ~200 | AI-generated findings with citations (after run completes) |
| `parameter-group.tsx` | — | Collapsible group of parameter Input/Select fields |
| `step-output-preview.tsx` | — | Modal preview for step output files (image, CSV, JSON, FASTA) |
| `step-adjust-modal.tsx` | — | Modal: edit step parameters and rerun from that step |
| `license-gate.tsx` | — | Credential check (e.g., AlphaFold database, licensed tools) |

### Server-side
| File | Lines | Purpose |
|---|---|---|
| `server/galaxy-assistant.ts` | ~2,400 | AI routing, pre-execution summary, workflow intent decomposition |
| `server/routes.ts` | ~800 | API proxy — execute, status, findings, step-file, methods-report |

---

## 4. Current Panel Scroll Order (Top → Bottom)

The current right panel renders these sections in this order when scrolled from top to bottom:

1. **Parameters section** (collapsible, open by default) — all workflow params shown at top
2. **Run controls** — License gate, Validate Environment, Confirm & Run button, Pause/Detach, Resume/Reconnect, Restart, Cancel, Usage meter
3. **QC Settings** (collapsible, always visible even when no QC applies) — pause-at-QC-fail toggle, threshold sliders, profile selector
4. Autofix status panel (if auto-fix is active)
5. Prereq checklist (if execution is blocked)
6. Blocked reason alert + "Confirm Anyway" button
7. **Results action buttons** — 4–5 full-width stacked buttons: View Results, Analyze Results, Download All, Download QC Audit Log, Download Methods Report
8. Run metrics strip (wall time, started, ended, per-step costs)
9. Live Nextflow process list (if trace data available)
10. **Capability hint** (small text: "You can edit parameters · adjust QC thresholds · skip steps · preview outputs")
11. **Step-controls hint** (small text)
12. **Phase-grouped step cards** (PhaseGroupSection → PhaseCard per process)
13. **[+ Suggest step]** dashed button
14. Preview modal, Adjust modal, Logs, Report confusion button
15. Output Results section (expanded when "View Results" toggled)
16. AI Findings card (after "Analyze Results" clicked)

---

## 5. Functional Description — All Features

### 5.1 Workflow Execution Flow

**Trigger:** User types a natural-language query in the chat textarea.

**AI processing pipeline:**
1. Intent decomposition (single workflow vs. multi-step pipeline)
2. Workflow retrieval (BGE dense retrieval + full-text search + LLM routing across 400+ pipelines)
3. Parameter pre-fill from query (pixel size, accession IDs, SMILES strings, file paths)
4. Disambiguation card if multiple candidates score closely
5. Pre-execution message in chat (currently being simplified to one line)
6. Workflow panel auto-opens with pre-filled parameters ready for review

**Execution states:** `idle → running → completed / failed`

**Execution engine:** Nextflow on AWS Batch. Status updates stream via SSE (Server-Sent Events) every few seconds.

### 5.2 Phase / Step Structure

**Conceptual model:**

- A **workflow** = 1 to 23 Nextflow processes
- Processes are grouped into **phases** — semantic stages of the biological analysis
- **Example: CryoSPARC SPA (23 steps, 5 phases)**
  - Phase A: Motion Correction + CTF Estimation (steps 0–4)
  - Phase B: Particle Picking (steps 5–8)
  - Phase C: 2D Classification (steps 9–13)
  - Phase D: 3D Reconstruction / Ab-Initio (steps 14–18)
  - Phase E: FSC Validation (steps 19–22)
- **Example: WGS Germline GATK (8 steps)** — no phase grouping currently, all flat
- **Example: ADMET Prediction (1 step)** — single process, no phases

### 5.3 Step-level Controls (PhaseCard)

Each step card currently provides:

- **Run step** — execute a single process (useful for debugging one step)
- **Rerun step** — after completion or failure, retry. Run count shown: "Rerun (×2)"
- **Skip step** ⚠️ — marks step as complete without running it
  - **RISK:** Downstream steps expecting this step's output may fail
  - **Action required:** Comment out or add a strong warning dialog before release
- **Pause-after toggle** — workflow stops after this step finishes for manual output inspection
- **Parameter override** — inline edit of step-specific params without changing global settings
- **Adjust & Rerun** — opens modal to edit params and rerun from this step (creates new runId)

### 5.4 Per-step Output Files

Each completed step card shows its output files with:

- File type icon (🖼 image / 📊 table / 📄 code / log)
- File name
- **View** link → opens StepOutputPreview modal (inline image, CSV table, JSON, FASTA)
- **Download** link → `/api/workflows/runs/{runId}/step-file?path=...&download=1`

**Supported preview formats:** `.png`, `.jpg`, `.svg`, `.pdf`, `.csv`, `.tsv`, `.json`, `.vcf`, `.fasta`, `.fastq`, `.html`, `.log`

### 5.5 Global Parameters

Parameters that apply to the **entire workflow run**, not to any individual step:

- **Input data** — primary input files or accessions (`input`, `reads`, `bam`)
- **Reference genome** — `genome: hg38` or explicit S3/local paths
- **Output directory** — `outdir`
- **Resources** — `max_cpus`, `max_memory`, `max_time`
- **Workflow-specific settings** — e.g., `aligner: bwa-mem2`, `variant_caller: gatk`

Currently shown in a collapsible section at the **top of the panel** before steps. Proposed: move below the run button, collapsed by default.

### 5.6 QC System

**When active:** Drug discovery (ADMET, docking, CYP-DDI, NCA-PK), Cryo-EM (motion correction, particle picking, 2D classification, FSC validation).

**QC Gate model:**
- Thresholds per metric (e.g., `herg_ic50 > 10 µM`, `ctf_fit_quality > 0.2`)
- Gate outcomes: PASS / ADVISORY / HALT
- Overall quality level: GOLD / SILVER / BRONZE / FAIL

**Current problem:** The QC Settings section is always shown in the panel — even for workflows like ADMET simple screening or WGS germline calling where there is no QC profile. This wastes space and confuses users.

**Proposed fix:** Hide the QC Settings section entirely when `availableQcProfiles.length === 0 AND no QC gate has fired`. QC gate results appear inline within the relevant phase card instead of as a global panel.

### 5.7 Auto-Loop (Automated Remediation)

When a QC gate HALTs execution, the system:

1. Analyzes which parameters caused the failure
2. Proposes adjusted parameters (with literature citations)
3. Re-runs the phase with adjusted params
4. Repeats up to N attempts (configurable, default 3)

**Current scope:** Workflow-level (whole pipeline reruns).
**Proposed scope:** Phase-level (only the failed phase reruns).

**Domains with auto-loop:** Drug discovery (ADMET, docking, CYP-DDI, NCA-PK), Cryo-EM (all 5 phases).

### 5.8 Detach / Reconnect (Nextflow on AWS Batch)

Nextflow jobs run as independent AWS Batch jobs that persist regardless of the frontend connection.

- **Detach** — frontend stops SSE polling; the Batch job continues running on AWS
- **Reconnect** — frontend resumes polling the same runId

This is **NOT** a pause/resume of the computation. The current label "Pause" is misleading. Should be renamed to **"Detach watcher"** / **"Reconnect watcher"** with a tooltip explanation.

**True per-step pause:** The "Pause-after" toggle on each PhaseCard stops the workflow orchestrator after the current step finishes, allowing manual inspection before the next step begins.

### 5.9 Suggest Step

A minor affordance at the bottom of the step list. When clicked, pre-fills the chat textarea with:

> `"Add a step after '[last step name]' that "`

Allows users to extend the workflow via chat without re-describing context. Currently rendered as a full-width dashed button — visually too prominent for this minor feature. Should be downgraded to a small inline text link.

### 5.10 Results & Outputs (Post-run)

After a workflow completes:

| Action | How accessed (current) | Proposed |
|---|---|---|
| View output files | Full-width button "View Results" | Text link "View results" |
| AI analysis of findings | Full-width button "Analyze Results" | Text link "AI analysis" |
| Download all outputs | Full-width button "Download All" | Text link "Download all" |
| Download QC audit log | Full-width button (if QC active) | Text link "QC audit log" |
| Download methods report | Full-width button | Text link "Methods report" |

**FindingsCard** (after AI analysis) shows: summary paragraph, key results table (metric / value / interpretation), citations (PMID, title, year), caveats, and next steps with "Continue in chat" button.

---

## 6. Identified UX Problems

| # | Problem | Severity |
|---|---|---|
| P1 | Steps buried at bottom — user must scroll past params + run controls + QC to reach them | **High** |
| P2 | All parameters global — no per-phase or per-step parameter scoping | **High** |
| P3 | QC Settings always visible even when workflow has no QC | **Medium** |
| P4 | 4–5 full-width stacked result buttons — heavy visual weight for post-run-only actions | **Medium** |
| P5 | Skip step has no warning about downstream dependency breakage | **High** |
| P6 | "Detach" labeled "Pause" — users expect pause to freeze the computation | **Medium** |
| P7 | Pre-execution chat message was verbose (parameter dump) — duplicates panel content | **Medium** |
| P8 | Panel width 420px too narrow for multi-param workflows | **Medium** |
| P9 | "Suggest step" rendered as prominent full-width dashed button for a minor feature | **Low** |
| P10 | No phase-level run/loop controls — only whole-workflow or individual step | **High** |
| P11 | Long workflows (23 steps) shown flat — no phase grouping as primary visual unit | **High** |
| P12 | Auto-loop reruns entire workflow — should rerun only the failed phase | **High** |
| P13 | Capability hint text is vague and not actionable | **Low** |

---

## 7. Proposed Redesign

### 7.1 Design Principles

1. **Phase-first, step-second** — phases are the primary interaction unit; individual steps expand within phases on demand
2. **Execution controls always visible** — the Run button and status badge never require scrolling
3. **Per-phase everything** — parameters, QC gates, outputs, and loop controls are all scoped to their phase
4. **Progressive disclosure** — global settings collapsed by default; step-level detail on demand
5. **Actions as links, not buttons** — post-run output access uses text links, not full-width buttons

### 7.2 Proposed Panel Layout (500px width)

```
┌─ Workflow Panel ─────────────────────── [STATUS] [×] ┐
│  Workflow Name                                         │
│  ─────────────────────────────────────────────────── │
│  Updated 3:41 PM          [Cancel]  [Restart]         │
│  ██████████░░ 62%  (progress bar when running)        │
│  ─────────────────────────────────────────────────── │
│                                                        │
│  ▾ Phase A — Motion Correction   RUNNING  2/4 done    │
│    ① MotionCorr2    ✓ done  [Rerun] [⚙ Params ▾]    │
│       Outputs: micrographs_ctf.star  View · Download  │
│    ② Gctf           ↻ running...                     │
│    ③ CTFFind4        ○ pending  [Pause-after toggle]  │
│    QC: ctf_quality > 0.2  [edit]  ☐ Auto-loop 3×     │
│    [Run Phase A]                                       │
│                                                        │
│  ▸ Phase B — Particle Picking    ○ pending            │
│  ▸ Phase C — 2D Classification   ○ pending            │
│  ▸ Phase D — 3D Reconstruction   ○ pending            │
│  ▸ Phase E — FSC Validation      ○ pending            │
│                                                        │
│  ─────────────────────────────────────────────────── │
│  ┌─────────────────────────────────────────────────┐  │
│  │  ▶  Confirm and Run Workflow                    │  │
│  └─────────────────────────────────────────────────┘  │
│  Detach watcher ↗  (job continues on AWS Batch)       │
│                                                        │
│  ▸ Workflow settings (outdir, genome, resources…)     │
│                                                        │
│  ─────────────────────────────────────────────────── │
│  After run: View results · Download all ·             │
│             AI analysis · Methods report              │
│  ─────────────────────────────────────────────────── │
│  + Suggest a new step via chat                        │
└───────────────────────────────────────────────────── ┘
```

### 7.3 Phase Card — Expanded State Design

```
┌─ Phase A — Motion Correction   RUNNING ──────────────┐
│  3 steps · QC: CTF quality gates active               │
│                                                        │
│  ① MotionCorr2      ✓ COMPLETED   [Rerun] [Params ▾] │
│     patch_x: 5  patch_y: 5  max_shift: 20Å           │
│     Outputs: 📊 motion_trace.star   View · Download  │
│                                                        │
│  ② Gctf             ↻ RUNNING  (~2 min)              │
│                                                        │
│  ③ CTFFind4          ○ PENDING                        │
│     Pause workflow after this step  [toggle ○]        │
│                                                        │
│  ── QC Gates (evaluated after step ③) ──────────     │
│  ctf_fit_quality  >  0.2     [edit threshold]        │
│  astigmatism      <  500 Å   [edit threshold]        │
│  ☐ Auto-loop this phase on fail (max 3×)              │
│                                                        │
│  [Run Phase A]                                         │
└────────────────────────────────────────────────────── ┘
```

**Skip phase** — requires a confirmation modal:
> ⚠️ Skipping Phase A removes its output files. Downstream phases that depend on these outputs may fail.
> [Skip anyway] [Cancel]

### 7.4 Chat Message — Before vs. After

**Current (verbose):**
> Understood from your message
> • Input: (no specific inputs detected…)
> • smiles: CC(=O)Oc1ccccc1C(=O)O (auto-filled)
> Running: workflow · 1 run · local
> ADMET Property Prediction — Predicts key drug safety…

**Proposed (one line):**
> **ADMET Property Prediction** is ready in the panel — check the steps and parameters, then click **Confirm & Run**.

*(Workflow card with "Open in panel" button appears below the text.)*

### 7.5 Workflow Settings (Global Params — Collapsed)

```
▸ Workflow settings ────────────────────────────────────
  Output directory:   results/run_2026-04-19/   [edit]
  Reference genome:   hg38                      [edit]
  Max CPUs:           16                        [edit]
  Max memory:         64 GB                     [edit]
  Email notification: (none)                    [edit]
```

---

## 8. Open Questions for Design

1. **Phase default state:** When all steps in a phase are `pending`, should the phase card be collapsed (show only header) or expanded (show step list)? Suggested: collapsed, expanding only the currently-running phase.

2. **Skip scope:** Should skip be per-step, per-phase, or removed entirely? Per-phase with a warning is probably the right level — skipping a whole phase is a deliberate decision.

3. **Auto-loop placement:** Inside the phase card (per-phase toggle) or a global workflow setting?

4. **1-step workflow:** For ADMET (1 step, no meaningful phases), should the phases section be hidden and replaced with a simple parameter list? The distinction between "phase params" and "global params" is meaningless for single-step workflows.

5. **Execution blocked state:** When required parameters are missing, should the Run button be hidden (cleaner) or disabled with inline explanation (more informative)?

6. **Mobile / narrow viewport:** The 3-column layout breaks below ~1200px. Should the workflow panel become a slide-over drawer on narrow screens?

---

## 9. Relevant Files for Designer

### Frontend component source
```
client/src/components/nextflow-workflow-viewer.tsx   (PRIMARY — 2,761 lines)
client/src/components/phase-card.tsx                 (PRIMARY — 385 lines)
client/src/components/chat-with-artifacts.tsx        (layout shell — 1,403 lines)
client/src/components/chat-interface.tsx             (chat thread)
client/src/components/chat-input.tsx                 (textarea + file upload)
client/src/components/auto-loop-panel.tsx            (QC gate table + remediation)
client/src/components/findings-card.tsx              (AI findings post-run)
client/src/components/parameter-group.tsx            (param field groups)
client/src/components/step-output-preview.tsx        (file preview modal)
client/src/components/step-adjust-modal.tsx          (step param edit + rerun modal)
```

### UI design system
```
client/src/components/ui/                   (shadcn/ui: Button, Card, Badge,
                                             Switch, Input, Select, Dialog, etc.)
client/src/index.css                        (Tailwind CSS color variables)
tailwind.config.ts                          (theme — colors, radius, fonts)
```

### Screenshots
```
/tmp/s3-e2e-screenshots/s3smoke-03-panel.png        Idle state, ADMET, panel open
/tmp/s3-e2e-screenshots/s3smoke-05-draft.png        Scrolled to bottom, steps visible
/tmp/s3-e2e-screenshots/s3b5-02-viewer-in-panel.png WGS Germline GATK, many params
/tmp/s3-e2e-screenshots/s3c9-02-skip-btn.png        Skip button visible on step
/tmp/s3-e2e-screenshots/s3c9-03-after-skip.png      After step skip
/tmp/s3-e2e-screenshots/s3c10-02-suggest-btn.png    Suggest-step button location
/tmp/s3-e2e-screenshots/s3c10-03-prefilled-input.png Chat pre-filled after click
/tmp/s3-e2e-screenshots/s3a1-01-response.png        Current verbose pre-exec summary
/tmp/s3-e2e-screenshots/s3a3-01-response.png        Multi-accession workflow
```

---

## 10. Technical Notes for Implementation

- **State management:** All panel state is in `nextflow-workflow-viewer.tsx` as local React state. No global store (Redux/Zustand).
- **Real-time updates:** SSE events update the `updatedPhases` array. Phase status is derived from `nextflowStatus.processes` (keyed by Nextflow process name).
- **Per-step params:** `PhaseCard` already accepts `parameters: Record<string, any>` prop. Backend already enriches steps with per-process parameter metadata via `_enrich_steps_with_phase_info()` in `ai_assistant.py`.
- **Phase grouping:** `PhaseGroupSection` groups `updatedPhases` by `phase_group` field (added by backend). CryoSPARC uses static index-based mapping. Other workflows use keyword matching.
- **Output files:** `PhaseCard` receives `taskFiles` (from Nextflow work_dir scan) and `outputFiles` (from S3). Both rendered in the step output section.
- **Auto-loop:** Backend emits `autoloop_gate_results`, `autoloop_update`, `autoloop_phase_complete`, `autoloop_escalation` SSE events. `AutoLoopPanel` renders these. Currently whole-workflow scope.
- **QC gate data:** `qcGateData` from SSE `qc_gate` events. `availableQcProfiles` from `GET /api/qc/profiles` (returns 32 profiles for active workflows).

---

*Document generated 2026-04-19 · BioMate `integration/next-phase` branch*
