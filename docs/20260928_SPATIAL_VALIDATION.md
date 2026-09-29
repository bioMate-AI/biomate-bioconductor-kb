# Spatial Domain Validation — Voyager Visium ESDA

**Date:** 2026-09-28 (updated 2026-09-29)
**Author:** Yaoyun Zhang
**Goal:** Make the spatial domain runnable + validated. The
`visium_voyager_spatial_esda` workflow referenced a spatial image that did
not exist. Build `bioc-domain-spatial:3.20-deps`, push to the (pre-created)
ECR repo, wire the workflow to it, and validate on real 10X Visium data via
the production AWS Batch path.

> **STATUS 2026-09-29 — ✅ VALIDATED end-to-end on production AWS Batch.** The
> 2026-09-28 run failed ONLY because the image was too fat (9.83 GB) for the CE node
> disk (`no space left on device` unpacking `reactome.db`). The image was slimmed
> (base swap `bioc-domain-transcriptomics:3.20` → `bioc-domain-single_cell:3.20-slim`;
> commit `57b56dca2`): **9.83 GB → 2.15 GB compressed** (digest
> `sha256:41fdd550…`). The re-validation Batch job `5390e911-…` SUCCEEDED (exit 0) —
> image pulled clean, all 7 real outputs persisted, science sound (top gene mt-Co1,
> Moran's I 0.828). Full detail in §3.2. Total slim + re-validation spend ≈\$0.06.

---

## 0. Assessment

- **Workflow:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf` (DB id 14438, domain `single_cell`, stale `docker_image=biomate/bioc-spatial:v1`).
- **Prior version was non-runnable:** it chained an upstream nf-core/spatialvi
  Space Ranger run and called a suite of bespoke `/opt/biomate/voyager/*.R`
  scripts (`validate_spaceranger.py`, `spe_to_sfe.R`, `spot_qc_norm.R`,
  `build_graph.R`, `run_univariate.R`, `run_bivariate_lees_L.R`,
  `run_multispati.R`, `cluster_and_stratify.R`, `render_report.R`) that were
  **never implemented** and required Space Ranger output dirs BioMate never
  stages. It also pinned a non-existent image `biomate/bioc-spatial:v1`.
- **Prior build agent** (spatial_20260928 S3 dir) failed EARLY — only at
  `aws ecr create-repository` (ecsInstanceRole lacked `ecr:CreateRepository`).
  The repo `biomate/bioc-domain-spatial` has since been created from local
  creds. The transcriptomics base `bioc-domain-transcriptomics:3.20` exists.
- **Canonical minimal-correct ESDA reference** found in the voyager
  `_interpretation.json`: `McKellarMuscleData()` -> in_tissue filter ->
  `logNormCounts` -> `findVisiumGraph` -> `runUnivariate(type="moran")`.

## 1. Changes made

Commit **e00c99f81** — `feat(spatial): runnable Voyager Visium ESDA + bioc-domain-spatial image`:

- **Rewrote** `visium_voyager_spatial_esda/main.nf` to a self-contained,
  minimal-correct Voyager Visium ESDA: one R process (`esda_run.R`) with a
  named `..._WORKFLOW` + anonymous entry. No Space Ranger dependency, no
  input params required. Container directive reads `params.container` so the
  executor's injected ECR image override applies.
- **Added** `backend/scripts/domain_images/voyager/esda_run.R` — the driver:
  load SFE (SFEData example default `McKellarMuscleData`, or user `--sfe_rds`),
  QC (in-tissue + min-count filter + subsample cap), `logNormCounts`, HVG via
  `modelGeneVar`/`getTopHVGs`, Visium spatial graph (`findVisiumGraph`, k-NN
  fallback), univariate Moran's I, emit SFE .rds + Moran's I CSV + QC CSV +
  2 plots + JSON summary.
- **Dockerfile.spatial:** `COPY esda_run.R -> /opt/biomate/voyager/esda_run.R`.
- **deps/spatial.txt:** added `jsonlite` (JSON summary).

## 2. Image build

- **Repo (pre-created):** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-spatial` (created 2026-09-28 17:42).
- **Base:** `bioc-domain-transcriptomics:3.20`.
- **Build box:** spot c5.4xlarge, stock Ubuntu 22.04 (ami-0fbdee0e602a53461),
  IAM `ec2-ecr-builder-profile`, SG `sg-0a70bb26e47332c55`, dead-man
  `shutdown -h +180`, `--instance-initiated-shutdown-behavior terminate`,
  `DOCKER_BUILDKIT=0`, self-contained cloud-init (build -> sanity -> push ->
  shutdown), logs -> `s3://biomate-nextflow-work/domain_image_builds/spatial_20260928/`.
  - First box `i-0063889486bdd49b2` (us-west-2a): terminated — over-strict
    `aws ecr describe-repositories` gate (role lacks `ecr:DescribeRepositories`;
    push actions ARE granted). Root-cause fix: removed the describe gate.
  - Active box `i-020d5a9c77bf7aaa8` (us-west-2d, after InsufficientInstanceCapacity in 2a/2b/2c).
- **Sanity gates (before push):** (1) `library(Voyager/SpatialFeatureExperiment/
  SpatialExperiment/SFEData/sf/spdep/scater/scran/jsonlite)` all load;
  (2) `esda_run.R` present + parses.

### Build result — SUCCESS

- **Image:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-spatial:3.20-deps`
- **Digest:** `sha256:bd10988d1f85ee768df3d3b75e05357822ccaa7bfa23a8ea062f74b50cfb9884`
- **Pushed:** 2026-09-28 18:11:15 PT · size ~9.83 GB (transcriptomics base + spatial deps).
- **Deps install:** `STILL MISSING: 0`, `INSTALLED BUT WONT LOAD: 0` — every
  package in `deps/spatial.txt` installed and loads.
- **Sanity gate 1 (before push):** `SANITY1 OK Voyager 1.8.1 SFE 1.8.6 SFEData 1.8.1`
  (also `SpatialExperiment`, `sf`, `spdep`, `scater`, `scran`, `jsonlite` all load).
- **Sanity gate 2 (before push):** `SANITY2 OK esda_run.R parses`
  (`/opt/biomate/voyager/esda_run.R` present + parses).
- **Build boxes:** `i-0063889486bdd49b2` (terminated — describe gate fix) and
  `i-020d5a9c77bf7aaa8` (built + pushed, then self-terminated). Both **terminated**.
  Zero orphan c5.4xlarge at end.
- **Build logs:** `s3://biomate-nextflow-work/domain_image_builds/spatial_20260928/`
  (`build.log`, `sanity1.txt`, `sanity2.txt`, `STATUS.txt`, `agent_launched_iid.txt`).

## 3. Validation run

**Owned by the main/coordinator session** (I held the git sync; SSM is
read-only per project rules, so I could not dispatch a production run myself).
Handoff spec provided:

- `POST /api/nextflow/execute`
- `nextflow_path`: `nextflow_nfcore/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf`
- `parameters`: `{}` (NONE — defaults to SFEData `McKellarMuscleData`, real 10X Visium mouse skeletal-muscle data; no Space Ranger / input staging needed)
- `compute_config.container`: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-spatial:3.20-deps`
- `workflow_domain`: `single_cell`
- Expected real outputs: `sfe_esda.rds`, `univariate_moran.csv`, `qc_metrics.csv`, `moran_top_genes.png`, `spatial_feature.png`, `esda_summary.json`, `versions.yml`.

### 3.1 Production dispatch result (2026-09-29) — ❌ FAILED: image too large for CE disk

Dispatched via the production path `POST /api/workflows/execute` on dev (→ backend
`/api/nextflow/execute`), e2e fixture `lifeifei163361@163.com`, params `{}`,
container override `bioc-domain-spatial:3.20-deps`, executor `awsbatch`.

| Field | Value |
|---|---|
| BioMate run id | `322b3216-e124-4b6a-8eab-3fcd6cc86349` |
| Nextflow run id | `6141f8f3-6a43-42d5-b0e3-bd5ae530305e` |
| Batch job id | `a42d9d00-0d27-4e23-9d69-974bac8d09eb` |
| Terminal status | **FAILED** — `Task failed to start` (returncode 1, ~2.9 s) |
| S3 outputs | **none** (task never started; only `.command.sh`/`.command.run` staged) |

**ROOT CAUSE (verbatim, `aws batch describe-jobs`):**
```
CannotPullContainerError: failed to register layer:
  write /usr/local/lib/R/site-library/reactome.db/extdata/reactome.sqlite:
  no space left on device
```
The `bioc-domain-spatial:3.20-deps` image is **~9.83 GB** (transcriptomics base +
spatial deps). The default Batch compute environment `biomate-nextflow-ce-v2`
provisions instances whose root/instance-store disk cannot unpack a ~10 GB image —
the pull fails partway (while writing `reactome.db`'s bundled sqlite). This is an
**infra/disk bug, not an image or workflow bug**: the image built + sanity-gated
clean (`ALL OK`, §2), the workflow `.nf` + `esda_run.R` are correct (the generated
`.command.sh` calls `Rscript /opt/biomate/voyager/esda_run.R --sfe_dataset
McKellarMuscleData …` exactly as designed), and the container directive resolved to
the right ECR image. The task simply never ran because ECS could not land the image
on the node.

**Fix (separate infra task — NOT done here, per capture-and-report):** either (a)
increase the EBS/instance-store size on `biomate-nextflow-ce-v2`'s launch template so
~10 GB images unpack, (b) route large-image bioc-domain workflows to a CE with bigger
disk, or (c) slim `bioc-domain-spatial` toward a `-slim` variant (drop reactome.db and
other non-load-bearing annotation DBs) so it fits the current CE like the
`bioc-domain-transcriptomics:3.20-slim` image (which pulls + runs fine — proven by the
single-cell dropletutils SUCCESS the same session). **Batch spend for this run: ~$0
(no compute ran; image-pull failure only).**


## 3.2 IMAGE SLIMMED + RE-VALIDATED (2026-09-29) — ✅✅✅ SUCCESS

The §3.1 blocker was 100% the image size. **Root cause of the bloat:** the spatial
image layered the ~15-package Voyager ESDA stack ON TOP OF
`bioc-domain-transcriptomics:3.20`, which is **~9.78 GB compressed on its own** (the
full 519-package transcriptomics stack — clusterProfiler / pathview / ChIPpeakAnno /
GenomicFeatures / signatureSearch / …). That stack transitively pulls the huge
annotation DBs `reactome.db` / `GO.db` / `org.*.db` / `TxDb.*` — `reactome.db`'s bundled
`reactome.sqlite` was the exact file the Batch node ran out of disk unpacking. None of
that stack is used by the minimal Voyager Visium ESDA. The spatial deps layer itself was
only ~0.05 GB — the base was the entire problem.

### The slim (commit `57b56dca2`)

- **Base swap:** `bioc-domain-transcriptomics:3.20` (9.78 GB) →
  `bioc-domain-single_cell:3.20-slim` (~2 GB) — the proven Batch-ready `:3.20-slim`
  family (same base family the single-cell dropletutils + ChIP-seq validations ran on).
  It already carries `SpatialExperiment` / `SingleCellExperiment` / `SummarizedExperiment`
  / `scater` / `scran` / `scuttle` / `ggplot2` / `patchwork`, so only the geospatial +
  Voyager stack is added on top.
- **`deps/spatial.txt` trimmed** to the minimal-correct set `esda_run.R` needs
  (Voyager, SpatialFeatureExperiment, SpatialExperiment, SFEData, sf, spdep, scater,
  scran, scuttle, BiocNeighbors, BiocSingular, scales, ggplot2, patchwork, jsonlite).
  **Dropped from the explicit list:** `terra`, `EBImage` (still arrive transitively as
  SFE/Voyager hard Imports — build stays intact), `magick`, `jpeg`, `png`, `rjson`,
  `pheatmap`, `spData`, `sfheaders`, `bluster` (not on the ESDA path).
- **Dockerfile:** `--no-install-recommends` + apt clean same-layer; R `INSTALL_opts`
  drop help/html/docs/manual/tests; prune doc/help/html/test dirs + strip caches in the
  same RUN layer; hard-fail (`quit status=1`) if any dep is missing so a broken build
  can't push.

### Build (spot c5.4xlarge, self-contained cloud-init)

- **Box:** `i-0c16b411cfe15cfea` (us-west-2b, after InsufficientInstanceCapacity in 2a),
  spot, stock Ubuntu 22.04 (`ami-0fbdee0e602a53461`), IAM `ec2-ecr-builder-profile`,
  SG `sg-0a70bb26e47332c55`, 60 GB gp3 root, dead-man `shutdown -h +180` FIRST +
  `--instance-initiated-shutdown-behavior terminate`, `DOCKER_BUILDKIT=0`. Build →
  sanity → push → shutdown all self-contained; logs →
  `s3://biomate-nextflow-work/domain_image_builds/spatial_slim_20260929/`.
- **Deps install:** `STILL MISSING: 0`, `INSTALLED BUT WONT LOAD: 0`.
- **Sanity 1 (before push):** `SANITY1 OK Voyager 1.8.1 SFE 1.8.6 SFEData 1.8.1`
  (also scater/scran/sf/spdep/SpatialExperiment/jsonlite load).
- **Sanity 2 (before push):** `SANITY2 OK esda_run.R parses`.
- **Box confirmed TERMINATED; zero orphan c5.4xlarge / spatial-slim boxes.**

### Size — before → after

| | Compressed | Unpacked |
|---|---|---|
| Old (transcriptomics base) | **9.83 GB** | ~20-23 GB |
| **New (single_cell:3.20-slim base, slimmed)** | **2.15 GB** | **8.36 GB** |

**78% smaller compressed; well under the ~6 GB target, unpacked under ~15 GB with margin.**

- **New image:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-spatial:3.20-deps`
- **New digest:** `sha256:41fdd55073ed9d361c939cc24bae5ebb570307e587b5539082174392130f51da`
  (was `sha256:bd10988d…`). Pushed 2026-09-29 13:08 PT.

### Re-validation — ✅ PULLED CLEAN + REAL OUTPUTS

Dispatched via the production path (`POST /api/workflows/execute` on dev, e2e fixture
`lifeifei163361@163.com`, `params={}`, container override `bioc-domain-spatial:3.20-deps`,
executor `awsbatch`, `workflow_domain=single_cell`).

| Field | Value |
|---|---|
| BioMate run id | `e7fdafc6-8727-4180-8a6b-d05123675bdc` |
| Nextflow run id | `07feba20-68ef-4b53-855e-0424020f52cd` |
| Batch job id | `5390e911-4999-48ae-9f52-05711a558e6d` |
| Terminal status | **SUCCEEDED** (exit 0), task ~46 s |
| Image on task | `…/biomate/bioc-domain-spatial:3.20-deps` — **pulled clean, no disk error** |

**The disk blocker is RESOLVED:** the 2.15 GB image unpacked and ran on the default CE
node `biomate-nextflow-ce-v2` — no `CannotPullContainerError` / `no space left on
device`. `.command.err` shows SFEData downloading + loading McKellarMuscleData cleanly.

**All 7 expected outputs persisted to S3** (`s3://biomate-nextflow-work/nextflow/outputs/unknown/991281a3/`,
non-empty, count-checked): `sfe_esda.rds` (20.96 MB), `univariate_moran.csv` (9.4 KB),
`qc_metrics.csv` (26.9 KB), `moran_top_genes.png` (31 KB), `spatial_feature.png`
(183 KB), `esda_summary.json` (248 B), `versions.yml` (142 B).

**Science confirmed real + biologically sound** (`esda_summary.json`): 928 in-tissue
spots × 15,043 genes; **top spatially autocorrelated gene = mt-Co1 (Moran's I 0.828)**
(mitochondrial, classic strong spatial autocorrelation), then Lgals3 / Spp1 / Psap /
Ctsb — all plausible spatially-structured genes in regenerating muscle; median Moran's I
0.34. Voyager 1.8.1 / SFE 1.8.6 / SFEData 1.8.1. **Spatial domain is now VALIDATED
end-to-end on production AWS Batch.**

## 4. Cost + cleanup

- **Build:** two spot c5.4xlarge boxes; the first ran ~few min before the
  describe-gate false-fail + self-terminate; the winning box built + pushed +
  self-terminated in ~10 min. Spot c5.4xlarge ~\$0.28/hr → build spend ≈ **<\$0.15**.
- **Both build boxes confirmed terminated; zero orphan c5.4xlarge.**
- Validation Batch spend (first, failed image-pull): ~\$0 (no compute ran).

### 2026-09-29 slim rebuild + re-validation spend

- **Slim build box** `i-0c16b411cfe15cfea`: one spot c5.4xlarge (~\$0.28/hr), ran ~8 min
  (build was fast — slim base, most deps as binaries; only sf/spdep/Voyager geospatial
  compiles) then self-terminated. **≈\$0.04.** Confirmed TERMINATED; zero orphans.
- **Re-validation Batch run** `5390e911…`: ~46 s process_medium compute. **≈\$0.02.**
- **Total slim + re-validation spend: ≈\$0.06.** Well under the ~\$4 cap.
