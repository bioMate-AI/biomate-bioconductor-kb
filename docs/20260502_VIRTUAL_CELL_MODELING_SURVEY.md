# Virtual Cell Modeling for BioMate: SOTA Survey & Implementation Guide
**Date:** 2026-05-02  
**Purpose:** Implementation-ready reference for building virtual cell capabilities into BioMate

---

## 1. ODE/SBML Mechanistic Simulation

### Tool Selection Summary

| Tool | GitHub | PyPI | License | Recommendation |
|------|--------|------|---------|----------------|
| **Tellurium** | sys-bio/tellurium | `pip install tellurium` | Apache 2.0 | **PRIMARY** — zero build overhead, SBML+Antimony, Gillespie, Jupyter |
| **AMICI** | AMICI-dev/AMICI | `pip install amici` | BSD 3-Clause | **Parameter fitting** — SBML→C++ adjoint sensitivity; pyPESTO integration |
| **SBMLtoODEjax** | flowersteam/sbmltoodejax | `pip install sbmltoodejax` | MIT | **ML-in-the-loop** — SBML→JAX; gradient-based fitting via Optax |
| **COPASI/basico** | copasi/basico | `pip install basico` | Artistic 2.0 | **PBPK parameter import** — stochastic; pyABC Bayesian; no official Docker |
| **SPARCED** | SPARCED/SPARCED | — | MIT | **Pan-cancer signaling** — Dockerized; Nextflow wrapper exists at ebenz99/MPCM-Nextflow |
| **BioNetGen** | RuleWorld/bionetgen | `pip install bionetgen` | MIT | **Rule-based** — BioContainers image; BioNetGen-2.9.1 (Feb 2024) |
| **COBRApy** | opencobra/cobrapy | `pip install cobra` | LGPL v2+ | **Metabolic FBA** — Bioconda auto-build; Recon3D/Human Metabolic Atlas |
| **VCell** | virtualcell/vcell | `pip install vcell` | MIT | **Spatial PDE** — REST API; Kubernetes; ghcr.io/virtualcell/biosimulators_vcell |

### Key Data Sources
- **BioModels Database**: https://www.ebi.ac.uk/biomodels/ — 1,000+ curated SBML models (free download)
- **Human Metabolic Atlas**: https://metabolicatlas.org/ — genome-scale metabolic models
- **BiGG Database**: http://bigg.ucsd.edu/ — Recon3D, iHuman metabolic reconstructions
- **FDA/CiPA SBML**: https://github.com/FDA/CiPA — O'Hara-Rudy action potential model (official)

### Docker Images
```
# Mechanistic ODE (build from pip):
FROM python:3.11-slim
RUN pip install tellurium amici pypesto basico sbmltoodejax cobra optax "jax[cpu]"

# BioNetGen (BioContainers):
docker pull quay.io/biocontainers/bionetgen:<version>

# VCell solvers:
docker pull ghcr.io/virtualcell/vcell-solvers:latest
```

### AWS Batch Instance Types
- COPASI/Tellurium parameter fitting: `c6i.8xlarge` (32 vCPU, no GPU)
- AMICI + pyPESTO multi-start: `c5.18xlarge` or `hpc6a.48xlarge`
- SBMLtoODEjax gradient: `g5.xlarge` (A10G 24GB)

---

## 2. AI/ML Perturbation Prediction Models

### Tool Selection Summary

| Model | HuggingFace / GitHub | License | Training Data | GPU Required | Rec. |
|-------|---------------------|---------|---------------|-------------|------|
| **GEARS** | snap-stanford/GEARS | MIT | Norman 2019, Replogle 2022 | Recommended | **PRIMARY** — GNN + GO graph; Nature Biotech 2024; best OOD combos |
| **CPA** | facebookresearch/CPA | MIT | Kang 2018, Norman 2019, Replogle 2022 | Recommended | **Drug combos** — scvi-tools; dose-response; compositional |
| **Geneformer V2** | ctheodoris/Geneformer | CC BY 4.0 | Genecorpus-104M (~104M cells) | Yes (≥12GB) | **Transfer learning** — 104M + 316M params; V2 Dec 2024 |
| **scFoundation** | genbio-ai/scFoundation | Research use | >50M human cells | Yes (≥16GB) | **Cross-tissue** — read-depth-aware; BioMap license |
| **TranscriptFormer** | czi-ai/transcriptformer | Apache 2.0 | 112M cells, 12 species | Yes | **BEST LICENSE** — cross-species; generative; v0.6.0 |
| **rBio** | czi-ai/rbio | Qwen Research | TranscriptFormer-supervised | Yes (≥6GB) | **Reasoning** — biological Q&A; chain-of-thought; 3B params |
| **TxPert** | Valence Labs | TBD | K562, RPE1, HEPG2, Jurkat | Yes | **Best OOD 2025** — multi-KG; Nature Biotech; check open-source status |
| **scGen** | theislab/scgen | BSD 3-Clause | Kang 2018 PBMC | Recommended | **Simple counterfactual** — arithmetic latent space |

### Key Benchmarking Datasets

| Dataset | Cells | Download |
|---------|-------|----------|
| **Norman 2019** (K562 CRISPRa, 112 genes, pairwise combos) | ~111K | Figshare: 24688110 |
| **Replogle 2022** (K562 + RPE1, genome-scale essential, ~8K genes) | ~450K | Figshare: 20029387; gwps.wi.mit.edu |
| **scPerturb** (44 harmonized datasets, 32 CRISPR + 9 drug) | avg 160K | Zenodo: 7041848; scperturb.org |
| **CZI K562 essential benchmark** | ~300K | virtualcellmodels.cziscience.com |

### Docker Images (GPU)
```
# Perturbation AI (GPU base):
FROM nvcr.io/nvidia/pytorch:24.05-py3
RUN pip install scvi-tools cpa-tools gears scgen pertpy anndata scanpy

# Geneformer:
FROM nvcr.io/nvidia/pytorch:24.05-py3
RUN pip install transformers geneformer cellxgene-census tiledbsoma

# TranscriptFormer (Apache 2.0 — preferred):
FROM nvcr.io/nvidia/pytorch:24.05-py3
RUN pip install git+https://github.com/czi-ai/transcriptformer.git
```

### AWS Batch Instance Types
- GEARS / CPA inference: `g4dn.xlarge` (T4 16GB) — sufficient for 10K cells
- Geneformer 104M: `g4dn.xlarge`; 316M: `g5.xlarge` (A10G 24GB)
- TranscriptFormer: `g5.2xlarge`
- rBio 3B (4-bit): `g4dn.xlarge`

---

## 3. Agent-Based / Spatial / Tissue Models

### Tool Selection Summary

| Tool | GitHub | Docker | Simulation Scale | Best For |
|------|--------|--------|-----------------|----------|
| **PhysiCell** | MathCancer/PhysiCell | Community image; physicell/physicell | 10^5–10^6 cells, 3D | Tumor microenvironment + PBPK drug exposure; v1.14.2 Jan 2025 |
| **FLAME GPU 2** | FLAMEGPU/FLAMEGPU2 | `pip install flamegpu` (CUDA) | 10^8–10^9 agents | Massive-scale GPU ABM; A100; CUDA required |
| **CompuCell3D** | compucell3d.org | Available; NanoHub online | 10^4–10^5 cells | Cellular Potts Model; morphogenesis |
| **Chaste** | Chaste/Chaste | `docker pull chaste/chaste` | 10^4–10^5 cells | Cardiac electrophysiology; off-lattice + lattice |
| **Morpheus** | morpheus.gitlab.io | `docker pull morpheus/morpheus` | Tissue-scale | CPM + ODE + diffusion in one XML |

### PhysiCell PBPK Integration Pattern
```python
# 1. BioMate PBPK workflow produces pk_summary.json with C_plasma[t]
# 2. Convert to PhysiCell XML substrate boundary condition:
#    Cplasma(t) × Kp_tumor → drug diffusion substrate
# 3. PhysiCell computes tumor drug penetration + cell kill
# 4. Output: TGI curve, viable cell count, spatial drug distribution
```

### AWS Batch Instance Types
- PhysiCell (CPU-intensive): `c6i.16xlarge` or `c5.9xlarge`
- FLAME GPU 2: `p4d.24xlarge` (A100×8) for massive ABM

---

## 4. Whole-Cell / Integrative Models

| System | Notes |
|--------|-------|
| **Vivarium** (vivarium-core, Apache 2.0) | `pip install vivarium-core` — composable multi-scale; wraps FBA + ODE + ABM; use for PBPK + ODE + FBA coupling |
| **vivarium-ecoli** (CovertLab) | E. coli whole-cell model in Vivarium; Docker-compatible; better maintained than Karr 2012 MATLAB |
| **Karr 2012 M. genitalium WCM** | MATLAB-based; no Docker; legacy; use vivarium-ecoli instead |
| **Recon3D / iHuman GEMs** | Load with COBRApy from BiGG Database; Human Metabolic Atlas |

---

## 5. Public Datasets for Model Training/Validation

| Dataset | Portal | Cells | API |
|---------|--------|-------|-----|
| **CZI CELLxGENE Census** | cellxgene.cziscience.com | Tens of millions | `pip install cellxgene-census`; S3: s3://cellxgene-census-public-us-west-2/ |
| **Human Cell Atlas** | data.humancellatlas.org | 70.8M from 11.2K donors | `pip install hca` |
| **LINCS L1000** | lincsproject.org | 1.3M profiles, 80 cell lines, 20K compounds | `pip install cmapPy`; L1000CDS² REST API |
| **scPerturb** | scperturb.org | 44 datasets avg 160K cells | Zenodo 7041848; `pip install scperturb` |
| **Replogle 2022** | gwps.wi.mit.edu | ~450K (K562+RPE1) | Figshare 20029387 |

---

## 6. Regulatory Landscape

### FDA Modernization Act 2.0 (Dec 29, 2022)
- **Removes mandatory animal testing** for IND submissions
- Explicitly permits: cell-based assays, in silico mechanistic models, microphysiological systems
- First FDA approval of FIH without preclinical animal efficacy already occurred (2024)
- **Impact**: ADMET + PBPK + virtual cell outputs can be primary IND evidence when validated

### FDA Draft AI Guidance (Jan 6, 2025)
- 7-step credibility framework for AI model outputs in regulatory submissions
- Risk-based: high-risk AI outputs (primary safety evidence) require more validation activities
- Comment period ended April 7, 2025; final guidance expected 2025–2026

### ICH S7B + CiPA
- Multi-ion channel ODE model (O'Hara-Rudy) accepted as **Tier 2** of 3-tier CiPA framework
- "Double-negative" scenario (neg hERG + neg in vivo) → reduced TQT study burden

### EMA Mechanistic Model Guideline
- Concept paper open Feb–May 2025 (EMA/5875/2025)
- Covers QSP, GEMs, agent-based models; ASME V&V 40 credibility framework
- PBPK: 26.5% of FDA-approved drugs 2020–2024 included PBPK submissions; 81.9% DDI applications

### What Level of Evidence Is Currently Accepted in IND

| Evidence Type | Current FDA/EMA Status |
|--------------|----------------------|
| PBPK for DDI/renal/hepatic | Fully accepted; routinely requested |
| CiPA in silico AP (hERG mechanistic) | Accepted as Tier 2 in CiPA framework |
| QSP for tumor immune / dose selection | Accepted with MIDD credibility documentation |
| QSAR ADMET | Accepted as supplementary; validation set required |
| AI foundation models (Geneformer etc.) | Not yet primary evidence; exploratory only |
| Agent-based tissue simulation | Emerging; no formal pathway yet |

---

## 7. BioMate Integration Points

| Existing Workflow | Virtual Cell Integration | Value |
|------------------|------------------------|-------|
| ADMET hERG IC50 → | CiPA cardiac ODE (id=12893) | Mechanistic APD/qNET confirmation; regulatory Tier 2 |
| RNA-seq DEGs → | LINCS L1000 MoA (id=12896) | Compound MoA from transcriptomics; combo synergy |
| PBPK plasma curve → | PhysiCell tumor TGI (P-VC4) | Mechanistic TGI from PK input |
| MAGeCK CRISPR screen → | GEARS perturbation (P-VC2) | Predict off-target transcriptional effects |
| Drug docking scores → | ODE receptor occupancy (id=12894) | Binding kinetics from IC50/Kd |
| DILI QSAR prediction → | Metabolic FBA (id=12895) | Mechanistic DILI mechanism confirmation |

---

## 8. Phase 1 Workflows Built (2026-05-02)

| Workflow | ID | File | Status |
|----------|-----|------|--------|
| `cipa_cardiac_safety_ode` | 12893 | virtual_cell/cipa_cardiac_safety_ode/main.nf | ✅ Built |
| `ode_signaling_simulation` | 12894 | virtual_cell/ode_signaling_simulation/main.nf | ✅ Built |
| `metabolic_flux_fba` | 12895 | virtual_cell/metabolic_flux_fba/main.nf | ✅ Built |
| `transcriptomic_moa_lincs` | 12896 | virtual_cell/transcriptomic_moa_lincs/main.nf | ✅ Built |

## Phase 2 Workflows Planned (GPU-required)

| Workflow | Description | Tools | Est. Complexity |
|----------|-------------|-------|----------------|
| `gears_perturbation_prediction` | CRISPR/drug perturbation → transcriptional response OOD | GEARS + PyG + scvi-tools | 3–4 weeks |
| `cpa_drug_combination_synergy` | Drug combination transcriptional synergy prediction | CPA + scvi-tools + AnnData | 2–3 weeks |
| `transcriptformer_cell_state` | Cross-species cell state prediction (Apache 2.0) | TranscriptFormer + CZI Census | 3–4 weeks |
| `physicell_tumor_tgi` | PBPK→PhysiCell tumor growth inhibition ABM | PhysiCell + PBPK bridge | 6–8 weeks |
| `virtual_patient_cohort` | Stochastic ODE × PopPK for virtual clinical trials | Tellurium + AMICI + popPK | 4–6 weeks |

---

## References

- O'Hara et al. 2011 PLoS Comput Biol 7(5):e1002061 (ORd action potential model)
- Dutta et al. 2017 Front Physiol 8:616 (CiPA qNET validation)
- Subramanian et al. 2017 Cell 171:1437 (CMap LINCS 2.0)
- GEARS: Roohani et al. 2024 Nature Biotechnology (graph-based perturbation)
- Orth et al. 2010 Nat Biotechnol 28:245 (flux balance analysis)
- Aleo et al. 2017 Chem Res Toxicol 30:1789 (mitochondrial DILI mechanisms)
- CZI TranscriptFormer: github.com/czi-ai/transcriptformer (Apache 2.0)
- CZI rBio: github.com/czi-ai/rbio (reasoning model)
- TxPert: arxiv.org/abs/2505.14919 (Valence Labs, 2025)
- PhysiCell v1.14.2: github.com/MathCancer/PhysiCell (Jan 2025)
- Vivarium: pip install vivarium-core (Apache 2.0)
- FDA Modernization Act 2.0 (Dec 2022); FDA Draft AI Guidance (Jan 2025)
- EMA Mechanistic Model Guideline EMA/5875/2025 (Feb 2025)
- ICH S7B (2021) + E14/S7B Q&A (CiPA framework)
