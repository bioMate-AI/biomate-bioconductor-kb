# Cyclic peptide model and closed-loop takeover — 2026-10-03

## Workspace and recovered run

Worktree: `/Users/kky/biomate-review`, branch `docs/peptide-pharma-loop-work-20260926`.
The pasted handoff matches commits `f4070a850` and `2b3aa0196` in this branch.
Pre-existing unrelated changes were left intact.

AWS run `unimomo-cyclic-ft-20261002T204906Z` reports completion at
2026-10-03 02:20:10 UTC. The old instance is no longer returned by EC2, and
no running or stopped instances tagged `project=cyclic_peptide` were found.
Status logs were downloaded from
`s3://knowledge-datasets-1759951976/cyclic_peptide/runs/unimomo-cyclic-ft-20261002T204906Z/status/`
to `research/guangzhou_all_atom/results/unimomo-cyclic-ft-20261002T204906Z/`.

## Result and qualification

The logs contain all 88 evaluation targets, each with 100 finite DockQ scores.
Pinned upstream metric code confirms aggregation is the mean of each target's
maximum DockQ: this is an oracle metric, not performance of a deployable ranker.

| Metric | Base | Fine-tuned |
|---|---:|---:|
| Oracle DockQ | 0.40292045 | 0.41259091 |
| Best-candidate AAR | 0.27766705 | 0.28951250 |
| Median minimum complex CA RMSD | 6.54 | 6.39 |
| Mean inner clash metric | 0.07988474 | 0.11392714 |

Paired target bootstrap (10,000 replicates, seed 0): DockQ difference
+0.00967045, 95% percentile interval [-0.00171591, +0.02140909].
47 targets improved and 41 worsened. This does not establish improvement.
The interval does not capture training-seed uncertainty or clear sequence leakage.
Do not compare these numbers to a different PepGLAD harness.

**Training is unqualified:** 79 OOM events across 90 attempted batches
(30 epochs, three batches/epoch; 502 train and 55 validation complexes).
Upstream forward OOM creates a fake zero loss; the trainer then calls the
optimizer and increments the step. AdamW momentum/weight decay can still change
weights in that state. Thus this is neither a clean trained model nor necessarily
an unchanged base checkpoint. The selected artifact was epoch27_step84.
Zero-valued dG outputs must not be presented as measured binding energies.

## Changes and verification

- `patch_unimomo_training.py`: patch the pinned trainer to abort before an
  optimizer step on forward/backward OOM, nonfinite loss, missing/nonfinite/zero
  gradients; reject empty loaders and invalid validation; log every completed
  optimizer step. Source-anchor checks reject drift and repeated application is safe.
- `unimomo_cyclic_ft.yaml`: use explicit single-complex batches. Merely reducing
  the dynamic budget would silently filter large complexes, so the wrapper is removed.
- Launcher: install the guard before training; preserve processed training data
  and evaluation outputs in S3; reject insufficient split data or missing DockQ.
- `wetlab_kd_to_pairs.py`: missing KD is not a negative; malformed, nonpositive,
  or nonfinite values fail; censored bounds retain their direction and gap;
  qualitative non-binders are weak labels. Require a target, preserve sequence
  case, and stop inventing a GenScript source for arbitrary input.
- `audit_unimomo_run.py`: reconstruct per-target scores from persisted logs,
  reject mismatched/incomplete target sets, report paired bootstrap uncertainty
  and flag OOM/update-evidence problems. Its log qualification is not a complete
  model-promotion gate.

26 focused tests passed, including real torch autograd/SGD execution of the
patched upstream training method. Both launcher and extracted driver pass
`bash -n`; patch applied and compiled against upstream commit
`f58f117d43975d45dc2521b34ae3066a095582f0`.
Scoped diff checks pass. Whole-worktree diff check reports an existing unrelated
blank line at EOF in `docs/20260928_PROTEOMICS_DDA_VALIDATION.md`.

## Remaining work

No new GPU instance or training job was launched in this takeover pass.
The corrected batch configuration has not yet been tested on CUDA.

1. Bring up the warm development GPU described in the existing program and run
   one complete train/validation epoch, checking all 502 update records,
   finite gradients, nonzero diffusion-weight changes, and frozen AE weights.
   Keep the environment for diagnosis if a single complex still exceeds memory.
2. Only after that smoke passes, run the full corrected fine-tune and matched
   evaluation. Audit target/sequence overlap, not only PDB-id holdout.
3. Add self-consistency selection and compare selected DockQ against the oracle;
   the recovered run cannot support a deployable best-of-N claim.
4. Validate wet-lab candidate IDs against retained featurized structures before
   DPO. The converter emits pairs, but the diffusion loader needs matching
   structure mmap IDs: the prior handoff's “fully closed loop” claim is not yet
   demonstrated by a real end-to-end run. Assay provenance/replicate handling
   and platform ingestion still need an integration test with real assay data.
