# Spatial Domain Validation — Voyager Visium ESDA

**Date:** 2026-09-28
**Author:** Yaoyun Zhang
**Goal:** Make the spatial domain runnable + validated. The
`visium_voyager_spatial_esda` workflow referenced a spatial image that did
not exist. Build `bioc-domain-spatial:3.20-deps`, push to the (pre-created)
ECR repo, wire the workflow to it, and validate on real 10X Visium data via
the production AWS Batch path.

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

<!-- FILL after coordinator dispatch: run id, Batch job id, status, S3 outdir, top Moran's I gene -->

## 4. Cost + cleanup

- **Build:** two spot c5.4xlarge boxes; the first ran ~few min before the
  describe-gate false-fail + self-terminate; the winning box built + pushed +
  self-terminated in ~10 min. Spot c5.4xlarge ~\$0.28/hr → build spend ≈ **<\$0.15**.
- **Both build boxes confirmed terminated; zero orphan c5.4xlarge.**
- Validation Batch spend: capped ~\$4 (owned by coordinator).
