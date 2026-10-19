# On-prem LLM — v3 SFT is MEASURED (not "built-not-run"), and GRPO is launch-ready (honesty-fixed)

**Date:** 2026-10-19 · Internal. Corrects a stale claim and records the next launch-ready step. Supersedes the
"SFT v3 real — BUILT-NOT-RUN" row in `20261015_ONPREM_LLM_SFT_DPO_RLVR_STATUS.md` §1.

## 1. Correction: the real-distribution v3 SFT was trained AND evaluated (twice)
S3 state (`.../models_20260919/med/`): `sft_v3clean_adapter` is a **healthy** real-distribution run
(pilot_result: 2.45 h, train_loss 0.863, 550 steps, 22,361 rows). `sft_sftv3real_adapter` is the earlier
**degenerate** empty-mask run (256 s, loss 7e-4 — do not use). The RealBio eval harness
(`run_eval_sftv3real.sh` → `spot_harness_sftv3real_entry.sh`, certified `harness_shim.py`) ran the base-vs-adapter
arms **twice** (`eval/spot_harness_sftv3real_20261007_070106` and `…_202844`); results are consistent.

## 2. Measured result (run `…_202844`, base vs base+v3 adapter; MEASURED)
| task | base | +v3 | read |
|---|---|---|---|
| **decomposition_real** node-F1 (OUT-OF-GENERATOR, headline) | 0.016 | **0.087** | near-floor; not a real decomp capability |
| decomposition_v2 node-F1 (IN-DISTRIBUTION / leaked) | 0.313 | 0.758 | the retracted "0.73"; **do not cite as capability** |
| cross_domain_routing (catalog mode, n=200) | 0.885 | 0.880 | flat |
| param_prefill F1 | 0.628 | 0.587 | ↓ |
| param_prefill **must_not_fill violations** | 34 | **51** | **regressed (worse over-fills)** |
| litqa2 | 0.251 | 0.312 | +6.1pt (only clear gain) |
| findings_probe ROUGE-1 (proxy) | 0.100 | 0.115 | +1.5pt proxy |

**Verdict: v3 real-distribution SFT does NOT beat `sft_gold` and regresses `param_prefill`/must_not_fill.**
`sft_gold_adapter` (ckpt-1000) remains the production SFT. v3's only out-of-generator signal is litqa2; the
headline decomp gain is the in-distribution decomposition_v2 artifact, not generalization. This is why the
benchmark leaderboard never added a v3 row — correctly. No new eval needed; re-running it would be redundant.

## 3. Next real lever: GRPO-on-decomp (benchmark-doc §4 priority #2) — now launch-ready + honesty-fixed
The genuine remaining model-level lever that needs **no AWS Batch** is GRPO with the gold-free structural reward.
State as of this doc:
- **Reward verified (CPU, no GPU):** `python3 decomp_reward.py --selftest` → SELFTEST PASS; ranks
  oracle 0.988 > all_chain 0.797 > all_parallel 0.714 > over_decomp 0.552 > malformed −0.367 (orders rollouts,
  penalizes degenerate/malformed). 
- **Start-policy unblock:** the launcher's precondition (`sft_decompv2_adapter`, which does not exist) is removed
  by env override `SFT_ADAPTER_S3=…/med/sft_gold_adapter` (exists) — the benchmark-doc §3 sanctioned repoint.
- **Honesty fix shipped (this doc):** `train_grpo_decomp.py` eval default changed from decomposition_v2
  (in-distribution) → **decomposition_real** (out-of-generator). The entry runs with `EVAL_HOOK=0`
  (no inline eval; GRPO trains against the reward, the adapter is graded post-hoc on decomposition_real),
  so the default flip only hardens the latent trap if the hook is ever enabled.

**Launch-ready command (spot-only, self-terminating, capped; NOT fired here):**
```
SFT_ADAPTER_S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912/models_20260919/med/sft_gold_adapter \
  bash evaluation/local_trial/run_grpo_decomp_9b.sh
# then grade the resulting grpo adapter with: ADAPTER_TAG=<grpo tag> bash run_eval_sftv3real.sh  (decomposition_real headline)
```
**Cost/time:** 1 spot GPU (g5/g6 pool), ~2–4 h, ~$2–5; no Batch.

## 3b. Launch ATTEMPTED (2026-10-19, with sign-off) — BLOCKED on spot GPU capacity
Staging completed (was missing; the launcher was "ready, never run"): built + uploaded the GRPO code tarball
`code/evaluation_local_trial_grpo_decomp.tgz` (includes the §3 honesty fix) and the train pool
`sft/decomp_depgraph.jsonl` (4,300 `catalog_depgraph_synth` rows, all buildable). Fired spot-only:
`SFT_ADAPTER_S3=…/sft_gold_adapter EVAL_HOOK=0 bash run_grpo_decomp_9b.sh`.
**Result: no instance obtained in ~8 min.** Config is valid (`run-instances --dry-run` → "would have
succeeded"); the blocker is **spot capacity** — `get-spot-placement-scores` returns **1/10 (lowest) across all
four us-west-2 AZs** for the g5/g6 (L4/L40S) pool, and zero instances were created. Per the spot-only rule
(no on-demand fallback), the retry loop was stopped (clean state: no orphaned instance). **Re-fire unchanged when
capacity returns** — staging persists on S3, so just re-run the command above; then grade with
`ADAPTER_TAG=_grpo_decomp bash run_eval_sftv3real.sh` (decomposition_real headline vs frontier).

## 4. Why the result is not yet measured (honest)
GRPO-on-decomp is a **research bet** (decomp is hard — flat ~0.40 zero-shot across 9B→27B; out-of-generator
base/v3 = 0.016/0.087, a near-zero start), and starting from `sft_gold` (a general gold adapter, not a
decomp-specialized SFT) is **off the designed path**. Cost/safety are controlled, but the *result* is genuinely
unpredictable and a null outcome is likely. Per "review before expensive test / don't launch a run you can't
predict," it is staged launch-ready with the exact command above rather than fired blind.

**The clearly-ready, predictable run (the v3 SFT eval) was already executed** — so the SFT thread's honest
conclusion (v3 ⟂ gold) is now recorded, and the only un-fired step is the research-bet RLVR run above.
