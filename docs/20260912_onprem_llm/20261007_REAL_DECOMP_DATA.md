# Real (non-synthetic) task-decomposition data + must-not-fill anchors

**Date:** 2026-10-07
**Goal:** Multiply the decomposition training set AND escape the "in-distribution to our own
synthetic generator" caveat on the decomposition_v2 win, by extracting **real** dependency
graphs whose topology we did **not** design. Plus: fix the param `must_not_fill` 34→61
over-fill regression with real negative anchors.

## Why this exists

The decomposition_v2 win (node-F1 0.36→0.73, edge-F1 0.44→0.79; see
`20261006_SFT_V2_DECOMP_RETRAIN.md`) folded **4,300 synthetic** parallel/mixed `depends_on`
rows from `data_pool_v2/decomp_depgraph.jsonl`. But both the SFT rows **and** the
decomposition_v2 benchmark were emitted by the same constructor
(`evaluation/local_trial/build_decomp_depgraph.py`), so the result is in-distribution to that
one generator. This deliverable builds dependency graphs from sources whose shapes a human or
a pipeline author designed — not our constructor — to (a) add training signal from a genuinely
different distribution and (b) provide a held-out set that finally tests
out-of-synthetic-generator generalization.

## Sources (real only — parsed from actual `.nf` / DB / tutorials)

| # | Source | What a node/edge is | Rows |
|---|--------|---------------------|------|
| 1 | **nf-core / Nextflow subworkflow channel graphs** (`backend/biomni_workflows/**`, `backend/nf-core-workflows`, `backend/nf-core-modules`) | node = a process invoked in the named `workflow{ main: … }` block; edge = channel wiring `PROC(OTHER.out.x)` / `ch = OTHER.out.y; PROC(ch)`. Versions plumbing excluded. | **25** |
| 2 | **`workflow_chains` DB table** (curated + bioc_reactive; execution-grounded) | node = a chain step; edge = an explicit `connections[] {from_step→to_step}` record; query = the chain's real `example_queries` / description | **62** |
| 3 | **GTN tutorials** (`midtrain_corpus/gtn_corpus.jsonl`) | node = a `{% tool %}` invocation in a `tutorial.md`; sequential edge between consecutive distinct tools in the author's hands-on order | **200** |
| | **Total real decomposition rows** | | **287** |

Parser: `evaluation/local_trial/nf_parse.py` (balanced-brace Groovy reader → process defs,
`take:`/`main:`/`emit:`, channel-variable resolution). Build driver:
`evaluation/local_trial/build_decomp_real.py`.

### Excluded on purpose (documented, not silently dropped)
- **`Biomni/biomni_nextflow/**` (~350 multi-process `.nf`, 352 parsed as DAGs)** — these are **not** real
  biological tool DAGs. They are either degenerate 2-node `TOOL() + OUTPUT()` wrappers, or
  auto-generated AST-level micro-step chains (`STEP_1__NP_ARRAY → STEP_2__NP_ABS →
  STEP_3__NP_ARGMIN …`, i.e. numpy primitives). Emitting them would fabricate "tool" nodes
  with no scientific meaning, so they are excluded.
- **20 nf-core subworkflows** whose catalog description, after scrubbing node labels, reduces
  to a bare tool-name list (no science left). Per the no-fabrication rule we drop rather than
  invent a query. (`session_workflows` is empty in this DB — 0 rows — so it contributes none.)

## Output artifacts (committed)

| Artifact | Path | Rows |
|----------|------|------|
| SFT training rows (folds into the mix; schema = `decomp_depgraph.jsonl`) | `docs/20260912_onprem_llm/data_pool_v2/decomp_real.jsonl` | **219** |
| Held-out real validation (schema = `decomposition_v2.jsonl`) | `evaluation/datasets/decomposition_real/decomposition_real.jsonl` | **68** |
| Scorer (extended `decomposition_v2/score.py`) | `evaluation/datasets/decomposition_real/score.py` | — |
| Disjointness proof | `docs/20260912_onprem_llm/data_pool_v2/decomp_real.split.json` | — |
| Distribution stats | `docs/20260912_onprem_llm/data_pool_v2/decomp_real.stats.json` | — |
| **Param `must_not_fill` negative anchors** | `docs/20260912_onprem_llm/data_pool_v2/param_mustnotfill_neg.jsonl` | **854** |

The SFT rows use the exact `{messages:[sys,user,assistant], task:"task_decomposition",
source, structure}` schema as the synthetic set (plus `provenance`/`unit` metadata), so they
fold into the next SFT mix with no loader change. `source` is prefixed `real_*` so the
provenance of every row is labelled.

## Counts — per source × structure

| | sequential | mixed | parallel | total |
|---|---|---|---|---|
| nfcore_subworkflow | 21 | 2 | 2 | **25** |
| workflow_chain | 49 | 9 | 4 | **62** |
| gtn_tutorial | 200 | 0 | 0 | **200** |
| **all** | **270** | **11** | **6** | **287** |

Train (219) / Val (68) per source×structure are in `decomp_real.stats.json`. The validation
split deliberately uses a **higher holdout rate on the rare branching classes** (≈40% of
mixed/parallel, ≈22% of sequential) so the OOD eval has statistical power on the exact
capability the synthetic fold was meant to add — val holds 5 mixed + 3 parallel + 60
sequential.

## Held-out split proof (zero overlap)

Split rule: deterministic per **source-unit** (nf-core file path / chain name / tutorial id),
stratified by `(provenance, structure)`.

```
train_rows = 219   val_rows = 68
train_units = 219  val_units = 68
unit_overlap_count = 0        ← hard partition: the required proof
train_nodes = 607  val_nodes = 219   node_overlap_count = 57
```

- **Source-unit overlap = 0.** No source workflow/chain/tutorial appears on both sides. This
  is the leakage guarantee the brief asked for.
- **Node overlap = 57** is reported honestly. It is **not** a unit leak: it comes from (a)
  `workflow_chains` reusing the same catalog workflow (e.g. `nf-core/sarek`) across different
  chains, and (b) ubiquitous GTN tools (`FastQC`, `MultiQC`). nf-core process nodes and GTN
  tool labels are otherwise file/tutorial-local. Because the *topology* (edge set) of each val
  unit is drawn from a source disjoint from training, node-label reuse does not leak the DAG
  shape — which is what the benchmark scores.

## Real vs synthetic — structure-distribution comparison (the headline)

Computed over all 287 real DAGs vs all 4,300 synthetic rows (`decomp_real.stats.json`):

| metric | **real** mean (max) | **synthetic** mean (max) | what it means |
|--------|--------------------:|-------------------------:|---------------|
| nodes `n` | 3.73 (**14**) | 3.25 (4) | synth is hard-capped at 4 nodes; real pipelines reach 14 |
| depth (longest path) | 3.58 (**11**) | 1.75 (4) | synth is shallow (≤4); real has long sequential spines |
| roots (parallel width) | 1.08 (4) | 2.10 (4) | synth **over-parallelizes** — it manufactures multi-root independence |
| **max fan-in** | 1.13 (**10**) | 0.60 (**1**) | **synth has NO joins** — every node has ≤1 parent |
| **max fan-out** | 1.11 (**9**) | 0.60 (**1**) | **synth has NO scatter** — every node has ≤1 child |
| edges | 2.86 (**22**) | 1.15 (3) | real DAGs are far denser |

| structure | real | synthetic |
|-----------|-----:|----------:|
| sequential | 270 (94%) | 900 (21%) |
| mixed | 11 (4%) | 1,700 (40%) |
| parallel | 6 (2%) | 1,700 (40%) |

### What the synthetic generator was missing
1. **Convergence and divergence (diamonds).** `max_fanin = max_fanout = 1` for *every*
   synthetic row — the constructor only ever emits linear chains and star-shaped roots. It
   **cannot** express a fan-out-then-fan-in join (e.g. cryo-EM: split batches → classify in
   parallel → merge → refine; or bioconductor multi-omics: two assays → MOFA2 → enrichment).
   Real DAGs reach fan-in 10 and fan-out 9. This is the single biggest topology gap, and it is
   exactly the shape intra-workflow pipelines actually have.
2. **Depth.** Synthetic depth ≤4; real spines reach 11. Deep sequential dependency (the common
   real case) is under-represented.
3. **Realistic structure prior.** The synthetic 1:1:1-ish split (40% parallel, 40% mixed, 21%
   sequential) is backwards: **real bioinformatics decomposition is ~94% sequential**. The
   generator over-trained the model on independent-root parallelism that is rare in practice.

The real set supplies all three — deep chains, true diamonds, and a sequential-dominant prior —
which is precisely the distribution the model will meet in production and the one the
in-distribution synthetic win could not certify.

## Scorer — reuse + extension

`decomposition_real/score.py` is `decomposition_v2/score.py` with one change: node matching
takes the **max** token-F1 over `{sub_task}`, `{sub_task∪tool_id}`,
`{sub_task∪tool_id∪domain}` instead of a single merged bag. Real gold carries single-word tool
nodes (GTN `FastQC`, `velveth`) whose one token was diluted below the 0.3 threshold by the v2
merged-bag match, so even a perfect prediction failed to match. After the fix, **gold-vs-gold
= node_f1 1.0 / edge_f1 1.0 / structure_accuracy 1.0** across all three classes — the
benchmark is calibrated (a perfect model gets 1.0). All other metrics (edge-F1, per-class
structure, WCC / parallel-width diagnostics) are unchanged from v2.

## Param `must_not_fill` negative anchors

Fixes the regression in `20261006_SFT_V2_DECOMP_RETRAIN.md`: the decomp-heavy fold pushed
param `must_not_fill` violations **34 → 61** (the model over-fills optional/conditional params
the request never stated). The remediation the doc itself flagged (item 4) is "add explicit
must_not_fill negative anchors."

`data_pool_v2/param_mustnotfill_neg.jsonl` — **854 anchors**, built by
`evaluation/local_trial/build_param_mustnotfill.py`:

| subtype | rows | lesson |
|---------|-----:|--------|
| pure restraint (`real_params_schema_restraint`) | 785 | bare-intent query (the workflow's own description) + the schema's optional params → correct output is `{}`: "state nothing → fill nothing" |
| selective restraint (`real_grounded_param_restraint`) | 69 | real `grounded_param` query that *does* state some params → fill exactly those, leave the schema's other optional params as `must_not_fill` |

- **727 distinct** `must_not_fill` params, 1,777 total, across 12+ domains
  (transcriptomics 438, genomics 123, epigenomics 66, proteomics 33, …).
- **Real source only** — optional flags + descriptions come from `workflows.params_schema`
  (2,336 workflows with params, 829 with ≥1 optional); selective anchors reuse the real
  `grounded_param` (query, `db_gold`) pairs.
- A small deterministic rule layer (CLAUDE.md hybrid rule+LLM policy) licenses the one fill a
  signal in the text justifies (human→`genome=GRCh38`, paired-end→`paired_end=true`, …), so
  the lesson is *selective* restraint, not "always empty".
- **Leakage control:** the param_prefill **eval** (`public_export/param_prefill/data.jsonl`)
  is query→params with no workflow names; these anchors are workflow/description→params and we
  additionally drop any anchor whose query duplicates an eval `user_query`.

## Ready to fold into the next (single, clean) retrain

- `decomp_real.jsonl` (219 rows) → add to the SFT mix beside `decomp_depgraph.jsonl`; schema
  is a superset of the synthetic rows, no loader change.
- `param_mustnotfill_neg.jsonl` (854 rows) → add to the mix to counter the 34→61 over-fill.
- Hold `decomposition_real/` out of training (unit-disjoint, proven) and score the resulting
  checkpoint with its `score.py`. A gain there — not on `decomposition_v2` — is the real,
  out-of-synthetic-generator evidence the win was missing.

### Honest limitations
- Real non-sequential DAGs are genuinely **rare** in these sources (17 of 287). The val set
  therefore has only 5 mixed + 3 parallel; treat per-class branching numbers on the held-out
  set as directional until more real diamond sources (full nf-core pipeline `workflows/*.nf`
  from upstream, not just the local stubs) are ingested. The *training* side still gains the
  deep-chain and diamond shapes the synthetic generator cannot emit.
- GTN contributes sequential-only (tutorials are linear); it multiplies volume and diversifies
  the tool vocabulary but does not add branching.

## Reproduce
```bash
cd evaluation/local_trial
python3 build_decomp_real.py        # -> decomp_real.jsonl, decomposition_real/, split+stats json
python3 build_param_mustnotfill.py  # -> param_mustnotfill_neg.jsonl
# calibration check (expect 1.0/1.0/1.0):
cd ../datasets/decomposition_real
python3 - <<'PY'
import json, score as S
g={r['id']:r for r in (json.loads(l) for l in open('decomposition_real.jsonl'))}
print(S.score_batch(g, {i:v['gold_subtasks'] for i,v in g.items()}))
PY
```
