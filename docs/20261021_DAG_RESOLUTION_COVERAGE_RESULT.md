# DAG composer — resolution coverage (offline measurement)

**Date:** 2026-10-21
**Probe:** `evaluation/local_trial/dag_resolution_coverage.py`
**Question:** Is enabling the multi-task DAG composer a wiring/flag task, or is resolution
confidence the real gap (a retrieval/training project)?
**Answer:** **Wiring, not training.** The harness resolves real decomposition subtasks ~fully.

## Setup
- 68 real topologies from `decomposition_real` (nf-core/chain/GTN), assuming a **perfect
  decomposition** (uses the gold subtasks) to isolate the HARNESS resolution + assembly gate.
- Real production resolver: `UnifiedWorkflowSearch.search(desc)` → `pick_workflow_match` with
  score ≥ `DAG_RESOLVE_MIN_SCORE` (6.0) — the exact path `ai_assistant._resolve_task_to_workflow`
  uses. Over the present workflow DB (324 MB).
- `build_dag_plan` returns None if ANY subtask fails to resolve, so per-plan "all-resolve" is the
  FIRE upper bound.

## Result

| Subtask description | per-subtask resolved | per-plan all-resolve (fire upper bound) | top-match score (min/med/max) |
|---|---|---|---|
| natural (`role + domain`) | **246/246 = 100%** | **68/68 = 100%** | 14.6 / 24.2 / 81.0 |
| raw token (`sub_task`)     | 206/246 = 84%      | 48/68 = 71%                              | 0.0 / 22.1 / 102.2 |

By structure (natural desc): sequential 60/60, mixed 5/5, parallel 3/3 — all resolve.

## Interpretation
- **Resolution is NOT the bottleneck.** With a natural description, every subtask of every real
  topology clears the ≥6 confidence bar by a wide margin (median 24). The composer would fire on
  essentially all real multi-task queries.
- The raw-token row (84%/71%) shows resolution is phrasing-sensitive: a decomposition must emit
  natural descriptions (role/domain prose), not bare tool-id tokens. Real LLM decompositions do.
- **P1 is a wiring task, not a training project** — consistent with `20261012` (composer is on
  `generate_workflow`, not the live `generate_workflow_unified`). The lever is the endpoint hook,
  not retraining resolution confidence or a bigger model.

## SECOND GATE — the type-handoff (the actual firing bottleneck)

Running the FULL `build_dag_plan` (real resolver + a replicated `_get_workflow_types` type
provider) over the same 68 topologies:

| Outcome | count |
|---|---|
| **FIRED** (returns a plan) | **3/68 = 4.4%** |
| fallback — a subtask unresolved | **0/68** |
| fallback — type-handoff no exact match | **65/68** (65 have dependent steps) |

Diagnostic on the resolved workflows: **96% have BOTH input and output types populated**
(only 4% empty input). So the 65 failures are **not missing type metadata** — the types are
present but do not **string-equal** across consecutive resolved workflows (e.g. one outputs
`counts_matrix`, the next declares `counts`/`expression_matrix`/`input`).

**Root cause:** `build_dag_plan` wires dependent handoffs by **exact** match (`decomposed_dag.py:200`
`if t in dst_in`), whereas the same codebase's `check_step_compatibility` uses **semantic** matching
(`_type_satisfies`, where `bam` satisfies `input_bam`, etc.). The exact gate rejects ~95% of real
dependent chains, and because one bad link fails the whole plan, the composer almost never fires.

**So P1 is two small, concrete HARNESS fixes — not training, not capacity, not a new benchmark:**
1. **Wiring** — hook the composer into the live `generate_workflow_unified` (20261012 §4).
2. **Handoff** — replace `build_dag_plan`'s exact type match with the sanctioned semantic
   `_type_satisfies`/`check_step_compatibility` (still refuses a genuinely incompatible handoff,
   but stops rejecting equivalent types). Expected: composer fire rises from 4.4% toward the 100%
   resolution ceiling, modulo real incompatibilities.

This probe re-runs both gates on demand — rerun after the handoff fix to confirm the lift.

### Fix #2 landed (semantic handoff) — measured lift

`build_dag_plan`'s handoff was switched from exact string match to the semantic
`type_satisfies` (alias table mirrored from `workflow_chain._type_satisfies`, inlined in
`decomposed_dag.py` because `workflow_chain` doesn't import offline; TODO: dedup into a shared
pure module in a full env). Unit tests 18/18 still pass (incompatible-type cases still refuse).

| build_dag_plan handoff | FIRED | type-handoff fallback |
|---|---|---|
| exact string match (before) | 3/68 = 4.4% | 65/68 |
| **semantic `type_satisfies` (after)** | **26/68 = 38.2%** | 42/68 |

**~9× lift from one local change** — confirming exact-match was a real overstrictness worth
fixing. The semantic fix is a correct keeper (18/18 tests, still refuses true incompatibilities).

### ⚠️ BUT these fire/precision numbers are on the WRONG granularity — do not cite as a product metric

Drilling into the 42 residual fallbacks revealed a **dataset granularity mismatch**, not an alias gap:
- **Resolver precision vs the gold `tool_id` is 4% (10/246).** The 100% "resolution" above was
  *confidence* (a ≥6 match exists), NOT *correctness* — the search confidently picks the WRONG
  workflow for these subtasks.
- The failing "type tokens" are free-text param descriptions of those wrong workflows
  (`Dasypus_novemcinctus…gtf.gz`, `mydata (NOISeq eSet…)`), not clean types.
- **Root cause:** `decomposition_real` is built from **GTN tutorials** (44/68 `real_gtn_tutorial`)
  whose gold `tool_id`s are **individual Galaxy Toolshed tools** (`…/feelnc/0.2.1`, `BIOC_DMRcate`,
  `interactive_tool_copernicus_notebook`) — **only 16% of them exist in the workflow DB**. But
  `build_dag_plan` composes **nf-core-style WORKFLOWS**. These are different abstraction levels; you
  cannot resolve a fine-grained Galaxy tool to a whole nf-core workflow.

**Consequences (honest):**
1. The semantic-handoff fix is still correct and kept — but its measured "4.4%→38%" lift on this
   dataset is **not a valid product number**; do not report it as composer performance.
2. **Widening `_TYPE_ALIASES` would GAME a mismatched eval** (fabricating handoffs between
   wrong-granularity workflows) — explicitly NOT done.
3. The composer's real metric needs **multi-WORKFLOW decomposition inputs** (user requests chaining
   several nf-core-style workflows, e.g. rnaseq→deseq2→enrichment→report), where resolution
   precision can be high. `decomposition_real` (GTN tool-chains) cannot measure this.
4. This is itself an instance of the diagnosis's core lesson — **a benchmark measuring the wrong
   thing**. The right composer eval is a small set of real multi-nf-core-workflow requests, to be
   authored (gold = the correct workflow per subtask + the stage DAG).

## Caveats (honest)
- **FTS/BM25 only** — the embedding model was blocked for env reasons (anaconda scipy ABI). Dense
  retrieval OFF; production with embeddings ON can only add coverage, and scores already sit ~4×
  above the bar, so the conclusion is robust.
- **Perfect-decomposition assumption** — this measures the harness ceiling given correct subtasks;
  LLM decomposition QUALITY is a separate, already-benchmarked axis (decomposition_real,
  DECOMP_SOLVE_LADDER).
- **Type-handoff gate now measured** (see section above): it IS the firing bottleneck (4.4%),
  via exact-match overstrictness — a local harness fix (semantic matching), still not capacity/training.
- The resolver resolves to *a confident* workflow, not necessarily the *gold* one — resolution
  *precision* vs the gold tool is a separate axis (already covered by decomposition_real node-F1);
  some handoff failures could reflect a wrong-but-confident resolution, so the semantic-handoff lift
  is an upper-ish estimate to confirm by rerunning the probe after the fix.

See `20261021_PERFORMANCE_DIAGNOSIS.md`, `20261012_COMPOSER_FLAG_ENABLED_AND_WIRING_GAP.md`.
