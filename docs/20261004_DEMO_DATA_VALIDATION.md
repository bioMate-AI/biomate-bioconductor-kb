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
| **pathology WSI** (`pathology/wsi_he_nuclei_segmentation`) | OpenSlide **CMU-1-Small-Region.svs** (auto-downloaded) | ⬜ **demo added; blocked on image** | `executable=0`. No registry image bundles OpenSlide + cellpose + scikit-image (mulled-hash probes all 401). Needs a custom image build (owner/infra). Demo slide makes that smoke test trivial once the image exists. See `docs/20261004_PATHOLOGY_WSI_CONTAINER_FINDINGS.md`. |

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

## Known related follow-up (NOT fixed here)
`immunology/analyze_atac_seq_differential_accessibility` also pins `biomni-tools:x86` and calls macs2 →
same missing-tool failure latent there. Same fix applies (MACS3 biocontainer). Deferred — out of this
task's scope; logged for a future pass.

## Commits
`8b62f332f` (metabo demo) → `c0051e686` (metabo rowu fix) → `3719a6807` (chip macs2 pin, superseded) →
`285921f4b` (chip → macs3) → `53749d9ac` (chip --nomodel fallback). WSI: `e170c7cf0` + `f47eb287f`.
All deployed to dev (`sync_to_dev.sh`, result=healthy).

## Cleanup note
Temporary Batch job definitions registered for the isolation probes (`chip-macs2-probe`,
`macs2probe-py39-same`, `macs2probe-py310-alt`, `macs3probe`, `macs3probe-b`, `spot-lt-probe`) are
harmless (no cost) but can be deregistered: `aws batch deregister-job-definition --region us-west-2
--job-definition <name>:1`.
