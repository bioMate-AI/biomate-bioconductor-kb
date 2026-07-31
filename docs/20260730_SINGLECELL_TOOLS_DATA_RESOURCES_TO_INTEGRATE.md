# Single-Cell + DL/FM — Tools, Data & Resources to Integrate (actionable registry)

**Date:** 2026-07-30
**Builds on:** `20260730_SCIENCE_2026_SINGLECELL_3DGENOME_NOTES_AND_INTEGRATION.md` (the team's
survey of the *Science* 23-Jul-2026 single-cell + 3D-genome issue) and the multi-omics
platform (`MULTIOMICS_PLATFORM_MASTER.md`). Turns the survey's *conceptual* targets into
**concrete resources with access points + how BioMate integrates each + priority.**
**Honesty:** every repo/accession below is from a real search hit; verify the exact
data-access terms before download. Code-availability of the newest FMs is flagged.

---

## 0. The convergence worth acting on first
Three threads point at the SAME next experiment:
1. **DL track** ("does deep learning actually help multi-omics integration?").
2. **The mosaic / missing-modality open regime** (our staged partial-overlap data).
3. **MultiVI** (scvi-tools) — a DL model that **natively handles cells/samples missing a
   modality.** It is *built* for the mosaic case.

→ **First integration = MultiVI + totalVI (scvi-tools) vs the 7 classical methods, on
matched cohorts, measuring the n-vs-performance crossover AND missing-modality robustness.**
This is the one move that serves the DL ask, the science bet, and reuses the apparatus.
Context that de-risks the *finding*: benchmarks already report FMs **losing to simple
baselines** ("*one PCA still rules them all*", arXiv 2410.13956; VCBench) — so a rigorous
"classical matches/beats DL below N; here's the crossover" result is credible and useful.

---

## 1. DL / deep-learning integration methods to ADD (the DL track)
| Tool | What | Access | BioMate integration | Priority |
|---|---|---|---|---|
| **MultiVI** | VAE, joint RNA+ATAC(+protein), **handles missing modalities** | scvi-tools (docs.scvi-tools.org/en/stable/user_guide/models/multivi) | **new `sc-scvi` GPU container** (python+torch+scvi-tools); workflow like the R methods but GPU Batch | ⭐ **P0** (mosaic regime) |
| **totalVI** | VAE for CITE-seq (RNA+ADT), cross-modal imputation | scvi-tools | same container | ⭐ P0 |
| **GLUE** (scglue) | graph-linked VAE, **diagonal/unpaired** integration | scglue (pip) | same container | P1 |
| **StabMap** | R/Bioc mosaic embedding (most efficient) | Bioconductor `StabMap` | ✅ reuse R container (drafted; needs *mosaic* data) | P1 |
| **Seurat-WNN** | R vertical integration (paired) | Seurat v5 | reuse R container | P2 |

## 2. Foundation models to BENCHMARK / FINE-TUNE (the FM-vs-classical study)
| FM | Scope | Access | Note |
|---|---|---|---|
| **scGPT** | GPT, sc multi-omics; annotation/integration/perturbation | `bowang-lab/scGPT` (Nat Methods 2024, weights released) | most-used; fine-tunable |
| **scMamba** (2026) | **multi-omics** (RNA+ATAC+protein), Mamba2, no HVG selection, contrastive | arXiv **2506.20697** — code/weights **not confirmed public** (verify) | most directly on-topic for OUR multi-omics integration |
| **Geneformer** | BERT-style, ~95M cells | `ctheodoris/Geneformer` (weights on HuggingFace) | classic baseline; we already have `SLE_GENEFORMER_ADAPTATION_SURVEY` |
| **UCE** | zero-shot universal cell embedding | `snap-stanford/UCE` (weights released) | zero-shot embedding baseline |
| **scFoundation** | 100M-param, 20k genes | (Nat Methods 2024) | large; inference-heavy |
| **SCARF** | RNA+ATAC FM | bioRxiv 2025.04.07.647689 | RNA+ATAC specialist |
> **FM caveat (honest, and it IS the story):** VCBench (bioRxiv 2026.06.18.733146) and
> "one PCA still rules them all" report FMs frequently **losing to linear/NN baselines** on
> integration/perturbation. So the FM integration = evaluate *whether they beat classical*,
> not assume they do.

## 3. Data / atlases to integrate (references + benchmark cohorts)
| Resource | What | Access | Use in BioMate |
|---|---|---|---|
| **CELLxGENE Census** | **30M+** human cells, SOMA/TileDB, versioned | `cellxgene-census` API (chanzuckerberg) | primary sc data source; query/slice cohorts on demand |
| **snm3C 3D-genome + methylation atlas** | 86,689 nuclei · 16 tissues · 35/206 types; **methylation = batch-robust** | bioRxiv **2025.03.23.644697**, PMID 40196612 (Ecker/Salk) | batch-robust **methylation reference** (addresses SLE batch confound); variant→cell-type |
| **SingleCellMultiModal** | one-command CITE-seq/multiome + labels | Bioconductor/ExperimentHub | staged de-risk data (CITE-seq already used) |
| **scMultiBench datasets** | 64 real + 22 sim sc multimodal | `PYangLab/scMultiBench` | the sc benchmark cohorts (vertical/mosaic/diagonal/cross) |
| **GAGE-seq (AD)** & **heart-failure multiomics** | joint 3D-genome+expr cohorts | Science adz1652 / medRxiv 2025.05.08.25327176 | method templates + variant→enhancer→gene cohorts |

## 4. 3D-genome / methylation TOOLS (the survey's autoimmune target-ID backbone)
| Tool | What | Access | Integration |
|---|---|---|---|
| **GAGE-seq** | scHiC + scRNA co-assay processing/analysis | `ma-compbio/GAGE-seq` (CMU Ma lab) | pipeline for joint 3D-genome+expr data |
| **Hicformer** | transformer: DNA seq + folding + 3D contacts → cell-type gene activity | Ma lab (with GAGE-seq; verify exact repo) | candidate 3D-genome model for the autoimmune backbone |
| **snm3C-seq processing** | methyl-3C (methylation + 3D contacts) | Ecker lab tooling | process the atlas / new immune data |
| **GWAS→enhancer→causal-gene** recipe | variant → cell-type regulatory program → target | from Papers 3/4 | autoimmune **target-ID backbone** (stronger than expression-only) |

## 5. Ecosystems / resources (the plumbing)
- **scverse**: scanpy, anndata, **muon/MuData** (multimodal container), scvi-tools — the Python sc stack; MuData is the natural multi-omics container (maps to our interface).
- **scvi-hub** (Nat Methods 2025): repository of **pretrained** scvi models — run integration on a query without retraining (fast, cheap).
- **Bioconductor ExperimentHub / SingleCellMultiModal**: R data access.
- **OmicsML/awesome-foundation-model-single-cell-papers**: curated FM index (track new releases).
- **Benchmarks to position against**: scMultiBench (sc method benchmark), **VCBench** & "one PCA rules them all" (FM-vs-baseline), scTranslation (modality translation).

---

## 6. Recommended integration order (cheap → decisive → ambitious)
1. **P0 — `sc-scvi` GPU container + MultiVI/totalVI** → benchmark vs the 7 classical methods
   on our cohorts + CITE-seq → the **n-vs-performance crossover** and **missing-modality
   robustness** (MultiVI natively handles missingness) → the honest "does DL help" finding.
2. **P1 — CELLxGENE Census + scMultiBench datasets** wired as data sources; StabMap on a real
   *mosaic* set (fixes the earlier CITE-seq/vertical mismatch).
3. **P2 — FM fine-tuning** (scGPT/Geneformer, weights released) on a task, evaluated against
   the classical + VAE baselines — the FM-vs-classical head-to-head (expect FMs to *not*
   dominate; that's the publishable angle).
4. **Autoimmune backbone (parallel, from the survey):** snm3C methylation atlas as a
   batch-robust reference + GWAS→enhancer→gene recipe → target-ID/stratification.

**Honest gates:** P0 needs a GPU container (real infra/cost lift, but BioMate already runs
GPU Batch for ADMET/DMPNN/cryoEM). FM code/weights: scGPT/Geneformer/UCE released; **scMamba
code not confirmed** — verify before committing. The "DL doesn't beat classical" finding is
the *hoped* result, not guaranteed (honest 50/50, same as the mosaic/predictor bets).

**Change log →** append to `MULTIOMICS_PLATFORM_MASTER.md`. Related: [[project_multiomics_benchmark]].
