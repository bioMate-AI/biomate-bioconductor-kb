# Dataset collection and initial training

## Reused dataset

The existing S3 prefix `s3://knowledge-datasets-1759951976/cyclic_peptide/` contains 32 objects (36,673,278 bytes), including raw CycPeptMPDB, previous permeability-model checkpoints and run metadata. The raw CSV is reused, not downloaded again from its publisher.

Verified raw snapshot: `cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv`; 19,068,277 bytes; 8,466 rows; 247 columns; SHA256 `54e2be28199c0c3a8d6d0923192161d418eca8efd5c9b804e9bceae2faa52e51`. This stored snapshot is larger than the original publication's 7,334-peptide release. Row counts do not establish independent molecules or uncensored assay observations. The reuse audit records source groups and available label columns. It has not been used to supply labels for peptide generation.

## Structural data acquisition

PepBench v2, Zenodo record 13373108, is the initial structure corpus. Source metadata declares CC-BY-4.0. The collector scans all object names in the existing bucket before downloading, checks candidate existing object sizes and verifies publisher MD5. Missing files are downloaded from the publisher, SHA256-hashed, conditionally uploaded to `cyclic_peptide/datasets/pepbench/v2/`, and verified by complete streamed S3 readback. A same-name object that fails the publisher checksum stops the run rather than being silently reused.

| File | Exact bytes | Initial role |
|---|---:|---|
| train_valid.tar.gz | 192,609,821 | Published train/validation data |
| LNR.tar.gz | 10,894,516 | Held-out test archive; never fitted |
| ProtFrag.tar.gz | 1,670,340,143 | Augmentation archive reserved for later training |
| README.md | 3,023 | Dataset provenance/documentation |

Source: https://zenodo.org/records/13373108 . Attribution: Kong, Jia, Huang and Liu, *PepBench: Dataset for Protein-Binding Peptide Design*, v2, 2024.

## Initial model run

Run ID: `pepglad-initial-20260912T214443Z`.

Instance: `i-08c76486fcee74391`, `g5.xlarge`, us-west-2. Run outputs: `s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-initial-20260912T214443Z/`.

Official PepGLAD source is pinned to `bad015ca50c312a89482adb5220c3d907f13df5c`. Initial scope is canonical-peptide, all-heavy-atom sequence/structure modeling: five autoencoder epochs followed by five latent-diffusion epochs. The full published supervised training split is used; ProtFrag augmentation is not included in this first bounded run. LNR is held out. The model does not thereby support arbitrary noncanonical chemistry or explicit hydrogens.

The validation-selected autoencoder checkpoint initializes the latent-diffusion stage. The integrity patch rejects nonfinite losses/gradients, forward/backward OOM, and nonfinite validation metrics. Gradient norms are logged every 100 steps. This avoids silently treating upstream zero-loss replacements as successful updates. Dataset-family leakage auditing beyond the original split remains pending; this is a baseline-start run, not an OOD performance claim.

Automatic termination is configured for four hours after setup begins, and on normal completion or failure. Timer verified: September 13, 2026, 01:45:52 UTC. Status/logs and completed checkpoints sync to S3 every two minutes. The GPU is isolated from existing production and research instances.

Verified setup: PyTorch 2.5.1+cu121 and NVIDIA A10G are operational. The full S3 inventory scan completed across 34 pages / 33,931 objects. No matching `train_valid.tar.gz` was reused, and the publisher download began. The train/validation archive, LNR archive and README have been uploaded and fully readback-verified. A v2 run bundle changes acquisition scheduling: core data is reused, optional ProtFrag acquisition runs concurrently with model preparation/training. The installed environment and original termination deadline are preserved. Actual optimizer updates remain to be verified; setup alone is not training evidence.

## Verified acquisition and retry

All four PepBench files are now in S3 and publisher-MD5/full-readback-SHA256 verified: 1,873,847,503 bytes total. Details: `results/pepbench_verified_acquisition.json`. No further publisher downloads are needed for this baseline.

The first instance failed when a service restart tried to clone into an existing directory. The source checkout is now idempotent. Replacement run: `pepglad-initial-20260912T215600Z`, instance `i-00ee634b80c07800c`, same original absolute deadline of 2026-09-13 01:45:52 UTC. The failed run did not reach verified optimizer updates. Current status is tracked under the replacement run prefix.

Published-split inspection: 4,157 training IDs, 114 validation IDs, 6,105 total raw indexed complexes. Train/validation have zero exact complex-ID overlap but three shared PDB accessions. This run is a published-split baseline, not a demonstrated unseen-target evaluation.

## Spot migration — 2026-09-12

At the user’s request, replaced On-Demand `i-00ee634b80c07800c` with Spot `i-0592cc555c2b6a711` (`g5.xlarge`, request `sir-i6gzm74j`). Two completed autoencoder epochs were synchronized to S3 before terminating the paused source instance. The replacement is configured to load the latest completed checkpoint and train the remaining three AE epochs, followed by five LDM epochs. Model weights are preserved; optimizer state resets because upstream checkpoints contain only the model.

Checkpoints and logs sync to S3 every 120 seconds, at stage completion, and best-effort upon an EC2 Spot interruption notice. Checkpoints are generated at each validation epoch; partial-epoch progress is not checkpointed. The original deadline of 2026-09-13 01:45:52 UTC remains in effect. Current run prefix: `s3://knowledge-datasets-1759951976/cyclic_peptide/runs/pepglad-spot-20260912T221107Z/`. Startup verification is pending.

The first Spot startup failed because Ubuntu held the apt/dpkg lock. Its replacement, `i-07b9bd8f9e354f6d4` (Spot request `sir-w3i7npsk`, run `pepglad-spot-20260912T221500Z`), waits for package locks before installing. The checkpoint source and original deadline are unchanged.

Verified replacement startup: status successfully uploaded to S3, package installation passed the previous lock failure, and the original termination timer is active. Training warm-start remains pending while dependencies and data are prepared. Validation: nine evaluator tests pass; warm-start configuration selects epoch 1 and requests the remaining three AE epochs; shell syntax and diff checks pass.
