# On-prem 9B Task-Decomposition — STAGE-2 Algorithm Harness (GRPO + verifiable reward + re-ranker)

**Date:** 2026-10-06
**Author:** Yaoyun Zhang · xiaoni5122@gmail.com
**Scope:** CPU authoring + unit-level dry-run only. **No GPU, no training launch, no serving.** Builds the STAGE-2 lever on top of the SFT-decomp data fix; consumes whatever checkpoint the separate retrain produces.
**Builds on:**
- `docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md` — decomposition was never trained (0/12,319 rows carry `depends_on`; 0 parallel/mixed); the honest metric is node/edge-F1, not the 4-class bin; the dominant residual failure is **under-parallelization** ("chain everything").
- `docs/20260912_onprem_llm/20261006_DECOMP_DATA_AND_BENCHMARK.md` — STAGE-1 data fix: `decomp_depgraph.jsonl` (4,300 rows with edges) + held-out `decomposition_v2` benchmark (165, 1:1:1, real catalog nodes) + graph-aware `score.py`.

---

## 0. TL;DR

- **Why STAGE-2 at all.** STAGE-1 (data) manufactures the 0%→present density of `depends_on`/parallel/mixed, which is the binding constraint. But SFT maximizes likelihood of one gold target; it cannot directly optimize the *graph-correctness* reward, and the error analysis showed SFT's prior collapses to a clean chain (parallel 4/6→2/6, mixed 0/8). GRPO on a **verifiable** reward optimizes exactly the thing we measure, and the inference re-ranker buys lift with no training at all.
- **Three deliverables, all authored + dry-run-proven on CPU:**
  1. **Verifiable reward** — `evaluation/local_trial/decomp_reward.py`. Reuses the benchmark node/edge-F1 scorer as the gold-grounded core **plus** a gold-free **catalog structural verifier** (node existence, edge type-match, parallel disjointness, acyclicity/well-formedness) against `galaxy_ai_tools.db`. Pure, deterministic, ~0 ms/rollout after a one-time catalog index. **Dry-run: oracle 0.988, all-chain 0.797, all-parallel 0.714, over-decomp 0.552, malformed −0.367** — and on the capability-failing classes the gap is sharp (parallel: oracle 1.00 vs all-chain **0.525**).
  2. **GRPO trainer** — `evaluation/local_trial/train_grpo_decomp.py` + `spot_grpo_decomp_entry.sh` + `run_grpo_decomp_9b.sh`. TRL `GRPOTrainer`, QLoRA 4-bit, group rollouts, KL-anchored to the SFT-decomp policy, `save_steps` + an optional held-out eval hook. **Written, parameterized, dry-run-verified (4,300 prompts build; oracle is the group-max reward). NOT launched.**
  3. **Self-consistency + verifier re-ranker** — `evaluation/local_trial/decomp_reranker.py`. Inference-time, no training: sample N, keep the max-structural-verifier plan. **Dry-run: structure_accuracy 0.333→0.770 (+0.436), parallel 0.00→1.00, mixed 0.00→0.56**, with no gold and no training.
- **Launch is one command, gated on the retrain checkpoint** (`run_grpo_decomp_9b.sh`; refuses to start until `sft_decompv2_adapter` exists on S3).
- **Single knob to tune first: the KL coefficient `beta`** (§7). It governs whether GRPO can shift the structure distribution off the SFT chain-prior without hacking the gold-free structural term or collapsing. Reward weight `w_edge` is the close second.

---

## 1. Where STAGE-2 sits in the pipeline

```
clean base ──SFT(gold mix)──> SFT ──SFT(+decomp_depgraph.jsonl)──> SFT-decomp ──GRPO(verifiable reward)──> GRPO-decomp
                                   └ STAGE-1 (data, done)              │  KL-anchored to SFT-decomp
                                                                       └ serve-time: self-consistency + verifier re-ranker (no train)
```

- **STAGE-1 = data** (done, separate retrain running). It is the root-cause fix; without it GRPO has nothing to reward (a policy that emits mixed ~1/8 almost never produces a correct mixed DAG to reinforce — the error analysis's explicit warning).
- **STAGE-2 = this harness.** Two independent levers that stack:
  - **GRPO** (needs the checkpoint + GPU) — shifts the policy's *structure distribution* toward graph-correct decompositions by optimizing the reward directly.
  - **Re-ranker** (needs only a serving endpoint) — ships immediately, orthogonal to GRPO, and also serves as the GRPO reward's sanity twin (same verifier).

---

## 2. Deliverable 1 — Verifiable reward (`decomp_reward.py`)

### 2.1 Specification

`reward = w_node · node_f1 + w_edge · edge_f1 + w_struct · struct_validity − malformed_penalty`

Defaults: `w_node=0.30, w_edge=0.40, w_struct=0.30, malformed_penalty=0.5`. Bounded in `[−0.5, 1.0]`.

**(A) Gold-grounded core — node-F1 + edge-F1.** Imported from `evaluation/datasets/decomposition_v2/score.py::score_one` (single source of truth — no re-implementation). node-F1 = greedy bipartite token-match of predicted `sub_task` to gold `{sub_task, domain, tool_id}`; edge-F1 = directed `depends_on` edges recovered on matched nodes. These anchor the reward so that degenerate structures can't win on shape alone (all-parallel tanks edge recall; over-decomposition tanks node precision).

**(B) Catalog structural verifier — gold-free** (`structural_validity`), against `backend/database/galaxy_ai_tools.db` → `workflows`:
- **(a) node existence** — every predicted `sub_task` resolves to a real catalog workflow (exact normalized-name → tool-id exact → token-F1 ≥ 0.34 fallback). Fraction resolved.
- **(b) edge type-match** — each `depends_on` edge `u→v` is a real `output_types(u) ∩ input_types(v) ≠ ∅` overlap (catalog I/O). Fraction of edges that are type-consistent.
- **(c) parallel disjointness** — independent roots (`depends_on==[]`) are pairwise I/O-disjoint (no chaining in *either* direction). Fraction of disjoint root pairs.
- **(d) acyclic + well-formed** — DFS cycle check; every `depends_on` references an existing, non-self `order`.

`struct_validity = 0.35·node_exist + 0.25·edge_type + 0.20·parallel_disjoint + 0.10·acyclic + 0.10·wellformed`, with edge/parallel terms defaulting to 1.0 when N/A (a pure-parallel plan has no edges to type-check; a pure-chain has no parallel roots) — the gold-grounded node/edge-F1 keeps those defaults honest.

**Purity / determinism / speed:** no network, no randomness; the catalog is parsed once into a module-level, path-keyed cache (`load_catalog`); per-call cost is set-intersections over small precomputed token/type sets. Safe to call once per rollout, thousands of times.

### 2.2 TRL adapter

`make_trl_reward_fn(gold_by_prompt, db_path, weights)` returns a `reward_fn(prompts, completions, gold=None, **kw) -> list[float]` matching TRL `GRPOTrainer`'s `reward_funcs` contract. The GRPO dataset carries the gold DAG as a `gold` column (JSON string); TRL forwards dataset columns as kwargs, so the reward reads `gold` per-rollout. Handles both string and conversational (`[{role,content}]`) completion formats.

### 2.3 Dry-run proof (CPU, no model) — `proofs/reward_selftest.txt`

`python3 decomp_reward.py --selftest` over all 165 benchmark rows, scoring 5 synthetic candidate types derived from each gold:

| candidate | overall mean reward | parallel | sequential | mixed |
|---|---|---|---|---|
| **oracle** (= gold) | **0.9882** | 1.0000 | 0.9809 | 0.9836 |
| all_chain ("chain everything") | 0.7967 | **0.5250** | 0.9809 | 0.8841 |
| all_parallel (drop all edges) | 0.7136 | 1.0000 | 0.5564 | 0.5844 |
| over_decomp (2× node inflation) | 0.5520 | 0.8164 | 0.4032 | 0.4363 |
| malformed (`{}`) | **−0.3667** | −0.100 | −0.500 | −0.500 |

**Reading it:** oracle is the clear max everywhere; malformed is pushed negative; and the two degeneracies are penalized exactly where they hurt — **all-chain collapses on `parallel` (1.00→0.525, a 0.475 gap)** and all-parallel collapses on `sequential`/`mixed`. That per-class contrast is the GRPO gradient: on a parallel/mixed prompt, a chain rollout is scored well below a correctly-grouped rollout, so GRPO's within-group advantage is positive for the correct structure. Self-test asserts oracle>0.85, oracle−allchain>0.1, malformed<0 → **PASS**.

---

## 3. Deliverable 2 — GRPO trainer (`train_grpo_decomp.py`)

### 3.1 Design

- **Start policy = the SFT-decomp adapter** (the separate retrain's `sft_decompv2_adapter`). GRPO's reference model is the frozen initial policy, so **the KL term anchors to SFT-decomp behaviour** — it preserves the parallel/mixed density STAGE-1 installed while the reward shifts the policy toward graph-correctness. This is the task's "KL-anchor to the SFT policy", for free, by construction.
- **Group rollouts** (`num_generations=8`) per prompt; reward via Deliverable 1. GRPO normalizes rewards *within* each group, so only the reward's **relative ordering** of a prompt's rollouts matters — which the §2.3 dry-run verifies.
- **GRPO prompts** are built from the **TRAIN pool** of `decomp_depgraph.jsonl` (`build_prompts`), reusing STAGE-1's hash split so `decomposition_v2` stays a true held-out gauge. 4,300 prompts; each carries its gold DAG.
- **QLoRA** 4-bit nf4 + `paged_adamw_8bit` + gradient checkpointing, LoRA r16/α32 on all attn+MLP projections — identical to the proven SFT/DPO setup (`train_dpo_grounded.py`), so the resulting adapter loads in the eval shim unchanged.
- **save_steps** (default 25, resume-safe, mirrored to S3 by the entry script).
- **Eval hook** (`make_eval_callback`, `EVAL_HOOK=1`): at each save, greedily generates on a 30-row `decomposition_v2` slice and logs `node_f1/edge_f1/structure_accuracy` via the benchmark scorer — so capability (not just reward) is tracked during the run.

### 3.2 Pinned deps

Same venv as SFT (`today_bootstrap.sh`): `torch==2.14.1 transformers==5.18.0 trl==1.14.1 peft==0.21.2`. **trl 1.14.1 ships `GRPOTrainer`/`GRPOConfig`** (verified against the pin in `today_bootstrap.sh`).

### 3.3 Dry-run proof (CPU, no model) — `proofs/grpo_dryrun.txt`

`python3 train_grpo_decomp.py --dry-run …` builds the dataset + reward + config without loading a model:

```
[dry-run] GRPO prompts built: 4300 (from decomp_depgraph.jsonl)
[dry-run] catalog indexed:    4210 workflows
[dry-run] reward over a simulated rollout group (prompt 0, struct=mixed):
            oracle        reward=+1.0000
            all_chain     reward=+0.8950
            all_parallel  reward=+0.5800
            malformed     reward=-0.5000
[dry-run] OK — oracle is the group-max; GRPO advantage would be positive for it.
DRY_RUN_OK
```

### 3.4 Launch command (READY — not run)

Gated: `run_grpo_decomp_9b.sh` refuses to launch until `…/models_20260919/med/sft_decompv2_adapter/adapter_config.json` exists on S3 (don't RL from the wrong policy).

```bash
cd evaluation/local_trial
# defaults: MAX_STEPS=400 SAVE_STEPS=25 NUMGEN=8 BETA=0.04 TEMP=0.9 LR=1e-6 BS=2 GA=8
#           reward weights 0.30/0.40/0.30, EVAL_HOOK=1
bash run_grpo_decomp_9b.sh
# -> spot g6/g5 24GB+, resume-safe, self-terminating; final adapter:
#    s3://biomate-models-399683337364/biomate-core-local-trial/20260912/models_20260919/med/grpo_decomp_adapter/
```

Then evaluate with the existing harness: `spot_harness_decompv2_entry.sh` (base vs GRPO arm) → `decompv2_runner.py` + `score.py` on held-out `decomposition_v2`. **Capability signal = `node_f1`, `edge_f1`, and per-class `structure_accuracy` (especially `parallel`/`mixed`)** — not the old 4-class average.

---

## 4. Deliverable 3 — Self-consistency + verifier re-ranker (`decomp_reranker.py`)

### 4.1 Design (inference-time, no training)

The error analysis showed the SFT policy often *can* produce the right grouping but doesn't pick it greedily (it defaults to chaining). So: sample N decompositions at `temperature>0`, score each with the **gold-free** structural verifier (Deliverable 1's `structural_validity`), keep the best. `rerank_from_endpoint(client, …)` wires it into the serve path (same prompt/parse convention as `decompv2_runner.py`), falling back to greedy if all N are malformed. Pure selection (`rerank`) is deterministic given the candidate set.

### 4.2 Dry-run proof — `proofs/reranker_selftest.txt`

No real base/SFT rollouts for `decomposition_v2` exist on disk (the error-analysis preds are the OLD `task_decomposition` eval on S3). So the self-proof constructs, per prompt, a **deliberately pessimistic** candidate set `[all_chain(modal), all_parallel, oracle, over_decomp, all_chain]` — the correct grouping is the *minority* sample and the modal/first pick is the all-chain failure. Selecting by the gold-free verifier, then scoring against gold:

| metric | greedy (no re-rank) | verifier re-rank | Δ |
|---|---|---|---|
| node_f1 | 1.0000 | 1.0000 | +0.0000 |
| edge_f1 | 0.6000 | 0.7697 | **+0.1697** |
| structure_accuracy | 0.3333 | 0.7697 | **+0.4364** |
| wcc_count_match | 0.3333 | 0.7697 | +0.4364 |
| parallel_width_match | 0.3333 | 0.7697 | +0.4364 |
| **parallel** struct acc | 0.0000 | **1.0000** | +1.0000 |
| sequential struct acc | 1.0000 | 0.7455 | **−0.2545** |
| **mixed** struct acc | 0.0000 | **0.5636** | +0.5636 |

**Reading it:** with no gold and no training, the verifier recovers parallel (0→1.0) and mixed (0→0.56) from a chain-defaulting sampler. The **sequential −0.25 regression is an honest limitation**: the gold-free verifier sometimes prefers an all-disjoint plan over a weakly-typed chain (catalog I/O overlap is heuristic, §6). Two mitigations, both cheap: (i) keep a small bias toward the greedy/first sample on near-ties (the verifier already breaks ties toward earlier candidates); (ii) at serve time the re-ranker is a *complement* to the GRPO policy, which carries the gold-trained chain prior the verifier lacks. The lift is dominated by the parallel/mixed recovery, which is the capability we set out to fix.

---

## 5. Deliverable 4 (sketch) — Grammar-constrained DAG decoding

Not built (correctness-floor, smallest behavioural lift per the error analysis), but specified so it's ready if malformed outputs reappear:

- Constrain decoding to the JSON grammar `[ {"sub_task": <str>, "order": <int>, "depends_on": [<int < order>]} , … ]` via a token-level logits processor (e.g. `outlines`/`lm-format-enforcer`, or a hand-rolled `LogitsProcessor` keyed on a small pushdown state). Enforce (i) valid JSON list, (ii) `order` strictly increasing, (iii) every `depends_on` element `< order` (guarantees acyclicity by construction), (iv) `sub_task` constrained to a trie of catalog workflow/tool names when node identity should be hard-grounded.
- **Effect:** eliminates the malformed class entirely and guarantees acyclic, well-formed, in-catalog output — but does **not** teach *when* to branch. Pairs well with the re-ranker (constrain each of the N samples) and with GRPO (removes malformed rollouts from the group, concentrating the reward signal on structural choices). Ship only if malformed/non-acyclic rates are non-trivial after GRPO; otherwise the `malformed_penalty` + well-formedness term already covers it.

---

## 6. Honesty — expected lift, limits, assumptions

- **Expected lift is modest and must be measured, not assumed.** The error analysis showed base→SFT moved the *real* metric (WCC-count) only +0.033 and was not significant at n=30. STAGE-1 (data) is the big lever; STAGE-2 refines on top. Realistic GRPO expectation: **recover the parallel regression (parallel WCC 2/6→≥4/6) and push mixed off 0/8**, i.e. gains concentrated in the two failing classes, with `edge_f1` and per-class `parallel`/`mixed` structure as the headline — *not* a large average jump (the benchmark is balanced 1:1:1, so an always-chain prior only scores ~0.33, and most of the room is in parallel/mixed). The re-ranker's dry-run (+0.44 structure on a pessimistic candidate set) is an upper-ish bound on the no-train lift; the real lift depends on how often the served policy samples a correct grouping at all.
- **node-F1 is granularity-tolerant by design** (token overlap vs `sub_task`/`domain`/`tool_id`), so it reads as "right sub-tasks at domain/tool granularity", not "guessed the exact slug". Don't over-read small node-F1 moves.
- **Catalog I/O is heuristic** (extracted, not execution-verified), so a type-overlap edge is *plausible*, not a proven runtime binding. The structural verifier is stronger than the eval's synthetic placeholders but is not an executor.
- **The benchmark is synthetic composition** (real nodes, type-checked edges, held-out — but composed, not harvested from real multi-pipeline sessions). A GRPO gain on it is evidence of learned inter-workflow composition, bounded by that caveat.
- **GRPO prompts and the benchmark share the STAGE-1 hash split**, so there is no train/eval workflow overlap — but both are drawn from the same catalog mine, so the benchmark tests generalization *within* the synthetic-composition distribution, not to naturally-occurring user compositions.

### Risks and mitigations

- **Reward hacking.**
  - *All-parallel to farm the disjointness/edge-N/A defaults* → blocked by gold edge-F1 recall (missing edges on sequential/mixed golds tank the score) and by KL to SFT. Dry-run confirms all-parallel = 0.556 on sequential.
  - *Over-decomposition to farm node existence* → blocked by node-F1 **precision** (extra nodes lower it); dry-run over_decomp = 0.552. If it emerges, add an explicit node-count penalty `max(0, |pred|−|gold|)·λ` (hook left in the reward via `malformed_penalty`-style term).
  - *Catalog name-spamming* (emit plausible real names regardless of query) → node-F1 matches against the prompt's gold, so off-query names don't match. The gold-free struct term alone could be farmed, which is exactly why it is only 30% of the reward and KL-anchored.
- **KL collapse / reward over-optimization** → low `lr` (1e-6), `beta=0.04` KL anchor, `num_generations=8` for a stable group baseline, `save_steps=25` + the eval hook to catch divergence between reward↑ and capability↓ (the classic over-optimization signature). If `node_f1` on the eval hook drops while reward rises, raise `beta`.
- **Sparse reward if STAGE-1 under-delivered** → if the SFT-decomp policy still rarely emits parallel/mixed, GRPO groups will be near-uniformly chains (no advantage signal). Mitigation: raise rollout `temperature` (0.9→1.1) for diversity, and lean on the re-ranker (which needs no positive-rate assumption) until data density is sufficient. **Check the SFT-decomp eval-hook parallel/mixed rate before committing GPU hours.**
- **Generation-batch divisibility** — on the box, verify `per_device_train_batch_size` × processes is compatible with `num_generations=8` (TRL constraint); `BS=2, GA=8` is the intended single-GPU shape.

---

## 7. The single knob to tune first

**`beta` (the KL coefficient), default 0.04.** The entire STAGE-2 premise is to move the policy *off* the SFT chain-prior toward graph-correct structure **without** (a) hacking the 30% gold-free structural term or (b) collapsing away from the parallel/mixed density STAGE-1 installed. `beta` is the one dial that trades those off: too low → reward over-optimization / hallucinated disjoint plans; too high → the policy never leaves the SFT chain-prior and GRPO is a no-op. Sweep `beta ∈ {0.02, 0.04, 0.08}` first, reading the eval-hook `parallel`/`mixed` `structure_accuracy` against reward — pick the largest `beta` that still moves parallel/mixed.

Close second: **`w_edge`** (reward weight on edge-F1, default 0.40). Nodes are already ~1.0 after SFT; the capability gap is *edges/parallel expression*, so edge-F1 should carry the most gradient. If parallel/mixed stall at fixed `beta`, raise `w_edge` to 0.50 (borrow from `w_struct`).

---

## 8. What is ready to launch once the retrain checkpoint lands

1. `evaluation/local_trial/decomp_reward.py` — verifiable reward + catalog verifier + TRL adapter. **Dry-run PASS.**
2. `evaluation/local_trial/decomp_reranker.py` — serve-time re-ranker. **Dry-run PASS (+0.44 structure, no train).** Can wire into the serve path today (needs only an endpoint).
3. `evaluation/local_trial/train_grpo_decomp.py` — GRPO trainer. **Dry-run PASS (dataset + reward + config build; oracle is group-max).**
4. `evaluation/local_trial/spot_grpo_decomp_entry.sh` + `run_grpo_decomp_9b.sh` — spot launch, resume-safe, **gated on `sft_decompv2_adapter`**. `bash -n` clean.
5. Eval loop already exists: `spot_harness_decompv2_entry.sh` + `decompv2_runner.py` + `evaluation/datasets/decomposition_v2/score.py`.

**To launch (after the retrain's `sft_decompv2_adapter` is on S3):** stage `decomp_depgraph.jsonl` → `$S3/sft/`, confirm the verifier DB is at `$S3/eval/harness_payload/galaxy_ai_tools.db`, then `bash run_grpo_decomp_9b.sh`. **First action before spending GPU hours:** read the SFT-decomp eval-hook parallel/mixed emission rate; if it's near-zero, GRPO's reward is too sparse — ship the re-ranker and push STAGE-1 density further instead.

---

## 9. Artifacts

- Reward + verifier: `evaluation/local_trial/decomp_reward.py`
- Re-ranker: `evaluation/local_trial/decomp_reranker.py`
- GRPO trainer: `evaluation/local_trial/train_grpo_decomp.py`
- Launch: `evaluation/local_trial/spot_grpo_decomp_entry.sh`, `evaluation/local_trial/run_grpo_decomp_9b.sh`
- Dry-run proofs: `docs/20260912_onprem_llm/decomp_stage2_proofs/{reward_selftest,reranker_selftest,grpo_dryrun}.txt`
- Reused scorer / bench / data / DB: `evaluation/datasets/decomposition_v2/score.py`, `…/decomposition_v2.jsonl`, `docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl`, `backend/database/galaxy_ai_tools.db`
- All CPU-only; no model, GPU, or serving endpoint touched.
