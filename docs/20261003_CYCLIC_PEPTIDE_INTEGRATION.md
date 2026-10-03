# Cyclic peptide integration continuation — 2026-10-03

## Review workflow

PR: https://github.com/bioMate-AI/biomate/pull/258
Review branch: `codex/cyclic-training-integration`, based on the remote peptide
work branch. Changes are developed in `/Users/kky/biomate-review`, committed in
scoped increments, and cherry-picked to `/tmp/biomate-cyclic-pr` for push. This
avoids publishing the ten unrelated unpushed commits on the working branch.

## CUDA smoke review and launch

Reviewed the full driver and the one-epoch branch before launch. The same pinned
UniMoMo environment and base weights are used; explicit batch size 1 replaces
packed batches. The smoke must produce one UPDATE_EVIDENCE record per retained
training complex, finite weights, changed trainable weights, and an unchanged,
frozen autoencoder. It stops before benchmark generation. Failures retain the
warm environment for diagnosis; an independently scheduled four-hour shutdown
terminates the instance. Failure to establish the timer shuts the instance down.

Local validation: launcher and extracted driver pass shell syntax checks; embedded
Python compiles. The upstream trainer guard already passed CPU optimizer tests.
This predicts a valid update per complex if each individual complex fits CUDA
memory; that memory condition is what the smoke is intended to verify.

Launched run `unimomo-cyclic-ft-20261003T163142Z` on spot instance
`i-0e66b63836f7e637b` (`g6.8xlarge`). Status and artifacts are under
`s3://knowledge-datasets-1759951976/cyclic_peptide/runs/unimomo-cyclic-ft-20261003T163142Z/`.
No completed CUDA result is claimed yet.

## Simulated integration scope

The user authorized simulated data. Planned test: use the actual platform assay
CSV validator and SQLite ingestion service, export campaign-scoped KD preferences,
resolve candidate IDs through the real DPO loader, optimize a clearly labeled
simulated denoiser, save/reload its checkpoint, and evaluate matched-noise
preferences. This verifies integration mechanics; it is not a wet-lab result or a
full UniMoMo structure-generation benchmark. Simulation artifacts must remain
explicitly labeled and separate from measured campaigns.
