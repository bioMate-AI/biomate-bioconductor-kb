# Bioconductor Workflow Connections: Architecture Assessment and Plan
**Date**: 2026-06-02  
**Status**: Active planning document

---

## Part 1 — Documented Opinion: nf-core → Bioconductor Connections

> **Disclosure**: "60–70% of nf-core workflows feed outputs into Bioconductor downstream" was opinion, not code-verified. Here is what is actually verified.

**Verified from `nfcore_index.json`:** 4 of 7 indexed nf-core workflows call Bioconductor internally:

| nf-core workflow | Internal Bioconductor usage |
|---|---|
| `differentialabundance` | DESeq2, edgeR, limma, SummarizedExperiment |
| `rnaseq` | DESeq2 (normalization), dupRadar |
| `chipseq` | ChIPseeker, DESeq2 (differential peaks) |
| `diaproteomics` | MSstats |

`sarek`, `methylseq`, `mag` do not call Bioconductor internally. Their outputs commonly flow into Bioconductor in practice but that step is not implemented in BioMate.

---

## Part 2 — Naming Problem: Two Levels, Same Pattern

BioMate has two tiers of Nextflow artifact that are currently named too similarly:

| Tier | Pattern | Example | What it does |
|---|---|---|---|
| Atomic wrapper | `BIOC_<PKG>` + `BIOC_<PKG>_WORKFLOW` | `BIOC_DESEQ2_WORKFLOW` | One package, passthrough shim |
| Multi-step pipeline | `<ANALYSIS_NAME>` | `DRUG_MOA_RNASEQ` | 4 chained processes, real DAG |

`BIOC_DESEQ2_WORKFLOW` is a passthrough that calls `BIOC_DESEQ2` and re-emits its outputs. It adds no analytical value and will collide in name with any real multi-step DESeq2 pipeline.

**Naming rule (no code change needed, convention only):**
- `BIOC_<PKG>` = atomic single-package wrapper, always
- `<DOMAIN>_<ANALYSIS>` = multi-step pipeline (e.g., `RNASEQ_DE_ANALYSIS`)
- `BIOC_<PKG>_WORKFLOW` = deprecated passthrough, mark as such in headers

---

## Part 3 — What Already Exists (and Was Missed in the First Plan)

Before proposing any new work, the existing systems must be understood:

### Chain framework (`workflow_chain.py`)
The most important existing piece. Already implements:
- Sequential multi-step execution with per-step status tracking
- **Automatic output-to-input wiring** via `_apply_connection_handoffs()`: reads completed step's output files, matches extensions to next step's parameter names (`fastq → reads`, `bam → input_bam`)
- Disk-persisted chain state (`chains/<chain_run_id>.json`) — survives restarts
- Resume from any step; manual approval pauses (`end_at_step`)
- REST API: `POST /api/workflows/chain`, `GET /api/workflows/chain/{id}/outputs`

**This is the right execution engine for multi-step Bioconductor pipelines. Do not build a parallel system.**

### Workflow history (`workflow-history-dialog.tsx`, `app-sidebar.tsx`)
- Lists all user runs with status, name, timestamp, progress
- Links back to originating chat session via `chatSessionId`
- "Run again" re-executes with prior params

**This is the right UI surface. Do not build a parallel run history view.**

### SSE completion events (`nextflow_executor.py`)
`_narrate_chat()` emits `workflow.completed` (or `workflow.failed`) via SSE to the frontend when a run finishes. The event already carries `run_id`, `workflow_name`, `status`.

**This is the right trigger mechanism. Do not add a new polling loop.**

### Task list (`task-list.tsx`)
Ephemeral in-progress task display during AI orchestration. Not relevant to cross-run routing — it's operational state, not history.

### Galaxy history module
Not integrated into BioMate's chat or workflow UI. BioMate moved to Nextflow-first tracking. This is vestigial — ignore it for this plan.

---

## Part 4 — The Actual Gaps (Connection Gaps, Not System Gaps)

The existing systems cover execution, history, and triggers. Three connection gaps remain:

### Gap 1: AI context does not include recent completed runs
When a user sends a message, `routes.ts` builds the assistant context from conversation history and user preferences. It does not query `execution_runs` or the chain state. The AI cannot see that a run just finished or what outputs it produced.

**Fix**: One DB/memory query added to the context-building step in `routes.ts`. Pull the last N runs for this chat session (run name, status, output file list) and inject as a structured block alongside existing context. The `GET /api/workflows/runs/overview` endpoint already has this data — it just needs to be called at context-build time, not only by the UI.

### Gap 2: Chain definitions are static, not AI-proposed
`drug_moa_rnaseq` is a hardcoded chain. The AI cannot currently say "your rnaseq run finished and produced a count matrix — submit this as a chain: rnaseq_counts → bioc_deseq2 → bioc_clusterprofiler". The chain framework can execute such a chain; there is no path for the AI to propose one.

**Fix**: Add one AI action type — `propose_chain` — that emits a structured chain definition the frontend renders as a confirmation card. User approves → frontend calls `POST /api/workflows/chain` with the AI-generated definition. The chain executor handles everything from there.

### Gap 3: `workflow.completed` SSE does not trigger an AI context refresh
When a run finishes, the SSE fires to update the UI (spinner → check mark). It does not trigger the assistant to consider what to suggest next. The user must send a new message, and even then the AI has no run context (Gap 1).

**Fix**: When `workflow.completed` fires and the chain framework has no next step queued, the frontend checks if the AI has a pending `propose_chain` for this run. If not, it optionally sends an automatic assistant prompt: "Run `{workflow_name}` completed. Here are its outputs: `{file_list}`. What should we do next?" — with output context already injected.

---

## Part 5 — How Bioconductor Pipelines Fit Into This

The multi-step Bioconductor pipelines planned (`RNASEQ_DE_ANALYSIS`, `CHIPSEQ_PEAK_ANNOTATION`, etc.) do not need to be hardcoded chains. They are **chain templates** the AI proposes when it sees matching outputs.

**Example flow (after Gap 1 and 2 are fixed):**

```
1. User: "Run rnaseq on my FASTQ files"
   → nf-core/rnaseq runs, produces count_matrix.tsv

2. workflow.completed fires
   → Frontend injects output file list into next turn context

3. User: "What now?"
   → AI sees: count_matrix.tsv in context
   → AI emits propose_chain action:
      step 1: BIOC_DESEQ2  (input: count_matrix.tsv)
      step 2: BIOC_CLUSTERPROFILER (input: from step 1 DE results)
      step 3: BIOC_ENRICHPLOT (input: from step 2 enrichment)

4. User approves chain card
   → Frontend calls POST /api/workflows/chain with AI definition
   → Chain executor runs, auto-wiring outputs between steps
```

At the plan stage (user specifies the full pipeline upfront), the existing multi-intent detection and chain submission already handle this. The new path adds the reactive case: user sees results, asks "what next?", AI proposes the chain.

### Bioconductor pipelines as first-class chain templates

Rather than implementing `RNASEQ_DE_ANALYSIS` as a monolithic Nextflow workflow, register it as a **named chain template** in the chain framework:

```json
{
  "chain_name": "rnaseq_de_analysis",
  "display_name": "RNA-seq → Differential Expression → Pathway Enrichment",
  "steps": [
    {"workflow": "BIOC_DESEQ2",        "input_from": null},
    {"workflow": "BIOC_CLUSTERPROFILER", "input_from": 1},
    {"workflow": "BIOC_ENRICHPLOT",      "input_from": 2}
  ],
  "trigger_on_output_types": ["tsv", "count_matrix"]
}
```

This reuses the chain executor entirely. The AI proposes the template name; the user approves; the chain framework wires and runs it.

---

## Part 6 — Revised Implementation Sequence

All work builds on existing systems. Nothing new is built from scratch.

### Phase 1 — Naming convention (no code)
- Mark all `BIOC_<PKG>_WORKFLOW` passthroughs as deprecated in their file headers
- Establish: `BIOC_*` = atomic, analysis-intent name = pipeline

### Phase 2 — Close Gap 1: run context in AI
- In `routes.ts` context-building block, add query for the last 3–5 completed runs in this chat session
- Inject as structured block: `run_name`, `status`, `output_files[]`, `completed_at`
- Small change, high leverage — the AI immediately knows what just ran

### Phase 3 — Close Gap 2: `propose_chain` AI action
- Add `propose_chain` to the AI action type set
- Frontend renders it as a chain confirmation card (similar to existing workflow card)
- On approval, calls existing `POST /api/workflows/chain`
- AI learns to emit this when it sees output types matching known chain templates

### Phase 4 — Chain templates for Bioconductor pipelines
- Register 4–6 named chain templates in the chain framework config:
  - `rnaseq_de_analysis`: BIOC_DESEQ2 → BIOC_CLUSTERPROFILER → BIOC_ENRICHPLOT
  - `chipseq_annotation`: BIOC_GENOMICRANGES → BIOC_CHIPSEEKER → BIOC_CLUSTERPROFILER
  - `scrna_cluster`: BIOC_SCE → BIOC_SCATER → BIOC_SCRAN → BIOC_UWOT
  - `variant_annotation`: BIOC_VARIANTANNOTATION → BIOC_ENSEMBLDB
  - `methylation_dm`: BIOC_MINFI → BIOC_DSS → BIOC_MISSMETHYL
  - `proteomics_de`: BIOC_MSNBASE → BIOC_LIMMA → BIOC_MSSTATS
- These are JSON chain definitions, not new Nextflow workflows

### Phase 5 — Close Gap 3: completion-triggered suggestion (optional)
- When `workflow.completed` SSE fires and no chain step is queued, frontend sends automatic context message
- Low priority — Phase 2 already enables the user to ask "what next?" with full run context

### Phase 6 — Typed inputs for top wrappers (incremental, not blocking)
- Replace opaque `count_data` with typed inputs for top 10 packages
- Add `qc.json` emit to each — feeds existing auto-loop QC system
- Work in parallel with other phases, not a dependency

---

## What Was Wrong in the Previous Plan

1. **Proposed building a new "output type → next workflow mapping" system** — the chain framework's `_apply_connection_handoffs()` already does this via file extension matching
2. **Proposed building new SSE triggers** — `_narrate_chat()` already fires `workflow.completed`  
3. **Missed that chain definitions are the right unit** — proposed monolithic Nextflow workflows where chain templates would be simpler and reuse the existing executor
4. **Did not account for workflow history dialog** — which is already the right UI for run browsing
5. **Did not account for the AI action type system** — `propose_chain` fits naturally into the existing `needsWorkflowGeneration`, `needsToolSearch` action flag pattern
