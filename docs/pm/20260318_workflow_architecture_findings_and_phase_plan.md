# Workflow Architecture — Findings, Resolved Discrepancies & Phase Plan
**Date**: 2026-03-18
**Branch**: connection_formal

---

## Q1. Why skip bioconductor? They ARE workflows.

**Correction: we should NOT skip bioconductor.** The earlier reasoning was a token-count fear. Let me be precise.

Bioconductor workflows in the DB (1,818 entries):
- domain distribution: transcriptomics(791), general(547), genomics(169), epigenomics(113), proteomics(93), variant_calling(59), metagenomics(27), imaging(19)
- format: `bioconductor_nf` — Nextflow wrappers that run R-based analysis
- They are as valid for user selection as any nf-core workflow

**The actual token problem and real fix**:
2,284 workflows × ~30 tokens = ~68k tokens for the catalog. With the system prompt + conversation history, this pushes against Haiku's practical limit. But the solution is not to exclude entire sources. It is a **hierarchical catalog**:

```
=== Selection Step 1: Pick relevant domains ===
[transcriptomics] 791 Bioconductor + 18 nf-core/nfcore_subwf + 45 biomni_nextflow
  Key tools: DESeq2, edgeR, limma, ballgown, tximport, clusterProfiler ...
[genomics] 169 Bioconductor + 22 nf-core + 31 biomni
  Key tools: GATK, BCFtools, SnpEff, GenomicRanges ...
[epigenomics] 113 Bioconductor + 8 nf-core + 12 biomni
...

=== Selection Step 2: Given domain = transcriptomics, pick specific workflow ===
[Bioconductor - bulk DE]
  - DESeq2: Differential expression for count-based RNA-seq [in: count_matrix → out: deg_list]
  - edgeR: DE for small-sample experiments or count data [in: count_matrix → out: deg_list]
  - limma: DE for microarray and RNA-seq (voom) [in: count_matrix → out: deg_list]
  ...
[nf-core]
  - nf-core/rnaseq: Full pipeline FASTQ→counts→QC [in: raw_fastq → out: count_matrix]
  - nf-core/differentialabundance: DE from pre-computed counts [in: count_matrix → out: deg_list]
[BioMate custom]
  - Transcriptomic Biomarker Discovery [in: count_matrix → out: biomarker_list]
```

Two LLM calls: domain selection (tiny, fast) → specific workflow selection (domain-scoped, ~200-400 workflows max).

---

## Q2. The 2,284 vs 2,771 discrepancy — root cause resolved

**Real counts from disk:**

| Top-level directory | .nf files on disk | In DB |
|--------------------|-------------------|-------|
| `nextflow_nfcore/subworkflows/bioconductor/` | ~1,824 | 1,818 (path-format mismatch for 6 new ones) |
| `nextflow_nfcore/subworkflows/` (non-bioconductor) | 272 | 0 |
| `nextflow/` | 415 | ~268 as biomni_nextflow (path mismatches) |
| `nextflow_generated/` | 237 | 0 |
| `pipeline_composition/` | 21 | 0 |
| nf-core pipelines | 100 | 100 |
| nfcore subworkflows | 93 | 93 |
| others | ~9 | 5 |
| **Total** | **2,771** | **2,284** |

**Five root causes of the discrepancy:**

**Root Cause A — Path format mismatch (DB ↔ disk)**
DB stores bioconductor paths as `nextflow_nfcore/bioconductor/{name}/main.nf`
Disk has them at `nextflow_nfcore/subworkflows/bioconductor/{name}/main.nf`
Missing: `subworkflows/` in the DB path. This means `_nextflow_workflow_key()` and any file-existence check FAILS for all 1,818 bioconductor entries. They appear indexed but the paths are wrong.
→ **Fix**: indexer stores canonical disk path; `_nextflow_workflow_key()` uses DB `filename` column, not a heuristic reconstruction.

**Root Cause B — 272 new domain subworkflows not indexed**
In `nextflow_nfcore/subworkflows/` there are domain directories (genetics, bioengineering, immunology, etc.) with 272 `.nf` files. These were created for BioMate but the indexer was never re-run for them.
→ **Fix**: re-run indexer on these paths; add them as source `biomni_nextflow` with correct domain tags.

**Root Cause C — `nextflow_generated/` (237 files) never indexed**
237 AI-generated subworkflows for less-common analysis types. Not in DB at all.
→ **Fix**: run indexer on `nextflow_generated/`; source = `generated_nextflow`, lower priority.

**Root Cause D — `pipeline_composition/` (21 files) never indexed**
These are multi-workflow orchestration .nf files. Not indexed because they're not single-analysis workflows.
→ These should be kept separate as "meta-pipelines" — a distinct catalog category. NOT mixed with single-analysis workflows.

**Root Cause E — `nextflow/` path mismatches**
415 files in `nextflow/` directory; DB has 268 as `biomni_nextflow`. Difference = 147 files either with wrong paths or not indexed. Need a path reconciliation run.

**Action**: `backend/scripts/index_all_workflows.py` needs to:
1. Use absolute disk paths as the source of truth for `filename` column
2. Scan ALL five directories above
3. Validate that every existing DB entry's `filename` points to an actual file; flag/update stale entries
4. Add 953 missing workflows on re-run

---

## Q3. Why only category information in the catalog?

Current catalog per entry: `domain + name + 80-char description` only.

The workflows table has these columns we're not using:
```
tools_used   → JSON list of tools (e.g. ["STAR", "DESeq2", "featureCounts"])
tags         → JSON list of tags (e.g. ["rnaseq", "paired-end", "differential"])
step_count   → number of steps/processes
source       → nfcore | bioconductor | biomni_nextflow
format       → nextflow | bioconductor_nf
```

What the LLM needs to make a better decision — and what we can add WITHOUT a new data pipeline:

```
[transcriptomics]
  - nf-core/rnaseq [src:nfcore] [tools:STAR,HISAT2,Salmon,DESeq2,MultiQC] [in:raw_fastq → out:count_matrix,qc_report] [steps:24]
    Full RNA-seq: alignment, quantification, QC, optional DE
  - DESeq2 [src:bioconductor] [tools:DESeq2,ggplot2] [in:count_matrix → out:deg_list] [steps:6]
    Differential expression analysis with negative binomial model
```

The `in:X → out:Y` data types are the one thing NOT yet in the DB. All other fields are already present.

---

## Q4. tool_knowledge vs nextflow_schema — the discrepancy

**tool_knowledge** (`recommended_parameters` column, 4,117 entries):
```json
{
  "DESeq2": {
    "alpha": "0.05 for FDR cutoff",
    "lfcThreshold": "0.5-1.0 for biologically meaningful fold changes",
    "shrinkage": "Use lfcShrink(type='apeglm') for effect size estimation"
  }
}
```

These are **tool-level parameter names** (R function arguments) with **human-readable guidance strings**, not typed values.

**nextflow_schema.json** (per nf-core workflow, not in DB yet):
```json
{
  "padj_threshold": {
    "type": "number",
    "default": 0.05,
    "description": "Adjusted p-value threshold for DE"
  },
  "lfc_threshold": {
    "type": "number",
    "default": 1.0,
    "description": "Log2 fold change threshold"
  }
}
```

These are **workflow-level CLI parameter names** (nf-core flag names) with typed constraints.

**Three discrepancies:**

| Discrepancy | tool_knowledge | nextflow_schema | Impact |
|-------------|---------------|-----------------|--------|
| Name mismatch | `alpha` (DESeq2 R arg) | `padj_threshold` (nf-core flag) | Can't use tool_knowledge name directly in nextflow CLI |
| Value format | Human string "0.05 for FDR cutoff" | Typed float 0.05 | Can't extract numeric value reliably |
| Scope | Tool-level (DESeq2 standalone) | Workflow-level (nf-core wraps DESeq2) | Tool params ≠ workflow params |

**Correct architecture (no guessing):**

```
User says: "change padj to 0.01"
        │
        ▼
1. Look up workflow's nextflow_schema.json:
   → finds parameter "padj_threshold" (type: float, range: 0.0-1.0, default: 0.05)
   → "padj" fuzzy-matches "padj_threshold" with 0.95 confidence
   → value 0.01 is valid float in range
        │
        ▼
2. For rationale/citation, look up tool_knowledge for the tool that implements this:
   → DESeq2 → "alpha: 0.05 for FDR cutoff" → "PMID:25516281"
   → Show user: "Setting padj_threshold=0.01 (DESeq2 alpha). Note: stricter than default 0.05. [PMID:25516281]"
        │
        ▼
3. Update WorkflowSession.steps[i].params["padj_threshold"] = 0.01
```

**What needs to be built:**
- Parse and store `nextflow_schema.json` in DB for all nf-core workflows (100 pipelines × 1 schema each)
- Build a `tool_param_to_workflow_param` mapping table: `(tool_name, tool_param) → (workflow_name, nf_flag_name)`
- Store this mapping once during indexing, use at runtime for correct flag name resolution

---

## Q5. "Add workflow to chain" = sequential task (clarification)

Yes — correctly understood. "Add workflow" means: after the current task completes, run another task. This creates a directed graph of tasks:

**Sequential** (B needs A's output):
```
raw_fastq
    ↓
[Task A: nf-core/rnaseq]  → count_matrix
                                ↓
                  [Task B: nf-core/differentialabundance]  → deg_list
```

**Parallel branches** (B and C both need A's output independently):
```
raw_fastq
    ↓
[Task A: nf-core/rnaseq]  → count_matrix + deg_list
                           ╱              ╲
    [Task B: GSEA]        ←deg_list    count_matrix→   [Task C: WGCNA]
    → pathway_results                                   → gene_modules
```

**Join** (Task D needs results from both B and C):
```
[Task B: GSEA] + [Task C: WGCNA] → [Task D: Integrate results]
```

This maps exactly to the LangGraph DAG already in BioMate's foundation (`pending_tasks` table, `depends_on` array column). The chain is a DAG, not just a list.

For the UI: the chat modification command "add pathway enrichment" appends a node to the DAG. If the new workflow's `input_type` matches the current tail's `output_type`, it's sequential. If it matches an intermediate node's output, it's parallel from that node.

---

## Q6. Can BioMate implement all this? — Honest capability assessment

**Things BioMate already has:**
- LangGraph installed, `pending_tasks` table with `depends_on` DAG structure
- Redis pub/sub + SSE pipeline events endpoint
- Celery async workers
- `_llm_rerank_results`, `_classify_intent_with_llm`, `_browse_catalog_with_llm` (built but not wired)
- `tool_knowledge` table with 4,117 entries, citations, alternatives
- S3 output listing, presigned URLs, download endpoints
- Nextflow -resume with shared work_dir
- WorkflowSession concept (data model defined in simulation doc, not yet built)

**What needs to be built — by complexity:**

| Feature | Effort | Blocker |
|---------|--------|---------|
| Fix catalog filter (bioconductor, 2-tier) | Small | None |
| Add tools_used/tags to catalog text | Small | None |
| Fuzzy name resolution (difflib) | Small | None |
| Fix indexer path bug (Root Cause A) | Small | None |
| Re-index 953 missing workflows | Small (script run) | Indexer fix |
| WorkflowSession Redis model | Small-Medium | None |
| nextflow_schema.json → DB | Medium | Need to parse 100 schemas |
| tool_param → workflow_flag mapping | Medium | nextflow_schema parsed |
| Modification classifier (value+skip) | Medium | WorkflowSession |
| Basic sequential chain execution | Medium | WorkflowSession + S3 wiring |
| Pipeline AWAITING REVIEW panel (DAG view) | Large | WorkflowSession |
| Input/output type system | Large | Domain knowledge encoding |
| Auto data-type wiring between steps | Large | Type system |
| Parallel branch execution | Large | LangGraph nodes wired |
| Parameter sweep orchestrator | Large | WorkflowSession + -resume |
| SweepResultsPanel (comparison table, Venn) | Large | Sweep orchestrator |

BioMate can implement everything in the "Small-Medium" tier within this version. The "Large" items need careful phasing. The foundations are real (not theoretical) — the DAG, the SSE, the LangGraph install are all live.

---

## Q7. Phase Split

### Phase 1 — This Branch / This Version
**Theme: "Correctly select the right workflow and execute it smoothly"**

Scope: Get workflow selection accurate, get modification reliable, get multi-turn context working. No pipeline view redesign.

**P1.1 — Indexer & Catalog Integrity**
- Fix `index_all_workflows.py` path bug (store canonical disk path in `filename`)
- Re-index to add 953 missing workflows (include nextflow/, nextflow_generated/)
- `pipeline_composition/` stored as separate catalog, not mixed with single-analysis
- Validate all 2,284 existing DB entries against disk; update stale paths

**P1.2 — Catalog Quality**
- Two-tier catalog: domain summary first (fast, tiny) → workflow list for selected domain (scoped)
- Catalog lines include: `[tools:...] [in:X → out:Y] [steps:N]` where tools/steps come from existing DB columns; in/out types encoded manually for the 100 nfcore + 268 biomni workflows (small enough to do by hand + LLM assist)
- Fuzzy name resolution in `_fetch_workflows_by_names` using `difflib.get_close_matches`

**P1.3 — Parameter Schema Integration**
- Parse `nextflow_schema.json` for 100 nf-core workflows → store in `workflow_json.nf_schema` in DB
- Build `tool_param_map` table: `(workflow_name, nf_flag, tool_name, tool_param, type, range)`
- `recommended_parameters` in tool_knowledge reformatted to separate value from guidance text
- Modification classifier for `value_change` and `skip_step` uses schema, not guessing

**P1.4 — WorkflowSession (multi-turn context)**
- `WorkflowSession` Redis model: steps[], user_intent, data_format, clarifications, session_id
- `session_id` threaded through chat context → API calls → modification endpoints
- "Run it again but change X" correctly retrieves previous params from session

**P1.5 — Sequential Chain (basic)**
- After confirmation, second workflow selection in chat → appended as Task B in session DAG
- Execution: Task A completes → S3 output URI → user reviews → Task B launched with S3 URI as input
- Manual wiring: BioMate shows "Task A output: s3://..." and lets user confirm it maps to Task B's input param
- No auto data-type detection — user confirms the wiring

**P1.6 — Colleague's fixes (apply immediately)**
- Reranker window 10 → 20
- Remove `'de': 2.0` keyword
- Fix `_nextflow_workflow_key` for `nextflow_nfcore/` path format

---

### Phase 2 — Next Version
**Theme: "Flexible pipeline composition, exploration, and automation"**

**P2.1 — Full Pipeline View UI**
- AWAITING REVIEW panel redesigned as DAG view
- Parallel branches shown side-by-side
- `[+ Add Step]` inline catalog search
- `[×]` step removal with downstream impact warning
- `[Skip]` toggle per-step (using nf-core skip flags from schema)

**P2.2 — Data Type System + Auto-wiring**
- `input_types` / `output_types` columns in workflows table (typed: raw_fastq, count_matrix, deg_list, ...)
- Compatibility matrix: which output_type feeds which input_type
- Format converters: known conversion steps (deg_list → ranked_list for GSEA)
- Auto-wiring: when Task B.input_type == Task A.output_type, pre-fill input param

**P2.3 — Parameter Sweep / Test Harness Integration**
- Sweep specification: user says "test padj [0.01, 0.05, 0.1]" → `SweepConfig` created
- **This is exactly what the test harness / pilot run should do**: the pilot run runs the FULL pipeline on a subset (10% of data), then the sweep tests parameter sensitivity on that subset before committing to full scale
- Execution: upstream steps run once → child runs with -resume sharing `work_dir`
- `SweepResultsPanel`: comparison table (N DEGs per threshold), Venn diagram, cost breakdown
- Pilot run integration: pilot always runs before sweep proposal; sweep values come from pilot QC gate analysis

**P2.4 — Parallel Branch Execution**
- LangGraph StateGraph wired to Celery fan-out (Phase D from team share doc)
- Parallel tasks tracked in `pending_tasks` table, live status via SSE → TaskList component

**P2.5 — Tool Substitution**
- `change_tool` modification type in classifier
- For nf-core: param-level substitution (--aligner hisat2) using schema
- For workflow-level: swap entire workflow step, validate data type compatibility

---

## Summary — What to Do Now (Phase 1 Sequence)

```
Week 1:
  P1.6  Apply colleague's 3 fixes immediately (30 min)
  P1.1  Fix indexer path bug + re-index (1 day)
  P1.2  Fix catalog (2-tier, add fields, fuzzy names) (1 day)

Week 2:
  P1.3  nextflow_schema parsing + tool_param_map table (2 days)
  P1.4  WorkflowSession Redis model + thread session_id (2 days)

Week 3:
  P1.5  Basic sequential chain (1-2 days)
  Test all with the 5 simulations from the gap analysis doc
```

Phase 2 starts in next version/branch, after Phase 1 is stable.
