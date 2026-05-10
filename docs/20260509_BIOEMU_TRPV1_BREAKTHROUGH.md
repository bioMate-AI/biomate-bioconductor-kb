# TRPV1 BioEmu — REAL ENSEMBLE PRODUCED (2026-05-09)

After multiple AWS Batch retries, BioEmu produced 100 real conformers for TRPV1.

## What worked

**Container:** `protein-dynamics-nf:v1.0.8` (built today)
- Correct build order: bioemu first, then `tensorflow-cpu==2.12.0` --force-reinstall, then `jax[cuda12_pip]==0.4.35` --force-reinstall last
- Verified CUDA jaxlib in final image (not CPU-only build)

**Inputs:**
- TRPV1 chain A monomer (594 aa) — extracted via `chainID A` selector (was previously 2324 aa tetramer)
- BioEmu checkpoint cached at `s3://biomate-nextflow-work/models/bioemu-v1.1/`
- AF2 weights downloaded fresh (~3.5 GB) — should add S3 cache for next run

**Result:**
- Output: `s3://biomate-nextflow-work/nf-work/bioemu-trpv1-v9-1778367656/7f/.../trpv1_ensemble.tar.gz` (35 MB)
- 100 conformer PDBs (`conf_0000.pdb` … `conf_0099.pdb`)
- Local copy: `experiments/local_runs/trpv1_bioemu/aws_output/trpv1_ensemble.tar.gz`

## What failed (and why it doesn't matter)

POCKET_MINER (downstream step) failed with `no space left on device` during container pull on Batch instance. This is the post-processing step that scans conformers for cryptic pockets — separable from BioEmu output.

## Issues fixed in this session

1. **Container build order** — JAX 0.4.35 CUDA was being overwritten by `bioemu`'s deps. Fix: install JAX last with `--force-reinstall` (Dockerfile v1.0.8).
2. **Tetramer vs monomer** — `mda.Universe.select_atoms('protein')` was selecting all 4 chains. Fix: `select_atoms('protein and chainID A')`.
3. **CTF pkl NaN** — `cryodrgn parse_ctf_star` left phase-shift column as NaN. Fix: replace col 8 with 0.0 explicitly.
4. **CTF numpy 2.x→1.x ABI break** — pickle written with NumPy 2.x has `numpy._core` path; container's NumPy 1.x can't import it. Fix: re-pickle as plain list of floats (no numpy metadata) → `ctf_v1compat.pkl`.
5. **Nextflow `errorStrategy`** — added `errorStrategy = { task.exitStatus == null ? 'retry' : 'finish' }` + `maxRetries = 2` to `process_gpu` label so Batch transient "Task failed to start" auto-retries.

## Cost cleanup

Terminated `cryosparc-biomate-job` (g6.12xlarge in us-east-1) — was idle at 0.1% CPU for 24+h, had been running 12 days, ~$1,400 burned, ~$118/day going forward.

## Next steps

- cryoDRGN r19 RUNNABLE on AWS Batch (with `ctf_v1compat.pkl`)
- AF3 v1.0.1 building on `i-038b64f058b9b395e` (added `build_data()` step for missing pickle files)
- After cryoDRGN completes, run gap analysis comparing BioEmu ensemble vs cryoDRGN clusters
