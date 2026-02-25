# BioMate Multi-Paper Publication Strategy
**Date:** 2026-02-25 15:45
**Status:** Active planning — 4-paper arc
**Scope:** QC governance, drug discovery, proteomics, PK/PD

---

## Overview

BioMate's core novelty is **machine-readable, evidence-graded QC governance** — a formally layered threshold system where citation evidence quality determines overridability. This enables reproducible multi-omics analysis at the protocol level rather than the parameter level.

**Six papers total.** Two run in parallel immediately (Proteomics + Cryo-EM). Four form a sequential arc.

---

## Active Parallel Papers (Start Now)

| Paper | Journal target | Folder | Status |
|---|---|---|---|
| **Proteomics QC** | MCP / J Proteome Res | `research_repos/biomate_proteomics_paper/` | Plan written; build phase next |
| **Cryo-EM SPA** | Nature Methods / Nat Comms | `research_repos/cryo_em_benchmark_paper/` | Pipeline implemented; benchmark runs needed |

See individual paper plans for full contribution/innovation statements.

---

## Sequential Arc Papers

---

## Paper 1 — Nature Methods (~Month 9)

**Title:** "BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale"

**Folder:** `research_repos/biomate_qc_governance_paper/`

**Core claim:** A 4-layer governance stack (Red Lines → GOLD → SILVER → BRONZE) with 20 named protocol-aware profiles reduces silent QC failures across 6 sequencing domains while enabling non-expert users to run protocol-appropriate analyses with audit-trailed decisions.

**Domains:** RNA-seq, scRNA-seq, WGS/WES, ATAC-seq, metagenomics, cryo-EM

**Benchmark datasets (all public):**
| Accession | Domain | Role |
|---|---|---|
| ENCSR000AED | RNA-seq, GM12878 | True negative (should pass cleanly) |
| GSE68086 | FFPE RNA-seq | Profile validation (rnaseq_ffpe profile) |
| GSE121893 | Cardiac scRNA-seq | Profile validation (scrna_cardiac profile) |
| SRP047083 | Soil metagenomics | Profile validation (metagenomics_soil profile) |
| ENCSR356LIU | ATAC-seq, flagged | True positive (ENCODE internally flagged) |

**Comparators:** MultiQC standalone, nf-core default QC checks

**Co-authors needed:**
- ENCODE contributor (validates ATAC/ChIP thresholds)
- Wet-lab PI running multi-omics at scale (core facility director ideal)
- Bioinformatics methods author with Nature Methods publication history
- Domain expert: single-cell (cardiac mito profile), RNA-seq (FFPE profile), cryo-EM (FSC gap)

**Minimum evidence:**
- Confusion matrix: BioMate vs MultiQC on 5 benchmark datasets
- 20 usability sessions (2 cohorts, wet-lab biologists with no bioinformatics training)
- Pilot-vs-full cost experiment (parameter error → early stop saves $X)
- 422+ unit tests as supplementary

**P0 backend gaps to fix before submission:**
- Hi-C false-positive duplication gate (`_skip_domains` missing "hic")
- WES somatic 150X auto-detection
- Sequencing saturation from CellRanger `metrics_summary.csv`
- FSC 0.143 gate for cryo-EM
- Near-threshold warnings for coverage/TSS/NRF

---

## Paper 2 — Genome Biology (~Month 15)

**Title:** "Protocol-aware QC threshold inference for heterogeneous sequencing cohorts using metadata-driven governance"

**Core claim:** Mapping sample metadata (tissue, organism, library prep) to protocol-appropriate QC profiles is a tractable ML classification problem; protocol-mismatched QC causes measurable false positive/negative rates correctable at GEO scale.

**Novel contribution:** Phase 3 of the governance stack — metadata-inferred profile suggestion. Training data: 500,000+ GEO samples with structured metadata and known protocols.

**What to pre-register:** Benchmark protocol and classifier design on OSF/protocols.io before running.

**Co-authors needed:**
- Biomedical ontology expert (EFO/OBI/UBERON — EBI or Jackson Lab)
- GEO/SRA metadata quality expert (NCBI collaboration)

---

## Paper 3 — Nature (~Month 24)

**Title:** "Systematic QC-driven biases in the Human Cell Atlas and their correction via protocol-aware governance"

**The experiment:** Download all 600+ HCA scRNA-seq datasets (~50M cells, public). Apply BioMate's protocol-appropriate QC to every dataset. Compare to original paper QC decisions. Show that existing HCA cell type proportions contain systematic biases — metabolically active cells (cardiac, kidney, hepatocytes) are over-excluded by labs using fresh-frozen mito thresholds on high-mito tissues.

**Why Nature:** Widely-used single-cell reference atlases contain correctable, systematic biases that propagate into deconvolution (CIBERSORT, MuSiC), trajectory, and cell communication analyses across thousands of downstream papers.

**Compute cost:** ~$8,000–12,000 on AWS Batch. Less than a single mouse experiment.

**Key risk:** If proportions are unchanged by re-QC, the finding is "HCA is remarkably robust" — also publishable.

**Co-authors needed:**
- HCA consortium team member (approach as collaborator, not competitor)
- Disease-focused PI whose patients are in the cohort
- Biostatistician (batch correction across 600+ studies requires rigorous treatment)

---

## Paper 4 — Nature Chemical Biology (~Month 30)

**Title:** "Evidence-graded QC governance for drug discovery workflows: proteomics, ADMET, and pharmacogenomics"

**Folder:** `research_repos/biomate_drug_discovery_paper/`

**Three QC governance claims:**

1. **Proteomics (LC-MS/MS):** PSM/protein FDR governance (GOLD, Elias & Gygi 2007) + phosphosite localization gates + label-free quantification CV gates — using mzQC (HUPO-PSI standard) as the schema. Covers target identification (affinity proteomics), mechanism of action (phosphoproteomics), biomarker validation (plasma proteomics).

2. **ADMET / compound QC:** SMILES structure validation before prediction (15% of ChEMBL compounds have SMILES errors per Whitehead et al. 2022 J Chem Inf). Governance layer prevents invalid inputs from corrupting ADMET predictions.

3. **Pharmacogenomics from WGS:** CYP gene minimum coverage gate (30x for PGx variant calls), VQSR PASS rate, star allele confidence governance — direct link to CPIC dosing guidelines.

**Co-authors needed:**
- Pharma/CRO collaborator with real LC-MS screening data
- Clinical pharmacogenomics researcher (CPIC contributor ideal)
- LC-MS proteomics expert (mzQC familiarity)

---

## Domain Expert Connections → Papers

| Expert available | Primary paper | Role |
|---|---|---|
| Single-cell | Paper 1 + Paper 3 | Validate cardiac mito profile; HCA reanalysis co-author |
| RNA-seq | Paper 1 | Validate FFPE/ribodepleted profiles; rRNA gate design |
| Cryo-EM | Paper 1 | Validate FSC 0.143 gap; membrane protein profile |
| GWAS | Paper 1 extension | Add GWAS QC domain (~2 days backend; see GWAS section) |
| Drug in vivo prediction | Paper 4 | Pharmacogenomics + ADMET QC governance design |

---

## Community Adoption Strategy

**Target: 5 core facility partners + 2 consortium adoptions before Nature submission**

| Milestone | Timeline | What It Unlocks |
|---|---|---|
| 5 benchmark datasets staged to S3 | Month 1 | All downstream experiments |
| ISMB/BOSC 2026 talk | Month 6 | Community awareness |
| Paper 1 submitted | Month 9 | Platform credibility |
| BQES spec submitted to GA4GH | Month 12 | Standardization pathway |
| Paper 2 submitted | Month 15 | Methods credibility |
| HCA reanalysis complete | Month 18 | Nature paper data |
| Paper 3 submitted | Month 24 | Field-level impact |
| Paper 4 submitted | Month 30 | Pharma adoption |
| GA4GH BQES standard ratified | Month 36 | Permanent infrastructure status |

**Competitive moat (3 things that cannot be replicated):**
1. The governance knowledge graph — version-controlled, citation-backed (assay, protocol, tissue) → threshold set. Analogous to PharmGKB for pharmacogenomics.
2. The audit trail — every QC decision logged with evidence level + override approver. Required for FDA 21 CFR Part 11 and CAP/CLIA compliance.
3. The biological discovery record — once the HCA reanalysis is published in Nature as enabled by BioMate, no engineering investment replicates that.

---

## GWAS Domain Addition (~2 days backend)

If a GWAS collaborator is available, add GWAS QC to Paper 1 scope:

| Metric | Evidence Level | Threshold |
|---|---|---|
| Sample call rate | GOLD | > 98% |
| SNP call rate | GOLD | > 98% |
| Hardy-Weinberg equilibrium | GOLD | p > 1×10⁻⁶ (controls) |
| Sex concordance | SILVER | ChrX het ratio within expected range |
| Kinship / relatedness | SILVER | PI-HAT < 0.185 (removes 2nd-degree relatives) |
| PC outlier | SILVER | Within 6 SD of population centroid |
| Differential missingness | BRONZE | Case-control missingness difference < 10⁻⁵ |
| Ti/Tv ratio | BRONZE | ~2.0–2.1 for WGS, ~3.0–3.3 for WES |

Output: PLINK2 `.log` + `.smiss` + `.vmiss` parsers feeding into `_check_qc_thresholds()`.

---

*See individual paper folders under `research_repos/` for detailed manuscript plans.*
