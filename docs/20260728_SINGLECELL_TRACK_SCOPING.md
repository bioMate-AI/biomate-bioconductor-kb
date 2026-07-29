# Single-Cell Multi-Omics Track — Scoping (Path A: unify bulk + single-cell SOTA)

**Date:** 2026-07-28
**Goal:** extend BioMate's multi-omics platform to the single-cell SOTA (scMultiBench 2025
winners), so one interface spans bulk (Cantini) AND single-cell (scMultiBench) — the
"unify two frozen benchmark worlds" tool advantage.

---

## 1. Container: which methods are R (reuse) vs Python (new container)

| Method | Ecosystem | scMultiBench role | Container |
|---|---|---|---|
| **StabMap** | **R / Bioconductor** (`SydneyBioX/MarioniLab`) | top **mosaic** method, most efficient | ✅ **reuse existing R bioc container** |
| **Seurat-WNN** | **R** (Seurat) | leading **vertical** integration | ✅ reuse R container |
| **totalVI** | **Python** (scvi-tools/torch) | strong CITE-seq cross/imputation | ❌ needs new Python/scvi container |
| **GLUE** | **Python** (scglue/torch) | **diagonal** (unpaired) integration | ❌ needs new Python container |

**Recommendation: two-phase.**
- **Phase 1 (cheap, reuses infra):** StabMap + Seurat-WNN in the existing
  `bioc-domain-general` R container. No new container to build.
- **Phase 2 (real lift):** a new `sc-scvi` Python container (python3.11 + torch +
  scanpy + anndata + scvi-tools + scglue) for totalVI + GLUE. Mirror the MOFA2
  dedicated-container pattern (`aws_infrastructure/configs/Dockerfile.*`).

⚠️ **StabMap install caveat:** StabMap is Bioconductor with ~44 deps (SingleCellExperiment,
scran, etc.). BiocManager in this container hits the container-binaries mirror that
returns 504 (the MOFA2 lesson). Install via explicit Bioc **source** repos + p3m CRAN
binary, as MOFA2/MCIA do. If the 44-dep source build is too heavy/slow at runtime, StabMap
may warrant a small **dedicated baked container** (`:3.20-stabmap`) like MOFA2 got. The
DRAFT workflow installs at runtime; escalate to a baked image if runtime install is slow.

## 2. Input interface — .h5ad vs the universal CSV

Single-cell multimodal data is normally AnnData/MuData (`.h5ad`/`.h5mu`) or a
SingleCellExperiment. Two options:
- **(a) Reuse the universal CSV interface** — StabMap's `assay_list` is literally *a named
  list of matrices, features × cells* — identical shape to BioMate's per-modality
  features×samples matrices (cells = "samples"). So for **modest** datasets, StabMap runs
  on the existing interface with ZERO new plumbing. This is the fastest E2E path.
- **(b) Accept `.h5ad` directly** — the executor already lists `.h5ad` as a data
  extension. Better for large datasets (sparse, 10⁴–10⁶ cells; CSV is wasteful) and for
  carrying modality/paradigm metadata. Phase-2 work.

**Paradigm note (which method for which shape):**
- **vertical** (same cells, ≥2 modalities): Seurat-WNN, StabMap.
- **mosaic** (different cells, partial-overlapping features): **StabMap's speciality** —
  needs the list-of-matrices with *unshared* features/cells; the CSV interface only
  exercises the shared/vertical case, so true mosaic needs `.h5ad` or an explicit
  topology (Phase 2).
- **diagonal** (unpaired): GLUE (Python).

## 3. Datasets — stage from Bioconductor (cleanest)

- **`SingleCellMultiModal`** (Bioconductor/ExperimentHub): one-command access to landmark
  multimodal sets — **CITE-seq** (RNA+ADT), **10x Multiome** (RNA+ATAC), scNMT, seqFISH —
  as `MultiAssayExperiment`, pre-processed. `SingleCellMultiModal::CITEseq(...)`.
- **SeuratData** `InstallData("pbmcMultiome")` for a 10x-multiome PBMC set.
- First to stage: a **CITE-seq PBMC** (RNA + ADT, paired) — small, vertical, has cell-type
  labels (ground truth for the metric harness, exactly like our bulk subtype labels).

## 4. Build sequence + E2E verification

1. **StabMap first** (R, reuse container, top mosaic method). DRAFT workflow written (see
   §5). E2E bar: run on a CITE-seq PBMC (RNA+ADT) via the universal interface → joint
   embedding → k-means into `n_clusters` → `stabmap_clusters.csv` → metric harness ARI/NMI
   vs cell-type labels, at matched k. Profile runtime/memory.
2. **Seurat-WNN second** (R). Vertical WNN graph → clusters.
3. **Phase 2:** build the Python `sc-scvi` container → totalVI, GLUE. Add `.h5ad` input +
   the mosaic/diagonal paradigms.
4. Reproduce a slice of scMultiBench on a canonical dataset to prove parity.

## 5. DRAFT workflow delivered

`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/stabmap_singlecell/main.nf`
— **DRAFT, untested.** Mirrors the intNMF template (universal CSV read, flatten,
sample/cell-intersect, `${params.n_clusters}`, versions.yml). StabMap-specific: explicit
Bioc-source install; `assay_list` = the per-modality matrices (features × cells);
`stab <- stabMap(assay_list, reference_list = names(assay_list), plot = FALSE)` → cells ×
dims embedding → `kmeans(stab, n_clusters)` → `stabmap_clusters.csv`. **Must be de-risked
on Batch** — the 44-dep Bioc install is the main risk; escalate to a baked container if slow.

Related: `docs/20260728_MULTIOMICS_FOUNDATION_ROADMAP.md` (§A single-cell inventory),
`docs/20260728_ADVANTAGE_AND_TWO_PATHS.md` (Path A).
