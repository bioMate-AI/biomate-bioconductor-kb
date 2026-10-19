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

## 3c. FIRED in us-east-1 (2026-10-19) — spot capacity found there
us-west-2 spot stayed 1/10; a cross-region check found **us-east-1 use1-az1/az4 = 9/10** for the g5/g6/g6e pool.
Discovered + fixed a latent launcher bug: `spot_launch.sh` did not propagate the GRPO env vars into instance
USERDATA, so on-box `SFT_ADAPTER_S3` fell back to the non-existent `sft_decompv2_adapter` (SFT_ADAPTER_FAIL) —
i.e. the GRPO launcher was never actually runnable. Fix: bake `SFT_ADAPTER_S3/DATA_S3/DB_S3/MAX_STEPS/…/EVAL_HOOK`
into the USERDATA export (empty + harmless for non-GRPO stages). Then fired **one** spot instance via
`spot_launch.sh` with us-east-1 overrides (AMI `ami-07ab2d4b1490816c3`, subnet `subnet-056f0aba4ab4f7ec2`=use1-az4,
default SG `sg-09a2408a8b8ca874b`, `g6e.xlarge` L40S 48GB, `SFT_ADAPTER_S3=sft_gold_adapter`, `EVAL_HOOK=0`).
**Instance `i-09fff702deba10e2f` — confirmed spot (sir-76jqmymh), running.** Logs/ckpts/final land in the
us-west-2 bucket (cross-region S3 read is functional): train.log `…/spot_logs/med/grpo_grpo_decomp/train.log`,
adapter `…/models_20260919/med/grpo_grpo_decomp_adapter/`. Grade when it lands:
`ADAPTER_TAG=_grpo_decomp bash run_eval_sftv3real.sh` (decomposition_real headline vs frontier).
**This is a LOW-EV bet** (decomp is hard; base/v3 on decomposition_real ≈ 0.016/0.087 — a near-zero start;
start policy is the general `sft_gold`, off-design). A near-floor result is the likely, honest outcome.

## 3e. trl GRPOConfig API reconciled (introspected, not guessed) + RE-FIRED
Introspected the pinned signatures by downloading the wheels (no torch install):
`trl-1.14.1` `GRPOConfig` (79 own fields + TrainingArguments parent) and `transformers-5.18.0` `TrainingArguments`.
Result: **the ONLY invalid kwarg is `max_prompt_length`** — trl 1.14.1 removed it from `GRPOConfig` (prompts are
tokenized as-is; truncation is tokenizer-side). Every other kwarg we pass is valid: `max_completion_length`,
`num_generations`, `beta`, `temperature`, `learning_rate`, `log_completions` (GRPOConfig fields) and
`output_dir/lr_scheduler_type/warmup_steps/max_steps/save_steps/per_device_train_batch_size/gradient_accumulation_steps/
bf16/gradient_checkpointing/gradient_checkpointing_kwargs/optim/report_to/seed` (TrainingArguments, all present in
5.18.0); and all `GRPOTrainer(...)` ctor args are valid. **Reconciliation: drop `max_prompt_length` only.**
Semantics preserved: the decomp prompts are ≤~505 tokens, so the old `--max-prompt-len 1024` cap never truncated —
dropping it is a **no-op**; the completion cap stays via `max_completion_length=640`. Fixed both the real
`GRPOConfig(...)` (train_grpo_decomp.py) and the `--dry-run` preview dict; rebuilt + re-uploaded the tarball.
**Re-fired ONE spot instance (us-east-1 use1-az4 still 9/10): `i-03c2a5b5939e78677`, confirmed spot, g6e.xlarge**,
same validated path (`sft_gold` start policy, `EVAL_HOOK=0`). Expected to pass GRPOConfig this time and enter the
GRPO loop. Adapter → `…/models_20260919/med/grpo_grpo_decomp_adapter/`; grade on decomposition_real vs frontier
when it lands. Headline deliverable = the RLVR pipeline runs end-to-end; the score is expected near-floor.

## 3f. GRPOConfig fix VALIDATED; 2nd trl-API issue found + fully reconciled (static), re-fired again
Re-fire #1 (`i-03c2a5b5939e78677`) **passed GRPOConfig** (the `max_prompt_length` fix works — confirmed via boot.log
reaching `[grpo] START GRPO` with no config error), then hit a *downstream* `GRPOTrainer` error:
`ValueError: You passed a PeftModel instance together with a peft_config`. Cause: the code loads the SFT adapter as
a `PeftModel` AND passes `peft_config=lora` — trl 1.14.1 forbids both. This revealed the trainer was written for an
older trl and never ran end-to-end, so I **statically reconciled the whole trainer path against the trl-1.14.1 wheel**
(no GPU, no whack-a-mole): (a) GRPOTrainer peft — drop `peft_config`; with peft≥0.20 (we have 0.21.2) the
no-peft_config + PeftModel path adds a frozen "ref" copy of the SFT adapter as the **KL reference** — exactly the
intended anchor-to-SFT behaviour, so semantics are preserved, not compromised; (b) reward calling — trl forwards
dataset columns (`gold`) as kwargs (grpo_trainer.py:1670/1712), so our `reward_fn(prompts,completions,gold,**kw)` is
compatible; (c) 4-bit prep — code already does `prepare_model_for_kbit_training`; (d) train/save/resume — standard.
**Fix: drop `peft_config` (+ the now-unused LoraConfig) from the GRPOTrainer call.** Rebuilt the tarball; re-fired
**`i-03726d2f9389d3965`** (us-east-1 az4 = 9/10, confirmed spot). This is a 2nd re-fire, justified by a *complete*
static reconciliation (not blind one-error looping). If it still errors, STOP and report.

## 3g. PeftModel fix VALIDATED; 3rd gap (reward scorer staging) fixed; now HELD on spot capacity
Re-fire #2 (`i-03726d2f9389d3965`) **passed GRPOConfig AND GRPOTrainer construction** (the peft_config fix works —
reached + held at `[grpo] START GRPO` ~3 min), then hit a 3rd, non-API gap: `FileNotFoundError` for
`../datasets/decomposition_v2/score.py` — `decomp_reward.py`'s structural scorer (stdlib-only) was not staged on the
box (the tarball unpacks to `code/`; `../datasets` is absent). **Fix:** `spot_grpo_decomp_entry.sh` now stages
`$S3/eval/decompv2/score.py` → `$SCRATCH/datasets/decomposition_v2/score.py`. All reward deps are now present
(scorer stdlib-only + DB staged) and the reward is CPU-selftest-validated, so the next fire should train end-to-end.
Tarball rebuilt. **Pipeline status: fully reconciled to trl 1.14.1 and validated on-box through GRPOTrainer
construction + reward setup — one resume-safe spot fire from the end-to-end run.**
**HELD:** at this moment no AZ meets the spot-only ≥6 threshold (us-east-1 best use1-az2=5; use1-az4 dipped 9→4;
us-west-2=1). Transient (az4 was 9 minutes earlier). Per spot-only, NOT firing into thin capacity or on-demand.
**Re-fire when ≥6 returns** (same command, §3c, pointing at subnet for the ≥6 AZ); then grade on decomposition_real.

## 3d. First us-east-1 run: booted clean, then crashed on a trl-API bug (adapter did NOT land)
The box (`i-09fff702deba10e2f`) booted fully: venv (torch2.14.1/transformers5.18/trl1.14.1/peft0.21), base
Qwen3.5-9B, and **the adapter/data/DB pulls all succeeded** — reaching
`[grpo] START GRPO (steps=400 numgen=8 beta=0.04 … EVAL_HOOK=0)`. **This validates the env-propagation fix**
(the `sft_gold` start policy + `EVAL_HOOK=0` reached the box; no SFT_ADAPTER_FAIL). It then crashed immediately at
config construction:
`TypeError: GRPOConfig.__init__() got an unexpected keyword argument 'max_prompt_length'`
(`train_grpo_decomp.py:212`, which also passes `max_completion_length`). The pinned **trl 1.14.1 GRPOConfig does
not accept these kwargs** — a trl-API mismatch in the trainer. The instance **self-terminated** (clean, no cost
runaway); **no adapter landed, so there is no measured result.**
**Fix before any re-fire (do NOT guess — it risks whack-a-mole on other kwargs like `log_completions`):** in the
pinned venv, introspect `inspect.signature(trl.GRPOConfig.__init__)` and reconcile the `GRPOConfig(...)` call
(drop/rename `max_prompt_length`/`max_completion_length` and verify every other kwarg), then rebuild the tarball
(`evaluation_local_trial_grpo_decomp.tgz`) and re-fire the **validated us-east-1 spot path** (capacity + launch +
env propagation are all confirmed working). Held per "one bounded attempt, don't loop."

## 3b. First attempt (us-west-2) — BLOCKED on spot GPU capacity
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
