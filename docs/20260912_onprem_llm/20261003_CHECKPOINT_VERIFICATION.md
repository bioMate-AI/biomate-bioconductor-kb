# LLM checkpoint verification — 2026-10-03

The saved adapters and optimizer states for `full_concept_recovery2_20261003` pass offline integrity checks. The artifacts substantiate completion of the 50-step continued-pretraining (CPT) and 10-step supervised-fine-tuning (SFT) smoke stages. Full merged-base loading and GPU inference remain pending an isolated restore report.

Evidence is recorded in [20261003_CHECKPOINT_VERIFICATION.json](20261003_CHECKPOINT_VERIFICATION.json), checked at 2026-10-03 19:49 UTC. The source checkpoint prefix is `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_ckpt/small/full_concept_recovery2_20261003/`.

## Verified artifacts

| Check | CPT: `midtrain/checkpoint-50` | SFT: `sft/checkpoint-10` |
| --- | --- | --- |
| Trainer global step | 50 | 10 |
| Optimizer parameter states | 504, each at step 50 | 504, each at step 10 |
| Adapter tensors | 504, all finite | 504, all finite |
| Nonzero LoRA B tensors | 252 | 252 |
| Final adapter matches step checkpoint | Yes, identical SHA-256 | Yes, identical SHA-256 |
| Adapter shapes compatible with merged-base header | All match | All match |
| Logged loss: first → last | 2.29837 → 2.00878 | 3.65231 → 1.62582 |
| Logged gradient norms | Finite and positive | Finite and positive |
| Scheduler `last_epoch` / `_step_count` | 50 / 51 | 10 / 11 |

The optimizer and scheduler files were downloaded and loaded on CPU using only `torch.load(weights_only=True, map_location="cpu")`. Each stage contains 3,024 finite optimizer tensors. Its bitsandbytes quantized state has 1,008 nonzero moment tensors and 1,008 strictly positive, finite scale tensors. Both optimizer groups and the scheduler record a final learning rate of zero. SHA-256 hashes for the adapters, optimizers, and schedulers are preserved in the evidence JSON.

The merged base has 398 tensors declared in its safetensors header. Header offsets are contiguous and valid against the 8,044,982,080-byte S3 object length. This check has not yet read every base tensor or established that the model can execute a forward pass.

## Isolated GPU restore

The reproduction runner is in [evaluation/local_trial/checkpoint_verification](../../evaluation/local_trial/checkpoint_verification/):

- `restore_bootstrap.sh` builds a separate environment with pinned model-loading dependencies.
- `restore_entry.sh` downloads the merged base and final SFT adapter from S3, then runs with Hugging Face and Transformers offline mode enabled.
- `verify_restore.py` checks CUDA availability, complete base loading, finite weights and logits, exact loaded-adapter tensor parity, a nonzero adapter effect on logits, exact logits after unloading and reloading the adapter, and token generation from a synthetic prompt.

The isolated on-demand `g6.2xlarge` worker is `i-08a854d4bd82c7aa7`, launched with a 2,400-second bootstrap/test timeout and termination on shutdown. It does not share the active medium-model training GPU.

On a CUDA host with AWS access, set `SCRATCH` to a writable directory, run `restore_bootstrap.sh`, then `restore_entry.sh`. The runner writes `$SCRATCH/restore/restore_report.json` and attempts to upload it to `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/spot_logs/small/restore_concept_recovery2_20261003/restore_report.json`.

Success requires the actual report to declare `complete: true` and all checks to pass. A submitted job, uploaded checkpoint, or successful shell invocation alone does not establish restore success. The GPU runner verifies inference restoration; it does not resume optimizer updates.

Offline checks can be reproduced with `python3 evaluation/local_trial/checkpoint_verification/verify_adapters.py ROOT` and `python3 evaluation/local_trial/checkpoint_verification/verify_optimizer.py ROOT`. The first expects the downloaded checkpoint layout plus `base-header.bin` containing the initial 262,144 bytes of the merged safetensors file. The second expects `midtrain/` and `sft/` directories containing the respective optimizer and scheduler files. These verifiers target the exact recovery run and its expected 50/10 steps.

## Limits and next evidence

These results establish artifact integrity and recorded optimizer progress for a short pipeline smoke run. Decreasing training loss and synthetic-prompt generation do not establish scientific accuracy, held-out generalization, or production readiness. Source-family separation and assistant-token masking still require their own validation.

Read and retain the isolated GPU restore report before qualifying full-model restoration. Then run held-out task evaluation with documented data separation before using the checkpoints as evidence of model-quality improvement or proceeding to the larger experiment.
