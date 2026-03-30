# Workflow Selection — Simulation, Gap Analysis & Flexible Architecture
**Date**: 2026-03-18
**Context**: Working through the proposed LLM-catalog architecture using real use cases in simulation to find unnoticed problems, and designing truly flexible workflow modification.

---

## Part 1: Simulations — What Actually Happens

---

### Simulation 1: The RNA-seq GEO case (the documented failing case)

**User query**: "I want to identify differentially expressed genes in lung adenocarcinoma. I have a publicly available RNA-seq dataset (GEO accession GSE68086) comparing tumor vs normal lung tissue (n=58 samples). Please run a complete RNA-seq DE and pathway enrichment analysis with adjusted p-value < 0.05 and |log2FC| > 1."

**Proposed Step 1 — LLM Intent Extraction**
- Returns: `analysis_type: "differential_expression"`, `search_terms: "RNA-seq alignment quantification differential expression DESeq2"`
- **Missed**: the query implies TWO phases: (1) download raw data from GEO/SRA, (2) run the analysis pipeline. Intent extraction sees "differential expression" but not "I need to fetch data first."
- **Missed**: data format is ambiguous — GEO accession GSE68086 could be raw FASTQ (via SRA), processed count matrices, or both. The intent extractor needs to trigger clarification here.

**Proposed Step 2 — Catalog Browse**
- Catalog currently queries `WHERE format = 'nextflow'` — this returns ALL 2,284 workflows including 1,818 bioconductor_nf. At ~30 tokens each, that is ~70k tokens — **exceeds Haiku's practical input limit for a well-structured prompt**.
- Fix: catalog must filter to `source IN ('nfcore', 'nfcore_subwf', 'biomni_nextflow')` → 461 workflows, ~14k tokens. **The catalog filter in `_get_workflow_catalog()` is wrong.**
- Haiku sees "Geo Data Connector: Fetch GEO datasets", "nf-core/rnaseq: RNA-seq pipeline", "nf-core/differentialabundance: DE analysis"
- **Problem**: catalog shows only names + 80-char descriptions. Haiku CANNOT tell that nf-core/rnaseq requires FASTQ inputs while differentialabundance requires a count matrix. Without input/output type information in the catalog, Haiku may select differentialabundance (sounds more specific to DE) when the user actually needs rnaseq (has raw FASTQ).
- This is the ROOT cause of the original bug, just moved from FTS to LLM. The catalog is still blind to data format requirements.

**Proposed Step 3 — Name lookup**
- `_fetch_workflows_by_names()` does an exact SQL `WHERE name IN (...)`. Haiku returns "nf-core/rnaseq" but the DB stores it as "Rnaseq" (or whatever the index script wrote). **Exact name match fails silently** — returns empty list, falls back to FTS (original problem).

**Unnoticed problems in Simulation 1:**
1. Catalog includes 1,818 irrelevant bioconductor workflows → token overflow
2. Catalog descriptions have no input/output type info → wrong workflow selected for wrong data format
3. Exact name match between LLM output and DB is fragile
4. The two-workflow need (data download + analysis) is not detected

---

### Simulation 2: User wants to add a step AFTER seeing the workflow card

**Scenario**: User gets nf-core/rnaseq AWAITING REVIEW. They say: "After RNA-seq, I also want GSEA pathway enrichment and WGCNA co-expression analysis."

**What happens now**: This goes through the chat. `_looks_like_multi_task` catches "also". `_handle_multi_task_clarification` calls `TaskDecomposer`. But the user already has a workflow in AWAITING REVIEW — the system doesn't know to APPEND to it. It generates a new message with a fresh workflow card, leaving the old one hanging.

**Data dependency problem**: Even if we detect 3 workflows (rnaseq → GSEA → WGCNA), the chain requires:
- rnaseq output: `{results}/star_salmon/salmon.merged.gene_counts_scaled.tsv` → WGCNA input (count matrix)
- rnaseq output: DEG table (gene, log2FC, padj) → needs to become `.rnk` file for GSEA (gene + ranking stat)

The GSEA input format (`.rnk`) is NOT the same as the DESeq2 output. **Format conversion step is missing from the chain.** No existing workflow in BioMate does this conversion. The user doesn't know they need it.

**Unnoticed problems in Simulation 2:**
1. No concept of "amend the current AWAITING REVIEW workflow with more steps"
2. Chain steps have typed input/output formats — auto-wiring requires format compatibility knowledge
3. Format conversion steps may be needed but are invisible to the user
4. Step ordering matters: WGCNA can run in parallel with GSEA (both take rnaseq outputs), but the current chain architecture is strictly sequential

---

### Simulation 3: Chat-driven modification

**Scenario A**: User in AWAITING REVIEW says "Actually, skip the adapter trimming. Also use HISAT2 instead of STAR."

**What happens now**: Goes to `POST /api/workflow/adjust-params` (Haiku call, returns updated params JSON). This endpoint knows only about PARAMETER VALUES — it has no knowledge that:
- nf-core/rnaseq has `--skip_trimming` flag (maps to "skip adapter trimming")
- nf-core/rnaseq has `--aligner [star_salmon, hisat2, star]` (maps to "use HISAT2")

The Haiku call in `adjust-params` does NOT have the workflow's parameter schema as context. It returns something like `{"skip_trimming": true, "aligner": "hisat2"}` but the actual nf-core/rnaseq params may be `{"skip_trimqc": false, "aligner": "hisat2"}`. Case mismatch, name mismatch — silent failure.

**Scenario B**: User says "Add pathway enrichment after the RNA-seq."

This is NOT a parameter change. It's a new workflow to chain. `adjust-params` cannot handle it — it only returns a modified params dict for the SAME workflow. The endpoint has no output channel for "also add workflow X to the chain."

**Scenario C**: User says "Remove the variant calling step."

Same problem as B. Step removal is structural, not parametric.

**Unnoticed problems in Simulation 3:**
1. `adjust-params` has no workflow parameter schema → can't reliably map natural language to correct flag names
2. `adjust-params` can only return parameter value changes, not structural modifications (add/remove steps)
3. No distinction between: change a value, skip a step, add a workflow, change a tool
4. After a workflow is confirmed and running, there is NO modification path at all

---

### Simulation 4: Parameter range / sweep

**User query**: "Run DESeq2 with adjusted p-value thresholds of 0.01, 0.05, and 0.1. Show me how many DEGs I get at each cutoff."

**What happens**: The user's request mentions three specific values for one parameter. `adjust-params` doesn't parse this. Even if it did, there's no "sweep" concept in the execution backend — only one `padj` value can be passed per run. The system would run a single workflow with the last value mentioned (0.1), or fail to parse entirely.

**What the user actually needs:**
- 3 separate DESeq2 runs: padj=0.01, 0.05, 0.1
- All 3 share the same alignment + quantification outputs (cost optimization via -resume)
- A comparison table after all 3 complete: N DEGs at each threshold, Venn diagram of overlap

**Unnoticed problems in Simulation 4:**
1. No sweep orchestrator exists
2. No mechanism to share upstream work across sweep runs (requires -resume + shared work_dir)
3. No result aggregation UI — user would have to mentally compare 3 separate workflow cards
4. The sweep request looks like a normal chat message — no specialized UI to express "test these 3 values"

---

### Simulation 5: Multi-turn modification context loss

**Turn 1**: User asks for RNA-seq analysis. Gets nf-core/rnaseq card. Confirms and runs.
**Turn 2**: User says "Run it again but exclude the 5 outlier samples."
**Turn 3**: User says "This time also increase the memory to 64GB per task."

**Problem**: The system has no memory of which workflow was run in Turn 1. Turn 2 and Turn 3 are treated as fresh queries. There is no "previous run context" thread that connects:
- The workflow that was confirmed
- Its current parameters
- The user's incremental modifications across turns

Each modification requires the user to re-specify the full intent. This is the opposite of the conversational flexibility they expect.

---

## Part 2: Root Problems (Consolidated)

From all 5 simulations, the fundamental gaps are:

| # | Problem | Current state | Impact |
|---|---------|--------------|--------|
| P1 | Catalog includes all 2,284 NF workflows → token overflow | `WHERE format='nextflow'` | Breaks catalog browse for large catalog |
| P2 | Catalog has no input/output data type info | 80-char description only | Wrong workflow selected for wrong data format |
| P3 | LLM name → DB name is fragile (exact match) | SQL `WHERE name IN (...)` | Catalog browse silently returns empty |
| P4 | No "amend current AWAITING REVIEW" concept | Only generates new card | User can't add steps mid-review |
| P5 | `adjust-params` has no parameter schema context | Haiku guesses flag names | Wrong param names in adjusted output |
| P6 | `adjust-params` is params-only, no structural changes | Returns dict only | Can't add/remove steps, can't add chain |
| P7 | No sweep/range concept anywhere | Not implemented | Parameter exploration impossible |
| P8 | No run context thread across turns | Each query is fresh | Incremental modification breaks |
| P9 | Chain data types not validated | No type system | Format mismatch breaks chain silently |
| P10 | Two-workflow needs (fetch + analyze) not detected | Single workflow selection | User gets wrong scope |

---

## Part 3: The Flexible Architecture

The shift required is: from **"select one workflow, fill its params"** to **"compose a pipeline from typed components, iterate with the user."**

---

### 3.1 WorkflowSession — the missing persistent context

Every AWAITING REVIEW state needs a server-side session object:

```python
@dataclass
class WorkflowSession:
    session_id: str            # UUID, stored in frontend + backend
    created_at: datetime

    # The composed pipeline (1..N steps)
    steps: List[WorkflowStep]  # ordered, typed

    # What the user has told us so far
    user_intent: str           # original query
    data_format: str           # "raw_fastq" | "count_matrix" | "vcf" | ...
    organism: str | None
    clarifications: Dict[str, str]  # Q → A pairs from conversation

    # Execution state
    confirmed: bool
    run_ids: List[str]         # child run IDs once executed

@dataclass
class WorkflowStep:
    workflow_name: str
    workflow_path: str         # nextflow path
    params: Dict[str, Any]
    skip_steps: List[str]      # e.g. ["MARKDUPLICATES"]
    input_type: str            # typed: "raw_fastq", "count_matrix", ...
    output_type: str           # typed: "count_matrix", "deg_list", ...
    status: str                # pending | running | complete | failed
    run_id: str | None
```

Stored in Redis (or Postgres). Referenced by `session_id` in all subsequent messages.

---

### 3.2 Catalog with data type annotations

The catalog text shown to the LLM must include input/output types:

```
[transcriptomics]
  - nf-core/rnaseq [in: raw_fastq → out: count_matrix, deg_list] Full RNA-seq: alignment, quantification, QC
  - nf-core/differentialabundance [in: count_matrix → out: deg_list] Differential expression from pre-computed counts
  - Geo Data Connector [in: geo_accession → out: raw_fastq] Downloads GEO/SRA datasets as FASTQ
  - GSEA Pathway Enrichment [in: deg_list → out: pathway_results] Gene set enrichment analysis
  - WGCNA Co-expression [in: count_matrix → out: gene_modules] Weighted gene co-expression network analysis
```

This is ~5-10 tokens of overhead per workflow but completely changes what the LLM can reason about. It can now detect:
- "User has GEO accession + wants DE" → needs Geo Data Connector [geo_accession→raw_fastq] THEN nf-core/rnaseq [raw_fastq→count_matrix] THEN differentialabundance [count_matrix→deg_list]
- The chain is inferred from data type compatibility

Input/output types are added to the workflows DB table (`input_types`, `output_types` columns, JSON arrays). Populated by `index_all_workflows.py` reading `output.yml` and known schema.

---

### 3.3 Fuzzy name resolution

`_fetch_workflows_by_names()` must not rely on exact match:

```python
def _fetch_workflows_by_names(self, names: List[str], ...) -> List[WorkflowMatch]:
    # 1. Try exact match first
    # 2. If any names missing: normalize (lowercase, strip punctuation, strip "nf-core/")
    #    and try fuzzy match against all workflow names
    # 3. Rank fuzzy matches by similarity score > 0.8
    # 4. Log any unresolved names as warnings
```

Use `difflib.get_close_matches()` already imported in the file.

---

### 3.4 Structured modification — not just `adjust-params`

The chat modification endpoint needs to classify the request type FIRST, then dispatch:

```
User modification request
        │
        ▼
LLM classify modification type:
  - "value_change": change param X to Y
  - "skip_step": skip/remove a step by name
  - "add_workflow": add another workflow to the chain
  - "change_tool": swap tool X for tool Y within same step
  - "sweep": run with multiple values of param X
        │
        ├── value_change → update WorkflowStep.params[key] = new_value
        │
        ├── skip_step → WorkflowStep.skip_steps.append(step_name)
        │              map natural name → nf-core skip flag via schema
        │
        ├── add_workflow → catalog browse for the additional workflow
        │                  validate data type compatibility with last step's output_type
        │                  append new WorkflowStep to WorkflowSession.steps
        │
        ├── change_tool → look up tool alternatives in tool_knowledge
        │                 check if it's a param change (--aligner) or requires different workflow
        │
        └── sweep → extract parameter name + value list
                    create SweepConfig (see 3.5)
```

The key: each modification type has its own handler with its own context (schema, alternatives, type system). NOT a single "call Haiku with the user's text and hope it produces valid JSON."

**Schema context for `value_change` and `skip_step`:**
When the user says "skip trimming", the handler looks up the workflow's skip flags:
```json
{
  "nf-core/rnaseq": {
    "skip_flags": {
      "trimming": "--skip_trimming",
      "deduplication": "--skip_markduplicates",
      "multiqc": "--skip_multiqc",
      "umi": "--skip_umi_extract"
    }
  }
}
```
This mapping is pre-built from nf-core parameter schemas (each nf-core pipeline has `nextflow_schema.json`). Stored in the workflow's `workflow_json.skip_flags`. Modification handler reads this instead of guessing.

---

### 3.5 Parameter sweep

**User expression** (natural language or structured):
- "Run with padj = [0.01, 0.05, 0.1]"
- "Test three thresholds: 0.01, 0.05, 0.1"
- "Sweep memory from 8GB to 64GB in steps of 8"

**SweepConfig object:**
```python
@dataclass
class SweepConfig:
    session_id: str
    sweep_param: str           # e.g. "padj_threshold"
    sweep_values: List[Any]    # [0.01, 0.05, 0.1]
    share_upstream: bool       # True = share alignment/quantification via -resume
    base_run_id: str | None    # run_id of the upstream run to resume from
```

**Execution:**
1. Run the upstream steps (alignment + quantification) ONCE → get `base_run_id` + `work_dir`
2. For each value in `sweep_values`, submit a child run with `-resume -w {work_dir}` + the swept parameter overridden
3. All child runs share Nextflow's cache → only the DE step re-executes per value

**Result view:**
A new `SweepResultsPanel` component shows a comparison table:
```
padj threshold | DEGs found | Up-regulated | Down-regulated | Runtime
0.01           |    842     |    391       |      451       |  4m 12s
0.05           |   1,847    |    876       |      971       |  4m 08s
0.1            |   2,531    |   1,203      |     1,328      |  4m 05s
```
Plus a Venn diagram (3-circle) showing overlap between the DEG lists.

---

### 3.6 AWAITING REVIEW panel redesign — Pipeline View

The current AWAITING REVIEW panel shows ONE workflow card. With chains and sweeps, it needs to show a pipeline:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PIPELINE — RNA-seq Differential Expression + Pathway Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Geo Data Connector               [raw_fastq]→  [Edit ×]
  GEO accession: GSE68086
  Output: 58 FASTQ pairs → s3://biomate-nextflow-work/...

        ↓ raw_fastq

Step 2: nf-core/rnaseq                   [count_matrix]→  [Edit ×]
  genome: GRCh38   aligner: STAR (salmon quantification)
  skip: [✓ trimming?] [□ dedup] [□ multiqc]
  ▸ Advanced params...

        ↓ deg_list  +  count_matrix (parallel)
       ╱                            ╲
Step 3: GSEA Pathway Enrichment    Step 4: WGCNA Co-expression
  [deg_list]→                        [count_matrix]→
  padj: [0.01 | 0.05 | 0.1] SWEEP    min_module_size: 30

                      ↓ (all complete)
                  [+ Add Step]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Adjust via Chat]                    [Confirm & Run Pipeline]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Key elements:
- Steps shown in order with data-type arrows between them
- Parallel branches shown side-by-side
- Sweep indicator on parameter fields (inline "| 0.01 | 0.05 | 0.1 | SWEEP" renders as a chip)
- `[+ Add Step]` opens a mini catalog search
- `[×]` on each step removes it (with data type validation — removing a middle step breaks the chain)
- `[Edit]` on each step expands its parameter panel inline

---

### 3.7 Chat as workflow editor

Chat messages in the context of an active WorkflowSession are parsed differently from fresh queries:

```
Active session detected (session_id in context)
        │
        ▼
Modification classifier (Haiku, fast, <200ms):
  Input: current session state (steps + params) + user message
  Output: {type, step_index, param_name, new_value, ...}
        │
        ├── If type == "value_change":
        │     Update session.steps[i].params[param] = value
        │     Return updated pipeline card (no full regeneration)
        │
        ├── If type == "skip_step":
        │     Map natural name → skip flag via nf-core schema
        │     Toggle step visibility in pipeline view
        │
        ├── If type == "add_workflow":
        │     Run catalog browse for the new step
        │     Validate data type: new_step.input_type == last_step.output_type
        │     If incompatible: suggest format converter or ask user
        │     Append to session.steps; return updated pipeline card
        │
        ├── If type == "change_tool":
        │     Check tool_knowledge.alternatives for the current tool
        │     If alternative is a param change: update param
        │     If alternative requires different workflow: swap step
        │
        ├── If type == "sweep":
        │     Extract param + values
        │     Create SweepConfig; show inline sweep indicator on param
        │
        └── If type == "unrelated" (fresh query):
              Start a new WorkflowSession (fresh flow)
```

The session_id is stored in the frontend's conversation context and passed in every API call. This is the thread that gives the system memory across turns (Simulation 5's gap).

---

## Part 4: Implementation Priority

### Tier 1 — Fix silent failures (do first, unblocks everything)

1. **Fix catalog filter** (`_get_workflow_catalog`): add `AND w.source IN ('nfcore','nfcore_subwf','biomni_nextflow')` → reduces catalog from 2,284 to 461 workflows
2. **Add fuzzy name resolution** (`_fetch_workflows_by_names`): `difflib.get_close_matches` fallback
3. **Add input/output type to catalog text**: parse from workflow JSON or known schema; add `[in: X → out: Y]` to each catalog line

### Tier 2 — WorkflowSession + structured modification

4. **`WorkflowSession` backend model + Redis storage** + session_id in API context
5. **Modification classifier endpoint** (`POST /api/workflow/modify`): replaces `adjust-params`; routes to type-specific handlers
6. **nf-core skip flag schema**: parse `nextflow_schema.json` for each nf-core workflow; store in workflow_json

### Tier 3 — Pipeline view UI + chain

7. **Pipeline AWAITING REVIEW panel**: multi-step layout, data-type arrows, + Add Step, × Remove Step
8. **Chain execution backend**: `POST /api/workflows/chain`; sequential execution with S3 output→input wiring
9. **Data type compatibility validation**: reject incompatible chains, suggest format converters

### Tier 4 — Parameter sweep

10. **`SweepConfig` model + sweep orchestrator**: spawn child runs with `-resume` sharing work_dir
11. **`SweepResultsPanel` frontend component**: comparison table + Venn diagram

---

## What This Enables

| User action | Before | After |
|------------|--------|-------|
| "Run RNA-seq and then GSEA" | Two separate workflow cards, no connection | One pipeline card, data flows automatically |
| "Skip adapter trimming" | Wrong param name guessed | Reads nf-core schema, sets `--skip_trimming true` |
| "Use HISAT2 instead" | Param value update (may fail) | Checks if it's a param (`--aligner hisat2`) or tool swap |
| "Add pathway enrichment after" | New unconnected card | Appends to session chain, validates data types |
| "Run with padj 0.01, 0.05, 0.1" | Three separate queries | One sweep run, shared upstream compute, comparison table |
| "Run it again but exclude 5 samples" | User re-specifies everything | Session context preserved, only modified param changed |
