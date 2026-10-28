# On-prem 9B Task-Decomposition — Rigorous Error Analysis

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (analysis), xiaoni5122@gmail.com
**Scope:** CPU-only error analysis of the SFT-from-gold 9B on the RealBio `task_decomposition` benchmark. No GPU, no serving, no training. Read-only pull of eval predictions from S3.
**Eval run analyzed:** `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/eval/spot_harness_gold_20261006_120457/results/{base,gold}/task_decomposition.jsonl` (the ckpt-550 run named in the task is **not present** on S3 — only `spot_harness_gold_20261006_120457`, `spot_harness_gold_20261006_102018`, and non-gold harness runs exist; analysis uses the `_120457` gold run, n=30).

---

## 0. TL;DR

- **The coarse metric is confirmed coarse.** `structure_accuracy` in `evaluation/datasets/public_export/score.py` is a **4-class topological bin** (`empty` / `parallel` / `sequential` / `mixed`) computed by `_structure_of()` from `depends_on` lengths only. It ignores *which* subtasks, *which* tools, and *which* edges. The reported 0.367 → 0.600 reproduces exactly, but it is **not** the capability number.
- **Proper re-score:** on a label-free DAG-topology metric (weakly-connected-component grouping), base → gold moves only **0.567 → 0.600 (+0.033)**, versus the +0.233 the 4-class bin advertises. **~85% of the headline gain is granularity/format conformance, not improved dependency reasoning.**
- **The gain is not statistically significant.** Paired McNemar exact two-sided **p = 0.092** (10 gold-only gains vs 3 base-only losses); Wilson 95% CIs overlap heavily (base [0.22, 0.55] vs gold [0.42, 0.75]).
- **Top-3 failure modes** (see §2): base = **over-decomposition** (14/19 failures, mean 2.78× node inflation) + 2 malformed empties; gold = **under-parallelization** (10/12 failures serialize parallel/mixed into a single chain), with **mixed structure 0/8 on component-grouping for both arms**.
- **Root cause is a data gap, not an algorithm gap.** **0 of 12,319 decomposition training rows contain a single `depends_on` field; 0 contain parallel or mixed topology.** The eval's entire dependency-structure behavior is emergent zero-shot from the instruction prompt — it was never trained.
- **Highest-leverage next step = DATA** (§4): synthesize inter-workflow **parallel/mixed** decomposition examples **with `depends_on` edges**, mined from the catalog (domain-independence → parallel roots; output→input type chaining → sequential edges; per-domain prep→analysis pairs → mixed), and re-emit every decomposition row in the eval output schema. GRPO / verifiers are a valuable *second* stage but cannot efficiently manufacture a behavior that has **0% density** in the training target.

---

## 1. Proper-metric re-score (base vs gold, n=30)

### 1.1 Confirming the scorer is coarse

`score_task_decomposition` (score.py:220) credits a row iff `_structure_of(pred) == gold["structure"]`, where (score.py:213):

```python
def _structure_of(plan):
    deps=[len(s.get("depends_on",[]) or []) for s in plan if isinstance(s, dict)]
    if not deps: return "empty"
    if all(d==0 for d in deps): return "parallel"       # every node a root
    if all(d>0 for d in deps[1:]): return "sequential"  # every non-first node has ≥1 dep
    return "mixed"
```

This is a **4-way classification of DAG shape**. `subtask_count_coverage` only compares `len(plan)` to `len(gold_subtasks)` (count, not identity, and capped at 1.0). Neither metric inspects subtask text, tool identity, edge endpoints, or edge direction. **The scorer cannot distinguish a right-tool DAG from a wrong-tool DAG of the same shape.** Confirmed coarse.

### 1.2 Why node-F1 / edge-F1 on *tool identity* is not computable against this gold

The eval gold (`task_decomposition/data.jsonl`, 30 rows) uses **synthetic template subtask labels**, not tool or workflow names:

- parallel rows → `["imaging analysis", "transcriptomics analysis", "metagenomics analysis"]`
- sequential rows → `["epigenomics step", "epigenomics step"]`, `["cancer_biology step" ×4]`
- mixed rows → `["biochemistry prep", "biochemistry analysis", "glycoengineering prep", "glycoengineering analysis"]`

These are `"<domain> prep|analysis|step"` placeholders. They carry **zero tool-level content**, so a node-F1/edge-F1 against *tool identity* (as framed in the task) has no ground truth to score against here. **This eval is a topology-shape benchmark by construction, not a tool-DAG benchmark.** The honest proper metric is therefore **label-free DAG topology**, which I compute below and which is also robust to the dominant base error (over-decomposition within a group).

### 1.3 Re-score table (real numbers, n=30)

| Metric | base | gold | What it measures |
|---|---|---|---|
| `structure_accuracy` (4-class, **reproduced**) | **0.367** | **0.600** | Scorer's shape bin |
| **WCC-count match** (label-free grouping) | **0.567** | **0.600** | # weakly-connected components (parallel-group count), invariant to within-group over-decomposition |
| Partition match (exact component-size multiset) | 0.067 | 0.467 | Strict: same grouping *and* same per-group size |
| Parallel-width match (# root nodes, `depends_on==[]`) | 0.367 | 0.600 | How many independent entry points |
| Edge-F1 (order-aligned, equal-node-count rows only) | 0.889 (n=3) | 0.811 (n=25) | Edge correctness *when granularity matches* |
| Mean pred/gold node ratio | **2.78×** (max 6×) | 1.13× (max 3×) | Over-decomposition factor |
| Malformed / empty outputs | **2** | 0 | Non-list / `{}` predictions |

**Reading it:**

- The **WCC-count** metric is the fair proper metric: a model that correctly separates three independent datasets but over-decomposes each into a 5-step chain still produces **3 components** = the right parallel grouping, even though the 4-class bin calls it `mixed` and marks it wrong. On this metric base→gold is **0.567→0.600 (+0.033)** — an order of magnitude smaller than the +0.233 headline. **"0.60 is low" is mostly the coarse metric, not the model's grouping ability.**
- Edge-F1 is **high when granularity matches** (base 0.889, gold 0.811) — i.e., when the model emits the right *number* of nodes, its edges are mostly correct. The problem is almost never edge direction; it is node granularity and parallel-group expression.
- SFT's real, measurable wins were: (a) **killing 2 malformed outputs** (format), and (b) **cutting node inflation 2.78×→1.13×** (granularity). Both help the 4-class bin without improving dependency reasoning.

### 1.4 Where the +0.233 actually came from (per-class, 4-class bin)

| Gold class (n) | base correct | gold correct | Δ |
|---|---|---|---|
| sequential (16) | 7 | **16** | **+9** |
| parallel (6) | 0 | 1 | +1 |
| mixed (8) | 4 | 1 | **−3** |
| **total (30)** | **11** | **18** | **+7** |

The entire headline gain is **sequential (+9)**, partially cancelled by a **mixed regression (−3)**. The eval is **53% sequential (16/30)**, so a model that simply emits one clean linear chain scores 0.53 on shape alone. **SFT taught a "collapse-to-a-clean-chain" prior that happens to match a sequential-heavy eval** — it does not generalize to parallel/mixed (gold mixed dropped from 4→1).

---

## 2. Error taxonomy (every wrong case categorized)

Counts sum exactly to each arm's failures (base 19 = 30−11; gold 12 = 30−18).

### 2.1 Base model — 19 failures

| Category | n | Note |
|---|---|---|
| Over-decomposition → shape flips to `mixed` | **14** | 7 `sequential→mixed`, 6 `parallel→mixed`, 1 `sequential→mixed` (non-inflated) |
| `mixed→sequential` collapse (over-decomp) | 3 | Loses the second parallel branch |
| **Malformed / empty output** | **2** | emitted `{}` (not a list) |

### 2.2 Gold model — 12 failures (all are *under-parallelization*)

| Category | n | Note |
|---|---|---|
| `mixed→sequential` (serialized the two domain pipelines) | **7** | Dominant gold failure |
| `parallel→sequential` (chained independent tasks) | 3 | |
| `parallel→mixed` / `parallel→sequential` (over-decomp) | 2 | |

**10 of 12 gold failures = failing to express parallelism.** The SFT model's prior is "chain everything."

### 2.3 Component-grouping per class (label-free, the capability view)

| | parallel (6) | sequential (16) | mixed (8) |
|---|---|---|---|
| base WCC-count hit | **4/6** | 13/16 | **0/8** |
| gold WCC-count hit | 2/6 | **16/16** | **0/8** |

Two findings the 4-class bin hides:
1. **On parallel grouping, base (4/6) actually *beats* the gold model (2/6)** — SFT's chaining prior *reduced* the model's willingness to emit independent roots.
2. **Mixed is 0/8 for both arms** on component grouping — a genuine, shared capability gap, not a metric artifact.

### 2.4 Concrete examples (quoted; `<-[...]` = `depends_on`)

**(A) Base over-decomposition — `decomp_parallel_0` (gold = parallel, 3 subtasks)**
Intent (abridged): *"three independent data-analysis tasks … imaging (threshold/label/watershed), transcriptomics (AWST), metagenomics (Kraken2 read extraction) … treat these as separate jobs."*
- GOLD: `1:imaging analysis<-[] | 2:transcriptomics analysis<-[] | 3:metagenomics analysis<-[]`
- GOLD-MODEL: `1:Imaging…<-[] | 2:Transcriptomics…<-[] | 3:Metagenomics…<-[]` ✓ (clean parallel)
- BASE: 9 nodes — imaging expanded to a 5-step chain (`2<-[1] … 5<-[4]`), then transcriptomics chain, etc. → scored `mixed`, **marked wrong despite 3 correct components**.

**(B) Gold mixed→sequential — `decomp_mixed_1` (gold = mixed, {2,2})**
Intent: dose–response + enzyme kinetics (biochemistry) **and** glycoengineering prep+analysis — two independent domain pipelines.
- GOLD: `1:biochemistry prep<-[] | 2:biochemistry analysis<-[1] | 3:glycoengineering prep<-[] | 4:glycoengineering analysis<-[3]` (two parallel 2-chains)
- GOLD-MODEL: `1:…<-[] | 2:…<-[1] | 3:…<-[2] | 4:…<-[3]` — **one straight chain**; the glycoengineering branch was serialized behind biochemistry. `mixed→sequential`.

**(C) Gold parallel→sequential — `decomp_parallel_44` (gold = parallel, 2 subtasks)**
- GOLD: `1:pathology analysis<-[] | 2:systems_biology analysis<-[]`
- GOLD-MODEL: `1:Aortic Imaging Analysis<-[] | 2:Boolean Network Predictive Performance<-[1]` — invented a dependency between two unrelated analyses.

**(D) Metric-artifact on the gold arm — `decomp_parallel_17` (gold = parallel, 2 subtasks)**
- GOLD-MODEL: `1:Proteomics…<-[] | 2:…<-[1] | 3:…<-[2] | 4:Immunology…<-[] | 5:…<-[4] | 6:…<-[5]` — this is **two parallel domain chains (WCC=2 = correct grouping)**, but `_structure_of` sees non-zero deps and labels it `mixed` → **marked wrong**. The coarse metric penalizes a structurally-correct answer.

---

## 3. Data-gap check (the decisive finding)

### 3.1 Training-set structure distribution (~12.3k rows)

| File | rows | schema | has `depends_on`? | parallel/mixed topology? |
|---|---|---|---|---|
| `decomp_intra.jsonl` | 2,010 | flat `[{sub_task, phase}]` | **0** | **0** (no edges at all) |
| `decomp_inter.jsonl` | 1,385 | `[{sub_task, order}]`, linear | **0** | **0** (linear `order` only) |
| `claude_decomp.jsonl` | 8,428 | `messages` (prose) | **0** | **0** (free-text) |
| `committee_decompose.jsonl` | 496 | — | **0** | **0** |
| **total** | **12,319** | | **0** | **0** |

**Not one training row contains a `depends_on` field. Not one contains a parallel (≥2 roots) or mixed structure.** The eval asks for `{"sub_task","order","depends_on"}` with parallel/sequential/mixed topology, and **that output schema and those structures have literally zero density in training.**

### 3.2 Tie each top failure mode to the data gap

| Failure mode | Data cause | Gap? |
|---|---|---|
| Base over-decomposition (14) | `decomp_intra` (2,010) is a **flat enumeration of every granular step with no grouping** → teaches "list everything" | **Yes** |
| Gold under-parallelization: mixed/parallel→sequential (10) | `decomp_inter` (1,385) is **all linear `order` chains**; **0** parallel/mixed examples → sequential prior, no parallel exemplar to imitate | **Yes (primary)** |
| Base malformed `{}` (2) | No structured `depends_on` target anywhere → format is unanchored | **Yes** |
| Edge-direction errors | ~none observed (edge-F1 0.81–0.89 when counts match) | No — not data-limited |

Every top failure traces to the same hole: **the dependency-structure behavior was never in the training data.** SFT could nudge granularity (toward `decomp_inter`'s coarser style) but could not teach a topology it never saw — which is exactly why mixed *regressed*.

### 3.3 Can the catalog supply the missing data?

`backend/database/galaxy_ai_tools.db` → `workflows` table = **4,210 rows**, with `workflow_json`, `step_metadata` (3,151 populated), `qc_steps` (389), `domain`. Reality check on edge availability:

- **Intra-workflow DAG edges are essentially absent from the catalog too:** only **2/4,210** workflows have explicit `input_connections`. `step_metadata` gives steps grouped by `phase` (e.g. "Core Analysis" → "Visualization & Output") — a weak *phase ordering*, not a true step→step DAG. So you **cannot** cheaply re-mine fine-grained intra-workflow `depends_on` for 2,010 workflows.
- **Inter-workflow structure is synthesizable and is what the eval actually tests.** The eval gold is literally built by composing *domain-labeled* pipelines (parallel = N independent domains; sequential = one domain's steps; mixed = per-domain prep→analysis pairs). The catalog has exactly the raw material: **domain** (independence → parallel roots) and **I/O types** in `step_metadata`/`workflow_json` (output-type→input-type match → a real sequential edge). `workflow_chains` (69 curated rows) is a seed for inter-workflow sequencing.

**Conclusion:** the right data to mine is **inter-workflow composition with explicit `depends_on`**, not intra-workflow edges (which the catalog lacks).

---

## 4. Recommendation — ranked (data vs algorithm)

### Rank 1 (highest leverage) — DATA: synthesize parallel/mixed decomposition with `depends_on` edges

Because the target behavior has **0% training density**, this is the binding constraint. Build ~3–5k decomposition rows **in the eval output schema** (`{"sub_task","order","depends_on"}`), mined/synthesized from the catalog:

1. **Parallel exemplars** — sample 2–4 catalog workflows from **distinct, I/O-disjoint domains**; emit each as a root (`depends_on=[]`). Target distribution ~25–30% parallel (eval is 20%, but training must over-represent the rare class).
2. **Sequential exemplars** — chain workflows where workflow A's output type matches workflow B's input type (from `step_metadata`/`workflow_json`), emitting `depends_on=[prev]`. Also **retrofit all 1,385 `decomp_inter` chains to carry explicit `depends_on`** (currently only `order`).
3. **Mixed exemplars (the 0/8 class)** — per-domain `prep→analysis` pairs across 2 independent domains, exactly the eval's construction; two parallel 2-chains → partition `{2,2}`. This is the single most under-represented pattern and the one both arms fail completely.
4. **Granularity anchoring** — emit subtasks at **workflow/phase granularity** (not per-tool) to directly counter base's 2.78× over-decomposition. Add a few "list-then-group" negatives if using DPO/contrastive pairs.

**Why this first:** no algorithm can learn a structure that appears zero times in the SFT target without the data showing it at least once; GRPO rollouts from a policy that emits mixed ~1/8 of the time will almost never hit a correct mixed DAG to reward, so the reward signal is too sparse to bootstrap. Fix the data density first. **Expected lift is the largest of any single change** — it is the only intervention that touches the actual root cause (0/12,319 coverage), and it directly targets both dominant failure modes (over-decomposition and under-parallelization).

### Rank 2 — ALGORITHM: GRPO on node/edge-F1 + a catalog structural verifier (second stage, after Rank 1)

Once the policy produces correct parallel/mixed DAGs with non-trivial frequency, reward-shape it:
- **Reward = edge-F1 + WCC-partition match** (label-free, exactly the §1 metric) — not the 4-class bin, which is too coarse to give gradient.
- **Catalog structural verifier** as a hard reward gate / self-consistency filter: (a) every named tool/workflow exists in the catalog; (b) each `depends_on` edge is type-consistent (producer's output type ⊇ consumer's input type, from `step_metadata`); (c) the DAG is acyclic. Sample k decompositions, keep the verifier-max. This closes the "plausible but non-executable" gap and is cheap on CPU.

### Rank 3 — Retrieval-augmented decomposition

Condition generation on the 2–3 most similar **validated** catalog pipelines (the 1,092-workflow validated subset / `workflow_chains`) retrieved by the intent embedding. Gives the model a real structural template to imitate at inference. Good complement to Rank 1; lower ceiling alone because retrieval can't fix a policy that ignores the retrieved parallelism.

### Rank 4 — Grammar-constrained DAG decoding

Constrain decoding to valid `[{sub_task,order,depends_on:[ints<order]}]` JSON. **Eliminates the malformed-output class entirely** (base's 2 empties) and guarantees acyclicity, but does **not** teach *when* to branch — so it's a correctness floor, not a capability lift. Cheapest to ship; smallest behavioral effect.

**Single change with the biggest expected lift: Rank 1 (data).** It is the only option that addresses the 0% coverage root cause and simultaneously attacks the two dominant failure modes; everything else refines a policy that first needs to have seen the structure.

---

## 5. Honesty / statistical limits

- **n=30 is far too small for any taxonomy claim to be robust.** Per class: parallel n=6, sequential n=16, mixed n=8. A single item flip moves a per-class rate by 0.06–0.17. The per-class numbers in §2.3 are **directional, not inferential**.
- **The headline gain is not statistically significant.** Paired **McNemar exact two-sided p = 0.092** (discordant pairs: 10 gold-only gains, 3 base-only losses). Wilson 95% CIs: base `structure_accuracy` [0.219, 0.545] vs gold [0.423, 0.754] — **substantial overlap**. We cannot claim at α=0.05 that gold > base on this benchmark.
- **The real-capability metric shows essentially no movement.** WCC-count match: base 0.567 [0.392, 0.726] vs gold 0.600 [0.423, 0.754] — CIs almost fully overlap. The defensible statement is: *SFT improved output format and granularity-conformance; there is no statistically supported evidence it improved dependency-structure reasoning.*
- **The gold node labels are synthetic templates**, so this eval can only measure **topology shape**, never node/tool correctness. The task's requested node-F1/edge-F1 *on tool identity* cannot be computed here.
- **A larger, real held-out decomposition benchmark is a prerequisite** before trusting any taxonomy or claiming a capability gain. It must: (a) use **real tool/workflow nodes** (from the catalog, so node-F1 and type-checked edge-F1 become computable); (b) carry **explicit parallel/sequential/mixed labels balanced ~1:1:1** (not 53% sequential, which lets a "always-chain" prior score 0.53); (c) be drawn from **held-out** workflows not in the training mine; and (d) target **n≥150** (≥50/class) so per-class rates have ±0.07 CIs. Build this *before* reading much into any future decomposition score — including after the Rank-1 data fix.

---

## 6. Artifacts & reproduction

- Predictions pulled read-only: `…/spot_harness_gold_20261006_120457/results/{base,gold}/task_decomposition.jsonl` (30 rows each, ids match the 30-row gold).
- Scorer: `evaluation/datasets/public_export/score.py` (`score_task_decomposition`, `_structure_of`).
- Gold: `evaluation/datasets/public_export/task_decomposition/data.jsonl`.
- Training: `docs/20260912_onprem_llm/data_pool_v2/{decomp_intra,decomp_inter,claude_decomp,committee_decompose}.jsonl`.
- Catalog: `backend/database/galaxy_ai_tools.db` → `workflows` (4,210), `workflow_chains` (69).
- All metrics computed on CPU; no model, GPU, or serving endpoint touched.
