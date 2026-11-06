# GRPO auto-fire — review-before-spend note

**Date:** 2026-10-19 · Internal. Mandatory pre-spend review (CLAUDE.md "Review Code Before Testing") for
the capacity-gated auto-fire of STAGE-2 GRPO. Pairs with `20261019_ONPREM_LLM_V3_SFT_MEASURED_AND_GRPO_READY.md`.

## What the fire does
One spot GPU instance (`g6e.xlarge`, L40S 48GB) runs `spot_grpo_decomp_entry.sh`: pulls Qwen3.5-9B base +
the `sft_gold` adapter (start policy / KL reference), the decomp data, the verifier DB, and the structural
scorer; then runs GRPO (trl-1.14.1 `GRPOTrainer`) for `MAX_STEPS=400` against the gold-free structural reward
(`decomp_reward.py`: node/edge-F1 + catalog structural verifier, weights 0.30/0.40/0.30). Checkpoints mirror
to S3 every 120 s; the instance self-terminates on completion or spot reclaim and resumes from S3 on relaunch.

## Why it is gated, not fired now
Live spot placement scores (checked this session): **best eligible AZ = us-east-1 `use1-az4` = 4**, us-west-2
max = 2 — both **below the ≥6 gate**. us-east-1 az4 was 9 earlier today and has receded. Policy is spot-only,
≥6-gated, so GRPO is **HELD**. `spot_grpo_autofire.sh` polls both regions every 5 min and fires the instant an
AZ we hold a subnet in clears ≥6. It is idempotent (exits without firing if the adapter already exists or a
prior fire is recorded) and self-limited (fires exactly one instance, 24 h deadline).

## Conditions traced (every gate)
- **Start policy exists:** `…/models_20260919/med/sft_gold_adapter/adapter_config.json` — present (the
  sanctioned repoint off the non-existent `sft_decompv2_adapter`; the launcher's own guard refuses otherwise).
- **All reward inputs present:** `sft/decomp_depgraph.jsonl`, `eval/harness_payload/galaxy_ai_tools.db`,
  `eval/decompv2/score.py` — all verified on S3 this session.
- **The 3 trl-1.14.1 errors are fully reconciled in the LIVE tarball** (uploaded 14:11:03): (1) `GRPOConfig`
  drop `max_prompt_length`; (2) `GRPOTrainer` drop `peft_config` (PeftModel path adds the frozen KL ref — the
  intended anchor-to-SFT); (3) on-box scorer staging (`76eb764cc`) — entry stages `score.py` to
  `$SCRATCH/datasets/decomposition_v2/score.py` = `/opt/dlami/nvme/datasets/decomposition_v2/score.py`, which is
  exactly `decomp_reward._DEFAULT_SCORER` (`HERE/../datasets/decomposition_v2/score.py`). The 14:08 crash used
  the pre-fix tarball; the fixed build has **not** been fired yet.
- **Reward CPU-validated end-to-end:** `decomp_reward.py --selftest` exercises `_load_scorer`→`decomp_reward`
  and PASSES (oracle 0.988 > all_chain 0.797 > all_parallel 0.714 > over_decomp 0.552 > malformed −0.367).
- **No silent skips:** the scorer stage has `|| exit 14` (fails loud); FORCE_NGPU=1; EVAL_HOOK=0 (no inline LLM
  eval — the adapter is graded post-hoc on `decomposition_real`).

## Predicted outcome
The pipeline runs end-to-end and writes `…/models_20260919/med/grpo_grpo_decomp_adapter/`. The **deliverable is
the RLVR pipeline completing end-to-end**, not a high score. On `decomposition_real` (out-of-generator) the score
is expected **near-floor** (base/v3 ≈ 0.016/0.087) — a LOW-EV bet, documented as such. Grade when it lands:
`ADAPTER_TAG=_grpo_decomp bash evaluation/local_trial/run_eval_sftv3real.sh`. Do **not** cite the in-distribution
`decomposition_v2` number (the retracted 0.73).

## Spend
1 spot `g6e.xlarge`, self-terminating, `MAX_STEPS=400` ≈ 2–4 h, ~$2–5. No AWS Batch. No on-demand.
