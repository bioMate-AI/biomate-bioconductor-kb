# Same-day training and evaluation — October 3, 2026

User instruction: start training ASAP and finish training/evaluation today (America/Chicago).
Keep working without approval pauses; Spot GPU or CPU only, ≤32B models, checkpoint/S3 backups.
No IND or peptide-model work. Preserve other sessions' changes in this shared checkout.

## Running jobs

- **9B candidate:** `i-08db6633722c9d20c`, g6.4xlarge (24GB GPU), us-west-2b.
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
