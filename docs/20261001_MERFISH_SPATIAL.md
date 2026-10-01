# MERFISH Spatial Analysis — stub → real squidpy pipeline

**Date:** 2026-10-01
**Author:** Yaoyun Zhang
**Companion to:** `docs/20260928_DOMAIN_VALIDATION_UNTESTED.md` (Spatial section)
**Workflow:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/merfish_spatial_analysis/main.nf`

## Headline

The `merfish_spatial_analysis` workflow — the only MERFISH / imaging-based-spatial
entry, previously an **honest-failing stub** (`sys.exit(1)` "no real implementation")
— is now a **minimal-correct REAL squidpy spatial-statistics pipeline**. Chosen path
**(A)**: re-wire to real tooling already present in an existing BioMate image; **no
image build needed**. Commit `586e89f05`.

## Scope assessment (done before building)

- **Stub located:** `single_cell/merfish_spatial_analysis/main.nf`. Body generated
  four output files from an `RNG`/zeroed template and then `sys.exit(1)` to refuse
  fabrication. Declared outputs: `spatial_qc.json`, `spatial_domains.csv`,
  `spatially_variable_genes.csv`, `spatial_report.txt`, `versions.yml`.
- **Container it references:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86`
  — **confirmed to exist** in ECR (tag `x86`, 3.4 GB, pushed 2026-05-21).
- **Does an existing image have MERFISH-ready tooling?** YES. `biomni-tools:x86` is
  built from `Biomni/biomni_galaxy/docker/Dockerfile.x86-comprehensive`, which installs
  **squidpy (1.7.x), scanpy (1.11.x), anndata (0.12.x), cellpose** into its `biotools`
  conda env (confirmed in the Dockerfile LAYER 24 + the X86 working-tools inventory doc).
- **Decision — path (A):** squidpy ships a built-in MERFISH dataset
  (`squidpy.datasets.merfish()` — Moffitt-2018 hypothalamus atlas, 73,655 cells × 161
  genes, with `.obsm['spatial3d']` coordinates + `Cell_class` / `Bregma` obs), so a real
  spatial-statistics pipeline runs with **zero external input**. This is far cleaner than
  re-implementing raw-image Cellpose segmentation + transcript decoding (which the stub
  comment scoped) — segmentation is upstream of the cell×gene matrix; the scientifically
  load-bearing, benchmarkable spatial analysis is the matrix→SVG→domains step, which is
  exactly what squidpy provides. (Note: `bioc-domain-spatial:3.20-deps` also exists in ECR
  now, but it is the R/Voyager stack for `visium_voyager_spatial_esda`, not the Python
  squidpy path appropriate for a MERFISH AnnData.)

## What was built / re-wired

Replaced the stub `script:` body with a real pipeline (same output channel names, so
nothing downstream breaks; added an optional `plots` channel for PNGs):

1. **Load** AnnData — user `--input_h5ad` if supplied, else `squidpy.datasets.merfish()`.
2. **Coords** — derive 2D `.obsm['spatial']` from `spatial3d`; auto-select the densest
   `Bregma` slice (a true 2D tissue section, ~5-6k cells → keeps compute tractable).
3. **QC + normalize** — library-size normalize + log1p (counts/genes per cell recorded).
4. **Spatial graph** — `squidpy.gr.spatial_neighbors(coord_type="generic", delaunay=True)`
   (the correct neighbor model for imaging-based platforms, vs `grid` for Visium).
5. **Spatially variable genes** — `squidpy.gr.spatial_autocorr(mode="moran", n_perms=100)`
   → real Moran's I + permutation p-values + BH-FDR → `spatially_variable_genes.csv`.
6. **Spatial domains** — `squidpy.gr.nhood_enrichment(cluster_key="Cell_class")` → per
   cell-type self-colocalization z + top heterotypic partner → `spatial_domains.csv`.
7. **Plots** — top-SVG spatial scatter + Moran's I ranking bar (PNG).
8. **Integrity** — if squidpy/scanpy/anndata are not importable, or the dataset cannot be
   obtained, the process exits **non-zero** with a clear message. **No fabricated output.**

### Key engineering detail (env resolution)

`biomni-tools:x86` installs squidpy into the **`biotools` conda env** and only activates
it via the image ENTRYPOINT. Nextflow/AWS Batch runs `.command.sh` through `/bin/bash`
and does **not** go through that entrypoint, so a bare `python3` would resolve to the base
interpreter without squidpy. The script therefore resolves the env python explicitly
(`/opt/conda/envs/biotools/bin/python`, falling back to `python3`). This is the same class
of gotcha that bit single-cell dropletutils (container/env mismatch).

## Commit

- **`586e89f05`** — `feat(spatial): real squidpy MERFISH pipeline (was honest-failing stub)`
  (`main.nf` only; Nextflow `-preview` DAG compiles exit 0; Python body `ast.parse` OK).

## DB registration

The workflow has two rows in the full `galaxy_ai_tools.db` (~328 MB, gitignored, lives on
dev + S3). The executable row is **id 14608**
(`nextflow_nfcore/subworkflows/single_cell/merfish_spatial_analysis/main.nf`), which still
cached the OLD stub body in `workflow_json` and had an **empty `docker_image`**. Updated
in place (count unchanged — 0 inserts, FTS auto-maintained by the `workflows_au` trigger):
- `workflow_json` → the new squidpy `.nf` body
- `docker_image` → `…/biomate/biomni-tools:x86`
- `description` / `tags` / `input_types` / `output_types` / `params_schema` → squidpy-accurate
- `executable=1`
Sibling row id 12910 (same workflow, non-prefixed filename) description/tags aligned too.
FTS verified: `workflows_fts MATCH 'squidpy'` returns both rows.

## Sync + validation

<!-- FILLED AFTER RUN -->
_Sync: pending (serialized behind concurrent agents on the sync lock)._
_Validation Batch run: pending._

## Spend + hygiene

- **No EC2 launched** (path A needed no image build).
- Batch spend: _pending validation run_ (one short process_medium task on the existing
  queue; budget cap ~$6, expected << $1).
- Zero orphans.
