# On-prem 9B SFT v3 — REAL-distribution decomp + must_not_fill anchors: retrain + out-of-generator re-eval

**Date:** 2026-10-07
**Author:** Yaoyun Zhang (automated run) · xiaoni5122@gmail.com
**Base:** `Qwen/Qwen3.5-9B` @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a` (clean base, NO CPT merge)
**Repo:** `/Users/kky/biomate-review`
**Builds on:** `20261006_SFT_V2_DECOMP_RETRAIN.md` (the synthetic decomp win, in-distribution to one
generator) + `20261007_REAL_DECOMP_DATA.md` (219 real decomp rows + 68-row real held-out set + 854
must_not_fill anchors).

---

## 0. Why this run exists (the out-of-generator question)

The v2 win — decomposition_v2 node-F1 0.36→0.73, edge-F1 0.44→0.79 — folded **4,300 synthetic**
`depends_on` rows. But both the SFT rows **and** the decomposition_v2 benchmark were emitted by the
same constructor (`build_decomp_depgraph.py`), so the result is **in-distribution to that one
generator**. The synthetic distribution is also *backwards* vs reality: synthetic is 21/40/40
seq/mixed/parallel with **zero diamonds** and depth ≤4; REAL is 94/4/2 seq/mixed/parallel with
fan-in up to 10 and depth 11 (`20261007_REAL_DECOMP_DATA.md`).

This run (v3) answers the question the prior win could not: **does the decomposition capability
transfer to the real distribution?** It (a) folds 219 real decomp rows + 854 must_not_fill anchors
into the mix and (b) scores base-vs-ckpt on `decomposition_real` — a 68-row held-out set whose
topologies (real nf-core channel graphs, curated workflow_chains, GTN tutorials) we did **not**
design.

**Honesty frame:** the real val set is small (n=68) and thin on non-sequential (60 sequential, 5
mixed, 3 parallel). Overall node/edge-F1 is the signal; per-class is **directional only**. If the
real-distribution number does **not** improve over base, that is the finding — it would say the
synthetic win did not transfer.

---

## 1. Data fold-in (done, verified)

Builder: `evaluation/local_trial/build_sft_v3_real.py` (seed 20261006). Keeps the v2 mix
**byte-frozen** and **appends** the real rows, stripped to the uniform `{messages, task, source}`
schema, then dedups with the exact prior user+assistant hash key and shuffles.

| source | rows |
|---|---:|
| v2 mix (`sft_from_gold_v2_decomp_20261006.jsonl`, sha256 `bb9ac44b…`) | 21,288 |
| + `decomp_real.jsonl` (real nf-core/chain/GTN DAGs) | 219 |
| + `param_mustnotfill_neg.jsonl` (real restraint anchors) | 854 |
| **v3 mix (`sft_from_gold_v3_real_20261007.jsonl`)** | **22,361** (0 dup) |

- **sha256** `84244779a7901e71030f7ddff89b2dc146e8f392ae2c079b8c07686d4bf51afa`
- Real `real_*` source rows in the final mix: `real_params_schema_restraint` 785 +
  `real_grounded_param_restraint` 69 (= 854 anchors) + `real_gtn_tutorial` 156 +
  `real_workflow_chain` 45 + `real_nfcore_subworkflow` 18 (= 219 decomp).
- Decomposition structure distribution after fold: sequential 4,505 / mixed 1,706 / parallel 1,703
  (the +210 seq / +6 mixed / +3 par deltas vs v2 match the `decomp_real` train split exactly).
- **Leakage checks (both clean):**
  - `decomp_real` train units (219) vs `decomposition_real` val units (68): **unit overlap = 0**.
  - 854 must_not_fill anchors vs the 170-row `param_prefill` eval: **0 exact-query, 0 substring** overlap.
- Uploaded: `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft/sft_from_gold_v3_real_20261007.jsonl` (32.8 MB).

---

## 2. Retrain (QLoRA, SPOT) — recipe

Exact prior recipe (`run_sft_v3_real_9b.sh` → `spot_sft_gold_entry.sh` → `spot_train.sh` STAGE=sft →
`train_qlora_pilot.py`): QLoRA 4-bit nf4, LoRA **r=16 α=32** on all 7 attn+MLP projections, seq 2048,
per-device batch 1, grad-accum 16 (eff. batch 16), lr 2e-4 cosine, `assistant_only_loss=True`,
**SAVE_STEPS=25** (intermediate checkpoints evaluable + S3-mirrored every 120 s, resume-safe).
**Stop ~550 steps** (the v2 plateau: gains realized ~550, must_not_fill penalty grows after).
Pinned venv via `today_bootstrap.sh` (torch 2.14.1 / transformers 5.18 / peft 0.21.2 / trl 1.14.1),
so the adapter loads exactly as the eval shim expects. TAG `_sftv3real` (prior adapters untouched).

<!-- RESULTS_RETRAIN -->

---

## 3. Eval — base vs ckpt (greedy, real score.py, incremental upload)

`run_eval_sftv3real.sh` → `spot_harness_sftv3real_entry.sh`: serves each arm via `harness_shim.py`
(same base tokenizer both arms, greedy/thinking-off → delta attributable to the adapter alone).
Per arm, in this order so a cap can never lose the headline: **(A) decomposition_real** (headline),
**(B) decomposition_v2** (comparison), **(C) regression guard** (param_prefill incl. must_not_fill,
cross_domain_routing, litqa2, findings_probe, task_decomposition old-coarse). Decomp runner capped at
`--max-tokens 256` (the 512 cap caused the v2 39-min base pass). **Every score is uploaded to S3 the
moment it computes** — the v2 eval lost its tail to a 2 h cap because it uploaded only at the end.

<!-- RESULTS_EVAL -->

---

## 4. Instance + cost

<!-- RESULTS_COST -->

---

## 5. Artifacts

- v3 mix: `s3://…/20260912/sft/sft_from_gold_v3_real_20261007.jsonl`; builder `evaluation/local_trial/build_sft_v3_real.py`.
- Real benchmark + scorer: `evaluation/datasets/decomposition_real/{decomposition_real.jsonl,score.py}` (staged `s3://…/eval/decompreal/`).
- Code tarball: `s3://…/20260912/code/evaluation_local_trial_sftv3real.tgz`.
- Launchers / entries: `evaluation/local_trial/{run_sft_v3_real_9b.sh, run_eval_sftv3real.sh, spot_harness_sftv3real_entry.sh}`.

<!-- RESULTS_ARTIFACTS -->

---

## 6. Unrun / next steps

<!-- RESULTS_NEXT -->
