# Workflow Selection & Generation — Architecture Plan
**Date**: 2026-03-18
**Status**: DRAFT — awaiting review
**Branch**: bioconductor_skill
**Context**: Addressing 8 architectural questions raised after reviewing the RNA-seq scoring root cause and audit knowledge

---

## Answers to the 8 Questions

---

### Q1. `domain_workflow_patterns.py` — what does it do, and is it reliable?

**What it does**
`domain_workflow_patterns.py` detects the user's analysis domain by counting keyword hits in the query string. Intent keywords score +2, tool keywords score +1; if no domain exceeds threshold 2, it returns GENERAL. It also provides required phase sequences per domain (e.g. TRANSCRIPTOMICS: QC → Preprocess → Align → Quantify → DE), which the LLM uses as a workflow structure hint.

**Is it reliable?**
**No — for the same reason we removed `_DOMAIN_KEYWORD_MAP`.**
The scoring is still keyword-count based. "RNAseq" or "DESeq" triggering `transcriptomics` is fine, but:
- Ambiguous queries produce GENERAL (no useful signal)
- Biological context terms (disease names, accession IDs) contaminate the signal
- It has zero knowledge of the 2,284 workflows actually in the DB
- Expert review data (7 domains, 140 packages, Kappa 0.718–0.868) shows the hardest cases are cross-domain misclassifications (e.g. single-cell vs bulk, epigenomics vs genomics, proteomics vs metabolomics) — exactly where keyword counting fails

**Proposed role going forward**
Keep the **phase sequence templates** as LLM guidance context (they encode bioinformatics best practices). **Remove** keyword-based domain detection from the search path entirely — replace with LLM intent extraction (Q2 → LLM returns explicit `analysis_type` and `data_format`).

---

### Q2. FTS on raw query — what is it, and why is it problematic?

**What it is**
`_build_fts_query()` tokenizes the entire user query into OR-joined FTS5 tokens, then scores via BM25. For the RNA-seq GEO query, this produced:

| Rank | Workflow | BM25 score |
|------|----------|------------|
| 1 | Geo Data Connector | −30.74 |
| 41 | **nf-core/rnaseq** | **−8.11** |

**Why it fails**
BM25 rewards **term rarity × frequency in document**. The user's biological context terms (`GSE68086`, `adenocarcinoma`, `lung`) are rare in the workflow corpus → huge IDF boost → workflows whose descriptions mention them (Geo Data Connector) score high even though they are data-fetch utilities, not analysis pipelines.

**Proposed fix**
**Stop feeding the raw user query into FTS.** Instead:
1. LLM extracts `search_terms` — workflow-vocabulary equivalents (e.g. "RNA-seq differential expression STAR featureCounts DESeq2") — not the user's biological context
2. FTS runs on `search_terms` only
3. Raw query BM25 is abandoned entirely

This directly addresses Root Cause #1 from the colleague's doc.

---

### Q3. Workflow counts — what is the correct number?

| Source | Count | Description |
|--------|-------|-------------|
| `nfcore` | 100 | Full nf-core pipelines (rnaseq, sarek, chipseq, …) |
| `nfcore_subwf` | 93 | nf-core composite subworkflows |
| `biomni_nextflow` | 268 | BioMate domain analysis workflows |
| `bioconductor` | 1,818 | Bioconductor R package NF wrappers |
| `galaxy_biomni` | 2 | Legacy |
| **Total** | **2,284** | In `galaxy_ai_tools.db` |

On disk: **2,771 `.nf` files** (difference = not yet indexed).

**For the catalog browse (LLM workflow selector)**: Use the **461 non-bioconductor nextflow workflows** (nfcore + nfcore_subwf + biomni_nextflow). Bioconductor wrappers are R-package level, useful for Bioconductor skill generation but not end-user workflow selection. Their catalog at ~150k tokens would overflow Haiku's context.

**For FTS fallback**: Include all 2,284 with appropriate source priority weights (nfcore=100, bioconductor=75, etc.).

---

### Q4. Clarification question — what are the criteria?

Clarification is needed when the query contains a **decision fork** that changes which workflow is selected or how it is parameterized. The criteria come from two sources:

**A. Workflow selection forks** (from expert review disagreement patterns + existing `workflowAmbiguity`)
| Fork | Trigger | Question |
|------|---------|----------|
| Bulk vs single-cell RNA-seq | RNA-seq with no cell count / droplet mention | "Is this bulk RNA-seq or single-cell?" |
| Somatic vs germline variant | "mutations", "variants", "SNVs" without tumor/normal or inherited context | "Are you looking for somatic (cancer) or germline (inherited) variants?" |
| Raw reads vs count matrix | GEO accession + DE analysis requested | "Do you have raw FASTQ reads, or a pre-computed count matrix?" |
| Targeted vs untargeted proteomics | Proteomics query without specificity | "Is this targeted (known analytes) or untargeted (discovery) proteomics?" |
| ChIP-seq vs ATAC-seq | "chromatin accessibility" or "open chromatin" ambiguity | "Is this ChIP-seq (histone marks/TF binding) or ATAC-seq (chromatin accessibility)?" |

**B. Parameter data gaps** (from `parameter_context_requirements.json` `user_providable` entries)
When a workflow requires `user_providable` parameters (file paths, genome version, sample grouping) that cannot be inferred from the query. Example: user says "run RNA-seq" but doesn't specify the reference genome or sample metadata.

**Criteria for NOT asking**:
- Query explicitly specifies the fork (e.g. "somatic variant calling" → no fork question)
- A previously stored user context resolves it (e.g. prior session said "hg38")
- The parameter has a safe default with low impact on results

**Implementation**: The LLM catalog browser returns `clarification_question: str | None` — non-null only for the above decision forks. This is propagated through `search_nextflow_workflow` → `galaxy-assistant.ts` → early-exit before `generateWorkflow()`, as `workflowAmbiguity` already does.

---

### Q5. Expert knowledge — rationale, citation, and user editability

**Current state**
`tool_knowledge` table: 4,117 entries. Each has `parameters` JSON with `recommended_value`, `citation` (DOI/PMID), `rationale`, `use_cases`, `limitations`, `alternatives`. No UI exists. Users cannot view or edit.

**Problems**
1. Expert recommendations are applied silently — user sees a parameter value but not WHY
2. No way for a domain expert user to override a recommendation with their own citation
3. Citations are stored but not shown in the workflow review UI

**Proposed architecture**

**A. Show citations in workflow review panel**
In `nextflow-workflow-viewer.tsx`, when a parameter was auto-filled by expert knowledge, show:
```
dedup_method: picard  [info icon]
  → Recommended: picard
  → Rationale: Picard MarkDuplicates standard for RNA-seq
  → Citation: PMID:20644199 (Picard toolkit)
  → [Override]
```

**B. User override with annotation**
Clicking [Override] opens an inline editor:
- New value field
- Reason field (free text, e.g. "Our protocol uses UMIs, samblaster is better")
- Overrides stored per-user, per-workflow in `user_param_overrides` table
- When user's override exists → shown with yellow "User override" badge; system recommendation shown as strikethrough

**C. Admin knowledge editing** (phase 2)
`GET/POST /api/admin/tool-knowledge/:tool_name` → view and edit `tool_knowledge` entries. Requires admin role. Changes version-tracked in `tool_knowledge_history` table.

---

### Q6. Workflow modification flexibility

**Current state**
Users can adjust parameter values via chat (`POST /api/workflow/adjust-params`), but cannot:
- Remove a step from the pipeline
- Substitute a tool (e.g. STAR → HISAT2 for alignment)
- Run a parameter range/sweep
- Add a step not in the original workflow

**Why this matters**
The expert review showed 390 disagreeing steps across 117 packages — meaning even "standard" workflows have legitimate alternative configurations. Users from different labs use different tools.

**Proposed architecture**

**A. Step-level tool substitution** (high value, medium effort)
When a workflow has a step with a tool that has documented alternatives (from `tool_knowledge.alternatives`):
- Show [Alternative tools] chip in PhaseCard
- Dropdown: "STAR → HISAT2 → Salmon (mapping-based)"
- Selecting an alternative: backend generates a modified `.nf` file with the alternative tool's process block, or routes to a different pre-built workflow variant

**B. Step removal** (medium value, low effort)
In AWAITING REVIEW, each PhaseCard gets a [Skip step] toggle. Skipped steps are passed as `skip_steps: ["TRIMGALORE"]` in the execution request. Backend maps this to Nextflow params: `params.skip_trimming = true` (most nf-core workflows have skip flags).

**C. Parameter range / sweep** (high value, high effort — phase 3)
Grid search or Latin hypercube sampling across a parameter range. Each combination spawns a child run. Requires a sweep orchestrator backend and result comparison UI. Not in scope for this plan.

**D. Chat-driven pipeline modification** (medium effort)
Extend `POST /api/workflow/adjust-params` to also accept structural changes:
- "Remove the deduplication step" → parses intent, sets `skip_steps += ["MARKDUPLICATES"]`
- "Use HISAT2 instead of STAR" → routes to HISAT2 workflow variant or patches aligner param

---

### Q7. nf-core output visualization — templates vs. reality

**Reality check (from codebase exploration)**

nf-core workflows have:
- `assets/email_template.html` — a summary email with per-sample QC stats
- Per-module `output.yml` / `output.md` — listing output file names, formats, descriptions
- **MultiQC is NOT embedded in main.nf for most workflows** — it is a separate optional step (`--skip_multiqc` flag exists), meaning it produces `multiqc_report.html` as an output file

**What BioMate is not leveraging**
1. `output.yml` — each nf-core module documents what files it produces (BAM, VCF, TSV, HTML). We could pre-parse these to know expected outputs before the run, enabling better `classifyFileType` and interactive tool routing.
2. `multiqc_report.html` — when present in S3 outputs, BioMate currently classifies it as a generic HTML file. Should be detected and rendered with a dedicated MultiQC viewer (or link to the HTML in an iframe).
3. `email_template.html` — contains structured QC tables (% mapped, duplication rate, etc.) that could feed the QC gate comparisons.

**Proposed fixes**

**A. Pre-parse expected outputs** (immediate, low effort)
`index_all_workflows.py`: when indexing an nf-core workflow, read `output.yml` from each included module. Store expected output file patterns in `workflows.output_patterns` JSON column. Use these patterns in `addS3OutputFiles()` to pre-label files by type.

**B. MultiQC HTML detection** (immediate, low effort)
In `classifyFileType()`: if filename is `multiqc_report.html` → type `'multiqc'`. Add `MultiqcViewer` component (iframe + download button). Wire into `isVisualizable()`.

**C. nf-core output summary card** (medium effort)
After workflow completion, show a structured summary card built from `output.yml` expected vs. actual files. Highlights which expected outputs are present/missing.

---

### Q8. Connecting multiple workflows together

**Current state**
No user-facing multi-workflow orchestration. Nextflow `include` directive handles it at the `.nf` level (e.g. `run_tests.nf` imports 20+ subworkflows). BioMate has no concept of a "pipeline of pipelines."

**When is chaining needed?**
- GEO data fetch → RNA-seq alignment → differential expression → pathway enrichment
- Variant calling → annotation → drug target analysis
- Raw proteomics → peptide identification → protein quantification → network analysis

Each step is a separate workflow in BioMate's catalog.

**Proposed architecture**

**A. Linear chain (phase 1 — medium effort)**
In the AWAITING REVIEW panel, if the AI detects the user's query spans multiple workflow types:
1. Show a "Workflow Chain" view listing N steps (each a separate workflow card)
2. Each step's output type must match next step's input type (validated by `output_patterns` from Q7-A)
3. "Run All" executes them sequentially: step N+1's input params auto-filled from step N's S3 output URIs

Backend: `POST /api/workflows/chain` — accepts `[{nextflow_path, params}, ...]`, executes sequentially, each step polls for completion before starting next. Returns a chain run ID that aggregates status.

**B. Output-as-input wiring** (prerequisite — low effort)
`POST /api/workflows/runs/:id/resolve-outputs` — given a completed run ID and a candidate next-workflow path, auto-matches S3 output files to the next workflow's input params by file extension + `output_patterns`.

**C. AI chain planner** (phase 2 — high effort)
When user query implies a multi-step analysis, the catalog browser LLM returns an ordered list of workflow names (not just one). The UI shows these as a chain for user review before execution. This requires extending `_browse_catalog_with_llm()` to return `selected_names: List[str]` in order.

---

## Proposed New Architecture for Workflow Selection

```
User Query
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  Step 1: LLM Intent Extraction (Claude Haiku, ~200ms)   │
│                                                          │
│  Input: raw user query                                   │
│  Output:                                                 │
│    analysis_type: "differential_expression"             │
│    data_format:   "raw_fastq" | "count_matrix" | ...    │
│    search_terms:  "RNA-seq alignment quantification DESeq2"│
│    workflow_fork: "rnaseq_type" → triggers Q4           │
│    clarification: "Do you have raw FASTQ or count matrix?"│
└──────────────────────────────────────────────────────────┘
    │
    ├─── if clarification_needed → return question to user
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  Step 2: Catalog Browse (Claude Haiku, ~1-2s)           │
│                                                          │
│  Input: analysis_type + data_format + search_terms       │
│         + catalog of 461 nextflow workflows              │
│         + domain phase sequences (from domain_patterns)  │
│         + relevant tool_knowledge entries                │
│  Output:                                                 │
│    selected: ["nf-core/rnaseq", "nf-core/differentialabundance"]│
│    confidence: "high" | "medium" | "low"               │
│    chain: true (multiple workflows needed)              │
└──────────────────────────────────────────────────────────┘
    │
    ├─── high confidence, single match → go to Step 4
    ├─── medium/low confidence → go to Step 3
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  Step 3: FTS Validation (SQLite, ~50ms)                 │
│                                                          │
│  Input: search_terms (NOT raw query)                    │
│  Purpose: confirm selected workflows exist in DB, fetch  │
│           full metadata, find alternatives if needed    │
│  Output: WorkflowMatch objects with full workflow_json  │
└──────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  Step 4: LLM Reranker (Claude Haiku, ~500ms)            │
│                                                          │
│  Window: top 20 candidates (expanded from 10)           │
│  Context: analysis_type, data_format, tool_knowledge    │
│           rationale for each candidate                  │
│  Output: ranked list with per-candidate explanation     │
└──────────────────────────────────────────────────────────┘
    │
    ▼
  Best match → AWAITING REVIEW
```

---

## Files to Change

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Replace Pass 0 name-match with `_browse_catalog_with_llm`; update `_classify_intent_with_llm` to return `analysis_type`, `data_format`, `search_terms`; use `search_terms` (not raw query) in FTS; apply colleague's fixes (window→20, remove `'de'`, fix nfcore path); propagate `clarification_question` in return value |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Propagate `clarification_question` from search result; pass `analysis_type`+`data_format` to workflow generation |
| `frontend/server/galaxy-assistant.ts` | Receive `clarification_question` from search result; early-exit to ask user (like existing `workflowAmbiguity`) |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Show expert knowledge citation inline per parameter; [Override] flow; Skip step toggle |
| `frontend/server/routes.ts` | `classifyFileType` multiqc detection; chain execution endpoint |
| `backend/scripts/index_all_workflows.py` | Parse nf-core `output.yml` to populate `output_patterns` |

---

## What NOT to Build (Explicitly Descoped)

- `domain_workflow_patterns.py` keyword-based domain detection as a search path (keep only phase templates as LLM context)
- Any new keyword maps, stopword lists, or hardcoded domain→workflow routing tables
- FTS on raw user query (BM25 anti-pattern confirmed by colleague's root cause)
- Parameter sweep / grid search (defer to phase 3)
- Admin knowledge editing UI (defer to phase 2)
- Multi-workflow chain planner (defer, Phase 1 only for manual linear chains)

---

## Immediate Wins (Colleague's Fixes — Apply First, ~30min)

These are low-risk, high-confidence fixes confirmed by the root cause analysis:

1. **Reranker window → 20** (line ~317): `top_candidates = results[:20]`
2. **Remove `'de': 2.0` keyword** — substring false positive
3. **Fix `_nextflow_workflow_key` for `nextflow_nfcore/` paths** — so biomni nfcore-format workflows appear as runnable

These should be committed separately from the larger architecture changes.
