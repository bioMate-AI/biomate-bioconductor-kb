# On-prem own-LLM — SFT / DPO / RLVR status (grounded)

**Date:** 2026-10-15 · Internal. Factual status of the drug-discovery on-prem own-model's supervised
fine-tuning, preference tuning, and reinforcement-learning-from-verifier work. Every row is flagged
**MEASURED** (a real eval ran) / **BUILT-NOT-RUN** / **PLANNED**. Numbers are from the repo's own result docs;
where a doc still has `<!-- RESULTS_* -->` placeholders the run did not happen.

**Model under test:** `Qwen/Qwen3.5-9B` clean base (no CPT merge), QLoRA r16/α32 on all attn+MLP projections,
`assistant_only_loss`.

---

## 0. Headline (read first)

- The **infrastructure is real and ahead of most**: execution-grounded preference mining, a gold-free
  structural-verifier RL reward, and an objective execution grader all exist and pass their dry-runs/eval.
- **No preference/RL training has actually run.** DPO and GRPO are authored + dry-run/pair-emission only.
- The **one fully-measured SFT run is modest and mixed** (litqa2 recall ↑, findings ↑ proxy; routing/param
  flat-to-regressed).
- **Do NOT cite `decomp node-F1 0.36→0.73`.** The project's own audit retracts it as a real capability gain
  (in-distribution to its own generator). This supersedes any earlier status that quoted it.

---

## 1. SFT

| Run | Status | Result |
|---|---|---|
| **gold-SFT ckpt-1000** (16,988 gold rows, 0 eval-leak vs 945 queries, real `score.py`) | **MEASURED** | routing acc 0.885→0.860 (−2.5pt, CIs overlap, no gain); param_prefill F1 0.628→0.612 (≈base); **must-not-fill violations 34→49 (regression, over-fills)**; litqa2 0.251→0.317 (+6.5pt, via abstaining less — per-answered precision dipped); findings ROUGE-1 0.10→0.25 (+15pt, proxy only, no judge) |
| **decomp-v2 ckpt-275** (interrupted 275/650, partial) | **MEASURED but DISCREDITED** | held-out node-F1 0.360→0.731, edge-F1 0.444→0.790, struct 0.715→1.000 — **in-distribution to its own generator** (`build_decomp_depgraph.py` emits both train rows and benchmark). Honest out-of-generator decomp ≈ **0.016**; zero-shot flat **~0.40 across 9B→27B**. Source: `20261008_ONPREM_DECOMP_ISSUE_IS_HARNESS_NOT_TRAINING.md` D3 |
| **SFT v3 real-distribution** (22,361 rows, sha verified, leak-clean) | **BUILT-NOT-RUN** | retrain + eval are empty `<!-- RESULTS_* -->` placeholders (`20261007_SFT_V3_REAL_RETRAIN.md`). "v3 fixes decomposition" is unproven |
| SFT v3 clean | **BUILT-NOT-RUN** | had a degenerate empty-mask bug (0/97,065 supervised tokens); mask fix shipped (`5ae31cc03`) but never run end-to-end |

**Defensible SFT claim:** litqa2 recall and findings (proxy) improve on the gold-SFT run; routing/param do not.
Everything beyond that is either unrun or an in-distribution artifact.

---

## 2. DPO

| Track | Status | Detail |
|---|---|---|
| **Routing/exec DPO** (`evaluation/local_trial/train_dpo_grounded.py`) | **BUILT-NOT-RUN (pairs emitted, not trained)** | 4 phases; shipped `exec` phase = **286 pairs / 15 domains** (commit `69bf80365`). chosen = workflow with `real_exec_status∈{ok,ok_warnings}`; rejected = confusable same-domain sibling that failed; request synthesized from shared signal only; leak-guarded. Reward = programmatic gold-match / did-it-run (**not** execution-graded). Only the `train` phase trains — **never executed; no DPO adapter exists** |
| **Peptide generator DPO** (`research/guangzhou_all_atom`) | **BUILT-NOT-RUN** | Diffusion-DPO on the frozen-AE + FullDPM generator. Only a **simulated** integration-mechanics run exists (`SIMULATED_dpo_integration/`, `data_origin:"simulated"`). 27 real αvβ6 pairs from this session's loop→DPO bridge (`cyclic_llm/target_kb/avb6_dpo_pairs.jsonl`, commit `7dda877b2`) are **unconsumed and below the no-tiny-dataset bar** |

---

## 3. RLVR / RL

Planned sequence **SFT → DPO → RL**, verifier-as-reward, gated by volume / no-tiny-dataset / compare-vs-frontier
(`20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md:36-61`).

| Component | Status | Detail |
|---|---|---|
| **GRPO-on-decomp** (`train_grpo_decomp.py`) — the actual RLVR attempt | **BUILT-NOT-RUN (blocked)** | real TRL GRPO, KL-anchored to the SFT adapter; **gold-free structural-verifier reward** (node_F1 + edge_F1 + struct_validity − malformed, checked vs the workflow catalog). CPU dry-run passes (reward orders rollouts correctly). Launcher **refuses to start until a finalized SFT-decomp adapter exists** — and that adapter is only the partial step-275 checkpoint ⇒ blocked on its own upstream |
| **Execution grader** (`execution_grader.py`, `grade_run`) — the un-gameable reward | **MEASURED eval-only** | objective PASS/FAIL (terminal success ∧ expected output type ∧ parses; no similarity/LLM). Validated on real dev runs + one cold ADMET loop. To become the training reward it needs three things that **do not exist yet**: a persisted **graded-run store**, **AWS Batch budget** to execute candidates, and the **verdict→reward wiring** (no SFT/DPO builder calls it) |
| `score()`→reward + loop→DPO bridge (`cyclic_llm/reward.py`) | **BUILT** | this session (#8): scalar reward (selectivity first-class) + preference-pair emitter. Emitter only; not trained |

---

## 4. The smallest concrete step to a first real preference-trained checkpoint

The RL path that needs **no Batch budget** is GRPO-on-decomp (its reward is gold-free/structural). The single
blocker is the unfinalized SFT-decomp adapter. Proposed minimal sequence:

1. **Finalize the decomp SFT adapter** — complete the interrupted v2 run (or run v3-real, data is ready), produce
   a real `adapter_config.json` on S3.
2. **Unblock GRPO** — its launcher's precondition is then satisfied; run a short GRPO job and report node/edge-F1
   **on an out-of-generator held-out set** (not the in-distribution benchmark), vs frontier.
3. **Only then** fund the graded-run store + Batch budget for the execution-grading reward (the un-gameable one),
   which is what the DPO/RL reward should ultimately be.

Guardrails to keep (from the direction doc): compare-vs-frontier on the narrow slice; don't RL before a real
reward distribution; scores are feasibility-level until assay outcomes return.

---

## Sources
`docs/20260912_onprem_llm/20261006_SFT_FROM_COLLECTED_GOLD.md`, `…20261006_SFT_V2_DECOMP_RETRAIN.md`,
`…20261007_SFT_V3_REAL_RETRAIN.md`, `…20261006_DECOMP_STAGE2_GRPO_DESIGN.md`, `…20261001_EXECUTION_GRADER_PLAN.md`;
`docs/20261008_ONPREM_DECOMP_ISSUE_IS_HARNESS_NOT_TRAINING.md`, `docs/20261008_DECOMP_SOLVE_LADDER.md`,
`docs/20261009_INTEGRATED_HARNESS_AND_MODEL_ROADMAP.md`, `docs/20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md`,
`docs/20261015_EVIDENCE_SYSTEM_STATUS_AND_LLM_TRAINING.md`; code `evaluation/local_trial/train_dpo_grounded.py`,
`train_grpo_decomp.py`, `decomp_reward.py`, `execution_grader.py`; `research/guangzhou_all_atom/cyclic_llm/reward.py`.
