# Smoke tests (written BEFORE the runs return)

## Smoke 1 (Boltz-2 2.2.1, job cycbench-smoke1, spot queue; 9CDT_2 strict H2T, 9B0A_2 strict disulfide bond-constraint, 8R7S_2 CCD tier cyclosporin-like H2T with 9 CCD modifications)
Review notes (diff read end to end): driver gates = (a) S3 `run.json` skip check (fresh prefix -> no skip), (b) `len(cifs)==N` after boltz (needs 25 files named *_model_<i>.cif under out/),
(c) PAE npz present (needs --write_full_pae; flag exists in `boltz predict --help`), (d) weights: image has none -> boltz downloads into --cache (needs internet; first job then uploads tar to S3 cache).
Silent-skip risks: if the MSA server is unreachable boltz fails loudly (not silent). If the NH2/ACE caps appear later they are untested here (none of the 3 complexes has caps).
Prediction: all 3 complexes finish (status ok, 25 cifs + 25 confidence json + pae_if.json each); first complex ~8-12 min (weights download + MSA), the others ~3-6 min each;
Boltz echoes "Found explicit empty MSA" for the peptide; the disulfide Z3-Z13 bond constraint parses. Total job ~20-30 min on one spot GPU (observed GPU in the earlier probe: Tesla T4 16 GB), cost ~$0.2-0.4.
I cannot predict DockQ; the smoke checks plumbing only. Failure modes I consider plausible: T4 OOM at 25 samples (driver retries with max_parallel_samples=1), NCAA modifications rejected (8R7S_2) -> would be a real finding about expressibility.

## Smoke 2 (after the driver fix) — prediction written BEFORE the run returns
smoke1b: Boltz-2 finished all 3 complexes (~3 min each for 25 samples at T4, so ~10–12 min total with MSA) but the driver crashed on `shutil.copy` of a directory
(`msa/in_unpaired_tmp_env`) AFTER prediction and BEFORE upload → 0 samples on S3, yet the job exited 0 ("SUCCEEDED"). Fixed: files-only best-effort MSA copy; non-zero exit if any complex fails; tests/test_driver.py.
Prediction for smoke2: job status SUCCEEDED with exit 0 *and* `ALL_DONE [[...,"ok"] x3]`; for each of 9CDT_2, 9B0A_2, 8R7S_2: 25 `sample_*.cif`, 25 `confidence_*.json`, `pae_if.json`, `run.json` (status ok) under
s3://biomate-nextflow-work/cyclic_peptide/cofold_bench/samples/boltz/<id>/. Wall time ~12–15 min, cost < $0.30. Residual risk: 8R7S_2 (9 CCD modifications) could fail inside boltz itself (not the driver) → would appear
as `status: fail` + non-zero exit, which is the correct behaviour now. If any complex fails the job must show FAILED, not SUCCEEDED.
