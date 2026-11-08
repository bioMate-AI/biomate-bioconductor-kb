# Overnight autonomous validation results (2026-10-04)

**Context:** after the 4 parallel threads (UX run-progress, team activity ledger, pathology WSI,
validation fixes) were committed + deployed, the owner authorized autonomous overnight work. This
records the validation runs on the production path (`/api/workflows/execute`, spot Batch,
self-terminating), audited by reading real `.command.err`/outputs — **honest pass / fail / blocked**,
no fabrication, no run marked "pass" on a mere exit code.

## Deploy (done, verified)
- 4 threads live on dev (commit `010bfee5`, sync health PASS). Verified on dev: `project_activity`
  table exists (B), chipseq real file-inputs (D), pathology WSI workflow present (C), spatial fix
  present (D), frontend healthy (A).
- **DB safe:** dev `galaxy_ai_tools.db` MD5 unchanged (`39d8b5a8…`); no concurrent DB change clobbered.

## Validation runs

| Workflow | Run | Result | Evidence / cause |
|---|---|---|---|
| **merfish** (A infra + libz regression check) | `a2352e0f` | ✅ **PASS** exit 0 | Real squidpy output: `spatially_variable_genes.csv`, `spatial_domains.csv`, `spatial_qc.json`, `morans_I_ranking.png`, `top_svg_spatial.png`, report. Confirms the always-on host-libz mount still holds on this branch and the production run path is healthy. |
| **metaboanalystr** (D metabolomics fix) | `85ed4681` | ⚠️ **BLOCKED on input** (not a fix failure) | exit 1, `Error: Required input peak-intensity table (peak_intensity_table.csv) not found.` This is **correct honest-fail behaviour** (param-less run → no input). The `ReplaceMin → ImputeMissingVar` fix lives on the with-input path; validating it needs a staged peak-intensity table. |
| **visium_voyager_spatial_esda** (D spatial fix) | `4d05c71d`→`549f4286`→`e12e8076` | ✅ **PASS** exit 0 → **`executable=1`** (resolved on run `8be17525`) | 3-run root-cause chain: **(1)** exit 127 `Rscript: No such file or directory` — ran in `biomate-nextflow-base` (no R) because the `.nf` used `container "${params.container}"` indirection, which the executor's `/single_cell/` force resolves to the base default → **fixed with a literal directive** (merfish pattern, commit `b25d4877c`). **(2)** full `bioc-domain-transcriptomics:3.20` → `CannotPullContainerError: no space left on device` (reactome.db; the DISK blocker) → **switched to `:3.20-slim`** (`1a0d86c5`). **(3)** slim fit disk + R installed Voyager/SpatialFeatureExperiment, but `sf.so` **fails to load — missing GDAL/GEOS/PROJ system libs** in the image. **Definitive blocker: needs a dedicated spatial image** (GDAL/GEOS/PROJ + the Voyager stack baked — the `bioc-domain-spatial` image that was referenced but never built). RESOLVED: pointed the literal directive at the EXISTING purpose-built `bioc-domain-spatial:3.20-deps` (an earlier "doesn't exist" claim was wrong — verified in ECR; it carries GDAL + the Voyager stack). Run `8be17525` exit 0, REAL Voyager 1.8.1 ESDA on built-in McKellarMuscleData (928 spots × 15,043 genes): top gene mt-Co1 Moran's I 0.828, then Lgals3/Spp1/Psap/Ctsb (biologically correct). Outputs: univariate_moran.csv, sfe_esda.rds, esda_summary.json, moran_top_genes.png, spatial_feature.png, qc_metrics.csv. |
| **chipseq** (D peak-calling fix) | — | ⚠️ **BLOCKED on input** | D's fix correctly made ChIP+control files mandatory (was fabricating demo peaks). Validating needs a small public ChIP+control BAM pair; `team-curated/epigenomics/` has only a txdb + peaks.bed, no reads. Not run (no fabricated input). |
| **pathology WSI** (C) | — | ⬜ not attempted | Needs a WSI slide (public OpenSlide sample) + confirmation the cellpose image ships OpenSlide. Deferred; `executable=0`. |

## Honest headline
- **1 genuine pass** (merfish — real output; also re-confirms the always-on host-libz mount on this branch).
- **2 input-blocked** (metaboanalystr, chipseq) — their *code* fixes are in place and they **honest-fail correctly** without input; end-to-end validation needs staged public/curated inputs.
- **2nd genuine pass** (voyager): four real runs peeled back wrong-image → disk → missing-GDAL, resolved by pointing at the EXISTING `bioc-domain-spatial:3.20-deps` (the "doesn't exist" claim was false). Real Voyager ESDA output; `executable=1`.
- **1 deferred** (pathology WSI — needs a slide; `executable=0`).
- This is the "indexed ≠ runs" gap made concrete: local checks passed, but only real runs exposed the container-resolution bug and the image-infra blocker. **No run was marked "pass" on an exit code; nothing fabricated.**

## Lesson reinforced
A `.nf` process `container` set via `"${params.container}"` indirection is NOT reliable for
`/single_cell/`-path workflows — the executor's container-force resolves it to the base image
(no R/python → exit 127). Use a **literal** container directive (merfish, now voyager). Logged to
`reference_executor_container_resolution` territory.

## Concrete next steps (for the owner — need a build or curated data)
1. **Spatial (voyager): DONE** — resolved tonight by using the existing `bioc-domain-spatial:3.20-deps`; `executable=1`. (No new image build was needed; the earlier "image doesn't exist" claim was false.)
2. **Metabolomics validation:** stage a MetaboAnalystR-format `peak_intensity_table.csv` (public /
   `team-curated` metabolomics), run `metaboanalystr` with it → validates the ReplaceMin→ImputeMissingVar fix.
3. **ChIP-seq validation:** stage a small public ChIP + control BAM pair (ENCODE / nf-core test),
   run `perform_chipseq_peak_calling_with_macs2` → validates the real-peak-calling fix.
4. **Pathology WSI:** run on a public OpenSlide sample (e.g. CMU-1-Small-Region); first confirm the
   cellpose image ships OpenSlide (else pin a mulled image). Then flip `executable=1`.

## DB state changes made tonight (local DB; ride the next sync)
- `14438` (visium_voyager_spatial_esda) `executable` → **1** (VALIDATED on run 8be17525); `docker_image` = bioc-domain-spatial:3.20-deps (already correct).
