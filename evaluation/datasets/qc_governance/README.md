# QC Governance Benchmark Dataset

**Status:** Construction spec — requires defect injection + expert labeling  
**Target size:** ~50 labeled samples (5 base datasets × ~10 variants each)  
**Effort:** 2 bioinformaticians × 2 days + 1 developer day  

## Purpose

Tests BioMate's GOLD/SILVER/BRONZE evidence-graded QC governance against MultiQC
and nf-core defaults. Controlled defects are injected into public datasets so that
the "correct" QC action (PASS/WARN/FAIL + suggested fix) is known a priori.

**Core claim:** BioMate achieves ≥90% sensitivity on QC failures with ≥20% fewer
false FAILs than MultiQC on protocol-specific edge cases.

## Base datasets

| ID | GEO/ENCODE accession | Type | Why chosen |
|---|---|---|---|
| D1 | ENCSR000AED | RNA-seq, GM12878 | Clean reference; establishes baseline |
| D2 | GSE68086 | FFPE RNA-seq | Protocol edge case: high degradation expected |
| D3 | GSE121893 | scRNA-seq, cardiac | Protocol edge case: low UMI expected |
| D4 | SRP047083 | Metagenomics, soil | Complex community; rRNA contamination risk |
| D5 | ENCSR356LIU | ATAC-seq, flagged | Already flagged in original paper |

## Defect categories (3 per dataset = 15 total defect sets + 5 unmodified controls)

### Category A — Silent quality failures (naive tools miss these)
| Defect | How to inject | Expected BioMate action |
|---|---|---|
| rRNA contamination ≥30% | `seqtk sample` + cat rRNA FASTQ | FAIL → suggest rRNA depletion |
| Adapter dimers ≥15% | Append adapter to 15% of reads | FAIL → suggest trimming |
| Mid-cohort protocol switch | Swap library prep label for 3 samples | WARN → flag batch effect |

### Category B — Near-threshold ambiguity (tools disagree)
| Defect | How to inject | Expected BioMate action |
|---|---|---|
| Duplication rate at 95% of threshold | Adjust via `samtools view` downsampling | WARN (not FAIL) |
| GC content 2% above expected | Replace 2% of reads with GC-skewed synthetic | WARN |

### Category C — Protocol-specific edge cases (naive tools false-alarm)
| Case | Expected naive action | Expected BioMate action |
|---|---|---|
| D2 FFPE: high degradation | FAIL (low RIN) | PASS with FFPE profile |
| D3 scRNA-seq: low UMIs | FAIL (low complexity) | PASS with low-input profile |
| D4 metagenomics: high rRNA | FAIL (rRNA contamination) | PASS (expected for 16S) |

## Construction steps

```bash
# Step 1: Download base datasets
cd evaluation/datasets/qc_governance/
python ../../scripts/inject_qc_defects.py --download-only

# Step 2: Inject defects
python ../../scripts/inject_qc_defects.py --inject-all

# Step 3: Run QC tools on all samples
python ../../scripts/inject_qc_defects.py --run-qc

# Step 4: Expert labeling
# Fill out labels.yaml following the template in labels_template.yaml

# Step 5: Validate inter-rater agreement
python ../../scripts/inject_qc_defects.py --validate-labels labels.yaml
```

## Labeling schema

```yaml
# labels.yaml — one entry per sample variant
- sample_id: D1_rRNA_contamination_30pct
  base_dataset: ENCSR000AED
  defect_category: A
  defect_type: rRNA_contamination
  correct_action: FAIL
  correct_suggested_fix: "Run rRNA depletion (RiboZero or similar)"
  confidence: HIGH
  rater_1: yzhang
  rater_2: <second_rater>
  rater_1_decision: FAIL
  rater_2_decision: FAIL
  agreement: true
```

## Expected output

After running all 3 QC systems on the labeled dataset:

```
evaluation/datasets/qc_governance/
├── samples/              # Modified FASTQ files (stored in S3, not git)
├── qc_results/
│   ├── multiqc/          # MultiQC HTML + JSON results
│   ├── nfcore/           # nf-core QC pipeline results
│   └── biomate/          # BioMate QC decisions (JSONL audit trail)
├── labels.yaml           # Expert ground truth labels
└── scores.json           # Sensitivity/specificity for each system
```

## S3 storage

Raw FASTQ files (modified): `s3://biomate-eval/qc_governance/samples/`  
QC stats (processed): stored locally in `qc_results/` (small, tracked in git)  
Cost: ~5 GB raw data, ~$0.12/month S3 storage
