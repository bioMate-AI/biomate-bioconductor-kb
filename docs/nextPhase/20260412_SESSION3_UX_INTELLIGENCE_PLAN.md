# Session 3 — UX Intelligence & Output Analysis Plan
**Date:** 2026-04-12  
**Branch:** integration/next-phase

---

## Context

Session 2 completed all UX surface work (upload, phase controls, inline viz, analysis card, accession resolver).
This session addresses the remaining UX communication gaps and adds the Output Intelligence layer.

---

## Track 3A — Pre-Execution Communication (Medium)

### Problem
Single-workflow responses (`_return_nextflow_match`, lines 1737/1762 in `galaxy-assistant.ts`) emit a one-liner like "I'll run the **rnaseq** workflow." The user gets no explicit confirmation of what BioMate understood before the workflow panel appears:
- Which inputs were recognised (files, accessions, server paths)
- Which parameters were pre-filled and why
- Whether multiple accessions mean multiple runs or one samplesheet run
- What is still missing / required before execution

Multi-step pipeline summaries already list steps (lines 1995–2009) but don't list understood inputs.

### What to build

**3A-1 — Structured pre-execution summary block** (galaxy-assistant.ts)

Before every workflow response, emit a fixed-structure summary:

```
**Understood from your message**
• Input: SRR1518169 → resolved to FTP path (SRA run, paired-end FASTQ)
• Reference genome: hg38 (auto-filled from request)
• Threads: 8 (default)

**Running:** nf-core/rnaseq  
**1 run** · ~45 min estimated · AWS Batch (us-west-2)

⚠️ Required before running: strandedness (--strandedness)
```

Emit this for both single-workflow and pipeline responses.

**3A-2 — Multi-run detection**

When multiple distinct inputs of the same type are detected (2+ SRR IDs, 2+ FASTQ files) AND the workflow takes a single `--input`:
- Tell the user: "3 SRR IDs detected → will generate a samplesheet and run once (nf-core batch mode)"  
- OR: "3 inputs detected → will run the workflow 3 times in parallel"
- Decision: check if workflow schema has `--input` accepting CSV (samplesheet) vs scalar

**3A-3 — Samplesheet auto-generation**

When `_inject_uploaded_files_into_params` sees multiple inputs of the same type:
- Generate a samplesheet CSV at a temp path
- Set `params.input = /tmp/samplesheet_<id>.csv`
- Report this in the pre-execution summary

**Files to change:**
- `frontend/server/galaxy-assistant.ts` — `_return_nextflow_match()` and pipeline summary builder
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — `_inject_uploaded_files_into_params()`

---

## Track 3B — Right Artifact Panel Layout (Medium)

### Problem
`chat-with-artifacts.tsx` comment says explicitly: "No split panel — workflows appear as collapsible cards within chat messages." For a workflow with 8 steps, parameter overrides, QC settings and output files, inline-in-chat is wrong:
- Gets buried as conversation grows
- Narrow column limits usable width
- Cannot reference while continuing to chat

### What to build

Split-panel layout in `chat-with-artifacts.tsx`:
- **Left (60%):** Chat messages — text, accession chips, DataAnalysisCard, plain AI responses
- **Right (40%):** Artifact panel — the active `NextflowWorkflowViewer`, persists across messages, scrollable independently

Behaviour:
- When a workflow is generated, it appears in the right panel (replacing any previous one)
- The chat message shows a small "→ Workflow panel" link/badge instead of the full viewer inline
- If no workflow is active, the right panel shows a placeholder or is collapsed
- On mobile / narrow viewport: stacks vertically, workflow panel below chat

**Files to change:**
- `client/src/components/chat-with-artifacts.tsx` — split layout
- `client/src/components/chat-message.tsx` — remove inline viewer, emit panel-open signal instead
- `client/src/components/nextflow-workflow-viewer.tsx` — no structural change needed

---

## Track 3C — Workflow Panel Self-Description & Phase Controls (Small)

### Problem
The workflow review panel doesn't explain itself. Users see asterisked fields and a Run button but nothing that says what else they can do.

`onSkip` in `PhaseCard` is also not wired — the button was built but the callback is never passed in `nextflow-workflow-viewer.tsx`.

### What to build

**3C-1 — Panel capability hint** (nextflow-workflow-viewer.tsx)

Add a compact "What you can do here" line near the top of the workflow panel:

> _You can edit parameters · adjust QC thresholds · skip steps · preview outputs · continue in chat →_

Each keyword is a link/button that scrolls to / opens the relevant section.

**3C-2 — Wire onSkip** (nextflow-workflow-viewer.tsx line ~1773)

Pass `onSkip={() => handleSkipPhase(phase.id)}` to each `PhaseCard`. 
`handleSkipPhase` already exists in the viewer state. Just missing the prop pass.

**3C-3 — Add-step via chat button**

Add a "+ Suggest step" button at the bottom of the step list that calls `onAdjustViaChat("Add a step after [last step name] that...")` — pre-fills the chat input so the user can describe the new step and the AI regenerates.

**Files to change:**
- `client/src/components/nextflow-workflow-viewer.tsx`

---

## Track 3D — Output Intelligence: Analysis, Findings & Citations (Large)

### Problem
Workflow outputs are currently: download link + inline visualisation (image/table/sequence viewer).
There is no:
- Biological interpretation of results
- Finding summarisation ("your ADMET screening ranked 47 compounds; top 3 by QED score are...")
- Literature search to confirm or contextualise findings
- Structured findings report with citations

### What to build

**3D-1 — Output analysis service** (backend)

New file: `backend/lib/galaxy/ai/output_analyzer.py`

`OutputAnalyzer.analyze(run_id, workflow_id, output_files)` → `AnalysisResult`

Per output type:
- **VCF/variant**: count variants by FILTER, IMPACT (HIGH/MODERATE), known pathogenicity; summarise per gene
- **CSV rankings** (ADMET, docking scores): identify top N by primary metric; flag threshold violations
- **FASTQ/alignment QC**: flag low mapping rate, duplication, adapter content; suggest remediation
- **MRC/map**: report resolution estimate, symmetry, map-model FSC if .pdb is also present
- **RNA-seq DEG table**: count up/down regulated genes, run quick pathway enrichment query

**3D-2 — Literature confirmation search**

Reuse the existing `research_agent.py` (PubMed/Semantic Scholar integration from MCP audit).

After analysis, for key findings (e.g. "gene TP53 variant p.R248W IMPACT=HIGH"), fire a targeted PubMed query:
- `search_pubmed("TP53 R248W pathogenicity")`
- Extract top 3 supporting/contradicting references
- Include PMID, title, year, conclusion snippet in the report

**3D-3 — Finding report generator** (backend)

`FindingReporter.generate(analysis_result, citations)` → markdown report

Structure:
```
## Findings Summary
[2–3 sentence plain-English summary]

## Key Results
| Metric | Value | Interpretation |
...

## Supporting Literature
1. [Title] (PMID:..., Year) — [one-line relevance]
...

## Caveats & Next Steps
[Flagged quality issues + suggested follow-up workflows]
```

Stored as `findings_report.md` in the run's output directory.

**3D-4 — Findings card in chat** (frontend)

New component: `client/src/components/findings-card.tsx`

Rendered in the chat when a run reaches `completed` state:
- Summary paragraph
- Collapsible key results table
- Citation list with links
- "Download full report" button → pandoc-generated PDF/DOCX
- "Continue analysis" suggestions → pre-fills chat input

Wiring: `chat-interface.tsx` polls run status; when terminal, fires `GET /api/workflows/runs/:id/findings` and renders `FindingsCard` below the workflow completion message.

**3D-5 — Findings API endpoint** (backend/frontend server)

`GET /api/workflows/runs/:id/findings`
- Checks if `findings_report.md` exists in output dir (generated post-run)
- If not: triggers `OutputAnalyzer` + `FindingReporter` + citation search (async, cached)
- Returns structured JSON: `{ summary, keyResults[], citations[], caveats[], reportUrl }`

**Files to change / create:**
- `backend/lib/galaxy/ai/output_analyzer.py` (NEW)
- `backend/lib/galaxy/ai/finding_reporter.py` (NEW)
- `frontend/server/routes.ts` — new `/findings` endpoint
- `client/src/components/findings-card.tsx` (NEW)
- `client/src/components/chat-interface.tsx` — trigger findings on run completion

---

## Implementation Order & Parallelism

| Track | Effort | Parallel with | Owner |
|-------|--------|---------------|-------|
| 3C-2 onSkip wire | 30 min | any | Agent-1 |
| 3C-1 panel hint + 3C-3 add-step | 1 h | 3A | Agent-1 |
| 3A-1 pre-execution summary | 2 h | 3C | Agent-2 |
| 3A-2/3 multi-run detection + samplesheet | 2 h | 3B | Agent-2 |
| 3B right artifact panel layout | 3 h | 3D | Agent-3 |
| 3D-1/2/3 output analyzer + citations | 4 h | 3B | Agent-4 |
| 3D-4/5 findings card + API | 2 h | after 3D-1/2/3 | Agent-4 |

---

## Key Facts for Implementation

- Pre-execution summary must work for both single-workflow (`_return_nextflow_match`) and pipeline (`isMultiIntent`) paths
- Samplesheet format: nf-core standard — `sample,fastq_1,fastq_2,strandedness` (RNA-seq), `patient,sample,lane,fastq_1,fastq_2` (sarek), etc. Varies by workflow — check `nextflow_schema.json`
- Research agent already exists: `backend/lib/galaxy/ai/agents/research_agent.py` — has PubMed + Semantic Scholar
- `pandoc` is the preferred tool for report generation (DOCX/PDF from Markdown) — see memory
- Right panel layout: use CSS `grid` with `grid-template-columns: 60fr 40fr`, collapse to single column at `< 1024px`
- The right panel should NOT re-render on every chat message — use a top-level state `activeWorkflow` that only changes when a new workflow is generated
