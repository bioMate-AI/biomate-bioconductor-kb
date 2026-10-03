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

## CPU integration completed

Executed `simulate_closed_loop.py` with the production assay service against a
fresh SQLite database. Six explicitly simulated KD rows persisted; six same-target
EXPERT pairs exported with campaign, assay IDs, and simulated provenance. The real
DPO loader resolved every ID, the shared optimizer completed 120 updates on the
simulated latent denoiser, and the saved checkpoint reloaded exactly.

All ten assertions passed. On 48 matched-noise evaluations of the training pairs,
mean DPO loss changed 0.693147 -> 0.659211 and mean reward margin 0 -> 0.072133.
All reference state remained unchanged. These numbers validate wiring, not
biological accuracy or held-out generalization. Evidence is in
`research/guangzhou_all_atom/results/SIMULATED_closed_loop_20261003/`.

Integration fixes: missing/duplicate candidate IDs now fail rather than silently
shrinking the dataset; batches load on demand rather than retaining the whole
pair set on GPU; the adapter restores the UniMoMo import root after loading the
shared PepGLAD core; nonfinite DPO loss/gradients stop training. Simulated pairs
require an explicit CLI flag. The launcher now stages the actual mmap bundle and
rewrites the config to its local paths; resampling wrappers are rejected.

The campaign bridge rejects cross-campaign manifests, unresolved replicates,
unknown candidates, unsupported qualifiers, and invalid numeric values. It is a
callable integration module, not yet connected to a live HTTP route or UI action.

32 focused tests pass (including the simulated platform-to-checkpoint roundtrip,
campaign isolation, malformed ID cases, nonfinite training, and dataset staging).
The separate `run_unimomo_dpo_smoke.py` is prepared for the warm GPU: it uses real
UniMoMo weights, three real featurized complexes, the same platform service, and
explicitly synthetic KD values to verify optimizer/checkpoint/frozen-state
invariants. It makes no binding or model-quality claim.
