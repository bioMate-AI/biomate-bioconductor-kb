# Three Questions — Resolved
**Date**: 2026-03-18

---

## Q1. Input/output data types — they DO exist, but not where needed

**What was found:**

| Location | What it has | For which workflows |
|----------|------------|---------------------|
| `tools` table (`inputs`, `outputs` columns) | File formats as arrays (e.g. `["fa","fasta"]`) | Galaxy tools only |
| `tool_compatibility` table (9,656 entries) | `tool_id → data_type → input/output` mapping | Galaxy tools only |
| `galaxy_tool_rag.py` | `get_compatible_tools(input_type, output_type)`, `get_pipeline_suggestions(start, end)` | Galaxy tools only |
| `workflow_generator.py` | `_types_compatible(input_type, output_type)` method | Galaxy workflows |
| `task_decomposer.py` | Tasks have `input_types` + `output_types` in JSON schema | Task decomposer (abstract) |
| `pilot_analysis/registry.py` | Every analyzer has `input_type` + `output_type` | Pilot analyzers |
| `test_harness/evaluators.py` | Evaluates `data_flow` dimension (0.0–1.0 score) | Test harness |

**The gap:** All of this exists for **Galaxy tools**. The `workflows` table (Nextflow workflows) has NO `input_types` / `output_types` columns. The 461 nextflow workflows and 1,818 bioconductor workflows are not covered by the existing data-type infrastructure.

**Fix (this version):**
1. Add `input_types TEXT` and `output_types TEXT` columns to the `workflows` table (JSON arrays)
2. In `index_all_workflows.py`, populate them by:
   - For nfcore: read workflow's `input_type` from `nextflow_schema.json` (nf-core schemas explicitly list required input files with formats)
   - For bioconductor: infer from the `take:` block of each `.nf` file (e.g. `take: counts_matrix` → input_type = count_matrix)
   - For biomni_nextflow: parse the `params.*_file` declarations (e.g. `params.genome_file_path` → input_type = fasta)
3. In catalog text rendering: add `[in:X → out:Y]` per workflow line
4. In `_types_compatible()` — already implemented in `workflow_generator.py` — re-use for nextflow workflow chain validation

**Data wiring in this version:** YES. Use the existing `get_pipeline_suggestions()` from `galaxy_tool_rag.py` as a model. Extend with nextflow workflow types from the `workflows` table once columns are populated.

---

## Q2. DAG pipeline — what for, what scenarios, and how to simplify

**What scenarios actually require multi-task?**

| Scenario | Frequency | Structure |
|----------|-----------|-----------|
| Full omics pipeline: fetch → align → DE → pathway | Very common | Sequential, 3–4 steps |
| Comparison run: STAR vs HISAT2 on same data | Common | Parallel from same input |
| Re-analysis with tweak: same pipeline, exclude samples | Common | One step repeated with modified params |
| Multi-omics integration: RNA-seq + ATAC-seq → joint analysis | Occasional | Parallel input → join |
| Iterative: run DE, look at results, run more pathway enrichment | Common | Sequential, user-driven |

**The DAG problem and why to avoid it:**
Galaxy's DAG editor is the canonical example of what NOT to do — it requires users to understand computational graph concepts, draw connections, configure port mappings. Expert bioinformaticians avoid it for anything complex. It shifts the cognitive load of the computation onto the scientist.

**The right model: Chat-first, list-based pipeline.**
Never show a graph. Show a numbered recipe. The user speaks what they want; the system figures out ordering.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PIPELINE — 3 steps
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① nf-core/rnaseq             PENDING
  genome: GRCh38 | samples: 58
  → outputs: count matrix, QC report

② nf-core/differentialabundance    PENDING
  padj: 0.05 | lfc: 1.0
  ← uses: ① count matrix

③ GSEA Pathway Enrichment    PENDING
  ← uses: ② DEG list

[Chat: "remove step 2" / "change padj to 0.01" / "add WGCNA after step 2"]

           [Confirm & Run Pipeline]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Key design decisions:**
- No arrows, no node boxes, no port connections — just a numbered list
- `← uses: ① output` is the only "connection" shown — one line, always auto-inferred from data types
- Parallel branches: shown as "② and ③ run in parallel" label, same indentation
- User NEVER configures connections. System configures them based on data types, user confirms
- Chat IS the editor. No drag-drop, no visual manipulation
- Each step shows only 2–3 key params inline; full param list is behind [Edit]

**What this replaces vs. Galaxy:**
Galaxy shows a graph of hundreds of nodes because it has no intelligence — every connection must be manual. BioMate's LLM infers connections. The user just says "and then do pathway enrichment" and the system wires it.

---

## Q3. Test harness inspiration — existing projects

**Already in BioMate (discovered above):**
- `pilot_analysis/registry.py`: 20+ lightweight analyzers (`estimate_fragment_size`, `detect_sequencing_protocol`, etc.) each with `input_type`, `output_type`, `command_template`, `runtime_estimate`, `sample_strategy`
- `test_harness/evaluators.py`: `WorkflowEvaluator`, `ToolEvaluator`, `ScientificEvaluator` — multi-level evaluation framework
- `test_harness/benchmark_suite.py`: runs evaluation suites
- **This infrastructure EXISTS but is disconnected from the execution path.** It was built for evaluation/benchmarking, not as a user-facing pre-flight.

**External inspiration — ML/AI oriented:**

**1. DVC Experiments** (closest model, highly relevant)
```bash
dvc exp run --set-param model.lr=0.01   # run with param override
dvc exp run --set-param model.lr=0.001  # run again
dvc exp show                            # comparison table
```
Key concept: every run is a lightweight experiment, all share the same pipeline code, only params differ. Results tracked in a comparison table. **For BioMate**: every sweep value is a "dvc exp" — shares upstream computation via Nextflow -resume.

**2. W&B Sweeps** (best UX model for parameter ranges)
User defines a sweep config:
```yaml
method: grid
parameters:
  padj:
    values: [0.01, 0.05, 0.1]
  lfc:
    values: [0.5, 1.0, 2.0]
```
W&B dispatches agents that pull work from a sweep queue; each agent runs one combination. Results shown in a **sweep dashboard** with parallel coordinate plots showing how params correlate with metrics. **For BioMate**: the "metric" is DEG count or QC score, not validation loss.

**3. nf-core test profile** (existing bioinformatics standard)
Every nf-core workflow has `conf/test.config` and `conf/test_full.config`:
- `test.config`: minimal dataset, fast runtime, checks the pipeline runs end-to-end
- `test_full.config`: realistic dataset, validates biological correctness
This is exactly the two-tier pilot run concept. The test profile is baked into the workflow; BioMate should USE it directly rather than building a custom pilot mechanism.
```
nextflow run nf-core/rnaseq -profile test,docker  # runs in ~5 min on built-in test data
```
**For BioMate**: before running on user data, offer "Validate pipeline with test data first (5 min)" — runs nf-core test profile, confirms environment works.

**4. Snakemake wildcards** (clean parameter sweep concept)
```python
THRESHOLDS = [0.01, 0.05, 0.1]
rule all:
    input: expand("results/DE_{threshold}.tsv", threshold=THRESHOLDS)
```
Snakemake auto-parallelizes the three DE runs, shares upstream steps via dependency graph. **Key insight**: declare what you want (3 output files), system figures out what to run and in what order.

**5. Cromwell/WDL scatter-gather** (bioinformatics native)
```wdl
scatter (threshold in [0.01, 0.05, 0.1]) {
  call RunDE { input: padj_threshold = threshold }
}
```
Native scatter-gather: parallel runs, auto-gathered results. **For BioMate**: this is how the sweep orchestrator should work internally — Nextflow's `Channel.of([0.01, 0.05, 0.1])` scattered over the DE step, sharing the upstream alignment.

**6. Optuna** (if the parameter space is large and continuous)
Bayesian optimization with pruning: unpromising trials stopped early. **For BioMate**: only relevant if doing actual hyperparameter optimization (e.g., scVI `n_latent`). For threshold exploration (padj), grid search is better. The `pilot_analysis/registry.py` already has the decision-tree approach for `data_dependent` parameters that maps closely to Optuna's suggest_float pattern.

---

## Phase 1 — This Version (Implementation Plan with Findings Incorporated)

**Theme: Correctly select, correctly parameterize, smoothly execute.**

### Milestone 1 — Index & Catalog (unblock everything)
1. Fix `index_all_workflows.py` path bug: store canonical disk paths
2. Add `input_types` + `output_types` columns to `workflows` table
3. Re-index 953 missing workflows
4. Two-tier catalog: domain summary → scoped workflow list (includes bioconductor)
5. Catalog entries: `[tools:...] [in:X → out:Y] [steps:N]`
6. Fuzzy name resolution in `_fetch_workflows_by_names`
7. Apply colleague's 3 fixes (window→20, remove `'de'`, path parsing)

### Milestone 2 — Correct parameterization (no guessing)
1. Parse `nextflow_schema.json` for 100 nf-core workflows → store in DB
2. Build `tool_param_map`: `(workflow, nf_flag, tool, tool_param, type, min, max, default)`
3. Modification classifier: `value_change` uses schema, `skip_step` uses skip-flag map
4. `tool_knowledge.recommended_parameters` reformatted: separate `value` (typed) from `rationale` (string)
5. Reconcile tool_knowledge param names with nf-core flag names; store mapping

### Milestone 3 — WorkflowSession + multi-turn (context across messages)
1. `WorkflowSession` Redis model (steps[], user_intent, data_format, session_id)
2. `session_id` threaded through chat context → API calls
3. Modification classifier: `value_change`, `skip_step`, `add_workflow` (sequential append)
4. Simple pipeline list view in AWAITING REVIEW (numbered steps, auto-inferred connections)
5. Data type compatibility check when appending steps

### Milestone 4 — Test harness wired to execution
1. Connect `pilot_analysis/registry.py` analyzers to the AWAITING REVIEW flow
2. Use nf-core `-profile test` for environment validation before user runs
3. Parameter sensitivity (sweep, 2–4 values): Nextflow scatter via `Channel.of(values)`, shares upstream with `-resume`, comparison table in UI
4. Wire `test_harness/evaluators.py` data_flow score to chain validation
5. `data_dependent` params from `parameter_context_requirements.json` trigger pilot analyzer automatically

**Milestone 4 = the test harness in this version.** Key: `pilot_analysis/registry.py` and `test_harness/` are already implemented. The work is wiring them to the execution path, not building from scratch.

---

## Phase 2 — Next Version

- Full parallel branch execution (LangGraph fan-out via Celery)
- SweepResultsPanel: comparison table with parallel coordinate plots (W&B-inspired), Venn diagram
- Format conversion steps: auto-insert when output_type of step N ≠ input_type of step N+1
- Tool substitution: swap alignment tool, validate type compatibility
- Visual pipeline list enhancements (re-order by drag, estimated runtime per step)
- Auto-suggest multi-step pipeline from single query (catalog browser returns ordered list)
