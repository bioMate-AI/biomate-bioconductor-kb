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

## Real-model integration queued and split audit prepared

SSM command `7920ee73-f7a3-42d1-aa27-ce7ad3ec27b9` successfully started
`biomate-simulated-dpo-integration.service` on the warm GPU. It waits for the
one-epoch smoke report, then runs the real model/real mmap test and uploads its
report under `SIMULATED_dpo_integration/` in the same S3 run prefix. Source hashes
for the staged Python files are recorded in `integration_code/source_sha256.json`.
The production assay modules are copied byte-for-byte into an isolated package;
no assay service calls are mocked. Selection requires distinct peptide sequences.

`audit_unimomo_splits.py` now compares the four-column UniMoMo train/validation
indexes with the thirteen-column original PepGLAD test index. It reports shared
PDB IDs, peptide sequences, receptor sequences, and receptor-peptide sequence
pairs, with unknown-sequence counts. Two additional tests verify sequence leakage
across different PDB IDs and rejection of empty/duplicate indexes. A clean exact
match audit still cannot establish homology or pretraining independence.

The 32 integration tests also passed from the exact PR checkout. Live installer
inspection confirmed active biotite compilation (not a stalled GPU job) and a
shutdown deadline at 2026-10-03 20:35:02 UTC.

CSV boundary follow-up: required KD/sequence/target headers are now validated,
so a misspelled KD header cannot silently yield an empty successful export.
Log-KD gaps use a difference of logarithms to avoid ratio overflow. The focused
converter/integration suite passes 18 tests after this change.

## Platform malformed-data boundary

The production assay validator previously accepted `NaN`/infinity and nonpositive
KD values. NaN could become NULL at SQLite insertion and violate its NOT NULL
constraint, while other invalid values could contaminate ranking. Validation now
rejects nonfinite raw/normalized values and nonpositive KD before persistence.
Five integration cases cover NaN, infinity, zero, negative KD, and unit-conversion
overflow; all return errors and persist zero rows. The nine-test closed-loop
integration suite passes. The preceding exact-PR full suite passed 35 tests.

## Spot interruption and recovery

EC2 terminated `i-0e66b63836f7e637b` for lost Spot capacity at
2026-10-03 16:50:23 UTC (`Server.SpotInstanceTermination`, request
`sir-cezznwjh`). Featurization was incomplete, so neither CUDA epoch validation
nor the queued real-model DPO test ran. Stale S3 logs were diagnosed via live
SSM/EC2 status rather than treated as completed work.

The still-attached root disk was captured as snapshot
`snap-0ed9ab890bd440ba6` to preserve the installed environment, base checkpoint,
and downloaded structures. A replacement uses on-demand capacity. The launcher
now accepts `MARKET=ondemand`, an AMI override, and `WARM_START=1`. Warm restore
checks the exact source revision, base checkpoint size, autoencoder presence,
reviewed parser patch, and CUDA availability. It reprocesses the interrupted mmap
from scratch using the cached PDBs; partial mmap output is never accepted.
Both launcher and extracted warm driver pass shell syntax checks. This recovery
change is based on the observed interruption and filesystem contents from the
last successful setup stages, not an attempt to fix an unknown training failure.
