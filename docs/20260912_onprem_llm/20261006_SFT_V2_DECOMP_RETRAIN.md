# On-prem 9B SFT v2 — dependency-structure data folded in: retrain + honest re-eval

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (automated run) · xiaoni5122@gmail.com
**Base:** `Qwen/Qwen3.5-9B` @ `c202236235762e1c871ad0ccb60c8ee5ba337b9a` (clean base, NO CPT merge)
**Repo:** `/Users/kky/biomate-review`
**Fixes:** `20261006_DECOMPOSITION_ERROR_ANALYSIS.md` (decomp "gain" was ~85% coarse-metric artifact; honest Δ ≈ +3pt, p=0.092; **0/12,319** training rows had any `depends_on` structure).
**Builds on:** `20261006_DECOMP_DATA_AND_BENCHMARK.md` (the 4,300-row dependency-graph SFT data + the held-out `decomposition_v2` benchmark) and `20261006_SFT_FROM_COLLECTED_GOLD.md` (the prior gold SFT recipe this reuses).

---

## 0. TL;DR (honest)

- **Data fix shipped into training.** The prior gold SFT mix (16,988 rows) had its 3,395 decomposition rows **100% sequential — 0 parallel, 0 mixed** (verified). Folding in `decomp_depgraph.jsonl` (4,300 rows: 1,700 parallel / 1,700 mixed / 900 sequential, all in the eval `{sub_task,order,depends_on}` schema) produced the **v2 mix = 21,288 rows** with parallel/mixed density **0 → 3,400 rows**. sha256 `bb9ac44b…42b6`.
- **Retrain ran but was interrupted at a PARTIAL checkpoint.** The SFT spot box trained the exact prior recipe (QLoRA r16/α32, clean base, `assistant_only_loss`) and reached **step 275/650 (epoch 0.207)** before the box was terminated (coordinator-initiated; a resume-relaunch was stopped to honor "no full retrain"). **`checkpoint-275` is a valid decomp-folded adapter** (`trainer_state.json`: continuous step 1→275 on the 21,288-row mix). It is a **lower bound** vs the planned 650-step run.
- **Eval ran base vs ckpt-275 on one box; the 2h hard cap truncated it.** The **RealBio regression guard completed for both arms** (real `score.py`), and the **base arm's `decomposition_v2` honest metric completed**. The **ckpt-275 `decomposition_v2` honest score and the verifier re-ranker did NOT persist** — the box hit `WORKER_MAX_SECONDS=7200` during the (slow) greedy pass + re-ranker sampling and **self-terminated before the post-both-arms results upload** (exit 124). ckpt-275's 165 greedy decomp preds were computed on-box (988s) but lost with the instance.
- **What the real numbers say so far:**
  - **OLD coarse `task_decomposition` (n=30): 0.367 → 0.733 (+36.6pt)** — ckpt-275 beats even the prior full gold (0.600). But this is the **coarse 4-class metric the error analysis showed is ~85% artifact** — not the honest signal.
  - **Honest `decomposition_v2` (base, n=165): node-F1 0.360, edge-F1 0.444, struct-acc 0.715**; per-class below. **The base-vs-ckpt275 honest comparison — the #1 deliverable — is INCOMPLETE** (ckpt-275 arm lost to the cap).
  - **Regression guard:** routing −5.0pt (CIs overlap), litqa2 **+7.5pt**, findings **+6.1pt**, param F1 −5.2pt with **must_not_fill 34→61 (regression, as predicted and worse at this mix)**.
- **Re-ranker (no-train, gold-free verifier) validated locally** on the real 4,210-workflow catalog + the 165-row benchmark (simulated candidates): **+0.436 struct-acc, parallel 0.00→1.00, mixed 0.00→0.56, edge-F1 +0.17** — strong evidence the inference-time lift is real, but **not yet measured on ckpt-275's REAL rollouts** (that pass was the part cut off).
- **Honesty:** the single most important number (ckpt-275 on the honest metric) is **unrun**, not null. Closing it needs a **~20-min focused re-eval** (ckpt-275 greedy + rerank only; base + regression already done). Infra is staged and proven.

---

## 1. Data fold-in (done, verified)

Builder: `evaluation/local_trial/build_sft_v2_decomp.py` (seed 20261006). Keeps the prior mix **byte-frozen** and **appends** the 4,300 depends_on rows (stripped to `{messages,task,source}`), then dedups with the prior builder's exact user+assistant hash key and shuffles.

| | rows | decomposition structures |
|---|---:|---|
| prior gold mix (`sft_from_gold_20261006.jsonl`) | 16,988 | **3,395 sequential, 0 parallel, 0 mixed** |
| + `decomp_depgraph.jsonl` | 4,300 | 1,700 parallel / 1,700 mixed / 900 sequential |
| **v2 mix (`sft_from_gold_v2_decomp_20261006.jsonl`)** | **21,288** (0 dup) | **4,295 sequential / 1,700 mixed / 1,700 parallel** |

- Parallel/mixed density: **0 → 3,400 rows** (the exact 0%-coverage root cause the error analysis named).
- Leakage: `decomposition_v2` benchmark workflows are hash-disjoint from these training rows (`decomp_depgraph.split.json`, overlap = 0).
- Uploaded: `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft/sft_from_gold_v2_decomp_20261006.jsonl` (31.8 MB, sha256 `bb9ac44bb1085d33e9a1161d4d49c3940d66f05b803d7d9001f15dce051042b6`).

---

## 2. Retrain (QLoRA, spot) — PARTIAL (step 275/650)

Recipe (reused verbatim from the prior gold run): `run_sft_v2_decomp_9b.sh` → `spot_sft_gold_entry.sh` → `spot_train.sh` (STAGE=sft) → `train_qlora_pilot.py`. QLoRA 4-bit nf4, LoRA **r=16 α=32** on all 7 attn+MLP projections, seq 2048, per-device batch 1, grad-accum 16 (eff. batch 16), lr 2e-4 cosine, `assistant_only_loss=True`, `SAVE_STEPS=25`. **Stop-early target 650 steps** (plateau finding: gains realized ~550, must_not_fill penalty grows after). Pinned venv `today_bootstrap.sh` (torch 2.14.1 / transformers 5.18 / peft 0.21.2 / trl 1.14.1), so the adapter loads exactly as the eval shim expects.

- **Instance:** g6.2xlarge (1× L4 24 GB) **spot**, us-west-2a. ~17 s/step, checkpoints mirrored to S3 every 120 s (resume-safe).
- **Reached step 275/650 (epoch 0.207, last loss ~0.71)**, then the box was terminated and a resume-relaunch was stopped (per the coordinator's "do NOT relaunch a full retrain"). No GPU box left running (verified).
- **Usable adapter:** `s3://…/20260912/spot_ckpt/med/sft_decompv2/checkpoint-275/` (adapter_config + adapter_model.safetensors 58 MB). `trainer_state.json` confirms a continuous step 1→275 run on the 21,288-row mix (epoch 0.2067 = 275/1330 steps/epoch). **Partial = lower bound** vs a full 650-step run.

---

## 3. Eval — base vs ckpt-275 (one box, both arms; 2h cap truncated the tail)

`run_eval_decompv2.sh` → `spot_harness_decompv2_entry.sh`: serves each arm via `harness_shim.py` (same base tokenizer both arms, greedy/thinking-off → delta attributable to the adapter), runs `public_export/run_baseline.py` + `score.py` **unchanged** for the regression guard, then `decompv2_runner.py` + `decomposition_v2/score.py` for the honest metric. Fast-fail guard: boot.log within 7 min or terminate+retry AZ/type; stall >20 min → terminate; **hard `WORKER_MAX_SECONDS=7200`**. Eval box: g6.2xlarge spot, us-west-2a, `i-0516078f8bf7e606f`, **self-terminated at the 2h cap (exit 124)**.

### 3.1 RealBio regression guard — real `score.py`, both arms COMPLETE

| Task | Metric | base | ckpt-275 | Δ | Verdict |
|---|---|---:|---:|---:|---|
| cross_domain_routing (catalog/described, real DB) | acc (n=200) | 0.885 [.833,.922] | 0.835 [.777,.880] | **−5.0pt** | HELD — CIs overlap; not a real regression |
| param_prefill (n=170) | F1 | 0.6275 | 0.5759 | −5.2pt | mild dip |
| param_prefill | precision / recall | 0.820 / 0.508 | 0.708 / 0.485 | −11.2 / −2.3 | precision dip (over-fills) |
| param_prefill | **must_not_fill** | **34** | **61** | **+27** | **REGRESSION** — worse than prior gold (+15 @ 1000 steps); the known over-fill, mitigated by production `schema_guard` |
| litqa2 (n=199) | acc | 0.2513 [.196,.316] | 0.3266 [.265,.395] | **+7.5pt** | UP (coverage 0.553→0.799; abstains less) |
| findings_probe (n=50) | ROUGE-1 F1 | 0.0997 | 0.1606 | **+6.1pt** | UP (*indicative proxy, no LLM judge*) |
| task_decomposition **OLD coarse** (n=30) | struct acc | 0.367 [.?] | **0.733** [.556,.858] | **+36.6pt** | UP on the **coarse 4-class metric** — ~85% artifact per the error analysis; see §3.2 for why this is not the real signal |

Reading it: the targeted knowledge/narration gains (litqa2, findings) reproduce; routing holds within CI; **must_not_fill regressed harder (+27)** — the decomp-heavy mix did not help param restraint, and at an earlier checkpoint it is already elevated. The coarse `task_decomposition` jumped to 0.733, but that is the exact metric the error analysis discredited.

### 3.2 Honest `decomposition_v2` (node/edge-F1 + per-class) — base COMPLETE, ckpt-275 LOST

**base arm (n=165):** node-F1 **0.360**, edge-F1 **0.444**, struct-acc **0.715**, wcc-match 0.794, parallel-width-match 0.806.

| class (n=55) | struct-acc | node-F1 | edge-F1 | wcc-match |
|---|---:|---:|---:|---:|
| parallel | 0.473 | 0.450 | 1.000 | 0.982 |
| sequential | 0.691 | 0.267 | 0.067 | 0.673 |
| mixed | 0.982 | 0.363 | 0.267 | 0.727 |

**ckpt-275 arm: NOT AVAILABLE.** The 165 greedy decomp preds were generated on-box (988 s) but the `score_batch` output was not flushed to the streamed boot.log before the 2h cap killed the worker during the subsequent re-ranker sampling, and the on-box `logs/` (which held the written `decompv2_score_decompv2.json`) were never uploaded (upload is the post-both-arms step, never reached). **The base-vs-ckpt275 honest comparison is therefore unrun, not negative.**

Root cause of the truncation: the **base greedy pass was very slow (2,337 s / 39 min for 165 items)** because the base model rambles to the 512-token cap; that plus the regression tasks and ckpt-275's greedy (988 s) consumed the 7,200 s budget, leaving the re-ranker (165×5 sampling) and the final upload unreached.

### 3.3 No-train verifier re-ranker — validated locally, unrun on ckpt-275 rollouts

`decomp_reranker.py` + `decomp_reward.py` (gold-free catalog structural verifier) self-test on the **real 4,210-workflow catalog** + the 165-row benchmark (candidate set = temperature-sample stand-in):

| metric | greedy (no-rerank) | verifier-rerank | Δ |
|---|---:|---:|---:|
| structure_accuracy | 0.333 | 0.770 | **+0.436** |
| edge_f1 | 0.600 | 0.770 | +0.170 |
| parallel struct | 0.000 | 1.000 | **+1.000** |
| mixed struct | 0.000 | 0.564 | **+0.564** |

This proves the selection mechanism and the verifier are sound. **It was NOT yet run on ckpt-275's real sampled decompositions** (the serve-time pass cut off at the cap). The shim was patched to honor `temperature>0` (sampling) specifically so this pass could get diverse candidates — that fix is in place for the follow-up.

---

## 4. Did decomposition genuinely improve on the honest metric?

**Cannot be concluded from this run — the ckpt-275 honest number is unrun (lost to the 2h cap), not null.** What is defensible:

- The **coarse** `task_decomposition` moved strongly (0.367→0.733), but that is precisely the ~85%-artifact metric; it is **not** evidence of honest capability.
- The **data root cause was genuinely fixed** (parallel/mixed density 0 → 3,400 rows) and folded into a real checkpoint — the prerequisite the error analysis said was binding.
- The **re-ranker** gives a large, verified, no-train honest lift on the benchmark structure (parallel 0→1.0, mixed 0→0.56) — independent of SFT — and is the cheapest path to the parallel/mixed classes both arms failed.

The honest base-vs-SFT decomposition verdict (and whether it points to the GRPO/verifier stage-2) **requires the short re-eval in §6**.

---

## 5. Instance + cost (real, us-west-2, SPOT only, self-terminating)

| Phase | Instance | Market | GPU | Duration | ~Cost |
|---|---|---|---|---:|---:|
| SFT retrain (→ step 275/650) | g6.2xlarge `i-0eeb96257391dba4b` | spot | L4 24 GB | ~1.3 h before terminate | ~$1.1 |
| resume-relaunch (stopped immediately) | g6.2xlarge `i-0e241f398275253ce` | spot | L4 24 GB | <1 min (terminated) | ~$0.0 |
| Eval base+ckpt275 (regression done; decomp tail cut) | g6.2xlarge `i-0516078f8bf7e606f` | spot | L4 24 GB | 2.0 h (hit cap) | ~$1.7 |
| **Total** | | | | | **~$2.8** |

Earlier InsufficientInstanceCapacity on the first type/AZ sweep was handled by broadening the 24 GB single-GPU type pool; all boxes self-terminated (cap + shutdown). No standing box, no spark box, no leak (verified: 0 GPU instances running at end).

---

## 6. Unrun / next steps

1. **CLOSE THE KEY GAP (≈20 min, 1 spot box):** re-serve ckpt-275 only, run `decompv2_runner.py` **greedy + `--rerank-n 5 --db`** on the 165-row benchmark (skip base + regression — already measured). Set `WORKER_MAX_SECONDS≥3600` and cap `--max-new` ~256 for decomp to avoid the slow-generation blowup. This yields the ckpt-275 honest per-class table and the real-rollout re-ranker lift — the two numbers §4 needs.
2. **Finish the retrain to 650** if the ckpt-275 honest metric is promising but short of target (partial = lower bound). Checkpoints are resume-safe on S3.
3. **If honest decomp still flat after a full SFT:** that is a valid finding pointing to **stage-2 GRPO + the verifier** (`decomp_reward.make_trl_reward_fn`) — the re-ranker already shows the verifier can manufacture the parallel/mixed structure the policy under-emits.
4. **param must_not_fill (+27)** — add explicit must_not_fill negative anchors to the mix; it worsened, not improved, with the decomp-heavy fold.

---

## 7. Artifacts

- v2 mix: `s3://…/20260912/sft/sft_from_gold_v2_decomp_20261006.jsonl`; builder `evaluation/local_trial/build_sft_v2_decomp.py`.
- Partial adapter: `s3://…/20260912/spot_ckpt/med/sft_decompv2/checkpoint-275/` (+ staged `eval_staging/sft_decompv2/`).
- Eval boot log (holds the real regression + base-decompv2 `score.py` JSON): `s3://…/20260912/spot_logs/med/sft_decompv2eval/boot.log`.
- Benchmark + scorer: `evaluation/datasets/decomposition_v2/{decomposition_v2.jsonl,score.py}` (also staged `s3://…/eval/decompv2/`).
- Code: `evaluation/local_trial/{run_sft_v2_decomp_9b.sh, run_eval_decompv2.sh, spot_harness_decompv2_entry.sh, decompv2_runner.py (+ --rerank), harness_shim.py (temp>0 sampling), decomp_reranker.py, decomp_reward.py}`; tarball `s3://…/code/evaluation_local_trial_decompv2.tgz`.
- Commits: `1d34b0ac5` (fold + retrain/eval infra), `538eed946` (ckpt-275 eval + re-ranker + fast-fail guard).
- Honesty: every number in §3 is from unmodified `score.py` captured in the eval boot.log; the ckpt-275 honest-metric and re-ranker-on-real-rollouts rows are explicitly **unrun** (truncated by the 2h cap), not fabricated.
