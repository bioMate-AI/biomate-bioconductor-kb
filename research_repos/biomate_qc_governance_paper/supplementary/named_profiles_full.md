# Supplementary Note S2: Named QC Profile Catalogue — Complete Provenance
**BioMate QC Governance Stack — Paper 1 Supplementary Material**
**Last updated:** 2026-02-26

## Overview

BioMate ships 28 named QC profiles spanning 7 omics domains. Each profile is a curated set of threshold overrides that replaces platform defaults for a specific assay protocol or sample type. Profiles are applied at workflow launch via the `qc_profile` parameter and are overridden by any explicit per-invocation `qc_overrides`.

The evidence grading system mirrors the GRADE framework used in clinical medicine:
- **[GOLD]** — Community gold standard; widely adopted; override disabled
- **[SILVER]** — Strong literature support (≥ 2 independent studies)
- **[BRONZE]** — Expert consensus or single study; may be updated as evidence accumulates
- *(no tag)* — Platform default or nf-core community standard

Profile IDs map to the `QC_NAMED_PROFILES` constant in `backend/lib/galaxy/jobs/qc_trace_monitor.py`.

---

### RNA-seq

#### `rnaseq_polya_standard`

Standard polyA-selected RNA-seq (default). No adjustments from platform defaults.

*No threshold overrides — all platform defaults apply.*

**Evidence:**

- nf-core/rnaseq v3.14 defaults

---

#### `rnaseq_ribodepleted`

Total RNA with ribosomal depletion (RiboZero / RiboMinus). Ribo-depletion removes large rRNA fractions, producing more intronic reads that may not align to a spliced transcriptome reference — lowering effective alignment rate by 10–20 pp compared to polyA libraries.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `alignment_rate` | `50.0` |
| `reads_surviving_pct` | `65.0` |
| `assigned_reads_pct` | `40.0` |

**Evidence:**

- Zhao S et al. 2020 RNA Biol 17(8):1105-1118

---

#### `rnaseq_ffpe`

FFPE-preserved tissue RNA-seq. RNA is highly fragmented (median fragment 100–200 bp), resulting in lower alignment rates, reduced Q30 scores, and more trimming failures. Standard thresholds generate systematic false-positive gates on valid FFPE data.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `alignment_rate` | `45.0` |
| `reads_surviving_pct` | `60.0` |
| `q30_pct` | `65.0` |

**Evidence:**

- Sinicropi D et al. 2012 PLoS ONE 7(5):e38396

---

#### `rnaseq_single_nucleus`

Single-nucleus RNA-seq (snRNA-seq). Intronic reads dominate — alignment to a spliced mRNA reference is fundamentally lower than cytoplasmic RNA-seq. Duplicate rate check is suppressed: nuclear RNA is rare, so PCR amplification is necessary and duplicates do not indicate library quality problems.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `alignment_rate` | `50.0` |

**Evidence:**

- 10x Genomics snRNA-seq Reagent Kit User Guide v2.0 (2023)

---

#### `rnaseq_nonmodel_organism`

Non-model organism RNA-seq with an incomplete or draft genome/annotation. Unannotated genes produce unmapped reads and inflate 'unassigned' counts in feature counting. Thresholds are relaxed; interpretation requires care.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `alignment_rate` | `40.0` |
| `assigned_reads_pct` | `30.0` |

**Evidence:**

- [BRONZE] community practice — no formal guideline

---

### DNA-seq / WGS

#### `wgs_germline_standard`

Standard germline WGS (default). 30X minimum coverage per GATK Best Practices.

*No threshold overrides — all platform defaults apply.*

**Evidence:**

- GATK Best Practices — Germline SNP/Indel calling (2023)

---

#### `wgs_germline_lowpass`

Low-pass WGS (0.5–10X) for population genetics, imputation, and polygenic score studies. 4X minimum is the empirical floor for reliable imputation with modern reference panels (TOPMed / 1000G).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `4.0` |
| `duplicate_pct` | `60.0` |

**Evidence:**

- Rubinacci S et al. 2021 Nat Genet 53:120-126 (UK Biobank)

---

#### `wgs_somatic_tumor_only`

Somatic tumor-only WGS without a matched normal. Higher coverage is required to detect low-VAF mutations and distinguish somatic from germline variants. 80X is the GATK Mutect2 recommendation for tumor-only calling.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `80.0` |
| `duplicate_pct` | `50.0` |

**Evidence:**

- GATK Mutect2 Best Practices — Tumor-Only (2023)

---

#### `wgs_ffpe`

FFPE-derived WGS. FFPE artifacts (C→T and G→A transitions) require higher depth to filter reliably, but FFPE PCR bias substantially increases duplicate rates — a 65% duplicate threshold is supported by Robbe et al. 2018.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `30.0` |
| `duplicate_pct` | `65.0` |

**Evidence:**

- Robbe P et al. 2018 Nat Med 24:1555-1563

---

### DNA-seq / WES

#### `wes_research`

Research-grade whole-exome sequencing. 50X is sufficient for most germline variant discovery studies; clinical applications require wes_clinical_germline (80X).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `50.0` |

**Evidence:**

- nf-core/sarek v3 WES defaults

---

#### `wes_clinical_germline`

Clinical-grade WES for germline diagnostic reporting. 80X minimum is the ACMG 2016 technical standard for NGS-based clinical diagnostics.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `80.0` |

**Evidence:**

- ACMG/AMP 2016 Standards and Guidelines for NGS Diagnostics

---

#### `wes_somatic_tumor_normal`

WES of matched tumor-normal pairs for somatic variant calling. Matched-normal design requires ≥ 150X tumor depth (100X acceptable but 150X recommended) to reliably detect mutations with variant allele frequency (VAF) ≥ 5%. The normal sample typically requires ≥ 80X. This profile applies 150X as the minimum; the `mean_coverage` override applies to the tumor sample. Apply separately to normal via a separate override.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `150.0` |

**Evidence:**

- GATK Mutect2 Best Practices — Somatic SNV/Indel Calling (2023)
- Sims D et al. 2014 Nat Rev Genet 15:121-132

---

#### `wes_somatic_tumor_only`

WES of tumor without a matched normal (tumor-only mode). Without a germline comparator, higher depth is required to distinguish somatic mutations from germline variants and sequencing artifacts. GATK Mutect2 recommends ≥ 200X for reliable tumor-only somatic calling. Duplicate rate is relaxed to 50%: FFPE and archival tumor samples are expected to have higher PCR duplication.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mean_coverage` | `200.0` |
| `duplicate_pct` | `50.0` |

**Evidence:**

- GATK Mutect2 Best Practices — Tumor-Only Mode (2023)
- Sims D et al. 2014 Nat Rev Genet 15:121-132

---

### Single-cell RNA-seq

#### `scrna_standard`

Standard single-cell RNA-seq (10x Genomics Chromium, default).

*No threshold overrides — all platform defaults apply.*

**Evidence:**

- 10x Genomics Cell Ranger v7 defaults

---

#### `scrna_cardiac`

Single-cell RNA-seq from cardiac or skeletal muscle tissue. Cardiomyocytes are rich in mitochondria — a mito fraction of 30–40% is biologically expected and does NOT indicate dead/damaged cells. The standard 20% gate produces high false-positive rates in cardiac studies.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mito_fraction_pct` | `40.0` |
| `mito_fraction_pct_warning` | `25.0` |

**Evidence:**

- Simonson B et al. 2023 Circ Res 132(9):1174-1193
- Kuppe C et al. 2022 Nature 605(7909):319-326 (cardiac cell atlas)

---

#### `scrna_neuronal`

Single-cell RNA-seq from brain / neuronal tissue. Neurons have elevated mitochondrial content relative to non-neural tissues; 30% mito is an appropriate permissive gate. Median genes per cell may be lower for inhibitory interneurons (narrower transcriptome).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `mito_fraction_pct` | `30.0` |
| `mito_fraction_pct_warning` | `20.0` |
| `median_genes_per_cell` | `300` |

**Evidence:**

- [BRONZE] Allen Brain Atlas scRNA-seq QC guidelines (community practice)
- Bakken TE et al. 2021 Nature 598:86-102 (Human Brain Cell Atlas)

---

### Metagenomics

#### `metagenomics_human_gut`

Human gut metagenomics with a comprehensive database (Kraken2 Standard or RefSeq). The gut microbiome is well-characterised — 50% classification is the HMP empirical floor for Illumina data.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `classified_pct_critical` | `50.0` |
| `classified_pct_warning` | `60.0` |

**Evidence:**

- HMP Consortium 2012 Nature 486:207-214

---

#### `metagenomics_soil`

Soil metagenomics — high microbial 'dark matter' fraction. Even with a comprehensive database, soil samples routinely classify 5–40% of reads. Warning threshold is set at 8% (investigation if lower); critical gate is suppressed to 3%.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `classified_pct_critical` | `3.0` |
| `classified_pct_warning` | `8.0` |

**Evidence:**

- Bahram M et al. 2018 Nature 560(7717):233-237
- Delgado-Baquerizo M et al. 2018 Science 359(6373):320-325

---

#### `metagenomics_marine`

Marine metagenomics — reference databases cover ocean microbiota poorly. Open-ocean samples commonly classify 10–50% of reads depending on depth, season, and geographic location. Critical gate suppressed to 4%; warning threshold at 10%.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `classified_pct_critical` | `4.0` |
| `classified_pct_warning` | `10.0` |

**Evidence:**

- Sunagawa S et al. 2015 Science 348(6237):1261359 (TARA Oceans)

---

#### `metagenomics_clinical_pathogen`

Clinical metagenomics for pathogen detection (bloodstream infection, CSF). Samples should be dominated by human reads (which are not classified by Kraken2 without a human database entry) or by the pathogen. Very low classification (<60%) is unusual and warrants investigation.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `classified_pct_critical` | `60.0` |
| `classified_pct_warning` | `70.0` |

**Evidence:**

- [BRONZE] IDSA clinical metagenomics guidance (2024)

---

### Cryo-EM

#### `cryoem_spa_purified`

Standard single-particle analysis of purified protein complexes (default).

*No threshold overrides — all platform defaults apply.*

**Evidence:**

- EMPIAR deposition standards; EMDB validation report (2024)

---

#### `cryoem_spa_membrane`

Single-particle cryo-EM of membrane proteins (GPCRs, channels, transporters). Membrane proteins embedded in detergent micelles or nanodiscs exhibit higher beam-induced motion than soluble complexes. 80Å drift threshold is appropriate.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `total_drift_angstrom` | `80.0` |
| `fit_quality` | `0.65` |

**Evidence:**

- [BRONZE] Membrane protein cryo-EM community practice (2024)

---

#### `cryoem_tomo_in_situ`

Cryo-electron tomography of cellular lamellae prepared by FIB-SEM milling. In-situ cryo-ET has much higher drift (100–200Å) due to lamella thickness, carbon contamination, and beam-induced charging.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `total_drift_angstrom` | `150.0` |
| `fit_quality` | `0.5` |
| `correlation_score` | `0.3` |

**Evidence:**

- [BRONZE] FIB-SEM cryo-ET community practice; Bharat & Bharat 2024

---

#### `cryoem_spa_phase_plate`

Single-particle cryo-EM using a Volta Phase Plate (VPP) or fringe-free illumination (FFI). Phase plates enhance contrast for small or flexible complexes by adding a ~π/2 phase shift to the scattered electrons. Optimal collection keeps phase_shift_rad in the 0.2–1.5 rad window. CTF fit quality is relaxed from 0.70 to 0.65 because near-focus collection makes CTF estimation harder. The phase shift gate (advisory) triggers if the plate becomes depleted (< 0.2 rad) or over-accumulated (> 1.5 rad).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `fit_quality` | `0.65` |

**Evidence:**

- [SILVER] Danev R & Baumeister W 2016 eLife 5:e13046
- [SILVER] Bharat TAM & Scheres SHW 2015 Curr Op Struct Biol 35:79-86

---

### Proteomics

#### `proteomics_standard`

Standard label-free DDA proteomics of cell lysate (default). Applies GOLD PSM/protein FDR gate (Elias & Gygi 2007) and SILVER missed cleavage / CV gates (EuBIC 2018 community standards). Use for standard bottom-up LC-MS/MS protein identification.

*No threshold overrides — all platform defaults apply.*

**Evidence:**

- [GOLD] Elias & Gygi 2007, Nature Methods — PSM/protein FDR < 1%
- [SILVER] EuBIC 2018 community standards — missed cleavage < 20%, CV < 20%

---

#### `proteomics_phospho`

Phosphopeptide enrichment proteomics (TiO2, IMAC, Fe-NTA). PSM count is reduced by design after enrichment; phosphosite localization score > 0.75 is the primary quality indicator (Beausoleil et al. 2006). CV gate relaxed to 25% (enrichment adds technical variance). Missed cleavage gate relaxed to 30% (phosphopeptides resist tryptic digestion at pSer/pThr/pTyr sites).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `psm_count` | `500` |
| `missed_cleavage_pct` | `30.0` |
| `cv_pct` | `25.0` |

**Evidence:**

- [SILVER] Beausoleil et al. 2006, Nature Biotechnology — localization score > 0.75
- [BRONZE] EuBIC 2018 phosphoproteomics community practice

---

#### `proteomics_plasma_biomarker`

Depleted plasma DIA/DDA proteomics for biomarker discovery. Tighter CV gate (< 15%) required for biomarker-grade reproducibility (Geyer et al. 2017, Cell Systems). Missing value fraction gate applied (< 30% missing per protein). Lower protein FDR thresholds remain GOLD.

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `cv_pct` | `15.0` |
| `missing_value_pct` | `30.0` |

**Evidence:**

- [SILVER] Geyer et al. 2017, Cell Systems — plasma DIA proteomics CV standards
- [SILVER] EuBIC 2018 — depleted plasma QC community practice

---

#### `proteomics_chemoproteomics`

Affinity proteomics / chemoproteomics pulldown (ABPP, drug bead pulldown). Enrichment ratio gate (prey/input > 3×) is the primary quality indicator. Protein FDR gate remains GOLD (Elias & Gygi 2007). PSM count gate relaxed (pulldown reduces total protein coverage compared to whole lysate input).

**Threshold overrides from platform defaults:**

| Metric key | Value |
|------------|-------|
| `psm_count` | `200` |

**Evidence:**

- [GOLD] Elias & Gygi 2007 — protein FDR < 1% (unchanged)
- [SILVER] ABPP community practice — enrichment ratio > 3× input proteome

---

## Notes on Profile Precedence

1. Named profiles have **lower precedence** than explicit `qc_overrides` passed at workflow launch.
2. Named profiles do **not** override Red Line thresholds (Tier 0) or GOLD thresholds (Tier 1).
3. A profile's `domain_hint` is advisory — it is used for documentation only; the actual gate logic still reads `workflow_domain` from the workflow metadata.
4. Multiple profiles cannot be combined. If combined behavior is needed, use explicit `qc_overrides`.

*For the implementation, see `lib/galaxy/jobs/qc_trace_monitor.py` lines 68–419.*
