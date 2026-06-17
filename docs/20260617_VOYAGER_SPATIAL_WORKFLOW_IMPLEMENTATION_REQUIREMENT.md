# Voyager Spatial Workflow — Implementation Requirement

**Date:** 2026-06-17
**For:** engineering / bioc-fix workstream
**Companion docs:**
- `docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md` (sibling spec; same conventions)
- `docs/20260616_SINGLE_CELL_DESIGN_REFERENCE_PACKET.md` (schema, phases, gates, pitfalls)
- `docs/20260616_SC_TUTORIAL_DEMO_DESIGN_REQUIREMENT.md` (the eventual D04 spatial demo will consume this workflow)

This document is the **engineering contract** for building one new spatial transcriptomics workflow that composes the existing (broken) Voyager + SpatialFeatureExperiment + VisiumIO Bioconductor stack into an end-to-end Visium ESDA pipeline. It also captures the **upstream container fix** that unblocks all four spatial workflows currently sitting at `exec_error`.

---

## Decisions locked

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Compose `nf-core/spatialvi` (id 12783) as sub-workflow or roll our own Space Ranger entrypoint? | **Sub-workflow call** to `nf-core/spatialvi` | upstream sync; nf-core handles Space Ranger output parsing + per-sample loading; we add the ESDA layer on top |
| 2 | Should this workflow re-implement Visium import or chain into existing `VisiumIO` (id 12616)? | **Chain into VisiumIO** once its container is fixed (see §0.1) | one canonical Visium import path across our spatial stack; fix once benefits four workflows |
| 3 | Output container: SFE or SpatialExperiment? | **`SpatialFeatureExperiment` (SFE)** | Voyager native; carries spatial neighborhood graph; sf-geometry-aware; downstream tooling (Banksy id 13079, regionalst id 12187) also expects SFE |
| 4 | Chained downstream visualization | **iSEE (id 11653)** for interactive exploration; per-statistic spatial PDF panel produced inline | iSEE supports SFE; no spatial-specific Shiny tool in our tested green set today |
| 5 | Acceptance dataset | **10X Visium Human Breast Cancer Block A Section 1** (public, ~4K spots, FFPE) | public, fixed-content, exactly matches Voyager's published vignette so we can verify expected Moran's I rankings |

## 0.1 Upstream P0 container fix (decision #2 dependency)

The Voyager workflow (id 12618) is `exec_error` because the canonical `bioc-domain-transcriptomics:3.20` ECR image is missing the `Voyager` R package. Same image is shared by `SpatialFeatureExperiment` (12434), `VisiumIO` (12616), `SpatialExperiment` (12433), `tidySpatialExperiment` (12537). All five are `exec_error` for the same upstream reason. **Fixing the container fixes all five.**

| Phase | Action | When | Owner |
|---|---|---|---|
| P0a | Add to `bioc-domain-transcriptomics:3.20` image: `Voyager`, `SpatialFeatureExperiment`, `SpatialExperiment`, `VisiumIO`, `SFEData`, `tidySpatialExperiment`, `sf`, `spdep`, `pheatmap` | this sprint | bioc-fix |
| P0b | Push new tag `:3.20-voyager` to ECR | this sprint | bioc-fix |
| P0c | Re-run the 5 affected workflows; expect `exec_error → ok_warnings` | this sprint | bioc-fix |
| P0d | (Optional) Tag the 5 as "spatial-stack" in DB so future chaining can group them | 2026 Q3 | engineering |

Once P0 is green, this workflow can be built and acceptance-tested.

---

## Spec — `visium_voyager_spatial_esda`

### Identity
- **Workflow ID to assign:** 14438
- **Domain:** `single_cell` (Bioconductor's convention for spatial transcriptomics)
- **Format:** `nextflow_nf`
- **Source:** `custom_composer` (sub-workflow include of `nf-core/spatialvi` id 12783 + composer of VisiumIO + Voyager + iSEE)
- **Docker image:** `bioconductor/scrnaseq-standard:v1` is reused for the Scanpy parts; the Voyager process uses `biomate/bioc-spatial:v1` — `bioc-domain-transcriptomics:3.20-voyager` (per §0.1) plus `procps`
- **Compute tier:** T2 CPU 16 vCPU / 64 GB Balanced
  - **Rationale:** Voyager's MULTISPATI PCA is memory-bound at ~12 GB for 4K spots × 18K features; Moran's I + Gi* are CPU-parallel but not GPU-suited. No CUDA path exists in `spdep`/`sf`. Standard Bioc spatial tier.

### Inputs (`params_schema.data_inputs[]`)

| name | type | optional | description |
|---|---|---|---|
| `spaceranger_dir` | `directory` | false | 10X Space Ranger output dir (must contain `outs/spatial/`, `outs/filtered_feature_bc_matrix/`, `outs/raw_feature_bc_matrix/`). Multi-sample supported via samplesheet. |
| `samplesheet.csv` | `csv` | false | nf-core format adapted for Visium: `sample, spaceranger_dir, condition` (+ optional `patient`) |
| `tissue_image` | `image` | true | If absent, falls back to `spatial/tissue_lowres_image.png` from Space Ranger output |

### Params (`params_schema.param_inputs[]`)

| name | type | default | range | description |
|---|---|---|---|---|
| `species` | `enum` | `human` | `human` \| `mouse` | drives QC defaults |
| `min_features_per_spot` | `int` | 200 | 50–1000 | spot QC |
| `max_pct_mito` | `float` | 30 | 5–50 | spot-level mito cutoff (typically higher than scRNA because spots contain multiple cells) |
| `n_hvgs` | `int` | 2000 | 500–5000 | for MULTISPATI PCA |
| `cluster_n_clusters` | `int` | 8 | 3–30 | k for spot clustering pre-ESDA |
| `graph_type` | `enum` | `visium` | `visium` \| `knn` \| `triangulation` | spatial neighborhood graph |
| `univariate_stats` | `multi_enum` | `["moran", "localG"]` | `moran, localG, geary, lee_l, localmoran` | univariate spatial statistics |
| `bivariate_top_n_genes` | `int` | 50 | 10–500 | for Lee's L bivariate analysis |
| `multispati_n_components` | `int` | 10 | 3–30 | MULTISPATI PCA dims |
| `swap_rownames` | `string` | `symbol` | column-name | rowData column for human-readable feature IDs |

### Steps (`step_metadata[]`)

```json
[
  {"step": "Validate samplesheet + locate Space Ranger output dirs",
   "phase": "Input & Preparation",
   "outputs": [], "visualizations": [], "qc": []},

  {"step": "Sub-workflow call: nf-core/spatialvi (id 12783) — Space Ranger → SpatialExperiment",
   "phase": "Core Analysis",
   "subworkflow_call": {"workflow_id": 12783,
                        "include_path": "subworkflows/nf-core/spatialvi/main"},
   "outputs": [{"file":"spe.rds","kind":"object"},
               {"file":"multiqc_report.html","kind":"report"}],
   "visualizations": [{"title":"Spatial QC summary","src":"multiqc_report.html","kind":"html"}],
   "qc": [{"metric":"n_spots_in_tissue","threshold":500,"direction":"gte","gate_action":"halt"},
          {"metric":"median_umi_per_spot","threshold":500,"direction":"gte","gate_action":"halt"}]},

  {"step": "Convert SpatialExperiment → SpatialFeatureExperiment (SFE)",
   "phase": "Input & Preparation",
   "outputs": [{"file":"sfe.rds","kind":"object"}],
   "visualizations": [], "qc": []},

  {"step": "Per-spot QC + normalization + HVG selection",
   "phase": "QC & Filtering",
   "outputs": [{"file":"sfe_normalized.rds","kind":"object"},
               {"file":"qc_metrics.csv","kind":"table"}],
   "visualizations": [{"title":"Spot QC violins (n_features, n_counts, pct_mito)",
                       "src":"qc_violins.png","kind":"image"},
                      {"title":"H&E tissue with QC-pass spot overlay",
                       "src":"qc_tissue_overlay.png","kind":"image"}],
   "qc": [{"metric":"spots_post_qc","threshold":500,"direction":"gte","gate_action":"halt"},
          {"metric":"median_genes_per_spot_post_qc","threshold":1000,"direction":"gte","gate_action":"advisory"}]},

  {"step": "Construct spatial neighborhood graph (findVisiumGraph / k-NN / triangulation)",
   "phase": "Input & Preparation",
   "outputs": [{"file":"sfe_with_graph.rds","kind":"object"}],
   "visualizations": [{"title":"Spatial graph overlay","src":"spatial_graph.png","kind":"image"}],
   "qc": [{"metric":"n_graph_edges","threshold":1000,"direction":"gte","gate_action":"halt"}]},

  {"step": "Univariate spatial statistics (Moran's I, Geary's C, Getis-Ord Gi*) via runUnivariate",
   "phase": "Core Analysis",
   "outputs": [{"file":"univariate_moran.csv","kind":"table"},
               {"file":"univariate_localG.csv","kind":"table"}],
   "visualizations": [{"title":"Top-20 Moran's I genes (spatial autocorrelation)",
                       "src":"top_moran_genes.png","kind":"image"},
                      {"title":"Local Getis-Ord hotspot map",
                       "src":"local_hotspots.png","kind":"image"}],
   "qc": [{"metric":"n_significant_moran_genes","threshold":50,"direction":"gte","gate_action":"advisory"}]},

  {"step": "Bivariate spatial correlation (Lee's L) for top HVGs via calculateBivariate",
   "phase": "Core Analysis",
   "outputs": [{"file":"lees_L_matrix.csv","kind":"table"}],
   "visualizations": [{"title":"Lee's L gene-gene spatial correlation heatmap",
                       "src":"lees_L_heatmap.png","kind":"image"}],
   "qc": []},

  {"step": "Multivariate analysis — MULTISPATI PCA via runMultivariate",
   "phase": "Core Analysis",
   "outputs": [{"file":"multispati_embedding.csv","kind":"table"},
               {"file":"sfe_with_multispati.rds","kind":"object"}],
   "visualizations": [{"title":"MULTISPATI eigenvalue scree","src":"multispati_eigen.png","kind":"image"},
                      {"title":"MULTISPATI PC1+PC2 spatial map","src":"multispati_pc12_spatial.png","kind":"image"}],
   "qc": [{"metric":"multispati_variance_explained_pc1to3","threshold":0.25,"direction":"gte","gate_action":"advisory"}]},

  {"step": "Spot clustering on MULTISPATI embedding + cluster-stratified ESDA",
   "phase": "Annotation & Interpretation",
   "outputs": [{"file":"spot_clusters.csv","kind":"table"},
               {"file":"per_cluster_moran.csv","kind":"table"}],
   "visualizations": [{"title":"Spatial cluster map","src":"spatial_clusters.png","kind":"image"},
                      {"title":"Per-cluster top Moran's I genes",
                       "src":"per_cluster_top_genes.png","kind":"image"}],
   "qc": [{"metric":"silhouette_per_cluster","threshold":0.0,"direction":"gte","gate_action":"advisory"}]},

  {"step": "Methods report + chain to iSEE interactive explorer",
   "phase": "Output & Reporting",
   "downstream_workflow_calls": [
     {"workflow_id": 11653, "name": "iSEE",
      "inputs": {"sce_rds": "sfe_with_multispati.rds"},
      "produces": ["isee_app.tar.gz"]}],
   "outputs": [{"file":"methods_report.html","kind":"report"},
               {"file":"voyager_results.tar.gz","kind":"archive"}],
   "visualizations": [], "qc": []}
]
```

### Output contract
- `sfe_with_multispati.rds` — required (final annotated SFE with QC + graph + univariate + multivariate)
- `univariate_moran.csv`, `univariate_localG.csv` — required (per-gene + per-spot statistics)
- `lees_L_matrix.csv`, `multispati_embedding.csv`, `spot_clusters.csv`, `per_cluster_moran.csv` — required
- `qc_metrics.csv` — required
- `methods_report.html` — required (cites Moreno-Pachter 2024 Nature Methods + Righelli 2022 SpatialExperiment + 10X Visium platform paper)
- `isee_app.tar.gz` (from chained id 11653) — recommended

### Auto-loop QC gates with remediation

| Gate | Direction | Threshold | Action | Remediation |
|---|---|---|---|---|
| `n_spots_in_tissue` | `gte` | 500 | halt | check Space Ranger `tissue_positions.csv` integrity; if multiple sections, suggest splitting samplesheet |
| `median_umi_per_spot` | `gte` | 500 | halt | data quality too low — surface to user; suggest re-checking sample depth |
| `spots_post_qc` | `gte` | 500 | halt | relax `min_features_per_spot` 200 → 100; relax `max_pct_mito` 30 → 50 |
| `median_genes_per_spot_post_qc` | `gte` | 1000 | advisory | surface to user |
| `n_graph_edges` | `gte` | 1000 | halt | switch `graph_type=knn` if Visium hex grid is malformed |
| `n_significant_moran_genes` | `gte` | 50 | advisory | likely uniform expression; tissue is poorly stratified or HVG threshold too strict |
| `multispati_variance_explained_pc1to3` | `gte` | 0.25 | advisory | weak spatial signal; suggest more HVGs or alternate graph |
| `silhouette_per_cluster` | `gte` | 0.0 | advisory | bump `cluster_n_clusters` lower (over-segmentation common in homogeneous tissue) |

### Acceptance criteria

| Test | Dataset | Tier | Wall time | Cost | Pass condition |
|---|---|---|---|---|---|
| Smoke | 10X Visium Human Breast Cancer Block A Section 1 (public, ~4K spots, FFPE) | T2 CPU | ~25 min | ~$1 | Voyager vignette's documented top Moran's I genes (IGHG1, IGHG3, IGKC, COL1A1, MGP) recovered in top-20; MULTISPATI PC1 separates tumor vs stroma compartments; spatial cluster map shows 4-8 stable clusters with silhouette ≥ 0.1 |
| Real | Maynard 2021 DLPFC (Sample 151673; well-studied reference dataset) | T2 CPU | ~30 min | ~$1.20 | The 6 cortical layers recovered as clusters (SNAP25, MOBP, MBP layer-specific genes top-ranked) |
| Auto-loop | low-quality forced fixture (only 300 spots passing QC) | T2 | — | — | `spots_post_qc` halts; remediation card surfaces; re-run completes |
| Chain | Voyager → iSEE | end-to-end | ~30 min | ~$1.30 | `isee_app.tar.gz` opens; SFE loads in iSEE with spatial coords + clusters visible |

### Known pitfalls
- Voyager requires `Voyager` R package — **upstream P0 container fix is a hard blocker** (see §0.1)
- `findVisiumGraph` assumes the standard 10X Visium hex grid; for custom or partial slides, `graph_type=knn` is safer
- `MULTISPATI PCA` is memory-bound — ~12 GB for 4K spots × 18K features; lineage-split is not applicable; recommend HVG-restrict first
- `tissue_lowres_image.png` from Space Ranger may be mirrored relative to spot coordinates; the workflow handles via `mirrorImg(sfe)` but custom images may need a flip flag
- LIANA+ / cell-cell communication workflows are **NOT** chained from this spec — spatial cell-cell communication requires Squidpy/COMMOT not LIANA+ (different design; future workflow)
- Voyager v1.12+ requires Bioconductor 3.20; older Bioc 3.18 base images will fail at install — pin the container tag

---

## Cross-spec engineering checklist

| # | Item | Owner | Priority |
|---|---|---|---|
| 1 | **P0 container fix** — add Voyager + SFE + VisiumIO + SpatialExperiment + tidySpatialExperiment + sf + spdep to `bioc-domain-transcriptomics:3.20`; tag `:3.20-voyager`; push to ECR | bioc-fix | **P0 (blocks everything below)** |
| 2 | Re-run workflows 12618, 12434, 12433, 12616, 12537 against new container; expect `exec_error → ok_warnings` | bioc-fix | P0 |
| 3 | Assign workflow ID 14438 in DB | engineering | P0 |
| 4 | Wire `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf` (or reuse the existing `bioconductor/voyager/main.nf` as a starting point) | engineering | P0 |
| 5 | Stage acceptance datasets to S3: 10X Visium Breast Cancer Block A Section 1; Maynard DLPFC 151673 | engineering | P0 |
| 6 | Index 14438 in `workflows` table with full `step_metadata`, `params_schema`, `input_types`, `output_types`; emit `workflow_chains` row for the chained Voyager → iSEE call | engineering | P0 |
| 7 | Add per-spec auto-loop gates to `qc_trace_monitor.py` | engineering | P0 |
| 8 | Add routing few-shots to `frontend/server/galaxy-assistant.ts` under the `single_cell` block | engineering | P0 |
| 9 | Tag iSEE (11653) as chainable downstream from 14438 (same affordance the 3 sc workflows use) | engineering | P0 |
| 10 | Smoke-test on CE `biomate-nextflow-ce-v2` until `real_exec_status='ok'` on both acceptance datasets | engineering | P0 |
| 11 | (Stretch) Re-run downstream workflows 13079 (`banksy_spatial_integration_with_harmony`) and 12187 (`regionalst`) against the fixed container; many of those `fixture_failed` / `exec_error` may resolve automatically once SFE is loadable | bioc-fix | P1 |

## Acceptance gate

Workflow 14438 must reach `real_exec_status='ok'` (or `ok_warnings`) on **both** acceptance tests (Visium Breast Cancer + Maynard DLPFC) before any spatial tutorial demo (a future D04 in Doc B) can be recorded. The Voyager-vignette ESDA results (top Moran's I = immunoglobulin + collagen genes for breast; top genes = layer-specific markers for DLPFC) are the scientific-correctness check — not just "the workflow returned outputs."

---

## Relationship to other docs

- **Doc A** (`docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md`) builds 3 scRNA-seq workflows (14435/14436/14437) for the Merck immune-oncology demo arc; this Voyager doc adds a 4th workflow (14438) for spatial transcriptomics on a separate thematic arc.
- **Doc B** (`docs/20260616_SC_TUTORIAL_DEMO_DESIGN_REQUIREMENT.md`) covers demos D01–D03 (the 3 sc workflows); a future **D04 spatial demo** would consume this workflow once it lands. Recommend writing D04 as a separate addendum to Doc B once 14438 reaches `real_exec_status='ok'`.
- **`docs/20260616_SINGLE_CELL_DESIGN_REFERENCE_PACKET.md`** §6 "Known pitfalls" applies unchanged (parameters: vs params:, procps, container tag flakes).

## Open questions

1. Is the 10X Visium Breast Cancer dataset preferable to Maynard DLPFC as smoke test, or should we use both? My recommendation: both — Breast Cancer for tumour-microenvironment relevance to Merck IO, DLPFC for scientific-correctness anchor (it's the published gold standard).
2. Should this workflow eventually chain into Banksy (id 13079, `fixture_failed`) for joint spatial integration across multiple samples? Recommend **yes, but after** Banksy reaches green — track as P1.
3. Should we add `xenLite` (id 12634) as an alternative Xenium-format entrypoint? Recommend **separate workflow** — Xenium has different geometry (transcript-level not spot-level) and warrants its own composer.
4. Sub-workflow call to `nf-core/spatialvi` (id 12783) is currently `null` exec_status (untested upstream). If nf-core/spatialvi turns out to be broken, fallback is to directly call VisiumIO. Track during implementation.
