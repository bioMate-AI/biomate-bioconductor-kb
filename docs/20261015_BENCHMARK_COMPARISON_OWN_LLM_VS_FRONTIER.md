# Benchmark comparison — own LLM + BioMate system vs frontier (grounded)

**Date:** 2026-10-15 · Internal. The honest own-model-vs-frontier head-to-head on the shared RealBio harness
(`evaluation/datasets/public_export/`, one objective scorer `score.py`, no LLM judge). Every number traces to a
committed `results/<model>/<task>.jsonl`. Compiled with `leaderboard.py`; dividend computed with `score.py`.

Own model = **Qwen3.5-9B** (clean base), served via `serve_openai_shim.py`; `base` = no adapter, `sft` = DB-gold
QLoRA adapter. Frontier via OpenRouter / native APIs.

---

## 0. Bottom line

- **A 9B will not top the raw leaderboard, and shouldn't try** (own strategy: `20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md`).
  On raw capability the own model is behind frontier on routing/protocol, **at frontier parity on autofix**, and
  **mid-pack among frontier on param_prefill** — strong for a privately-deployable 9B, but not SOTA.
- **The SOTA claim is the SYSTEM, and it holds:** the **catalog dividend** lifts *every* model by +34–64pp on
  routing, is **largest for the smallest model (+63.5pp)**, and brings our on-prem 9B to **0.815** — within
  striking distance of frontier-with-catalog (0.93–0.97) and far above any raw LLM (0.18–0.62). The catalog is
  the equalizer that makes a small, private, deterministic deployment competitive.
- **No raw-capability win over frontier is recorded** on any task; claims of "our model beats frontier" are not
  supported. The defensible wins are (a) the catalog/system dividend, (b) 9B deployable parity on autofix/param.

---

## 1. Raw LLM-direct leaderboard (no catalog) — `leaderboard.py`

| Model | routing | autofix | param_prefill F1 | protocol_QC |
|---|---|---|---|---|
| Claude Opus 5 | **0.615** | 0.870 | **0.757** | 0.330 |
| Claude Opus 5.5 | 0.610 | 0.870 | 0.663 | **0.700** |
| GPT-6.1-sol-pro | 0.590 | 0.870 | 0.686 | 0.450 |
| Gemini 3.1 Pro | 0.580 | **0.880** | 0.693 | 0.630 |
| Gemini 3.8 Flash | 0.560 | 0.870 | 0.722 | 0.470 |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.460 |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.440 |
| DeepSeek V4 | 0.415 | 0.800 | 0.621 | 0.420 |
| **own 9B — base** | 0.180 | **0.870** | **0.664** | 0.430 |
| **own 9B — SFT** | 0.285 | 0.850 | 0.657 | 0.430 |

Eval sizes: routing n=200, autofix n=100, param n=170, protocol n=100.

Reads: **autofix is saturated** (~0.85–0.88 for everyone incl. our 9B → parity). **param_prefill**: our 9B base
0.664 beats DeepSeek-V4 (0.621), GLM-5.2 (0.641), Kimi (0.628) and ties GPT-5.6 (0.671) — competitive for a 9B.
**routing/protocol** are where raw LLMs (incl. frontier) are weak and where the catalog carries the task (§2).
**SFT** moved routing +10.5pp (0.180→0.285); param/protocol flat; autofix −2pt.

## 2. The catalog dividend — the system-level SOTA result

Same routing task, model deciding **with** the BioMate catalog vs **without**:

| Model | bare | + catalog | dividend |
|---|---|---|---|
| **own 9B — base** | 0.180 | **0.815** | **+63.5pp** |
| own 9B — SFT | 0.285 | 0.805 | +52.0pp |
| GPT-6.1-sol-pro | 0.590 | **0.975** | +38.5pp |
| Claude Opus 5 | 0.615 | 0.960 | +34.5pp |
| Gemini 3.1 Pro | 0.580 | 0.950 | +37.0pp |
| GPT-5.6 | 0.530 | 0.930 | +40.0pp |
| GLM-5.2 | 0.400 | 0.890 | +49.0pp |
| DeepSeek V4 | 0.415 | 0.800 | +38.5pp |

**The dividend scales inversely with model strength** (KB-dividend finding, `project_kb_dividend_finding`): the
weaker the base, the more the catalog lifts it — so a small on-prem model benefits most. This is the mechanism by
which BioMate makes a private 9B viable, and it is reproducible across every model.

---

## 3. What is measured vs gated (training)

- **SFT (DB-gold):** real, modest — routing +10.5pp; autofix/param parity; findings/litqa2 proxy gains (see
  `20261015_ONPREM_LLM_SFT_DPO_RLVR_STATUS.md`). The strong adapters on S3: `sft_gold_adapter` (loss 1.08, 4.2h,
  real) and `sft_v3clean_adapter` (loss 0.86, 2.4h, real); `sft_sftv3real_adapter` is **degenerate** (loss 7e-4,
  256s — empty-mask artifact, do not use).
- **DPO:** a `dpo_v5` adapter was trained and evaluated (`eval_dpo_full.json`): macro 0.429→0.430 — **no gain**.
- **GRPO (RLVR, decomp):** real setup, gold-free structural reward; **not run** — its launcher requires a
  finalized `sft_decompv2_adapter` that does not exist on S3. Can be repointed at `sft_gold_adapter` as start
  policy and measured on the **out-of-generator** `decomposition_real` set (NOT the leaked `decomposition_v2`).
- **Execution-graded reward:** eval-only; needs a graded-run store + Batch budget + verdict→reward wiring.

## 4. What the budget should buy (highest value → lowest)

1. **Make the catalog-dividend result airtight across ALL tasks** (not just routing) + **complete the own-model's
   missing cells** (litqa2, boin, pbpk, drug_discovery, `decomposition_real`) so the head-to-head is complete.
   Cost: cheap — serve the own model on one spot GPU (vLLM, `serve_openai_shim.py`) + OpenRouter for frontier.
   Near-certain value; this finishes the benchmark comparison.
2. **One honest RLVR run** — GRPO from `sft_gold_adapter`, gold-free reward, measured on `decomposition_real` vs
   frontier. A *research bet* (decomp is hard; bigger models don't help — flat ~0.40 at 9B→27B), but it's the one
   place a new model-level win is plausible, and it needs no Batch.
3. **Execution-graded DPO/RL** — only after a graded-run store + Batch budget exist (the un-gameable reward).

**Do NOT** spend budget trying to make the raw 9B beat frontier broadly — the strategy says it won't and shouldn't.

---

## Sources
`evaluation/datasets/public_export/{leaderboard.py,score.py,results/*}`, `.../leaderboard.md`,
`docs/20261015_ONPREM_LLM_SFT_DPO_RLVR_STATUS.md`, `docs/20261008_ONPREM_DECOMP_ISSUE_IS_HARNESS_NOT_TRAINING.md`,
`docs/20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md`; S3 adapters/evals under
`s3://biomate-models-399683337364/biomate-core-local-trial/20260912/`.
