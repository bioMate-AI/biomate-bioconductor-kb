# Resume the BioMate worker

The current worker auto-terminates at 2026-09-12 20:20:03 UTC. Spot can interrupt earlier. S3 snapshots remain available. Do not launch a duplicate while the current worker is healthy.

1. Locate the committed workspace receipt in `latest-workspace-backup.json`, and the verified knowledge receipt in `knowledge-backup-receipt.json`. Only select `manifest.json` snapshots; loose uploaded files are not committed checkpoints.
2. If replacement compute is needed, use `cpu-launch-template.json` with `aws ec2 run-instances --region us-west-2 --cli-input-json file://infra/local-trial/cpu-launch-template.json`. Supply a fresh `--client-token` for the replacement and reuse that token on uncertain retries. The template is specific to this account, subnet, SSH /32, key and IAM profile; verify those still exist. It launches one CPU Spot instance with automatic termination, never on-demand.
3. Restore the workspace to a new directory with `checkpoint_store.py restore ... --manifest-sha256 ...`. Apply `implementation.patch` to the recorded Git base in an isolated checkout, then copy the included new files. Do not apply the patch blindly to a different working tree.
4. On the prepared CPU worker, install the checkpoint scripts under `/opt/biomate-trial/scripts/`, restore the knowledge snapshot and run SQLite integrity checks. Restore the same five-minute progress backup timer and Spot notice service. Attach only the scoped instance profile; never copy workstation AWS keys.
5. Run `start-cpu-work.sh`. `download_model.py` reads the immutable model revision pin from S3 and restores completed verified files. It does not follow upstream main after a pin exists. Up to three in-flight shard transfers can be lost; completed S3 files are reused.
6. Start `finish-cpu-work.sh` and `run-cpu-checks.sh` as the documented worker services. The former waits for conversion, backs up quantized shards and serves on loopback. The latter waits for health and records live diagnostic results. Inspect failures before restarting a stage.

For an already backed-up quantized inference checkpoint, restore its committed manifest directly, verify hashes, and serve the first GGUF shard. This avoids repeating conversion. A full training checkpoint, when one exists, requires matching model/data/runtime metadata and `resume_from_checkpoint`; see CHECKPOINTS.md. There is currently no BioMate fine-tuned checkpoint to resume.

The frozen original checkpoint is Qwen/Qwen3.8-27B revision `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`. The private S3 prefix is `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/`.
