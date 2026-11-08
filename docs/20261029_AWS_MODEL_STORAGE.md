# AWS-only checkpoint storage

The project owner requires model checkpoints and model execution to remain on AWS. Do not download ChemFM or PeptideCLM weights into the laptop cache. Local source editing and inspection remain separate from cloud model execution.

AWS bootstrap prefix:

`s3://biomate-nextflow-work/cyclic_peptide/allatom/model_checkpoints/migration_20261029/`

This prefix stores `manifest.json`, `fetch_pinned_checkpoints.py` and small ChemFM metadata files. **The model weights are fetched directly by AWS workers from pinned upstream commits; this prefix is not a complete S3 mirror of the weights.** The slow laptop weight upload was stopped before completion.

The companion `20261029_AWS_CHECKPOINT_STORAGE.json` records all 19 files, byte counts, SHA-256 hashes and exact download sources. Local weight SHA-256 values were checked against upstream Git LFS hashes at the pinned commits. Small source files were checked against Git blob identities. Local-only metadata has verified small S3 backups. `pinned_upstream_files_verified` describes source verification, not a completed AWS model execution. The local-removal field separately records cache deletion.

For an authorised EC2 Spot worker, obtain the manifest and fetch script from this prefix and invoke the script with the committed manifest SHA-256, a cloud destination and one of `chemfm1b`, `pclm2/base` or `pclm2/small`. The script checks EC2 Spot identity before downloading, verifies each downloaded file against its length and SHA-256, and downloads only the selected model. The new fetch script has not yet been executed on a worker. Supply the resulting cloud directory to the runner's `--model-dir` or `--encoder-dir`; preserve the manifest in experiment provenance.

No checkpoint was loaded or executed during source verification. No compute instance was launched. This storage change does not establish model performance or authorise a new training budget.
