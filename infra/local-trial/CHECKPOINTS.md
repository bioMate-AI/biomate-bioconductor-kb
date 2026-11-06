# BioMate checkpoint and recovery policy

User preference: Spot instances or CPU; no on-demand GPU fallback. Scope is the main BioMate assistant, excluding IND models and data.

## Active storage and CPU worker

- Bucket: `biomate-models-399683337364`, region `us-west-2`.
- Dedicated prefix: `biomate-core-local-trial/20260912/`.
- CPU Spot: `i-0a9ed4897fee6ffc2`, `r5.4xlarge`, 128 GB RAM, $1/hour Spot ceiling. Three-hour automatic shutdown terminates the instance and deletes its encrypted root disk.
- Instance role `biomate-core-trial-20260912` permits Get/Put only within this prefix and prefix-scoped listing. No static credentials are stored on the worker.
- Bucket public-access blocking is enabled. Bucket-wide versioning was not changed; snapshots use unique keys and conditional write-once PUTs instead.

## What is backed up

1. **Implementation bundles:** scoped BioMate code patches, new files and recovery scripts. These are explicitly labeled artifacts, not trained model checkpoints. The first bundle has completed a real S3 restore/checksum verification; see `backup-receipt.json`.
2. **Worker progress every five minutes:** bounded service logs, runtime revision, completed-stage markers and results. The systemd backup timer is active. Logs/status snapshots cannot resume optimizer state.
3. **Base checkpoint files:** `download_model.py` pins an upstream commit, verifies completed files, writes each completed file to S3 using at most three parallel transfers and restores cached files on replacement workers. A complete-model manifest appears only after all selected files are present. A partial file download may be lost on interruption.
4. **Future training checkpoints:** use the single-process `BioMateCheckpointBackup` callback after Trainer saves a full checkpoint. Save every 25 steps and at least every 300 seconds at step boundaries; include model/adapter, optimizer, scheduler, RNG and trainer state. `save_only_model=False`. No training run is claimed yet.

## Consistency and publication

`checkpoint_store.py seal` is called only after the producer finishes writing. It hashes a fixed file set. `push` verifies it, uses S3 SHA256 validation and conditional PUTs for each file, verifies the source again, and commits `manifest.json` last. An interrupted upload has no committed manifest and must not be selected for restore. Earlier committed snapshots are retained; backup never deletes remote checkpoints.

`restore` downloads into a new temporary directory, verifies every file and optional manifest checksum, then atomically promotes the directory. Existing destinations are refused. Files over 5 GiB must be sharded first; unsupported distributed checkpoint layouts are rejected. Model quantization is not evidence of original parameter count: check the complete original checkpoint against the 32B cap.

## Resume training

Restore using the recorded bucket, manifest key and SHA256 into a fresh directory. Check that base model revision, dataset manifest hash, tokenizer/chat-template revision and training configuration match the checkpoint metadata. Then call `trainer.train(resume_from_checkpoint=restored_directory)`. Loading only a LoRA adapter restarts optimization; it is not full training resumption.

The callback currently supports single-process Trainer saves only, not Ludwig, FSDP or DeepSpeed distributed state. It is a provided integration component; no running BioMate training job has yet been wired or launched.

An IMDSv2 Spot watcher writes `SPOT_INTERRUPTION.json` and triggers a progress backup. The training callback requests save/stop at the next completed step. A step that exceeds the interruption window may not finish; recovery must use the previous committed checkpoint. Periodic backup is the primary protection.

## Tests

Offline tests cover commit ordering, changed source, corrupted restore, incomplete training state, symlinks and interrupted manifest publication. The first implementation bundle also passed an actual S3 upload/download/hash round trip. Actual model training save/resume equivalence still needs a training smoke run.

The knowledge database backup has also been restored on the CPU worker with matching file hashes and SQLite quick_check=ok (12,312 tools, 4,200 workflows). See knowledge-backup-receipt.json. A preparation restart successfully reused verified completed model files, exercising the download-resume path.

Automated continuation on the CPU worker: prepare/pin/download → verify original model size → convert/quantize → shard and back up inference artifact → serve on loopback → run live transport and 12 BioMate development cases → back up incremental results. Each stage fails visibly rather than marking the trial passed. The raw smoke service remains failed because the server returned fenced JSON; the application adapter's strict JSON handling passed a separate live check. All 12 core diagnostics and the actual GalaxyAssistant history-tool loop with synthetic storage passed. Evidence is in results/.

Verified base checkpoint: Qwen/Qwen3.8-27B revision 1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0; all 31 selected files completed and backed up. Original safetensors inspection counted 27,781,427,952 stored tensor elements across 1,199 tensors in 18 shards, passing the conservative 32B cap. The complete model manifest is under models/Qwen--Qwen3.8-27B/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0/complete.json in the dedicated prefix. This is the official base assistant checkpoint, not a BioMate fine-tune.

The temporary scratch volume was increased to 500 MiB/s / 6,000 IOPS to reduce conversion I/O time. It remains encrypted and delete-on-termination. Storage charges are separate from the $1/hour Spot instance ceiling.

The quantized inference snapshot is committed and has passed a full S3 restore of all five GGUF shards with manifest and file SHA256 checks. See results/quantized-backup-receipt.json and results/quantized-restore-result.json. Source revision 3057bb66c86c46d5781e50e85462a760ba7d1feb is pinned in the preparation script. Conversion outputs and shard directories are promoted only after their producer finishes. The new restart safeguards passed shell syntax checks; a complete replacement-worker boot has not been exercised.
