# QC Threshold Evidence & Rationale
**Date:** 2026-02-24
**Author:** BioMate Engineering
**Scope:** All thresholds in `qc_trace_monitor.py` and `parameter_suggester.py`

---

## Overview

This document records the authoritative source for every QC threshold used in BioMate's automated quality gate system. Thresholds without a citation are marked `[EMPIRICAL]` — they are reasonable defaults based on common practice but should be updated when domain-specific publications are identified.

**Confidence ratings:**
- `[GOLD]` — Published ENCODE, GATK, or nf-core standard; well-validated
- `[SILVER]` — Recommended by major tool authors; widely adopted
- `[BRONZE]` — Reasonable default based on community practice; no single canonical source
- `[EMPIRICAL]` — Set from first principles; needs literature validation

---

## Cryo-EM / Single-Particle Analysis

### MOTION_CORRECTION

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `total_drift_angstrom` | fail | > 50 Å | [SILVER] | CryoSPARC documentation; Grant & Grigorieff (2015) *eLife* 4:e06980 — beam-induced motion correction |
| `correlation_score` | fail | < 0.5 | [BRONZE] | CryoSPARC v4 output range; empirically set |

**Notes:** Total drift > 100 Å is almost always pathological (stage drift, electrostatic charging). 50 Å represents "moderate but correctable" motion. The correlation score threshold of 0.5 is conservative; CryoSPARC typically reports > 0.8 for good data.

### CTF_ESTIMATION

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `defocus_u_angstrom` | fail (out-of-range) | 1,000–100,000 Å valid | [SILVER] | CTFFIND4 documentation; Rohou & Grigorieff (2015) *JSB* 192:216-221 |
| `astigmatism_angstrom` | **advisory** (non-blocking) | > 1,000 Å | [BRONZE] | No published consensus threshold; community practice only |
| `fit_quality` | fail | < 0.7 | [SILVER] | CryoSPARC v4 CTF score scale (0–1); values < 0.7 indicate unreliable CTF estimates |

**Notes (astigmatism — Round 2 audit correction 2026-02-24):** After scientific literature review, no published consensus exists for using raw astigmatism as a hard gating criterion. Published high-resolution structures (< 3 Å) have been obtained from datasets with 500–2,000 Å astigmatism. The cryo-EM field uses `fit_quality` (CTF resolution) as the authoritative primary gate. The 500 Å threshold applied in the round 1 correction was overly strict and not backed by citable evidence.

**Current implementation:** astigmatism > 1,000 Å fires as an **advisory** informational item only — workflow is not blocked. `fit_quality < 0.7` remains the hard gate. Rating [BRONZE] acknowledges absence of a citable publication standard.

**What elevated astigmatism may indicate (operator reference only):**
- Contaminated objective lens
- Stage/beam tilt not accounted for
- Specimen charging

### PARTICLE_PICKING

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `particles_picked` | fail | < 1,000 | [BRONZE] | Minimum practical number for 2D classification; EMPIAR submission guidelines recommend ≥ 10,000 for high-resolution work |
| `duplicate_fraction` | fail | > 0.2 (20%) | [SILVER] | CryoSPARC particle curation defaults |

---

## RNA-seq

### FASTP / TrimGalore / Trimmomatic

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `reads_surviving_pct` | fail | < 70% | [SILVER] | nf-core/rnaseq pipeline default; ENCODE RNA-seq QC standards recommend ≥ 80% surviving trimming |
| Near-threshold warning | warn | 70–77% | [SILVER] | 10% margin above gate; consistent with nf-core monitoring |

### STAR / HISAT2 / BWA-MEM / Bowtie2 (alignment)

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `alignment_rate` | fail | < 70% | [SILVER] | nf-core/rnaseq pipeline; community consensus; ENCODE recommends ≥ 85% but no longer mandates it as a hard threshold in post-2020 standards |
| `alignment_rate` | fail (critical) | < 25% | [SILVER] | Widely accepted as indicative of species mismatch, contamination, or corrupt input (nf-core, GATK, STAR documentation) |
| Near-threshold warning | warn | 70–77% | [SILVER] | 10% margin above gate |

**Note (rating correction 2026-02-24):** Downgraded from [GOLD] to [SILVER]. ENCODE RNA-seq data standards (post-2020 update) no longer formally mandate 85% unique alignment as a hard threshold — they describe it as a target for high-quality data from well-annotated organisms. 70% as a minimum gate is reasonable community practice but not a formally published ENCODE requirement. [SILVER] is the correct rating.

**Reference:** ENCODE RNA-seq standards (2024): https://www.encodeproject.org/data-standards/rna-seq/
**Reference:** STAR manual alignment rate statistics

### featureCounts

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `assigned_reads_pct` | fail | < 50% | [SILVER] | nf-core/rnaseq pipeline; DESeq2 vignette recommends ≥ 60% for DGE analysis; 50% chosen as minimum |

### Salmon / Kallisto (quasi-mapping)

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `mapping_rate` | fail | < 50% | [SILVER] | Salmon documentation; Rob Patro recommends ≥ 70% for mRNA experiments; 50% as minimum for polyA depletion data |
| Near-threshold warning | warn | 50–55% | [SILVER] | 10% margin above gate |

---

## DNA-seq / Variant Calling

### FLAGSTAT (samtools)

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `mapped_pct` | fail | < 80% | [GOLD] | GATK Best Practices; < 80% mapped indicates serious quality issues |
| `duplicate_pct` | fail | > 40% | [GOLD] | GATK Best Practices WGS guidelines (typical: 10–25%; PCR-free: < 5%); 40% chosen as absolute maximum before results are unreliable |

### MARKDUPLICATES (Picard)

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `duplicate_pct` | fail | > 40% | [GOLD] | GATK Best Practices; dupRadar (PMC5073875): "for WGS, typical rates are 10–30%; > 40% is concerning" |
| RNA-seq / ATAC / ChIP / scRNA skip | — | domain-aware | [GOLD] | dupRadar (PMC5073875, Bioinformatics 2016): "fixed duplication thresholds are inappropriate for RNA-seq"; enriched-region assays (ChIP, ATAC) also exempt |

**Reference:** R. Sayols et al., "dupRadar: a Bioconductor package for the assessment of PCR artifacts in RNA-seq data" *BMC Bioinformatics* 17:428 (2016). DOI: 10.1186/s12859-016-1276-2

**Why we raised from 30% → 40%:** The old 30% threshold was arbitrary. GATK recommends flagging at 20–30% for *fresh tissue* WGS, but PCR-amplified libraries, FFPE samples, and low-input protocols routinely hit 35–40% without quality problems. We use 40% as the point where signal:noise is demonstrably degraded.

### Coverage Depth (mosdepth / Picard WGS Metrics)

| Metric | Sequencing type | Threshold | Rating | Source |
|--------|----------------|-----------|--------|--------|
| `mean_coverage` | WGS germline | ≥ 30X | [GOLD] | GATK Best Practices (WGS germline variant calling) |
| `mean_coverage` | WES germline | ≥ 80X | [GOLD] | GATK Best Practices; Illumina WES guidelines; Sims et al. (2014) *Nat Rev Genet* 15:121–132 |
| `mean_coverage` | WES somatic | ≥ 150X | [GOLD] | GATK somatic short mutation guidelines; typical clinical WES tumor/normal: 100–200X |

**Implementation note:** BioMate detects WES vs WGS from `workflow_domain`. Domains `wes`, `whole_exome`, `exome_seq`, `exome`, `targeted_seq` apply the 80X germline threshold. All other domains default to the 30X WGS threshold. Somatic WES (150X) is not yet automatically detected — tracked as a future improvement.

**Reference:** Sims, D. et al. "Sequencing depth and coverage: key considerations in genomic analyses." *Nat Rev Genet* 15, 121–132 (2014). DOI: 10.1038/nrg3642

---

## Single-Cell RNA-seq

### CellRanger / STARsolo / Alevin

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `cells_detected` | fail | < 200 | [BRONZE] | CellRanger QC guide; < 200 cells makes clustering unreliable; typical 10x Chromium target: 500–10,000 |
| `median_genes_per_cell` | fail | < 500 | [SILVER] | 10x Genomics cell quality guidelines; < 500 genes/cell often indicates dead or empty droplets |
| `mito_fraction_pct` | fail | > 20% | [BRONZE] | Permissive universal gate; see caveat below |
| `mito_fraction_pct` | warn (near-threshold) | 10–20% | [BRONZE] | sc-best-practices.org advisory: ≤ 10% for standard tissues |

**Mitochondrial fraction caveats (Round 2 audit correction 2026-02-24):**
Rating downgraded from [SILVER] to [BRONZE]. Evidence review:
- sc-best-practices.org (Luecken et al. 2022, biases toward 8–10% cap for human PBMCs)
- Seurat v5 default filter: 5% mitochondrial reads
- Osorio & Cai (2021) PMC8599307: 5% mouse, 10% human ideal thresholds
- Cardiac and muscle cells legitimately exceed 20% due to high respiratory activity
- Published meta-analyses suggest adaptive MAD-based thresholds outperform fixed gates

**Current implementation:** Hard gate > 20% (permissive universal default). Near-threshold advisory warning 10–20% (informational; workflow not blocked). The 20% gate catches truly compromised samples while accommodating high-respiration cell types. Tissue-specific thresholds require cell-type metadata not currently available at QC time.

---

## ChIP-seq

### MACS2 / MACS3

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `peaks_called` | fail | < 1,000 | [SILVER] | ENCODE ChIP-seq standards; experiments with < 1,000 peaks are considered failed; high-quality TF ChIP should yield 5,000–50,000 peaks |

**Gaps (Task #47):**
- FRiP (Fraction of Reads in Peaks): ENCODE requires ≥ 0.01 (TF), ≥ 0.1 (histone marks)
- NRF (Non-Redundant Fraction): ENCODE requires ≥ 0.8 (ENCODE3), ≥ 0.9 (ENCODE4)

**Reference:** ENCODE ChIP-seq standards: https://www.encodeproject.org/chip-seq/transcription_factor/

---

## Metagenomics

### Kraken2 / Bracken / MetaPhlAn / Kaiju

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `classified_pct` | fail (critical) | < 30% | [SILVER] | Wood, Lu & Langmead (2019) *Genome Biology* 20:257 (Kraken2 paper); < 30% indicates possible database mismatch, contamination, or highly divergent organisms |
| `classified_pct` | fail (warning) | 30–60% | [BRONZE] | QIIME2 community practice; HMP data typically 60–90% (human-associated); **soil/environmental: typical range 40–58%** |
| Near-threshold warning | warn | 60–66% | [BRONZE] | 10% margin above 60% gate |

**Why we changed from flat 30% → tiered (30%/60%):**
The old 30% floor was vastly too permissive. For human microbiome samples, the Human Microbiome Project (HMP) reports 70–95% classification; values 30–60% warrant investigation. The 60% warning tier is reasonable for human-associated and gut microbiomes.

**⚠️ Soil / environmental metagenomics caveat (Round 2 audit finding):**
The 60% tier may be too strict for environmental and soil metagenomics. Published soil studies with standard Kraken2 databases (RefSeq + Viral) report classification rates of 40–58%, even from well-characterized samples (Illumina HiSeq, comprehensive databases). The < 30% critical gate remains valid for all sample types. The 30–60% warning tier should be interpreted in the context of sample type: expected for soil/ocean/rhizosphere metagenomics; concerning for gut/clinical samples. Ratings downgraded from [SILVER] to [BRONZE] for the warning tier.

**Reference:** D.E. Wood, J. Lu & B. Langmead, "Improved metagenomic analysis with Kraken 2" *Genome Biology* 20:257 (2019). DOI: 10.1186/s13059-019-1891-0

---

## FastQC / MultiQC

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `module_failures` | fail | > 0 | [SILVER] | FastQC documentation; any FAIL module indicates actionable quality issues; WARN modules are acceptable |

---

## Near-Threshold Warning System

All warnings use a 10% headroom above the gate threshold to catch approaching problems before they trigger hard gates:

| Domain | Metric | Gate | Warning Range |
|--------|--------|------|--------------|
| Alignment | `alignment_rate` | < 70% | 70–77% |
| Trimming | `reads_surviving_pct` | < 70% | 70–77% |
| Quasi-mapping | `mapping_rate` | < 50% | 50–55% |
| Metagenomics | `classified_pct` | < 60% | 60–66% |
| scRNA-seq | `mito_fraction_pct` | > 20% | 10–20% (elevated, approaching gate) |

---

## Missing Metrics — Planned (Task #47 & #48)

| Domain | Metric | Standard | Priority |
|--------|--------|----------|----------|
| DNA-seq | Coverage depth (mosdepth) — WES distinction | GATK: ≥ 80X WES germline, ≥ 150X WES somatic (30X WGS implemented) | High (partially implemented) |
| ChIP-seq | FRiP score | ENCODE4: ≥ 0.01 TF, ≥ 0.1 histone | High |
| ChIP-seq | NRF | ENCODE4: ≥ 0.9 | High |
| scRNA-seq | Mitochondrial fraction | Luecken & Theis 2019: ≤ 20% | High |
| RNA-seq | rRNA fraction | < 10% for mRNA; < 5% for ribo-depleted | Medium |
| Cryo-EM | FSC 0.143 resolution criterion | EMDB gold standard | Medium |
| ATAC-seq | TSS enrichment score | ENCODE4: ≥ 7 | High (Task #48) |
| ATAC-seq | FRiP | ENCODE4: ≥ 0.3 | High (Task #48) |
| ATAC-seq | NRF | ENCODE4: ≥ 0.9 | High (Task #48) |

---

## ATAC-seq QC Domain (implemented 2026-02-24)

| Metric | Gate | Threshold | Rating | Source |
|--------|------|-----------|--------|--------|
| `tss_enrichment` | fail (warning) | < 5.0 | [GOLD] | ENCODE4 ATAC-seq (human GRCh38): < 5 unacceptable, 5–7 acceptable, > 7 ideal |
| `tss_enrichment` | fail (critical) | < 3.0 | [GOLD] | Below 3 = near-complete loss of signal-to-noise |
| `frip_score` | fail | < 0.2 | [GOLD] | ENCODE4 ATAC-seq: > 0.3 ideal, > 0.2 acceptable. EN-TEx tissue samples exempt. |
| `nrf_score` | fail (warning) | < 0.9 | [GOLD] | ENCODE4: NRF ≥ 0.9 (NRF = Distinct/Total; different from PBC1 = One/Distinct) |
| `nrf_score` | fail (critical) | < 0.5 | [GOLD] | < 0.5 = severe PCR amplification bias |

**Mouse caveat:** ENCODE4 TSS thresholds for mm10 are 10 (acceptable) and 15 (ideal) — 2× higher than human. Current implementation uses human thresholds. Add genome-awareness when pipeline metadata is available.

**NRF vs PBC1:** Both have ≥ 0.9 ENCODE4 threshold but are different metrics. `pbc.txt` column 4 (0-indexed) is NRF; column 5 is PBC1. The code reads the correct column.

---

## Expert Audit Corrections (2026-02-24)

Applied after dual expert audit (code analysis + web research against ENCODE4/GATK/literature):

| Change | Old | New | Reason |
|--------|-----|-----|--------|
| scRNA-seq mito threshold | > 25% | > 20% | Osorio & Cai 2021 (PMC8599307): 5% mouse, 10% human ideal; 25% too permissive |
| ATAC FRiP gate | < 0.3 | < 0.2 | ENCODE4: > 0.3 ideal but > 0.2 is explicitly "acceptable" |
| ChIP FRiP | hard gate | advisory (non-blocking) | ENCODE4 explicitly has NO hard FRiP threshold; 0.01 is ENCODE2/3 historical guideline only; workflow not blocked |
| MARKDUPLICATES skip | rna_seq, rnaseq, scrna_seq | + atac_seq, atacseq, chip_seq, chipseq, cut_and_run | Open-chromatin assays have expected duplication from enriched regions |
| Metagenomics citation | Wood & Salzberg 2019 | Wood, Lu & Langmead 2019 | 2019 paper is Kraken2; Wood & Salzberg is 2014 Kraken1 |
| MetagenomicsParameterSuggester | only < 30% | now < 60% | Suggestions now also fire in 30-60% warning zone |
| Coverage "total" line detection | broad `"total" in line.lower()` | specific `line.startswith("total\t")` | Prevents false match on contig names like "total_rRNA" |
| CTF astigmatism suggestion | > 1000 | > 500 | Aligned with updated gate threshold |

## Round 2 Expert Audit Corrections (2026-02-24)

Applied after second dual expert audit (deeper code analysis + expanded web research against current ENCODE4/sc-best-practices/GATK documentation):

| Change | Old | New | Reason |
|--------|-----|-----|--------|
| CTF astigmatism gate | hard gate at 500Å [SILVER] | advisory at 1000Å [BRONZE] | No published consensus; field uses fit_quality as primary gate; published high-res structures have 500–2000Å astigmatism |
| CTF astigmatism routing | qc_gate_triggered (blocking) | qc_warning (advisory, non-blocking) | Advisory items no longer block workflow |
| ChIP FRiP routing | qc_gate_triggered despite advisory flag | qc_warning (advisory path) | Fixed: advisory=True items now correctly route to warning event, not gate event |
| NRF parser | `if metrics.get("nrf_score"): break` | `if "nrf_score" in metrics: break` | Python falsy-value bug: NRF=0.0 evaluates as False; parser never stored the value |
| MARKDUPLICATES skip | missing "rna", "single_cell" | + "rna", "single_cell" added | Short-form domain names not covered; causes false MARKDUP gate on RNA-seq |
| RNA-seq alignment rating | [GOLD] | [SILVER] | ENCODE post-2020 standards don't formally mandate 85% minimum; 70% gate is community practice |
| Metagenomics warning tier | [SILVER] | [BRONZE] | 60% tier is too strict for soil/environmental metagenomics (typical 40–58% with good DBs) |
| WGS coverage gate | single 30X for all | WGS: 30X, WES: 80X germline | SIGNIFICANT ERROR: WES requires 80X germline, 150X somatic — single 30X gate was wrong for WES |
| scRNA mito rating | [SILVER] | [BRONZE] | sc-best-practices recommends 8–10%; cardiac/muscle exceed 20% naturally; fixed threshold inappropriate |
| scRNA mito near-threshold warning | none | 10–20% advisory warning | Added in _check_qc_warnings; sc-best-practices recommends ≤ 10% for standard tissues |

---

## Version History

| Date | Change | Author |
|------|--------|--------|
| 2026-02-24 | Initial document; astigmatism 1000→500Å; MARKDUPLICATES domain-aware + 40%; metagenomics tiered 30%/60% | BioMate Engineering |
| 2026-02-24 | Post-audit #1 corrections: mito 25→20%, ATAC FRiP 0.3→0.2, ChIP FRiP→advisory flag, MARKDUP skip extended, metagenomics citation, NRF/PBC1 clarification | BioMate Engineering |
| 2026-02-24 | Post-audit #2 corrections: CTF astigmatism [BRONZE]+advisory+1000Å; NRF falsy-value bug; ChIP FRiP truly non-blocking; WES/WGS coverage split; MARKDUP skip "rna"+"single_cell"; RNA-seq [GOLD]→[SILVER]; mito [BRONZE]+near-threshold warning; metagenomics soil caveat+[BRONZE] | BioMate Engineering |
