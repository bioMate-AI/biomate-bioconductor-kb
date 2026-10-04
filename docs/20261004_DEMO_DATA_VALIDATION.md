# Built-in demo data for param-less quick runs (2026-10-04)

**Ask:** like other BioMate workflows (merfish → squidpy built-in, voyager → McKellarMuscleData),
the input-blocked workflows should ship a **default demo dataset** so a param-less "quick run" works
end-to-end. Done for three workflows; validated on real AWS Batch runs (honest pass/fail — no run
marked pass on an exit code alone; real outputs inspected).

## Results

| Workflow | Demo (real, labeled) | Status | Evidence |
|---|---|---|---|
| **metaboanalystr** (`bioconductor/metaboanalystr`) | MetaboAnalyst **human_cachexia** (77 samples × 63 metabolites, cachexic vs control; the official tutorial dataset, auto-downloaded) | ✅ **PASS** exit 0 | Real stat pipeline: *"A total of 55 significant features were found"* (fold-change + t-test), `mSet.rds` + significant-feature CSVs written. PLS-DA + volcano skipped **non-fatally** (MetaboAnalystR packaging quirks: `util_volcano.Rc` missing; PLS ncomp=62 on 77 samples — affect user data too, not demo-specific). |
| **chipseq** (`genomics/perform_chipseq_peak_calling_with_macs2`) | Canonical MACS **CTCF_SE** ChIP + control (chr22, ~50k reads each; macs3-project/MACS repo, auto-downloaded) | ✅ **PASS** exit 0 | macs3 3.0.5, auto `--nomodel` fallback fired, **802 peaks** called. Outputs: `*_peaks.narrowPeak` (63 KB), `*_peaks.xls` (69 KB), `*_summits.bed` (43 KB), `results.json`. "Peak calling completed successfully." |
| **pathology WSI** (`pathology/wsi_he_nuclei_segmentation`) | OpenSlide **CMU-1-Small-Region.svs** (auto-downloaded) | ✅ **PASS** exit 0 (custom image built) | Real end-to-end run: OpenSlide read the Aperio SVS (2220×2967, 0.499 µm/px) → 30 tiles, 17 tissue → cellpose segmented nuclei → outputs `cell_table.csv` (35 KB, real per-nucleus centroids + µm² areas), `qc_overlay.png` (3.1 MB), per-tile masks, `qc_summary.json` (`status: completed`), report, manifest. Runs on the purpose-built `biomate/bioc-domain-pathology:1.0` (built on AWS from `Dockerfile.pathology`). **Note:** the workflow's DB row is not in the local `workflows` table, so `executable=1` must be set via the canonical dev DB update path (not a local edit) — the *workflow + image* are validated; only the DB discoverability flag remains. Ready-to-run registration: `backend/scripts/register_wsi_pathology.py` (adds the row + FTS, `executable=1`, idempotent) — but it HARD-REFUSES to run against the local embeddings-stub, because registering there + syncing would clobber dev's vector search. Safe procedure (in the script header): fetch the ENRICHED dev DB → run the script → `sync_to_dev.sh`. |

All three fall back to a **real, clearly-labeled** dataset (`[demo]` / `[DEMO DATA]` in logs/output) and
**honest-fail** if the download is unavailable — no fabricated data, per the no-fabrication rule.
`scripts/audit_fabrication.py` PASS after every change.

## Two root-cause fixes the real runs exposed (would not show locally)

1. **metaboanalystr — colu rebuild corrupted comma-containing metabolite names.** First run fired the
   demo correctly but died in `Read.TextData -> "Duplicate feature names are not allowed!"`: the code
   transposed cachexia and rebuilt a MetaboAnalyst "colu" CSV with `quote=FALSE`, which splits
   metabolite names that contain commas. **Fix:** feed cachexia **natively as "rowu"** (it already is a
   valid MetaboAnalyst upload — the canonical tutorial path), bypassing the rebuild. Commit `c0051e686`.

2. **chipseq — macs2 is unrunnable from available containers; switched to MACS3.**
   - `biomni-tools:x86` ships **no macs2** (`which macs2` empty — verified on a real Batch probe).
   - **Every** available bioconda **macs2** biocontainer (2.2.9.1 py39 **and** py310, build `_5`) fails at
     runtime: `macs2 callpeak` → `ImportError … ScoreTrack…so: undefined symbol: __log_finite`. Their
     compiled `.so` links a glibc math alias removed in glibc ≥2.28; the modern base lacks it. Verified
     broken on **both** builds **in isolation** (raw Batch jobs, no Nextflow mounts) — so it's the image
     build, not the executor.
   - **MACS3** (`quay.io/biocontainers/macs3:3.0.5--py312h9639c01_0`) is the maintained, CLI-compatible
     successor — imports clean (no `__log_finite`), `macs3 callpeak` takes the same `-t/-c/-n/-g/-q`
     args, same output filenames. Commit `285921f4b`.
   - Sparse/single-end ChIP (incl. the demo) can't build macs3's fragment model (`needs ≥100 paired
     peaks … found 0`). Added an **auto-fallback** to `--nomodel --extsize 200` (macs3's own
     recommendation) when model building fails — robust for real SE data, not a demo-only hack.
     Commit `53749d9ac`.

## WSI image — built on AWS (`biomate/bioc-domain-pathology:1.0`)

No registry image bundles OpenSlide + cellpose + scikit-image, so the image was built from
`backend/scripts/domain_images/Dockerfile.pathology` (Python/micromamba base) on a **self-terminating
x86 spot instance** (user-data: install docker → pull Dockerfile from S3 → build → ECR push → upload
log to S3 → `shutdown -h` with `instance-initiated-shutdown-behavior=terminate` + a +45 min dead-man's
switch). Four build/run iterations, each root-caused from a real failure (the iterative loop working):
1. `pip ... cellpose torch --index-url <pytorch>` → cellpose unfindable (single `--index-url` hides
   PyPI). **Fix:** install torch (CPU index) and cellpose (PyPI) as separate steps.
2. WSI run exit 1: `Command 'ps' required by nextflow … cannot be found`. **Fix:** add `procps-ng`.
3. WSI run exit 1: `skimage.draw.rectangle_perimeter … requires "matplotlib >=3.3"`. **Fix:** add
   `matplotlib-base` (and to the build-time sanity gate).
4. ✅ WSI run exit 0 — real nuclei segmentation (see the table row above).

The Dockerfile has a build-time import sanity gate (`import openslide, cellpose, skimage, numpy,
scipy, matplotlib; rectangle_perimeter; openslide.__library_version__`) so a broken combo fails the
build, not a Batch run. (A pip `| tee` in the build user-data initially masked exit codes → fixed with
`set -o pipefail`.)

## Related follow-up — DONE (`immunology/analyze_atac_seq_differential_accessibility`)

Had the same latent macs2-missing bug plus three more. All fixed (commit `b9d2a0ff0`) and validated
on Batch (param-less run, SUCCEEDED exit 0):
```
[demo] nf-core test-datasets human BAM pair (test=treatment, test2=control)
macs3 callpeak (treatment) -> 2 peaks ; macs3 callpeak (control) -> 2 peaks
macs3 bdgdiff -> 1 region up in treatment, 1 up in control ; all steps completed
```
Four stacked bugs fixed: (1) macs2 missing/broken → **MACS3** biocontainer + `macs3` binary for
`callpeak`×2 and `bdgdiff`; (2) `callpeak` lacked **`-B`**, so `bdgdiff` had no pileup/lambda bedGraph
inputs → added `-B`; (3) **double-`output_dir`** path bug (`-n` carried the dir *and* `--outdir` was
set, and Step 3 re-joined `output_dir`) → `-n` is now a bare name + `--outdir`, and bdgdiff outputs are
globbed by macs3's `_cond{1,2}.bed` naming; (4) param-less run **honest-failed on `SIMULATE`** → now
auto-downloads the real labeled nf-core demo BAM pair (honest-fail only if the download fails).
(Peak counts are small because the demo BAMs are ~179 KB subsets — real macs3 on real data, pipeline
proven end-to-end including the differential step.)

## Commits
`8b62f332f` (metabo demo) → `c0051e686` (metabo rowu fix) → `3719a6807` (chip macs2 pin, superseded) →
`285921f4b` (chip → macs3) → `53749d9ac` (chip --nomodel fallback). WSI: `e170c7cf0` + `f47eb287f`.
All deployed to dev (`sync_to_dev.sh`, result=healthy).

## Cleanup note
Temporary Batch job definitions registered for the isolation probes (`chip-macs2-probe`,
`macs2probe-py39-same`, `macs2probe-py310-alt`, `macs3probe`, `macs3probe-b`, `spot-lt-probe`) are
harmless (no cost) but can be deregistered: `aws batch deregister-job-definition --region us-west-2
--job-definition <name>:1`.
