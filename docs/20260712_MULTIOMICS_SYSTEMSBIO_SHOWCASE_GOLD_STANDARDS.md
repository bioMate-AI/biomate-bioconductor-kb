# Deep-Orchestration Showcases — Multi-Omics & Systems Biology, with Gold Standards (Immune Domain)

**Date:** 2026-07-12
**Thesis:** The orchestration platform is a profitable product in its *deep* form — flexible multi-omics combination and systems-level analysis — because that is the capability point solutions (CANVAS, scFMs) structurally cannot provide. This doc lists four **immune-domain showcases with held-out gold standards** so the capability can be demonstrated credibly, not just asserted.

---

## Why deep orchestration is the sellable product (not a commodity)

- **Thin orchestration** (prompt → run one workflow) commoditizes: the workflows are open, and every agentic-bio platform is racing there (documented in Qi et al. 2026, *Brief Bioinform*).
- **Deep orchestration** — combine modalities, chain analyses, reconcile results, reason across them — is hard and is exactly what a single model cannot do. CANVAS is single-modality (H&E→spatial); scFMs are single-modality (RNA). The **combinatorial multi-omics + systems-biology design space is the defensible, payable core.**
- **Discipline (from the FM leaderboard lesson):** every showcase must beat the *simple baseline* (pseudobulk/Wilcoxon, linear models, single-tool default). The value is the orchestrated ensemble + verification, not a bigger model. Report the baseline alongside the result.

---

## Direction A — Flexible multi-omics combination

### A1. Immune cell deconvolution from bulk RNA-seq — gold standard: flow cytometry
- **Gold standard:** matched **flow cytometry** cell-type proportions. Canonical benchmark: Sturm et al. 2019 (*Bioinformatics*), which evaluated 7 methods over 9 cell types across ~1,800 samples, with 9 PBMC samples flow-validated as ground truth. Tooling: the `immunedeconv` R package (CIBERSORTx, EPIC, quanTIseq, TIMER, xCell, MCP-counter).
- **Orchestration showcase:** a single BioMate chain runs **all six deconvolution methods**, reconciles absolute-vs-relative score semantics (only EPIC/quanTIseq give true fractions), builds an ensemble, and validates against the flow gold standard. This demonstrates flexible combination + result reconciliation across tools — not runnable as any single method.
- **Why it showcases well:** applied, immuno-oncology-relevant, quantitative accuracy vs a hard readout, immediately credible to pharma/TME audiences.

### A2. Paired single-cell multi-omics integration (CITE-seq + Multiome) — gold standard: NeurIPS 2021 Open Problems
- **Gold standard:** the **NeurIPS 2021 Open Problems Multimodal Single-Cell Integration** benchmark — a purpose-built human **bone-marrow** dataset (12 donors, 4 sites) with **CITE-seq (RNA + surface protein)** and **Multiome (RNA + ATAC)**, expert cell-type annotations as ground truth, and held-out modality-prediction / matching / integration tasks with automated scoring.
- **Orchestration showcase:** chain multiple integration methods (Seurat WNN, totalVI, MOFA+, GLUE) across the RNA/protein/ATAC layers and score against the challenge metrics. Demonstrates true cross-modality integration on immune/hematopoietic cells.
- **Why it showcases well:** the dataset *is* immune (bone-marrow mononuclear cells), the ground truth is public and held-out, and it directly proves "flexible combination of multi-omics."

---

## Direction B — Systems biology research/application

### B1. Gene regulatory network inference on immune differentiation — gold standard: BEELINE
- **Gold standard:** **BEELINE** (Pratapa et al. 2020, *Nature Methods*) — curated Boolean ground-truth networks including **hematopoietic stem cell (HSC) differentiation**, plus synthetic/curated trajectories; metrics AUPRC and early-precision ratio (EPR) over 12 GRN algorithms.
- **Orchestration showcase:** run an ensemble of GRN methods (SCENIC, GENIE3, GRNBoost2, PIDC, SINCERITIES) on immune-differentiation single-cell data, reconcile into a consensus network, and benchmark against BEELINE's curated ground truth. Core systems-biology capability with a quantitative accuracy readout.
- **Immune anchor:** HSC → immune-lineage differentiation is the ground-truth network; extends naturally to T-cell/myeloid differentiation GRNs.

### B2. Single-cell perturbation response prediction — gold standard: NeurIPS 2023 Open Problems (OP3)
- **Gold standard:** the **NeurIPS 2023 Open Problems Single-Cell Perturbations** benchmark (OP3) — a novel **PBMC** dataset, **~144–146 LINCS/Connectivity-Map small-molecule compounds**, 3 healthy donors, 24 h treatment, with a held-out leaderboard and formal metrics for predicting cell-type-specific differential expression.
- **Orchestration showcase:** a systems-level chain predicting perturbation response, **explicitly benchmarked against the simple baseline** (pseudobulk + Wilcoxon won this competition — so the showcase's honesty is the point: orchestration + mechanism must match/beat it to earn its place).
- **Immune anchor:** PBMCs; direct read on immune-cell drug response — the systems-biology-for-immunopharmacology use case.

---

## How these ladder into the paying product

- A1 (deconvolution vs flow) and B2 (PBMC perturbation) are **immuno-pharmacology** showcases → the Series-A/B-biotech-at-IND-crunch buyer.
- A2 (bone-marrow multi-omics) and B1 (immune GRN) are **systems-immunology** showcases → academic/translational systems-biology labs and core facilities (the distribution flywheel).
- All four connect to the **type-I-IFN/STING franchise**: deconvolution + IFN-signature scoring, immune GRN around the IFN axis, and perturbation prediction for IFN/JAK modulators are the same capability aimed at the chosen vertical.

## Benchmark citations

- Sturm G, Finotello F, Petitprez F, et al. Comprehensive evaluation of transcriptome-based cell-type quantification methods for immuno-oncology. *Bioinformatics*. 2019;35(14):i436–i445. doi:10.1093/bioinformatics/btz363
- Luecken MD, et al. A sandbox for prediction and integration of DNA, RNA, and proteins in single cells (NeurIPS 2021 Multimodal Single-Cell Integration). *NeurIPS Datasets & Benchmarks*. 2021. (Open Problems in Single-Cell Analysis)
- Pratapa A, Jalihal AP, Law JN, Bharadwaj A, Murali TM. Benchmarking algorithms for gene regulatory network inference from single-cell transcriptomic data. *Nat Methods*. 2020;17:147–154. doi:10.1038/s41592-019-0690-6
- Open Problems in Single-Cell Analysis. Predicting transcriptomic responses to chemical perturbations across cell types (NeurIPS 2023 competition / OP3 benchmark). *NeurIPS Datasets & Benchmarks*. 2024.
