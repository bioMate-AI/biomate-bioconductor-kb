# Multi-Omics Gold Standard Benchmark Datasets
**Date:** 2026-07-19 | Purpose: Validate `rnaseq_proteomics_multiomics_integration` + `gwas_scrna_eqtl_target_chain` workflows

---

## Top 5 Datasets (ranked by relevance to conference contacts)

### 1. CLL MOFA2 Canonical Benchmark — use first
**Citation:** Argelaguet et al. 2018, *Molecular Systems Biology* (original MOFA paper)  
**Omics combination:** RNA-seq + DNA methylation (450K) + somatic mutations + drug response IC50  
**N:** 200 CLL patients, matched across 4 modalities (~40% missing values)  
**Access:** `BiocManager::install("BloodCancerMultiOmics2017")` — also built into the MOFA2 R package  

**Gold standard answer:**  
- Factor 1 separates IGHV-mutated vs IGHV-unmutated CLL (clinically established prognostic dichotomy)  
- Factor 2 = trisomy 12 copy number  
- Factor 1 IGHV-status AUROC ≈ 0.98  

**BioMate test query:** `modalities=rna,methylation` on BloodCancerMultiOmics2017  
**Pass criterion:** Factor 1 AUROC > 0.90 vs IGHV labels  

**Why use first:** Canonical MOFA2 benchmark. Any correct integration must reproduce this result. Fastest to obtain (1-line R install).

---

### 2. Banchereau SLE Longitudinal Multi-Omics — most relevant to autoimmune demos
**Citation:** Banchereau et al. 2016, *Cell* 165:551–565  
**Omics:** Whole blood microarray transcriptomics + 10 serum cytokines (IL-1β, IL-6, IL-17, IFN-α, BAFF…)  
**N:** 158 pediatric SLE patients (up to 4 years longitudinal, 924 timepoints) + 48 healthy controls  
**Access:** GEO **GSE65391** (transcriptomics); cytokine data in paper Supplementary Table S1  

**Gold standard answer:**  
- IFN signature (IFI6, IFI44L, IFIT1, RSAD2) is top factor  
- 7 patient clusters: neutrophil-, plasmablast-, monocyte-, T-cell-dominant  
- IFN module AUROC vs SLEDAI > 0.85  

**BioMate test query:** `modalities=rna,protein` (RNA=GSE65391, protein=cytokine table)  
**Pass criterion:** Complement OR IFN is top enriched GO term from Factor 1  

**Conference relevance:** Directly analogous to MG/CIDP responder stratification. Maps cleanly to Ruchi Gupta/Gilead use case (transcriptomic context layered on protein biomarkers).

---

### 3. RA Tofacitinib Multi-Omics Responder Prediction — best drug-response benchmark
**Citation:** Wei et al. 2025, *Frontiers in Immunology* (PMC12884169)  
**Omics:** RNA-seq + miRNA-seq + proteomics (LC-MS/MS) + untargeted metabolomics — all from PBMCs  
**N:** 14 RA patients (10 responders, 4 non-responders by EULAR DAS28)  
**Access:** ArrayExpress **E-MTAB-16533** (RNA-seq); external validation GEO **GSE253495**  

**Gold standard answer:**  
- RPL21 (ribosomal protein) = top baseline RNA predictor  
- APOA1 protein = top proteomic predictor (AUROC 78–100% for hub genes)  
- Ribosome pathway = top GSEA hit across CAMERA/ROAST/GSEA  

**BioMate test query:** `modalities=rna,protein,metabolomics`  
**Pass criterion:** Ribosome or APOA1 pathway in top 3 enriched terms  

**Caveat:** Small N (14), AUROC claims are high-variance — treat as directional not definitive.

---

### 4. MG GWAS+eQTL+pQTL Integration — directly on-topic for gwas_scrna_eqtl_target_chain
**Citation:** Chia et al. / Yu et al. 2024, *Nature Communications* (PMC10960998)  
**Omics:** GWAS summary stats + blood eQTLs (eQTLGen, n=31,684) + plasma pQTLs (ARIC/INTERVAL/KORA) + cell-type eQTLs (DICE, 15 immune cell types)  
**N:** 1,873 MG cases vs 36,370 controls; UK Biobank + FinnGen validation  
**Access:**  
- GWAS: GWAS Catalog **GCST90093061**  
- eQTLs: eqtlgen.org  
- Cell-type eQTLs: dice-database.org  
- pQTL: dbGAP (ARIC), European Genome-phenome Archive (INTERVAL)  

**Gold standard answer:**  
- **CTSH (Cathepsin H) in TH2 cells** — colocalization PP4 = 0.854  
- Replicated in both ARIC and INTERVAL pQTL cohorts  
- This is the druggable target the integration MUST surface  

**BioMate test query:** Run `gwas_scrna_eqtl_target_chain` with disease="Myasthenia Gravis"  
**Pass criterion:** CTSH appears in top 5 candidate genes with eQTL support score > 0  

**Conference relevance:** Direct functional test of Tarek Samad's workflow. Same analysis design as the CD40L indication expansion task.

---

### 5. COMBAT COVID-19 Multi-Omics Atlas — largest, 3-way combination test
**Citation:** The COMBAT Consortium, *Nature* 2022  
**Omics:** Whole blood transcriptomics + plasma proteomics + epigenomics + metabolomics + immune repertoire  
**N:** ~600 patients across COVID severity groups (critical, severe, moderate, mild, healthy)  
**Access:** COMBATdb: https://db.combat.ox.ac.uk — bulk download available; ArrayExpress + EGA accessions on portal  

**Gold standard answer:**  
- Myeloid activation (S100A8/S100A9/S100A12) = top discriminator of severe vs mild  
- Complement activation (C3, CFB, CFD) elevated in severe  
- Plasma APOE and TREM2 correlate with macrophage activation  
- Severity AUROC > 0.9 in cross-cohort validation  

**BioMate test query:** `modalities=rna,protein,metabolomics`  
**Pass criterion:** Complement enrichment p < 0.05; S100A8/S100A9 in top RNA weights  

**Conference relevance:** Best dataset for testing the 3-way combination. Complement signature directly relevant to Martin Kolev (Apellis/Biogen) and Salma Merchant (Alnylam).

---

## Evaluation Table

| Dataset | BioMate modalities | Expected top result | Pass criterion | Conference contact |
|---------|-------------------|--------------------|-----------------|--------------------|
| CLL BloodCancerMultiOmics2017 | `rna,methylation` | Factor 1 = IGHV status | AUROC > 0.90 | (methods validation) |
| GSE65391 SLE (Banchereau) | `rna,protein` | IFN signature Factor 1 | IFN or complement top GO term | Ruchi Gupta / Gilead |
| E-MTAB-16533 RA tofacitinib | `rna,protein,metabolomics` | RPL21 RNA, APOA1 protein | Ribosome pathway top hit | Beatrix Bartok / Biogen |
| GCST90093061 MG GWAS | GWAS chain | CTSH in TH2 (PP4=0.854) | CTSH in top 5 genes | Tarek Samad / Lundbeck |
| COMBAT COVID | `rna,protein,metabolomics` | S100A8/S100A9 + complement | Complement p < 0.05 | Martin Kolev, Salma Merchant |

---

## Implementation Plan

**Step 1 (fastest — do today):** Download CLL dataset via R, run `rnaseq_proteomics_multiomics_integration` with `modalities=rna,methylation`, verify Factor 1 AUROC > 0.90 vs IGHV labels.

**Step 2 (conference-relevant):** Download GSE65391 (SLE), run with `modalities=rna,protein`, check IFN/complement pathway enrichment. This is the Demo A benchmark.

**Step 3 (highest BD value):** Use GCST90093061 MG GWAS as input to `gwas_scrna_eqtl_target_chain`, verify CTSH surfaces as top candidate. This directly validates the Tarek Samad demo.

**Step 4 (post-conference):** COMBAT COVID 3-way integration for comprehensive validation.

---

## Notes

- CLL and SLE datasets are the highest priority for pre-conference validation given time constraints
- The MG GWAS benchmark (#4) is the most direct test of what we will demo to Tarek Samad
- For the COMBAT dataset, use the publicly downloadable PBMC subset (smaller than full cohort) to keep runtime manageable
- All datasets have matched sample IDs across modalities — critical for MOFA2 joint training

---

## 2024–2026 Additions (Latest Datasets)

Supplements the five canonical benchmarks above with the most recent published data. These are not yet run through BioMate — they are targets for post-conference validation.

---

### 6. MG CFD+CD14+ Monocytes — scRNA + GWAS (2026)
**Citation:** Li S, Zhang Y, Hou C, Chang T. "CFD+CD14+ monocytes: potential pathogenic subset in myasthenia gravis uncovered by multi-omics integration and machine learning analysis." *Frontiers in Immunology* 2026. DOI: 10.3389/fimmu.2026.1813107  
**Omics:** scRNA-seq (10 MG anti-AChR+ + 10 HC) + GWAS summary stats (GCST90093061) + eQTL (GTEx v8) + TWAS  
**N:** 10 MG + 10 HC (scRNA); RT-qPCR validation: 13 MG + 13 HC  
**Accessions:** GEO **GSE227835** (scRNA-seq); GWAS Catalog **GCST90093061** (shared with dataset #4)

**Gold standard answer:**  
- **CFD (complement factor D) marks pathogenic CD14+ monocytes** in MG  
- Complement/coagulation cascades + antigen processing are top enriched pathways  
- CFD expression in CD14+ monocytes discriminates MG from HC; validated by RT-qPCR

**BioMate test query:** `modalities=scrna` on GSE227835 with outcome=MG_vs_HC  
**Pass criterion:** CFD in top 20 marker genes for a CD14+ monocyte cluster  
**Conference relevance:** Complement angle directly relevant to Martin Kolev (Apellis) and Salma Merchant (Alnylam)

---

### 7. MG Platelet-Neutrophil Aggregates — scRNA + bulk RNA (2025)
**Citation:** Wen Q et al. "Platelet activation plays a pro-inflammatory role in myasthenia gravis." *Nature Communications* 16, 8779 (2025). DOI: 10.1038/s41467-025-63750-2. PMC12491536  
**Omics:** scRNA-seq (10X Genomics, 88,942 cells, 16 immune lineages) + bulk RNA-seq on purified platelets  
**N:** 209 newly diagnosed MG + 114 HC + 119 MMS (post-treatment minimal manifestation status)  
**Accessions:** No GEO listed — source data provided as supplementary file; contact authors or check paper repository link

**Gold standard answer:**  
- **Platelet-neutrophil aggregates (PNAs)** correlate with disease severity (QMG score R=0.46, p=0.00084)  
- **RANTES (CCL5)** is the pivotal mediator — elevated in plasma and platelets, drives pathological Th1 responses  
- PNA percentage normalizes after treatment (MMS group)

**BioMate test query:** `modalities=rna,scrna` — should surface CCL5 / platelet activation pathway  
**Pass criterion:** CCL5 or platelet activation term in top enriched pathways  
**Conference relevance:** Largest MG cohort (N=209). AChR+ biology relevant to Jessica VanBaaren (UCB) and Jeremy Sokolove (Vor)  
**Caveat:** No public accession confirmed — data may require direct request to first author

---

### 8. SLE Telitacicept Proteomics + Metabolomics — treatment responder (2026)
**Citation:** "Unveiling biomarkers of telitacicept's efficacy in SLE treatment through proteomics and metabolomics." *Frontiers in Immunology* 2026. DOI: 10.3389/fimmu.2026.1779880  
**Omics:** LC-MS/MS DIA proteomics (DIA-NN) + UHPLC-Orbitrap metabolomics (pos + neg ion mode), both from serum  
**N:** 25 SLE patients — 20 responders vs 5 non-responders (SRI-4 criteria; 80% response rate)  
**Accessions:** ProteomeXchange **PXD073923** (proteomics); OMIX **OMIX014815-01** (metabolomics)

**Gold standard answer:**  
- Protein biomarkers: **XPNPEP3** (AUC 0.891), **SRSF5** (0.802), **SRSF6** (0.800), WARS1, IDH1, ITLN1  
- Metabolite biomarkers: **pyruvate** (AUC 0.845, elevated in responders), **GABA** (AUC 0.920, elevated in non-responders)  
- Integrated mechanism: IDH1 + pyruvate → TCA cycle activation in responders

**BioMate test query:** `modalities=protein,metabolomics` (no RNA data in this study)  
**Pass criterion:** IDH1/TCA or XPNPEP3 in top differentially expressed features between responders/non-responders  
**Conference relevance:** Direct 2026 drug-response dataset. Most directly maps to Ruchi Gupta/Gilead use case. `protein + metabolomics` modality combo exercises the non-RNA multi-omics path.

---

### 9. MS Multi-Omics Drug Targets — GWAS + plasma + brain proteomics (PNAS 2025)
**Citation:** Yuan Jiang, Qianwen Liu, Pernilla Stridh, Xia Jiang. "Multiomics integration prioritizes potential drug targets for multiple sclerosis." *PNAS* 2025. DOI: 10.1073/pnas.2425537122  
**Omics:** Plasma proteomics (pQTL, 2,004 proteins) + brain proteomics (1,443 proteins) + GWAS (14,802 MS cases, 26,703 controls) + bulk + cell-type transcriptomics  
**N:** 14,802 MS cases for GWAS; pQTL summary stats from large population cohorts (UKBB, FinnGen)  
**Accessions:** GWAS summary stats from GWAS Catalog (IEU GWAS id: ebi-a-GCST005531); supplementary tables for 18-target list; full pQTL stats from ARIC/INTERVAL/UKBB portals

**Gold standard answer:**  
- **18 causal drug targets** identified (9 plasma, 9 brain)  
- Confirmed causal via Mendelian randomization + proteome-wide association + SMR colocalization PP > 0.7  
- Key targets include druggable kinases and complement proteins

**BioMate test query:** Run `gwas_scrna_eqtl_target_chain` with disease="Multiple Sclerosis"  
**Pass criterion:** At least 3 of the 18 published targets appear in BioMate's top 10 candidate genes  
**Conference relevance:** Large-scale MR validation provides a gold-standard gene list for measuring the target chain's precision

---

## Updated Evaluation Table (all datasets)

| # | Dataset | BioMate modalities | Expected top result | Pass criterion | Accession |
|---|---------|-------------------|--------------------|-----------------|----|
| 1 | CLL BloodCancerMultiOmics2017 | `rna,methylation` | Factor 1 = IGHV status | AUROC > 0.90 | BiocManager package |
| 2 | GSE65391 SLE Banchereau | `rna,protein` | IFN signature Factor 1 | IFN or complement top GO | GEO GSE65391 |
| 3 | E-MTAB-16533 RA tofacitinib | `rna,protein,metabolomics` | RPL21 RNA, APOA1 protein | Ribosome pathway top hit | ArrayExpress E-MTAB-16533 |
| 4 | GCST90093061 MG GWAS | GWAS chain | CTSH in TH2 (PP4=0.854) | CTSH in top 5 | GWAS Catalog GCST90093061 |
| 5 | COMBAT COVID | `rna,protein,metabolomics` | S100A8/S100A9 + complement | Complement p < 0.05 | COMBATdb |
| 6 | GSE227835 MG CFD+CD14+ (2026) | `scrna` | CFD in CD14+ monocytes | CFD in top 20 markers | GEO GSE227835 |
| 7 | MG platelet PNAs (2025) | `rna,scrna` | CCL5/platelet activation | CCL5 in top pathways | No public accession yet |
| 8 | PXD073923 SLE telitacicept (2026) | `protein,metabolomics` | IDH1 + pyruvate TCA | XPNPEP3 or IDH1 top hit | PXD073923 + OMIX014815-01 |
| 9 | MS PNAS 2025 GWAS chain | GWAS chain | 18 published targets | ≥3/18 in top 10 | GWAS Catalog + supplement |
