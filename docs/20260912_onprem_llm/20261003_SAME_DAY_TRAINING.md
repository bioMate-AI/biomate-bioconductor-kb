# Same-day training and evaluation — October 3, 2026

User instruction: start training ASAP and finish training/evaluation today (America/Chicago).
Keep working without approval pauses; Spot GPU or CPU only, ≤32B models, checkpoint/S3 backups.
No IND or peptide-model work. Preserve other sessions' changes in this shared checkout.

## Running jobs

- **9B candidate replacement:** `i-0e80fb51b235fff89`, g6.2xlarge (24GB GPU, 32GB host RAM), us-west-2b.
  Tag `_today_20261003`, MODEL_SIZE=med, STAGE=full, ENTRY=today_entry.sh,
  BOOTSTRAP=today_bootstrap.sh. 48GB g6e Spot capacity failed across all four configured AZs.
  Price ceiling $1/hour; maximum bootstrap/train/eval time 28,800 seconds, then termination.
  Model Qwen/Qwen3.5-9B pinned to `c202236235762e1c871ad0ccb60c8ee5ba337b9a`.
  300 CPT steps then 500 SFT steps; sequence 2,048, batch 1, accumulation 4, rank 16.
  This is a bounded candidate run, **not a complete pass through the 593M-token corpus or 72K SFT rows**.
  Do not claim an effective customer replacement merely because it finishes.
- **4B recovery:** `i-0565e90849ec84609`; 50 CPT steps completed, average loss
  2.081644, about 409K tokens. Checkpoint-50 is present in S3. **Merge and ten SFT steps also
  completed**, SFT mean loss 2.201492, runtime 29.28 seconds. The final 66,127,776-byte adapter,
  tokenizer and pilot_result.json are in S3. These remain pipeline-validation weights, not a
  demonstrated customer-quality model.
- **Literature:** `i-0c39359695d5c6804`; index build finished and uploaded:
  287,121 unique articles, 1,995,344 passages, 6,473,867,264-byte SQLite file, manifest and SHA256SUMS.
  This is a lexical retrieval baseline requiring relevance checks, not an embedding index.

All paths below are under:
`s3://biomate-models-399683337364/biomate-core-local-trial/20260912/`

| Artifact | Path |
|---|---|
| 9B code snapshot | `code/today_9b_20261003.tgz` |
| 9B logs | `spot_logs/med/full_today_20261003/` |
| 9B checkpoints | `spot_ckpt/med/full_today_20261003/` |
| 9B CPT base | `models_20260919/med/base_domain_today_20261003/` |
| 9B final SFT adapter | `models_20260919/med/full_today_20261003_adapter/` |
| Paired evaluation | `eval/med_today_20261003/` |
| Literature index | `airgap/literature_identified_20261003/` |

## What changed for speed and correctness

Four data-preparation processes replace the earlier single-process preprocessing path.
Checkpoints are requested every 25 steps. The trainer uses the recorded working library versions
(Transformers 5.18.0, TRL 1.14.1, Torch 2.14.1, PEFT 0.21.2, datasets 5.0.1,
accelerate 1.15.0, bitsandbytes 0.50.2); the 9B environment additionally installs flash-linear-attention.
Resolved versions are recorded in S3. Hybrid-kernel performance remains to be measured on the worker.

Qwen3.5 has a multimodal config. The shared loader extracts its text config, maps
`model.language_model.*` checkpoint keys to the text model, and rejects missing language weights.
It is used consistently for training, merging and evaluation. The intended text-only path follows
[the Transformers Qwen3.5 documentation](https://huggingface.co/docs/transformers/en/model_doc/qwen3_5).
Actual successful GPU loading remains a worker validation gate, not something unit mocks establish.

## Evaluation queued automatically after training

`today_entry.sh` performs training, verifies the downloaded literature index checksum, freezes
retrieved evidence once, and evaluates original base and CPT-base-plus-SFT-adapter in separate
processes using exactly the same prompts/evidence. It uploads both reports without waiting for
another user message. Baseline means original weights, never CPT weights with only SFT disabled.

The frozen diagnostic contains 261 MCQA items from the existing objective evaluation artifact
(`knowledge_recall` and `scientific_qa`). Of the original 300, 39 were excluded because their
question stem was under 40 characters or appeared within a training user message. This is a
conservative exact-stem check, not semantic or source-family leakage certification. Each item keeps
its prompt hash; both reports keep the full prepared-evaluation SHA256. Strict letter scoring counts
ambiguous outputs as failures. All raw predictions, timing and empty-retrieval counts are retained.

**This diagnostic is not the whole requested evaluation.** Full-system execution tests and a
task-by-task client acceptance report remain required. Do not use the older content-overlap or
question-mark graders as proof of domain judgment. Once candidate weights exist, complete that
evaluation against the current BioMate harness and report any task that remains untested explicitly.

## Supervision and completion

Thread heartbeat `finish-biomate-llm-training-today` checks every ten minutes and continues repairs
or evaluation. Notify only on meaningful changes. Pause it when delivery is complete or at
23:59 America/Chicago today; report any unfinished work then. Do not launch duplicate workers or
switch to on-demand. Retain the hourly/time bounds and avoid replacements that run beyond today.
Both a complete model artifact and measured evaluation results are required before claiming success.

## 18:35 UTC supervision

The 9B run reached CPT step 75/300, approximately 21.2 seconds per step, with finite logged gradients.
S3 contains checkpoint-25, -50 and -75. Checkpoint-25 trainer state was separately inspected and
confirmed global_step=25 and max_steps=300; file presence is not a tested restore.

The old `backend_bakeoff.py` still asked the model to recall SMILES, despite the October design
rejecting that evaluation. It now requires `--facts resolved_compounds.json`, validates all requested
compound evidence before any model calls, and feeds identical frozen SMILES/source URLs to both
arms. Two regression tests pass. Actual resolver evidence, candidate inference and execution remain
to be performed; this correction alone is not an execution-evaluation result.

## 18:53 UTC Spot recovery

AWS interrupted worker `i-08db6633722c9d20c` after CPT step 113. It is terminated.
Checkpoint 100 was downloaded and structurally verified: trainer step100/max300, adapter tensor
offsets, ZIP CRCs for optimizer/scheduler/RNG/training arguments, and SHA256 for every file.
See `20261003_9B_CHECKPOINT100_VERIFICATION.json`. This is not yet a successful trainer restore.
The prior attempt log is retained at `spot_logs/med/full_today_20261003/attempt_i-08db6633722c9d20c_train.log`.

After five capacity failures, replacement `i-0e80fb51b235fff89` was allocated as g6.2xlarge
in us-west-2b. Same code snapshot, pinned model, run tag, checkpoint prefix, hyperparameters and
cost/time limits. Startup is installing dependencies; actual resume remains to be verified.
The replacement has 32GB host RAM: watch preprocessing and CPU merge memory. No duplicate worker
is running. The ten-minute supervisor now tracks this replacement.

## 19:01 UTC evaluation preparation

Frozen live PubChem resolver output for aspirin, caffeine, ibuprofen and imatinib in
`evaluation/local_trial/today_resolved_compounds.json`, including CID, source URLs and retrieval
time. This public online preparation is not a demonstrated offline ChEMBL deployment. Both
bake-off arms must consume this same file; no model is asked to recall chemical identities.

Corrected execution grading to parse full JSON artifacts instead of silently truncating at
4KB/20KB. A completed run with neither a successful process status nor exit code now fails
for missing execution evidence. Two regression tests pass, as do the two grounded-prompt tests.
These tests validate the grader, not the candidate model. Actual model decisions and workflow
execution remain pending. Replacement startup passed dependency installation, downloaded the pinned 9B model, and selected
`midtrain/checkpoint-100` for resume. Dataset preprocessing and actual resumed optimizer progress
still need verification; selecting a checkpoint alone does not prove a successful restore.

## 19:14 UTC supervision and workflow evaluation preparation

Replacement remains running. Tokenization completed; label preparation is near completion.
Actual post-restore optimizer progress is still unverified. SSM lists no managed connection for
this worker; no command was injected and the running code archive remains unchanged.

`evaluation/local_trial/eval_grounded_workflows.py` now supports direct Transformers inference
using the same strict text-weight loader as training. Run once with original `--base`, and once
with CPT `--base` plus SFT `--adapter`, both using
`--facts evaluation/local_trial/today_resolved_compounds.json` and separate `--out` JSONL files.
It preserves raw model decisions, timing, exact prompt/evidence hashes, expected molecular weights
and source evidence. Checks enforce the selected workflow, allowed parameters, requested model,
and exact compound multiset; three regression tests pass. Every result records
`execution_status=NOT_RUN` until separate BioMate execution and output grading are performed.
This runner is prepared locally but **not injected into the current training worker**. It covers
only two ADMET decisions and cannot establish all-task client readiness. Next evaluation worker
or an accessible post-training process must run it against the delivered weights.

## 19:25 UTC successful checkpoint restoration

Replacement `i-0e80fb51b235fff89` has completed optimizer step **116/300** after selecting
checkpoint100. This exceeds the interrupted attempt's final step113 and confirms actual
post-restore training, not merely checkpoint discovery. Latest logged step115 loss1.844,
grad_norm0.2322 and learning_rate7.468e-05; recent wall-clock steps are about21seconds.
The fresh-run progress bar's smoothed ETA initially understates step time because restored
steps count toward its progress; use observed per-step time for estimates.

S3 currently contains checkpoints25/50/75/100. Checkpoint125 has not yet been reached; verify
its backup in the next check. No paired model predictions exist yet. Training, merge, SFT and
paired MCQA remain automatically chained; no stage was skipped. Resume verification is now
passed, while successful final artifact delivery and execution evaluation remain pending.

## 19:37 UTC halfway CPT milestone

9B CPT reached **150/300**, latest loss1.882 and grad_norm0.2207, about20.9seconds/step.
Approximately52minutes of CPT remain at this rate, excluding merge, SFT and evaluation.
Replacement is running with no new error or interruption observed in the checked log.

The first post-recovery backup, checkpoint125, is present in S3 with adapter weights, optimizer,
scheduler, RNG, tokenizer, training arguments and trainer state. Downloaded trainer_state.json
confirms global_step125/max_steps300, with finite loss and gradients. This verifies new backup
production and state contents; checkpoint125 has not itself undergone a restore test or full
file checksum/CRC audit. Checkpoint150 had just been reached and was not yet listed at inspection.
