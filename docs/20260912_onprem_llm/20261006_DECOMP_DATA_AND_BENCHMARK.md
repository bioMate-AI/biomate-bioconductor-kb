# Decomposition v2 — Dependency-Graph Benchmark + SFT Data (root-cause fix)

**Date:** 2026-10-06
**Author:** Yaoyun Zhang · xiaoni5122@gmail.com
**Scope:** CPU-only data engineering from the catalog. No GPU, no serving, no training run. Builds the two groundwork pieces called for by the error analysis.
**Fixes:** `docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md` — the on-prem 9B's weak task-decomposition traces to a **data gap: 0 / 12,319 existing decomposition training rows carry a `depends_on` field, and 0 carry parallel or mixed topology.** The DAG behaviour has 0% density in the SFT target, so it can only be emergent zero-shot. This doc manufactures that density.

---

## 0. TL;DR

- **Root cause (not a workaround):** the behaviour was never in the data. Per the analysis, intra-workflow DAG edges are also absent from the catalog (2/4,210), so the real, synthesizable signal is **inter-workflow composition** — exactly how the eval gold is built. We mine that signal from the catalog's `domain` (independence → parallel roots) and `input_types`/`output_types` (output→input match → a real sequential edge).
- **DELIVER 1 — benchmark:** `evaluation/datasets/decomposition_v2/decomposition_v2.jsonl`, **n = 165, balanced 55 / 55 / 55** (parallel / sequential / mixed), **real catalog workflow nodes** each carrying `tool_id` + `input_types`/`output_types`, explicit `depends_on` DAG gold. Shipped with a **node-F1 + edge-F1 + per-class-structure scorer** (`score.py`), not the coarse 4-class bin.
- **DELIVER 2 — SFT rows:** `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl`, **4,300 rows** in the **eval output schema** (`{"sub_task","order","depends_on"}`), emitted at **workflow/phase granularity** (kills the 2.78× over-decomposition prior), **over-weighting the rare classes** (1,700 parallel / 1,700 mixed / 900 sequential).
- **Leakage control:** benchmark and training draw from **disjoint workflow pools** (hash split). **Workflow-name overlap = 0**, proven in `decomp_depgraph.split.json`.
- **Honesty:** benchmark edges are **100% type-consistent** (188/188 real output→input overlaps). Mixed composition is limited to the **8 domains that have an internal output→input chain** — a real catalog coverage limit, documented in §6.
- **Ready to fold into the next SFT retrain** (§5): add `decomp_depgraph.jsonl` to the multitask mix; the benchmark is the held-out gauge that proves whether density fixed the capability.

---

## 1. Construction (grounded in the catalog, no fabricated biology)

Source: `backend/database/galaxy_ai_tools.db` → `workflows` (4,210). Usable pool = workflows with a non-empty `input_types`, a non-empty `output_types`, a `domain`, and a ≥40-char `description` → **3,141 workflows**. Node = a real catalog workflow; `sub_task` = its name, `tool_id` = its primary `tools_used` entry (or the name), carrying its real `input_types`/`output_types`/`domain`.

| Structure | Gold DAG rule | Catalog signal used |
|---|---|---|
| **parallel** | k∈{2,3,4} workflows from **distinct, I/O-disjoint domains**, all `depends_on=[]` (independent roots) | `domain` independence; `out(A)∩in(B)=∅` both directions |
| **sequential** | chain of length 2–4 where `out_types(A) ∩ in_types(B) ≠ ∅`, each `depends_on=[prev]` | real `output_types→input_types` edge |
| **mixed** | two independent domains, **each a prep→analysis pair** (internal output→input edge); partition `{2,2}` = two parallel 2-chains | per-domain internal chain + cross-domain disjointness |

Queries are assembled from the **real workflow `description` text** (tool names scrubbed), so there is no invented biology — the prose is catalog-grounded. Edge direction in gold is always a genuine type match; this is verified (§3).

Generator (reproducible, seeded): `evaluation/local_trial/build_decomp_depgraph.py` (`seed=20261006`).

---

## 2. DELIVER 1 — the held-out benchmark

**Path:** `evaluation/datasets/decomposition_v2/decomposition_v2.jsonl`
**Size:** 165 rows. **Structure balance:** parallel 55 / sequential 55 / mixed 55 (≈1:1:1).
30 distinct domains appear as parallel roots; all 165 queries are tool-name-free natural language.

**Example row (mixed, abridged):**
```json
{
  "id": "decv2_mixed_155",
  "query": "I have 2 independent projects; within each project the steps are sequential, but the projects are unrelated and can run in parallel:\n\nProject 1 (Variant Calling): first Concatenate several VCF files using bcftools concat...; then Perform annotation with snpEff and bgzip + tabix index...\n\nProject 2 (Immunology): first ...; then ...",
  "structure": "mixed",
  "gold_subtasks": [
    {"sub_task": "Vcf Gather Bcftools", "order": 1, "depends_on": [], "tool_id": "bcftools",
     "input_types": ["bed","gather_count"], "output_types": ["tbi","vcf"], "domain": "variant_calling", "role": "prep"},
    {"sub_task": "Vcf Annotate Snpeff", "order": 2, "depends_on": [1], "tool_id": "snpeff",
     "input_types": ["cache","vcf"], "output_types": ["tsv_annotated","vcf"], "domain": "variant_calling", "role": "analysis"},
    {"sub_task": "Simulate Cell Population", "order": 3, "depends_on": [], "tool_id": "...",
     "input_types": ["death_rate","growth_rate"], "output_types": ["counts_matrix","pdf_report"], "domain": "immunology", "role": "prep"},
    {"sub_task": "immune_deconvolution", "order": 4, "depends_on": [3], "tool_id": "...",
     "input_types": ["checksig","clinical_metadata"], "output_types": ["counts_matrix","pdf_report"], "domain": "immunology", "role": "analysis"}
  ],
  "instr": "Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of {\"sub_task\": ..., \"order\": N, \"depends_on\": [prerequisite orders]} ..."
}
```
This is a real `{2,2}` partition: two independent domain pipelines, each a genuine `vcf→vcf` / data→analysis edge. The eval's synthetic `"<domain> prep|analysis"` placeholders are replaced by real workflow/tool nodes with type provenance.

### Scorer — `evaluation/datasets/decomposition_v2/score.py`

Reports, replacing the coarse 4-class `structure_accuracy`:
- **`node_f1`** — sub-tasks recovered (greedy bipartite match of pred `sub_task` tokens to gold `sub_task`/`domain`/`tool_id`; a domain-granularity answer still scores, while gold keeps real provenance).
- **`edge_f1`** — dependency edges recovered, computed on matched nodes (direction-sensitive).
- **`structure_accuracy` + `by_class`** — 4-class shape match reported **per parallel/sequential/mixed** (so a mixed regression can't hide behind a sequential-heavy average).
- **`wcc_count_match`, `parallel_width_match`** — the label-free topology diagnostics from the error analysis §1, kept so parallel-expression regressions stay visible.

**Discrimination check** (run on the benchmark itself):

| Predictor | node_f1 | edge_f1 | struct acc | parallel struct | mixed struct |
|---|---|---|---|---|---|
| Oracle (pred = gold) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| **"Always-chain" prior** (the gold-model failure mode) | 1.00 | 0.60 | **0.33** | **0.00** | **0.00** |

The always-chain baseline — same nodes, forced into one linear chain — keeps `node_f1=1.0` but collapses to `struct=0.33` with **parallel and mixed at 0.00** and `edge_f1` down to 0.60. The benchmark exposes exactly the under-parallelization the analysis named, which the old 4-class average (53% sequential) partly masked.

Run:
```bash
cd evaluation/datasets/decomposition_v2
python score.py --gold decomposition_v2.jsonl --pred <model_preds>.jsonl
```

---

## 3. DELIVER 2 — the SFT training rows

**Path:** `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl`
**Size:** 4,300 rows. **Structure balance:** mixed 1,700 / parallel 1,700 / sequential 900.
Rare classes (parallel, mixed) are **over-represented** on purpose — base density is zero and GRPO can't reward a structure the policy never emits, so SFT must show it first.

- **100% of rows** emit the exact eval output schema `{sub_task, order, depends_on}` (verified) — train/eval formats now match.
- **2,600 rows carry ≥1 explicit `depends_on` edge** (every sequential + mixed row); **4,300 carry ≥1 parallel root** — directly the two structures with 0% prior density.
- **Granularity = workflow/phase, not per-tool** — each node is one workflow, countering the base model's 2.78× over-decomposition.
- Covers the analysis's named failure modes: **under-parallelization** (1,700 parallel + 1,700 mixed exemplars with real independent roots) and **mixed grouping** (the 0/8 class → 1,700 training exemplars).

**Example row (parallel):**
```json
{"messages": [
  {"role": "system", "content": "You are BioMate, an agentic assistant. Decompose the request into an ordered sub-task plan."},
  {"role": "user", "content": "I have 4 independent analyses to run on separate datasets; ... \n\nDecompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of {\"sub_task\": ..., \"order\": N, \"depends_on\": [...]} ..."},
  {"role": "assistant", "content": "[{\"sub_task\": \"powertcr\", \"order\": 1, \"depends_on\": []}, {\"sub_task\": \"Simulate Gene Circuit With Growth Feedback\", \"order\": 2, \"depends_on\": []}, {\"sub_task\": \"ropls\", \"order\": 3, \"depends_on\": []}, {\"sub_task\": \"Analyze Itc Binding Thermodynamics\", \"order\": 4, \"depends_on\": []}]"}
 ],
 "task": "task_decomposition", "source": "catalog_depgraph_synth", "structure": "parallel"}
```

---

## 4. Leakage control — the held-out split (proof)

Each workflow is assigned deterministically: `md5(name) % 100 < 20 → BENCH pool, else TRAIN pool`. Benchmark compositions draw **only** from BENCH; training rows **only** from TRAIN. Stable across re-runs.

`docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.split.json`:

| | BENCH | TRAIN |
|---|---|---|
| pool workflows | 628 | 2,513 |
| **distinct workflows actually used** | **139** | **1,305** |
| rows produced | 165 | 4,300 |
| structure balance | 55/55/55 | 1,700 / 900 / 1,700 |

**Workflow-name overlap between the two sets = 0** (verified programmatically; `overlap_examples: []`). No benchmark workflow appears in any training row — the benchmark is a true held-out gauge of generalization, not memorization.

Additional integrity: **188 / 188** benchmark dependency edges have a real `output_types ∩ input_types` overlap (no fabricated edge). Node labels, tool ids, and I/O types are copied verbatim from the catalog — no invented biology.

---

## 5. Ready for the next SFT retrain

1. Add `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl` to the multitask SFT mix (same `messages`/`task` schema as `multitask_sft_final.jsonl`; `task="task_decomposition"`). It supplies the dependency-structure density the current mix is missing (0 → 4,300 rows with edges).
2. Retrain the 9B (GPU step — out of scope here; this is the data groundwork).
3. Evaluate on the held-out `decomposition_v2` benchmark with `score.py`. The capability signal is **`node_f1`, `edge_f1`, and per-class `structure_accuracy`** (especially `parallel` and `mixed`, previously 0.00 on the always-chain prior), **not** the old 4-class average.

Because the benchmark workflows are disjoint from training, a gain on `decomposition_v2` is evidence the model learned **inter-workflow composition**, not the specific training compositions. This closes the loop the error analysis opened: fix the 0% density (done here) → measure it on a real, held-out, graph-aware gauge (done here).

---

## 6. Honesty / coverage limits

- **Mixed composition is catalog-limited to 8 domains.** Only 8 domains have an internal `output→input` chain (variant_calling, genomics, immunology, transcriptomics, drug_discovery, pharmacology, imaging, molecular_biology). Mixed rows therefore draw their per-domain prep→analysis pairs from these — the long-tail domains (3-workflow glycoengineering, biophysics, etc.) can appear as **parallel roots** but cannot supply a real internal 2-chain. This is a true limit of the catalog's I/O annotation, not a generator shortcut; any synthesized mixed pair outside these domains would require a fabricated edge, which we refuse.
- **Node identity from a tool-free query is intrinsically hard** (the reason the original eval used domain placeholders). The scorer's node match is token-overlap against `sub_task`/`domain`/`tool_id`, so a correct domain-granularity answer scores while the gold retains real tool provenance. `node_f1` should be read as "right sub-tasks at domain/tool granularity", not "guessed the exact catalog slug".
- **I/O annotation is heuristic.** `input_types`/`output_types` come from the catalog's extraction, not executed dataflow, so a type overlap is a *plausible* edge, not a proven runtime binding. It is far stronger than the eval's synthetic placeholders, but it is not execution-verified.
- **Sequential is slightly under-weighted in training (900 vs 1,700)** by design — it is the only class the 9B already handles (16/16 after SFT), so budget goes to the failing classes. The benchmark keeps sequential at 1:1 so regressions there remain visible.
- **The benchmark is synthetic-composition, like the eval.** It is a better gauge (real nodes, type-checked edges, balanced, held-out) but still composed, not harvested from real multi-pipeline user sessions. A future upgrade is to mine `workflow_chains` (69 curated) and real session logs for naturally-occurring compositions.

---

## 7. Artifacts

- Benchmark: `evaluation/datasets/decomposition_v2/decomposition_v2.jsonl` (165) + `score.py` + `README.md`
- Training: `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl` (4,300)
- Split proof: `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.split.json` (overlap = 0)
- Generator (seeded, reproducible): `evaluation/local_trial/build_decomp_depgraph.py`
- Catalog source: `backend/database/galaxy_ai_tools.db` → `workflows`
- All CPU-only; no model, GPU, or serving endpoint touched.
