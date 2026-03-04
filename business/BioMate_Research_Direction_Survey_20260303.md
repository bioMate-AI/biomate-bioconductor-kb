# BioMate AI — Research Direction Survey & Beta Release Plan
*Four Strategic Directions · Market Analysis · Gap Assessment · Beta Roadmap · Network Strategy*
*March 2026 · Prepared for Mentor Discussion*

---

## The AI Clinical Trial Signal — Context for All Four Directions

Before evaluating each direction, one validated finding shapes the entire landscape:

> **AI-discovered drugs reach Phase I with an 80–90% success rate, compared to the industry baseline of 52%.**

**Source:** Jayatunga et al., *Drug Discovery Today*, June 2024
[[PubMed]](https://pubmed.ncbi.nlm.nih.gov/38692505/) · [[ScienceDirect full text]](https://www.sciencedirect.com/science/article/pii/S135964462400134X)

**What the data actually says:**
- Based on 21 AI-developed drugs that completed Phase I as of December 2023
- Industry Phase I baseline: **52%** (BIO report, 4,414 programs, 2011–2020) [[BIO.org]](https://www.bio.org/clinical-development-success-rates-and-contributing-factors-2011-2020)
- The advantage is **Phase I only** — Phase II success (~40%) matches the industry average (no AI advantage yet at proof-of-concept stage)
- Sample size caveat: 21 programs is small; reporting bias likely (failures may not be publicized)
- AI candidates in clinical trials grew: 3 (2016) → 17 (2020) → 67 (2023)

**The landmark clinical confirmation:**
Insilico Medicine's **Rentosertib** (ISM001-055) for Idiopathic Pulmonary Fibrosis became the first fully AI-designed drug to reach Phase 2a with positive results.
- Target: TNIK inhibitor; designed in 30 months (vs. typical 4–6 years)
- Phase 2a result: +98.4 mL FVC improvement vs. −62.3 mL decline in placebo at 60mg QD
- Published: *Nature Medicine*, 2025 [[link]](https://www.nature.com/articles/s41591-025-03743-2)

**What this means for BioMate:**
The AI advantage appears to be concentrated at the **molecular design and target selection** stages — where AI improves the quality of candidates entering the clinic. BioMate's role is complementary: providing the downstream computational infrastructure (multi-omics QC, PK/PD analysis, pharmacogenomics) that converts a good candidate into a reproducible, defensible data package. This is the **evidence layer** that makes AI-designed drugs credible in regulatory submissions.

**What is still missing and where BioMate can contribute:**
- No platform currently provides **end-to-end reproducible QC governance** from hit-to-lead through Phase I NCA — BioMate does
- The Phase II bottleneck (40% success, same as conventional drugs) suggests the AI advantage stops at molecule design; **patient stratification from RNA-seq** (Direction 3) and **biomarker-driven trial design** are the next frontiers
- **Nature Communications, 2025:** Dynamic clinical trial success rates update [[link]](https://www.nature.com/articles/s41467-025-64552-2)

---

## Priority Matrix

| Direction | Market Size (2024) | CAGR | BioMate Current State | Gap Size | Business Priority | Beta Priority |
|---|---|---|---|---|---|---|
| **A. Drug Discovery** | $1.7B → $16.5B by 2034 | ~30% | ✅ COMPLETE (12 phases) | Small | **#1** | **#1** |
| **B. RNA-seq / Precision Medicine** | $4.45B → $11.1B by 2030 | 20% | ✅ SUBSTANTIAL (186 tools, 5 QC profiles) | Medium | **#2** | **#2** |
| **C. Cryo-EM + AI Structures** | $1.42B AI segment → 19.3% CAGR | 19% | ✅ COMPLETE (SPA+ET, 23+5 steps) | Medium (benchmarking) | **#3** | **#3** |
| **D. Single-Cell Perturbation** | $4.09B → $18.7B by 2034 | 16.4% | ⚠️ PARTIAL (14 tools, no CRISPR screen) | Large | **#4** | **#4** |

---

## Direction A: Drug Discovery — Hybrid AI + Wet Lab Team

### Market

| Metric | Value | Source |
|---|---|---|
| AI Drug Discovery market (2024) | ~$1.7B | [Grand View Research](https://www.grandviewresearch.com/industry-analysis/artificial-intelligence-drug-discovery-market) |
| Projected (2034) | $16.52B | [GM Insights](https://www.gminsights.com/industry-analysis/ai-in-drug-discovery-market) |
| CAGR | ~30% | [Mordor Intelligence](https://www.mordorintelligence.com/industry-reports/artificial-intelligence-in-drug-discovery-market) |
| AI candidates in clinic (2023) | 67 programs | Jayatunga et al. 2024 [[link]](https://pubmed.ncbi.nlm.nih.gov/38692505/) |

**Landmark events (2024–2026):**
- **Insilico Medicine**: Rentosertib Phase 2a positive [[Nature Medicine]](https://www.nature.com/articles/s41591-025-03743-2) — first proof that AI-designed drugs work in patients
- **Recursion + Exscientia merger** (Nov 2024): Vertical integration of AI target discovery + drug design; 7 clinical readouts expected within 18 months [[IR]](https://ir.recursion.com/news-releases/news-release-details/recursion-gives-guidance-seven-clinical-readouts-within-18)
- **Schrödinger**: zasocitinib (TAK-279) at Phase III; 13 royalty-eligible programs [[pipeline]](https://www.schrodinger.com/pipeline/)
- **Leading platforms 2025 landscape review** [[ScienceDirect]](https://www.sciencedirect.com/science/article/abs/pii/S0031699725075118)

### What BioMate Has (Complete)

All 12 phases of the drug development pipeline are covered:

| Phase | Key Workflows | Status |
|---|---|---|
| 1. Target identification | TxGNN drug repurposing, DDI mechanisms | ✅ |
| 2. Target validation | DiffDock, AutoDock Vina, AutoSite, 1D binding affinity | ✅ |
| 3. Hit identification | DrugCLIP virtual screening (ultra-fast ML) | ✅ |
| 4. Hit-to-lead (ADMET) | `predict_admet_properties`, physicochemical properties | ✅ |
| 5. Lead optimization | hERG/DILI/Ames/ClinTox QC gates (GOLD/SILVER) | ✅ |
| 6. Preclinical | Xenograft TGI, 3D chondrogenic, radiotherapy dosimetry | ✅ |
| 7. Regulatory prep | FDA recalls, drug labels, VCOG-CTCAE toxicity grading | ✅ |
| 8. Phase I — NCA | `nca_pknca`: AUC, Cmax, t½, CL/F, MRT | ✅ |
| 9. Phase II/III — PopPK | `nlmixr2_population_pk`: SAEM (FDA-recognized) | ✅ |
| 10. Personalized medicine | PGx gene coverage gates (CPIC Tier 1+2) | ✅ |
| 11. Formulation | Accelerated stability, in vitro release kinetics | ✅ |
| 12. Post-market | FDA adverse event signal analysis | ✅ |

**QC governance**: 9 profiles (proteomics standard, phospho, plasma biomarker, chemoproteomics, compound druglike, natural product, peptidomimetic, PGx clinical/research). 8 QC parsers with GOLD/SILVER/BRONZE tiering.

### What Is Missing

| Gap | Priority | Action |
|---|---|---|
| **LC-MS Agent integration** — built but not wired into main platform | Medium | 1-week engineering task: connect `LC-MS-agent` endpoints through Galaxy proxy |
| **Paper 4 manuscript** — all data exists, manuscript directory empty | High | Recruit clinical PK + pharmacoproteomics co-author; write methods section |
| **Real benchmark data** — need de-identified LC-MS dataset | High | CRO collaborator or public PXD dataset from ProteomeXchange |
| **Wet lab partner team** — for hybrid AI + wet lab story | High | Approach pharma collaborator (BCM, UT Southwestern, Baylor Genetics in Texas targets) |
| **AlphaFold3 integration** — structure-based drug design loop | Medium | Add AlphaFold3 server API call before molecular docking step |

### What BioMate Uniquely Contributes

No current AI drug discovery platform (Insilico, Recursion, Schrödinger) provides **end-to-end reproducible QC governance with published citations** covering proteomics, SMILES compound quality, PGx coverage, NCA metrics, and PopPK convergence. BioMate's GOLD/SILVER/BRONZE framework covers the entire evidence chain from molecule selection to Phase II analytics — this is the "evidence layer" that AI-designed drugs need to survive regulatory scrutiny.

### Beta Test Plan — Drug Discovery

**Pilot users:** 3–5 academic labs or CROs with existing LC-MS or compound screening data

| Phase | Target | Success Criterion |
|---|---|---|
| **Beta 1 (Month 1–2)** | 1 Texas pharma/biotech (Baylor Genetics or NeuroX1) runs ADMET + docking on 10 compounds | BioMate generates complete ADMET report + QC gates in < 10 min |
| **Beta 2 (Month 2–4)** | 1 proteomics lab runs MaxQuant output through QC governance + PGx | QC audit log exported; journal-ready methods section auto-generated |
| **Beta 3 (Month 4–6)** | 1 clinical lab runs NCA on PK data from Phase I study | nlmixr2 PopPK convergence verified; NCA report auto-generated |

**Public release trigger:** 5 pilot users have completed at least 1 full workflow end-to-end with QC audit log exported.

---

## Direction B: RNA-seq for Patient Subgrouping, Diagnosis & Prognosis

### Market

| Metric | Value | Source |
|---|---|---|
| NGS RNA-seq market (2025) | $4.45B | [Towards Healthcare / Mordor](https://www.towardshealthcare.com/insights/ngs-based-rna-sequencing-market-sizing) |
| Projected (2030) | $11.11B | Same |
| CAGR | **20.06%** | Same |
| Broader RNA analysis (2024) | $8.62B → $23.65B (2033) | [Grand View Research](https://www.grandviewresearch.com/industry-analysis/transcriptomics-technologies-market) |
| RNA analysis market (2035) | $23.39B | [GlobeNewswire Feb 2026](https://www.globenewswire.com/news-releases/2026/02/11/3236097/0/en/RNA-Analysis-Market-Size-Worth-USD-23-39-Billion-by-2035-Fueled-by-Expansion-of-RNA-Therapeutics-and-Precision-Medicine.html) |

**Why this direction matters clinically:**
- Transcriptomics is the primary tool for patient stratification in cancer and complex diseases
- AML (acute myeloid leukemia) transcriptome stratification — foundational clinical application: *Nature Communications* 2021 [[link]](https://www.nature.com/articles/s41467-021-22625-y)
- Leveraging transcriptomics for precision diagnosis (cancer, sepsis, autoimmune): PMC review [[link]](https://pmc.ncbi.nlm.nih.gov/articles/PMC10036914/)
- Transcriptomics in drug discovery pipeline (npj Drug Discovery 2025 perspective): [[link]](https://www.nature.com/articles/s44386-025-00029-y)

### What BioMate Has (Substantial)

| Asset | Count / Status |
|---|---|
| RNA-seq tools in database | **186 unique tools** |
| QC parsers | 9 (FastQC, trimming, alignment, featureCounts, Salmon, flagstat, Picard dup, coverage, ATAC) |
| Named QC profiles | 5 (polyA standard, ribo-depleted, FFPE, single-nucleus, non-model organism) |
| Bioconductor DE tools | DESeq2, edgeR, limma-voom, deconRNAseq, easyRNAseq (14+ packages wrapped) |
| RNA-seq embeddings | TransformerX, STATE embeddings, ARCHS4 similar-study query |
| QC gates | GOLD: mapping ≥70%, TSS enrichment ≥5, NRF ≥0.9; SILVER: reads surviving, assigned reads, Q30 |

**The FFPE RNA-seq profile is a key clinical differentiator:** formalin-fixed paraffin-embedded tissue (the dominant biobank format for hospital specimens) has specific QC requirements that BioMate encodes — no competitor does this explicitly.

### What Is Missing

| Gap | Priority | Notes |
|---|---|---|
| **Patient stratification / survival analysis** | **HIGH** | No Kaplan-Meier, Cox proportional hazards, log-rank test, or risk score workflows |
| **Cancer subtype discovery** | **HIGH** | No consensus clustering (ConsensusClusterPlus), NMF, or PAM50/TCGA subtyping |
| **nf-core/rnaseq unified wrapper** | Medium | Only Bioconductor DE tools exposed; no single click from raw FASTQ → count matrix → DE |
| **Deconvolution for clinical samples** | Medium | `deconRNAseq` exists but no CIBERSORT, MuSiC, or BayesPrism wrapper |
| **Longitudinal / time-series RNA-seq** | Low | Treatment-response tracking over time; not implemented |
| **Clinical trial data integration** | Medium | No workflow to connect RNA-seq subgroups to clinical outcomes (OS, PFS, ORR) |

### What BioMate Uniquely Contributes

The FFPE QC profile and evidence-graded QC thresholds directly address the clinical lab use case. When a hospital genomics lab processes tumor RNA-seq specimens for subgrouping, BioMate's QC audit log provides the defensibility that CLIA/CAP certification requires. This is the bridge between research transcriptomics and clinical implementation — a gap that Illumina, PacBio, and 10x Genomics leave to the user to figure out.

### Beta Test Plan — RNA / Precision Medicine

| Phase | Target | Success Criterion |
|---|---|---|
| **Beta 1 (Month 1–2)** | 1 oncology lab (MD Anderson or UT Southwestern) runs differential expression on FFPE tumor cohort | BioMate applies `rnaseq_ffpe` QC profile; DE analysis with DESeq2 complete with QC report |
| **Beta 2 (Month 2–4)** | 1 clinical lab runs patient subgrouping on existing TCGA dataset | Unsupervised clustering results with reproducible QC log; comparison to published subtypes |
| **Beta 3 (Month 4–8)** | Add Kaplan-Meier survival workflow | BioMate connects DE results → survival groups → K-M curves in single session |

**Gap to close first for Beta 1:** Add `survival_analysis` subworkflow with Kaplan-Meier + Cox regression (R `survival` package — available as Bioconductor tool wrapper within 1 week of implementation).

---

## Direction C: Cryo-EM + AI-Based Structure Generation

### Market

| Metric | Value | Source |
|---|---|---|
| Cryo-EM instruments market (2024) | $1.54B | [Markets and Data](https://www.marketsandata.com/industry-reports/cryo-electron-microscopy-market) |
| Projected (2032) | $3.45B at 10.57% CAGR | Same |
| Cryo-EM AI image processing (2024) | **$1.42B at 19.3% CAGR** | [Growth Market Reports](https://growthmarketreports.com/report/cryo-em-image-processing-ai-market) |
| Cryo-EM structure analysis services | $1.30B (2025) → $2.51B (2032) at 9.8% | [Coherent Market Insights](https://www.coherentmarketinsights.com/industry-reports/cryo-em-structure-analysis-services-market) |

**The AlphaFold3 watershed (May 2024):**
Abramson et al., *Nature* 630:493–500 [[PubMed]](https://pubmed.ncbi.nlm.nih.gov/38718835/)
- Unified diffusion architecture for proteins, nucleic acids, small molecules, ions, modified residues
- "Far greater accuracy for protein-ligand interactions compared with state-of-the-art docking tools"
- Directly integrated into Isomorphic Labs' internal drug design pipeline

**AlphaFold3 + Cryo-EM synergy (2025 finding):**
Combining AlphaFold3 with cryo-EM flexible fitting improved ligand model-to-map cross-correlation from **40–71% → 82–95%**
*PLOS Computational Biology, 2025* [[link]](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1013367)

**2025 drug discovery reviews:**
- Expert Opinion on Drug Discovery (Feb 2025): [[PubMed]](https://pubmed.ncbi.nlm.nih.gov/39789967/) · [[Tandfonline]](https://www.tandfonline.com/doi/full/10.1080/17460441.2025.2450636)
- Frontiers in Molecular Biosciences (2025 review): [[Frontiers]](https://www.frontiersin.org/journals/molecular-biosciences/articles/10.3389/fmolb.2025.1688455/full) · [[PMC]](https://pmc.ncbi.nlm.nih.gov/articles/PMC12590954/)

### What BioMate Has (Complete)

**Single-Particle Analysis (SPA) — full 23-step pipeline:**
Import movies → motion correction → CTF estimation → denoising → blob picking → junk detection → 2D classification (×2 rounds) → ab initio reconstruction → homogeneous refinement → CTF refinement → non-uniform refinement → local resolution → sharpening

**Cryo-ET — full 5-step pipeline:**
Import tilt series → tilt alignment → tomogram reconstruction → subtomogram averaging → full pipeline

**3 execution modes:** Mock (realistic sim), live CryoSPARC v5 API, opensource (RELION/Topaz/CTFFIND/Phenix)
**8 GPU configs:** standard, docker, local_gpu, multi_gpu, slurm, singularity, aws, test
**4-level Nextflow parallelism:** movies → micrographs → particles → volumes
**7 QC parsers:** motion, CTF (incl. phase plate), picking, 2D classification, refinement, sharpening, local resolution
**3 named profiles:** purified protein, membrane protein, in-situ cryo-ET
**43 tests passing** (P1 gates, P2 gates, phase plate, near-threshold warnings)

### What Is Missing

| Gap | Priority | Action |
|---|---|---|
| **EMPIAR live benchmarking** | **HIGH** | Paper requires runs on EMPIAR-10061 (TRPV1), 10005, 10017, 10028 — needs AWS g6.2xlarge with real CryoSPARC license |
| **AlphaFold3 integration** | **HIGH** | Post-refinement: call AlphaFold3 server for atomic model fitting into cryo-EM density map |
| **Heterogeneity analysis** | Medium | 3D variability display, cryoDRGN, manifold learning — none implemented |
| **Manuscript content** | High | `research_repos/cryo_em_benchmark_paper/manuscript/` directory empty |
| **User study** | Medium | 5–10 structural biologist sessions to validate usability |
| **Model quality assessment** | Medium | No MolProbity, PHENIX comprehensive validation, or EMRinger score integration |

### What BioMate Uniquely Contributes

BioMate is the **only platform** that combines:
1. Complete end-to-end cryo-EM SPA pipeline (23 steps) with QC governance (GOLD/SILVER/BRONZE gates)
2. Phase plate CTF support (VPP mode) with evidence-cited thresholds
3. Cryo-ET with Nextflow parallelism (vs. IMOD's serial processing)
4. Direct bridge to drug discovery pipeline (cryo-EM structure → docking → ADMET → PGx → NCA)

**The missing link the field needs:** Reproducible, QC-governed cryo-EM pipelines with auditable decision logs. Most structural biology labs run CryoSPARC or RELION interactively with no systematic QC documentation. BioMate's audit trail enables FAIR data sharing and supports collaborative multi-institution datasets.

### Beta Test Plan — Cryo-EM

| Phase | Target | Success Criterion |
|---|---|---|
| **Beta 1 (Month 1–2)** | Run pipeline on EMPIAR-10061 (TRPV1, 3.8Å reference) | BioMate achieves ≤ 4.0Å with all QC gates passing; runtime comparison vs. manual CryoSPARC |
| **Beta 2 (Month 2–4)** | 1 structural biology lab (UT Southwestern Lyda Hill) runs own dataset | Full audit log generated; QC decisions traceable to published thresholds |
| **Beta 3 (Month 4–6)** | Add AlphaFold3 structure fitting into cryo-EM density | Model-to-map cross-correlation reported in QC output |

**Technical prerequisite for Beta 1:** Provision AWS g6.2xlarge with CryoSPARC license (estimated: $50–100/dataset for EMPIAR-10061).

---

## Direction D: Single-Cell Research — Perturbation & Modeling

### Market

| Metric | Value | Source |
|---|---|---|
| Single-cell analysis market (2024) | $4.09B | [Precedence Research](https://www.precedenceresearch.com/single-cell-analysis-market) |
| Projected (2034) | $18.68B at 16.4% CAGR | Same |
| Single-cell omics market (2024) | $1.94B → $12.05B by 2034 | [GlobeNewswire](https://www.globenewswire.com/news-releases/2025/11/05/3181538/0/en/Single-Cell-Omics-Market-to-Reach-USD-12-05-Billion-by-2034-Growing-at-a-16.14-CAGR-Towards-Healthcare.html) |

**Technology wave (2024–2026):**

1. **Multiome Perturb-seq** — simultaneous transcriptome + chromatin (ATAC) readout from CRISPR screens
   *Cell Systems*, 2024 [[PubMed]](https://pubmed.ncbi.nlm.nih.gov/39689711/) · [[full text]](https://www.cell.com/cell-systems/fulltext/S2405-4712(24)00366-1)

2. **Compressed Perturb-seq** (Genentech) — 10× cost reduction via composite perturbations
   *Nature Biotechnology*, 2024 [[Nature Biotech]](https://www.nature.com/articles/s41587-023-01964-9) · [[PMC]](https://pmc.ncbi.nlm.nih.gov/articles/PMC11035494/)

3. **Spatial CRISPR screening** — CRISPR screen × spatial transcriptomics
   *Cell*, 2025 [[full text]](https://www.cell.com/cell/fulltext/S0092-8674(25)00197-7)

4. **VIPerturb-seq** — genome-wide perturbation screens at single-cell resolution (2026 preprint)
   *bioRxiv*, 2026 [[link]](https://www.biorxiv.org/content/10.64898/2026.02.12.705613v1.full)

5. **scPerturb** — harmonized repository of 44 perturbation datasets (160K cells avg)
   *Nature Methods*, 2024 (Peidli et al.)

6. **PerturbSeq.db** — integrated computational repository for perturbation data
   *ScienceDirect*, 2025 [[link]](https://www.sciencedirect.com/science/article/abs/pii/S002228362500275X)

**Key players:**
- **10x Genomics** — Chromium GEM-X Flex for large-scale CRISPR screening [[product]](https://www.10xgenomics.com/products/single-cell-crispr-screening); 2025 AGBT innovation roadmap [[announcement]](https://www.prnewswire.com/news-releases/10x-genomics-unveils-innovation-roadmap-at-agbt-general-meeting-advancing-leadership-in-large-scale-single-cell-and-spatial-analysis-302382827.html)
- **Broad Institute** — Pioneered Perturb-seq; continues compressed + spatial extensions
- **Genentech** — Co-authored Compressed Perturb-seq; building CROPseq-multi
- **Recursion** — Large-scale cellular phenomics + CRISPR perturbation post-Exscientia merger

### What BioMate Has (Partial)

| Asset | Count / Status |
|---|---|
| Single-cell tools in database | **79 unique tools** |
| Bioconductor packages wrapped | 14+ (scannotatr, clustifyr, cardelino, speckle, scmeth, hippo, m3drop, singlecelltk, etc.) |
| Core workflows | 6 generated (cell type annotation, scVI embeddings, Harmony embeddings, UCE embeddings, unsupervised transfer) |
| QC parser | 1 (`_parse_singlecell_metrics()` — CellRanger / STARsolo) |
| Named QC profiles | 3 (standard, cardiac, neuronal) |
| CRISPR perturbation | `analyze_crispr_genome_editing` (CAS9 outcomes only) |

### What Is Missing (Largest Gap of the Four Directions)

| Gap | Priority | Effort | Notes |
|---|---|---|---|
| **Perturb-seq end-to-end pipeline** | **HIGH** | 3–4 weeks | MAGeCK + CRISPResso + scVI perturbation modeling; connects CRISPR screen → single-cell readout → hit calling |
| **CRISPR screen hit calling** | **HIGH** | 1 week | MAGeCK MLE/RRA; edgeR-based hit calling; no current implementation |
| **scVI perturbation modeling** | **HIGH** | 2 weeks | SCVI-tools perturbation state inference (Norman et al. approach) |
| **Trajectory inference** | Medium | 1 week | Monocle3, scVelo, PAGA — none implemented |
| **Differential abundance testing** | Medium | 1 week | MiloR, Nebula, edgeR-based DA testing |
| **Doublet detection** | Medium | 3 days | DoubletFinder, Scrublet — add to QC pipeline |
| **Spatial transcriptomics** | Low | 3 weeks | Visium, MERFISH, seqFISH+ data types not yet supported |
| **Full scRNA-seq test suite** | Medium | 1 week | No dedicated `TestSingleCell_*` class; only embedded coverage |

### What BioMate Uniquely Contributes

Once the Perturb-seq pipeline is built, BioMate can offer something unique: **reproducible, QC-governed CRISPR screen analysis pipelines** that can be re-run identically by any authorized user. The field currently lacks this — most Perturb-seq analyses are done ad hoc in Jupyter notebooks. BioMate provides the audit trail that reproducibility-focused publications and regulatory submissions require.

**The gap BioMate can close:** scPerturb (Nature Methods 2024) identified poor reproducibility and non-standardized QC across 44 published datasets. BioMate's GOLD/SILVER/BRONZE QC framework, applied to Perturb-seq, would directly address this.

### Beta Test Plan — Single-Cell

| Phase | Target | Success Criterion |
|---|---|---|
| **Beta 1 (Month 2–3)** | Build MAGeCK + scVI perturbation pipeline (internal) | Hit calling from simulated CRISPR screen dataset |
| **Beta 2 (Month 3–5)** | 1 lab (Rice Treangen Lab or MD Anderson) runs Perturb-seq data | End-to-end: guide assignment → cell filtering → hit calling → DE → visualization |
| **Beta 3 (Month 5–8)** | QC profile for Perturb-seq | New profile `scrna_perturbation` covering guide library coverage, transfection efficiency |

**Prerequisite:** Build the Perturb-seq pipeline first (3–4 weeks). This is the largest implementation gap.

---

## Network Strategy — Connecting Teams Through BioMate

### The Opportunity

Each of the four directions maps to different teams that currently work in isolation:
- **Drug discovery teams** (pharma, biotech) running ADMET and proteomics
- **Structural biologists** running cryo-EM
- **Clinical oncologists** running RNA-seq for patient stratification
- **Functional genomics labs** running single-cell CRISPR screens

These teams often study the **same disease** (cancer, rare disease, neurological) but use incompatible workflows, different QC standards, and produce data that cannot be directly compared.

### BioMate as the Network Layer

```
Drug Discovery Team (pharma)              Clinical Lab (hospital)
    → identifies target via AI                → RNA-seq patient stratification
    → runs ADMET/docking in BioMate           → DESeq2 + survival in BioMate
              ↘                                         ↙
         BioMate SHARED STANDARDS
         - Same QC governance (GOLD/SILVER/BRONZE)
         - Same tool catalog (10,595 validated)
         - Same audit trail format (JSONL per-run)
         - Same workflow templates (citable, reproducible)
              ↙                                         ↘
    Structural Biology Lab                Single-Cell Lab
    → cryo-EM structure in BioMate          → Perturb-seq CRISPR screen in BioMate
    → AlphaFold3 model fitting              → scVI perturbation modeling
```

### Concrete Network Mechanisms

**1. Shared Dataset Registry (immediate, 0-cost)**
- BioMate maintains a registry of datasets that labs have made available for cross-lab analysis
- Each dataset has a QC certificate (BioMate audit log)
- Labs that use the same QC-certified dataset get comparable results by design
- **Action:** Create `biomate_dataset_registry.json` linked to public accessions (GEO, EMPIAR, ProteomeXchange)

**2. BioMate Methods Citations (publication network)**
- Every paper citing BioMate in its methods section creates a citable workflow
- Other labs can click "re-run" on a published BioMate workflow using the same parameters
- This is the "cite-to-adopt" flywheel: Paper cites BioMate → new lab discovers BioMate → new paper cites BioMate
- **Comparable model:** Nextflow's published workflow DOI system; BioMate adds the QC governance layer

**3. Consortium Pilot Program (6-month structured collaboration)**
- Recruit 1 team from each direction as a "BioMate Consortium" member
- Each team gets: free Enterprise tier, co-authorship on BioMate paper, shared QC thresholds
- Teams share anonymized QC statistics (what parameters work for FFPE, what doesn't)
- **Target teams:** TMC Innovation Hub (umbrella), UT Southwestern (cryo-EM + RNA), Rice Treangen Lab (single-cell/metagenomics), Baylor Genetics (clinical), NeuroX1 (drug discovery)

**4. Cross-Domain Workflow Templates (technical integration)**
- **Template: "Drug Target to Cryo-EM Structure"** — DiffDock molecular docking → cryo-EM structure preparation → AlphaFold3 fitting
- **Template: "RNA-seq Biomarker to Drug Target"** — DESeq2 DE → gene set enrichment → TxGNN drug repurposing
- **Template: "CRISPR Screen to Drug Target"** — Perturb-seq MAGeCK hits → ADMET screening → binding affinity prediction
- These cross-domain templates are the network connectors: they create dependency between teams

**5. BioMate Research Network (formal structure)**
- Named group: "BioMate Research Network" (analogous to Broad Institute's Single Cell Portal community)
- Annual virtual event: teams share QC learnings, propose new threshold evidence
- QC threshold database open-sourced on GitHub — community contributes new evidence citations
- **Metric:** Number of external QC threshold contributions = measure of network health

### Network Priority: Texas First

The 13 Texas Priority-A targets span all four directions:
- **Drug discovery:** Baylor Genetics, NeuroX1, ARPA-H Dallas Hub
- **RNA-seq/clinical:** MD Anderson, UT Southwestern Simmons Cancer Center, Sonic Healthcare USA, UTHealth McWilliams
- **Cryo-EM:** UT Southwestern Lyda Hill Bioinformatics (UTSW Cryo-EM core)
- **Single-cell:** BCM HGSC, BCM Quantitative & Computational Biosciences, Rice Treangen Lab

**One institutional partnership** (e.g., TMC Innovation Hub) could span all four directions simultaneously, creating a multi-team network within a single institution.

---

## Consolidated Beta Test & Release Timeline

### Phase 0 — Beta Stabilization (Month 0–1, NOW)

Before any external beta users:

| Requirement | Action | Owner | Done? |
|---|---|---|---|
| Technical stability (crash rate, response time, data safety) | Deploy monitoring; error rate dashboard | DevOps | ✅ Mostly done |
| Workflow clarity (input → execute → export) | User documentation; video walkthrough | Product | ⚠️ Docs incomplete |
| Report export (PDF/HTML per workflow run) | Build `export_qc_report` endpoint | Backend | ❌ Not built |
| Cohort cost tracking (cost per active user) | Add cohort dimension to billing dashboard | Backend | ⚠️ Partial |
| Free-to-Pro conversion flow | Stripe payment UI; invite code expiry | Frontend | ✅ Done |

### Phase 1 — Closed Beta — Domain A (Drug Discovery) (Month 1–3)

- **Users:** 3–5 pharma/biotech labs (from Texas Priority-A: NeuroX1, Baylor Genetics, 1 CRO)
- **Workflow:** ADMET → docking → QC governance → NCA or PopPK
- **Data:** Lab provides own compound set or public ChEMBL data
- **Success gate:** 3 labs complete end-to-end workflow; QC audit log exported; lab provides testimonial
- **Instrumentation:** NPS survey; session recording (Hotjar/equivalent); feature request log

### Phase 2 — Closed Beta Expansion (Month 2–4)

Add Directions B (RNA-seq) and C (Cryo-EM) in parallel:

- **RNA-seq beta:** MD Anderson or UT Southwestern oncology lab; FFPE tumor RNA-seq cohort
- **Cryo-EM beta:** EMPIAR-10061 (TRPV1) first, then structural biology collaborator
- **Cross-domain pilot:** 1 lab that has both RNA-seq and proteomics data (e.g., MD Anderson Bioinformatics & Comp Bio)
- **Metrics:** Time-to-first-result per domain; QC pass rate; workflow completion rate

### Phase 3 — Public Beta Launch (Month 3–4)

- Open free tier to all users
- Post to Reddit r/bioinformatics, nf-core Slack, Galaxy community, Twitter/X
- GitHub: open-source QC threshold database
- bioRxiv: post Paper 1 (QC governance) preprint
- Invite-code system for Pro tier (beta pricing)

### Phase 4 — Single-Cell Beta (Month 4–8)

- Perturb-seq pipeline built internally (Month 2–4)
- First external beta user: functional genomics lab with existing CRISPR screen data
- Build `scrna_perturbation` QC profile
- Add trajectory inference (Monocle3, scVelo)

### Phase 5 — Enterprise & Clinical Launch (Month 9–18)

- SOC 2 Type I audit initiated
- SSO/SAML for institutional deployments
- Clinical QC compliance dashboard (audit export, CLIA/CAP reporting)
- Outcome-based pricing tier launched
- Nature Methods preprint: Month 9
- Enterprise sales hire: Month 9–12

---

## Summary: Priority Scores for Mentor Discussion

| Dimension | Drug Discovery | RNA Precision Medicine | Cryo-EM + AI Structures | Single-Cell Perturbation |
|---|---|---|---|---|
| **Market size** | ★★★★★ ($1.7B → $16.5B) | ★★★★★ ($4.45B → $11.1B) | ★★★☆☆ ($1.42B AI segment) | ★★★★☆ ($4.09B → $18.7B) |
| **Market growth (CAGR)** | ★★★★★ (30%) | ★★★★★ (20%) | ★★★★☆ (19%) | ★★★★☆ (16%) |
| **BioMate readiness** | ★★★★★ (12 phases complete) | ★★★★☆ (QC done; stratification missing) | ★★★★☆ (pipeline complete; benchmarking missing) | ★★☆☆☆ (partial tools only) |
| **Time to first beta user** | ★★★★★ (Month 1) | ★★★★☆ (Month 2) | ★★★★☆ (Month 2) | ★★☆☆☆ (Month 5+) |
| **Academic paper fit** | ★★★★★ (Paper 4 ready) | ★★★★★ (Paper 1 RNA-seq; Paper 2 metadata) | ★★★★★ (Paper B benchmark) | ★★★☆☆ (Paper 2 metadata) |
| **Network building** | ★★★★★ (pharma + CRO + clinical) | ★★★★★ (hospital + oncology + diagnostics) | ★★★☆☆ (structural biology niche) | ★★★★☆ (Broad + 10x ecosystem) |
| **Clinical compliance fit** | ★★★★★ (21 CFR, FDA, CPIC) | ★★★★★ (CLIA/CAP audit trail) | ★★☆☆☆ (research only) | ★★★☆☆ (research-to-clinical path unclear) |
| **OVERALL PRIORITY** | **🥇 #1** | **🥈 #2** | **🥉 #3** | **4th** |

---

## All Validated References

| Topic | Citation | URL |
|---|---|---|
| AI Phase I success rate (80–90%) | Jayatunga et al., *Drug Discovery Today*, 2024 | [PubMed](https://pubmed.ncbi.nlm.nih.gov/38692505/) · [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S135964462400134X) |
| Industry Phase I baseline (52%) | BIO Clinical Development Success Rates 2011–2020 | [BIO.org](https://www.bio.org/clinical-development-success-rates-and-contributing-factors-2011-2020) |
| Dynamic trial success rates update | *Nature Communications*, 2025 | [Nature Comms](https://www.nature.com/articles/s41467-025-64552-2) |
| Rentosertib Phase 2a (first AI drug in Phase 2) | *Nature Medicine*, 2025 | [Nature Med](https://www.nature.com/articles/s41591-025-03743-2) · [PubMed](https://pubmed.ncbi.nlm.nih.gov/40461817/) |
| AI Drug Discovery market | GM Insights | [GMInsights](https://www.gminsights.com/industry-analysis/ai-in-drug-discovery-market) |
| AI Drug Discovery market | Grand View Research | [GVR](https://www.grandviewresearch.com/industry-analysis/artificial-intelligence-drug-discovery-market) |
| Leading AI drug platforms 2025 | *ScienceDirect* review | [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0031699725075118) |
| Recursion + Exscientia merger | Recursion IR | [Recursion IR](https://ir.recursion.com/news-releases/news-release-details/recursion-and-exscientia-two-leaders-ai-drug-discovery-space) |
| Single-cell analysis market | Precedence Research | [Precedence](https://www.precedenceresearch.com/single-cell-analysis-market) |
| Single-cell omics market | GlobeNewswire | [GlobeNewswire](https://www.globenewswire.com/news-releases/2025/11/05/3181538/0/en/Single-Cell-Omics-Market-to-Reach-USD-12-05-Billion-by-2034-Growing-at-a-16.14-CAGR-Towards-Healthcare.html) |
| Multiome Perturb-seq | *Cell Systems*, 2024 | [Cell Systems](https://www.cell.com/cell-systems/fulltext/S2405-4712(24)00366-1) · [PubMed](https://pubmed.ncbi.nlm.nih.gov/39689711/) |
| Compressed Perturb-seq (Genentech) | *Nature Biotechnology*, 2024 | [Nature Biotech](https://www.nature.com/articles/s41587-023-01964-9) · [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11035494/) |
| Spatial CRISPR screening | *Cell*, 2025 | [Cell](https://www.cell.com/cell/fulltext/S0092-8674(25)00197-7) |
| VIPerturb-seq (genome-wide) | *bioRxiv*, 2026 | [bioRxiv](https://www.biorxiv.org/content/10.64898/2026.02.12.705613v1.full) |
| PerturbSeq.db repository | *ScienceDirect*, 2025 | [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S002228362500275X) |
| 10x Genomics CRISPR screening | 10x Genomics | [10x Genomics](https://www.10xgenomics.com/products/single-cell-crispr-screening) |
| NGS RNA-seq market (20% CAGR) | Towards Healthcare / Mordor | [Towards Healthcare](https://www.towardshealthcare.com/insights/ngs-based-rna-sequencing-market-sizing) |
| RNA Analysis market ($23.39B by 2035) | GlobeNewswire, Feb 2026 | [GlobeNewswire](https://www.globenewswire.com/news-releases/2026/02/11/3236097/0/en/RNA-Analysis-Market-Size-Worth-USD-23-39-Billion-by-2035-Fueled-by-Expansion-of-RNA-Therapeutics-and-Precision-Medicine.html) |
| Transcriptomics for precision diagnosis | PMC review | [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10036914/) |
| Transcriptomics in drug discovery | *npj Drug Discovery*, 2025 | [npj](https://www.nature.com/articles/s44386-025-00029-y) |
| AML transcriptome stratification | *Nature Communications*, 2021 | [Nature Comms](https://www.nature.com/articles/s41467-021-22625-y) |
| AlphaFold3 | *Nature*, 2024 | [PubMed](https://pubmed.ncbi.nlm.nih.gov/38718835/) |
| AlphaFold3 + cryo-EM ligand fitting | *PLOS Computational Biology*, 2025 | [PLOS Comput Biol](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1013367) |
| Cryo-EM + AI review 2025 | *Frontiers Mol Biosci* | [Frontiers](https://www.frontiersin.org/journals/molecular-biosciences/articles/10.3389/fmolb.2025.1688455/full) · [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12590954/) |
| Cryo-EM drug discovery 2025 | *Expert Opinion Drug Discovery* | [PubMed](https://pubmed.ncbi.nlm.nih.gov/39789967/) · [Tandfonline](https://www.tandfonline.com/doi/full/10.1080/17460441.2025.2450636) |
| Cryo-EM AI image processing market | Growth Market Reports | [GMR](https://growthmarketreports.com/report/cryo-em-image-processing-ai-market) |
| Cryo-EM instruments market | Markets and Data | [Markets and Data](https://www.marketsandata.com/industry-reports/cryo-electron-microscopy-market) |

---

*BioMate AI LLC · biomate.ai · March 2026 · Confidential*
