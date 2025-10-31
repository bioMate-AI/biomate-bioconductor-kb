# bioMate Instrument Connection Workflows - Real-World Scenarios

**Document Created:** 2025-10-30 15:45:00 UTC
**Last Updated:** 2025-10-30 15:45:00 UTC
**Author:** bioMate Development Team
**Version:** 1.0.0
**Scenario Date:** 2025-10-30 (All examples use this date for consistency)

---

## Overview

This document illustrates typical workflows for laboratories using bioMate with instrument connections, showing the complete data flow from instrument to analysis with timestamped file examples.

---

## Scenario 1: Clinical Diagnostics Laboratory

**Lab Profile:**
- Hospital clinical chemistry department
- 50-100 patient samples per day
- Instruments: Roche Cobas C311 (chemistry), Sysmex XN-1000 (hematology)
- Goal: Automated results reporting, quality control, trend analysis

### Morning Routine - Chemistry Panel (8:00 AM - 9:30 AM)

#### Step 1: Morning QC Run (8:00 AM)

**Technician:** Runs daily quality control samples on Cobas C311

```
Local Instrument PC:
C:\Cobas\Results\
└── 2025-10-30\
    └── QC_20251030_080015.csv
```

**File Content Preview:**
```csv
SampleID,TestCode,Result,Unit,RefRange,QCLevel,Status,Timestamp
QC_L1,GLU,95,mg/dL,70-100,Level1,PASS,2025-10-30T08:00:15Z
QC_L1,CHOL,185,mg/dL,<200,Level1,PASS,2025-10-30T08:00:18Z
QC_L2,GLU,245,mg/dL,200-300,Level2,PASS,2025-10-30T08:02:22Z
```

#### Step 2: Auto-Transfer to bioMate (8:05 AM)

**Method:** Network share monitoring service

```bash
# Windows network share mounted on bioMate server
/mnt/instruments/cobas/
└── incoming/
    └── QC_20251030_080015.csv  [transferred at 08:05:12]
```

**bioMate Service Log:**
```
[2025-10-30 08:05:12] FileWatcher detected: QC_20251030_080015.csv
[2025-10-30 08:05:13] Routing to OpenELIS client (Cobas_C311)
[2025-10-30 08:05:15] OpenELIS import successful: 6 QC results
[2025-10-30 08:05:16] Galaxy dataset created: qc_results_f2a8e9c1
[2025-10-30 08:05:17] S3 upload: s3://biomate-instruments/2025/10/30/QC_20251030_080015.csv
```

**Files Created in bioMate:**
```
/var/lib/biomate/
├── data/
│   └── uploads/
│       └── 2025-10-30/
│           ├── QC_20251030_080015.csv
│           └── QC_20251030_080015_parsed.json
└── logs/
    └── instrument_imports/
        └── 2025-10-30_08-05-12_cobas_qc.log

Galaxy Instance:
/galaxy/database/files/
└── 002/
    └── dataset_2145.dat  [qc_results_f2a8e9c1]

S3 Bucket:
s3://biomate-instruments/
└── 2025/10/30/
    ├── QC_20251030_080015.csv
    └── QC_20251030_080015_metadata.json
```

#### Step 3: Patient Samples Processing (8:30 AM - 9:30 AM)

**Technician:** Loads 45 patient samples into Cobas C311

```
Cobas Run Progress:
08:30 - Start run: 45 samples (CMP + Lipid panels)
08:35 - Sample 1-10 complete
08:45 - Sample 11-20 complete
09:00 - Sample 21-30 complete
09:15 - Sample 31-40 complete
09:25 - Sample 41-45 complete
09:30 - Run complete, exporting results...
```

**Instrument Exports:**
```
C:\Cobas\Results\2025-10-30\
├── Patient_Batch_001_20251030_093142.csv  (Primary results)
└── Patient_Batch_001_20251030_093142.hl7  (HL7 for LIS integration)
```

#### Step 4: Auto-Import to bioMate (9:32 AM)

```bash
# Transfer detected
/mnt/instruments/cobas/incoming/
└── Patient_Batch_001_20251030_093142.csv  [transferred at 09:32:05]
```

**bioMate Processing:**
```
[2025-10-30 09:32:05] FileWatcher detected: Patient_Batch_001_20251030_093142.csv
[2025-10-30 09:32:06] File size: 125 KB (45 samples)
[2025-10-30 09:32:07] Routing to OpenELIS client (Cobas_C311)
[2025-10-30 09:32:10] OpenELIS import: Parsing 45 samples...
[2025-10-30 09:32:12] Success: 45 samples, 360 test results
[2025-10-30 09:32:13] Flagging abnormal results: 12 critical values found
[2025-10-30 09:32:14] Galaxy dataset created: patient_results_a7f3d2b8
[2025-10-30 09:32:15] Triggering QC workflow...
```

**Files in bioMate System:**
```
/var/lib/biomate/data/
└── 2025-10-30/
    ├── Patient_Batch_001_20251030_093142.csv
    ├── Patient_Batch_001_20251030_093142_parsed.json
    ├── Patient_Batch_001_20251030_093142_qc_report.pdf
    └── Patient_Batch_001_20251030_093142_critical_values.json

Galaxy:
/galaxy/database/files/002/
├── dataset_2146.dat  [patient_results_a7f3d2b8]
├── dataset_2147.dat  [qc_workflow_output]
└── dataset_2148.dat  [flagged_results]

PostgreSQL Database:
instrument_imports table:
┌──────┬─────────────────────────────────────┬────────────┬──────────┬─────────────┐
│ id   │ filename                            │ instrument │ samples  │ imported_at │
├──────┼─────────────────────────────────────┼────────────┼──────────┼─────────────┤
│ 1523 │ QC_20251030_080015.csv              │ Cobas_C311 │ 6        │ 08:05:15    │
│ 1524 │ Patient_Batch_001_20251030_093142   │ Cobas_C311 │ 45       │ 09:32:12    │
└──────┴─────────────────────────────────────┴────────────┴──────────┴─────────────┘

test_results table:
┌────────────┬───────────┬─────────┬────────┬───────────┬──────────────────────┐
│ sample_id  │ test_code │ result  │ unit   │ ref_range │ flags                │
├────────────┼───────────┼─────────┼────────┼───────────┼──────────────────────┤
│ P00012345  │ GLU       │ 325     │ mg/dL  │ 70-100    │ HIGH,CRITICAL        │
│ P00012345  │ CHOL      │ 245     │ mg/dL  │ <200      │ HIGH                 │
│ P00012346  │ GLU       │ 88      │ mg/dL  │ 70-100    │ NORMAL               │
│ ...        │ ...       │ ...     │ ...    │ ...       │ ...                  │
└────────────┴───────────┴─────────┴────────┴───────────┴──────────────────────┘
```

#### Step 5: Hematology Testing (10:00 AM - 11:00 AM)

**Technician:** Running CBC panels on Sysmex XN-1000

```
Sysmex PC:
D:\Sysmex\Export\
└── 2025-10-30\
    └── CBC_Batch_20251030_110245.txt
```

**Auto-transfer and Processing:**
```
[2025-10-30 11:02:50] FileWatcher: CBC_Batch_20251030_110245.txt
[2025-10-30 11:02:51] Routing to SENAITE client (Sysmex_XN)
[2025-10-30 11:02:55] SENAITE API: Import successful
[2025-10-30 11:02:56] Results: 38 samples, 456 parameters (WBC, RBC, PLT, etc.)
[2025-10-30 11:02:57] Abnormal flags: 15 samples flagged for review
[2025-10-30 11:02:58] Galaxy dataset: hematology_results_c9e4f6a2
```

**bioMate File Structure After Morning:**
```
/var/lib/biomate/
├── data/
│   └── 2025-10-30/
│       ├── 08-00-15_QC_Cobas/
│       │   ├── QC_20251030_080015.csv
│       │   ├── parsed_results.json
│       │   └── qc_report.pdf
│       ├── 09-32-12_Patient_Cobas/
│       │   ├── Patient_Batch_001_20251030_093142.csv
│       │   ├── parsed_results.json
│       │   ├── qc_report.pdf
│       │   └── critical_values.json
│       └── 11-02-56_CBC_Sysmex/
│           ├── CBC_Batch_20251030_110245.txt
│           ├── parsed_results.json
│           └── flagged_samples.json
├── reports/
│   └── daily/
│       └── 2025-10-30_morning_summary.pdf
└── logs/
    └── 2025-10-30/
        ├── cobas_import.log
        └── sysmex_import.log
```

---

## Scenario 2: Research Genomics Laboratory

**Lab Profile:**
- University cancer genomics research lab
- 5-10 sequencing runs per week
- Instruments: Illumina NovaSeq 6000, ONT PromethION
- Goal: Variant discovery, RNA-seq analysis, long-read assembly

### Monday Morning - NovaSeq Run Completion (9:00 AM)

#### Step 1: Sequencing Run Complete (9:00 AM)

**NovaSeq Run Summary:**
```
Run ID: 20251027_NB551234_0045_AHGV5NBGXY
Started: 2025-10-27 14:30:00
Completed: 2025-10-30 09:00:00
Total Runtime: 66.5 hours
Flow Cell: AHGV5NBGXY
Samples: 12 (4 tumor, 4 normal, 4 RNA-seq)
Output: 2.4 TB raw data
```

**Instrument Output Directory:**
```
/mnt/novaseq/output/
└── 20251027_NB551234_0045_AHGV5NBGXY/
    ├── RunInfo.xml
    ├── RunParameters.xml
    ├── InterOp/
    ├── Data/
    │   └── Intensities/
    │       └── BaseCalls/
    │           ├── L001/  (Lane 1)
    │           ├── L002/  (Lane 2)
    │           └── Stats/
    └── Analysis/
        └── 1/
            └── Data/
                └── fastq/
                    ├── Sample_Tumor_01/
                    │   ├── Tumor_01_S1_L001_R1_001.fastq.gz  [12.5 GB]
                    │   ├── Tumor_01_S1_L001_R2_001.fastq.gz  [12.5 GB]
                    │   ├── Tumor_01_S1_L002_R1_001.fastq.gz  [12.3 GB]
                    │   └── Tumor_01_S1_L002_R2_001.fastq.gz  [12.3 GB]
                    ├── Sample_Normal_01/
                    │   └── ... (similar structure)
                    └── ... (10 more samples)
```

#### Step 2: Demultiplexing QC (9:30 AM)

**Researcher:** Reviews bcl2fastq demultiplexing report

```
/mnt/novaseq/output/20251027_NB551234_0045_AHGV5NBGXY/Analysis/1/
└── Reports/
    └── html/
        ├── index.html
        ├── flowcell_summary.html  [opened at 09:30:15]
        └── demux_stats.json

Demux Stats Summary:
- Total Reads: 3.2 billion
- % Perfect Index: 95.3%
- % One Mismatch: 3.8%
- % Undetermined: 0.9%
✓ All samples > 200M reads
✓ Q30 > 85% for all samples
```

#### Step 3: Transfer to bioMate (10:00 AM)

**Method:** Rsync from instrument to bioMate server

```bash
# Researcher initiates transfer
rsync -avz --progress \
  /mnt/novaseq/output/20251027_NB551234_0045_AHGV5NBGXY/Analysis/1/Data/fastq/ \
  biomate-server:/data/incoming/sequencing/20251030/

Transfer Progress:
[10:00:23] Starting transfer...
[10:15:45] Sample_Tumor_01: 50 GB transferred (15%)
[10:32:18] Sample_Tumor_01: Complete
[10:45:22] Sample_Normal_01: Complete
[11:20:15] All samples transferred: 600 GB
```

**bioMate Server:**
```
/data/incoming/sequencing/20251030/
└── novaseq_run_20251027/
    ├── Tumor_01_S1_L001_R1_001.fastq.gz  [received 10:32:18]
    ├── Tumor_01_S1_L001_R2_001.fastq.gz
    ├── Tumor_01_S1_L002_R1_001.fastq.gz
    ├── Tumor_01_S1_L002_R2_001.fastq.gz
    └── ... (12 samples total)
```

#### Step 4: Import via bioMate Web UI (11:30 AM)

**Researcher:** Logs into bioMate dashboard

```
Browser: https://biomate.university.edu/dashboard

Actions:
[11:30:45] Navigate to: Instruments → Import Data → Sequencing
[11:31:12] Select files: 12 samples (48 FASTQ files)
[11:31:45] Instrument: Illumina_NovaSeq_6000
[11:31:52] Backend: Direct Parser (auto-selected)
[11:32:00] Click: "Import and Create Workflow"
```

**bioMate Processing:**
```
[2025-10-30 11:32:01] Batch import started: 12 samples
[2025-10-30 11:32:02] Parallel processing: 4 workers
[2025-10-30 11:32:05] Worker 1: Parsing Tumor_01_S1_L001_R1...
[2025-10-30 11:32:05] Worker 2: Parsing Tumor_02_S2_L001_R1...
[2025-10-30 11:32:05] Worker 3: Parsing Normal_01_S5_L001_R1...
[2025-10-30 11:32:05] Worker 4: Parsing Normal_02_S6_L001_R1...
[2025-10-30 11:32:45] Tumor_01 complete: 250M reads, Q36.2, 50.1% GC
[2025-10-30 11:33:12] Tumor_02 complete: 248M reads, Q35.8, 50.3% GC
[2025-10-30 11:45:23] All samples parsed successfully
[2025-10-30 11:45:24] Creating Galaxy history: "Cancer_Panel_Run_20251027"
[2025-10-30 11:45:30] Uploading 48 datasets to Galaxy...
[2025-10-30 11:52:15] Galaxy upload complete
```

**Galaxy History Created:**
```
History: Cancer_Panel_Run_20251027 (created 2025-10-30 11:45:24)

Datasets:
├── 1: Tumor_01_R1_L001 [12.5 GB] fastq.gz
├── 2: Tumor_01_R2_L001 [12.5 GB] fastq.gz
├── 3: Tumor_01_R1_L002 [12.3 GB] fastq.gz
├── 4: Tumor_01_R2_L002 [12.3 GB] fastq.gz
├── 5-8: Tumor_02 (4 files)
├── 9-12: Tumor_03 (4 files)
├── 13-16: Tumor_04 (4 files)
├── 17-20: Normal_01 (4 files)
├── 21-24: Normal_02 (4 files)
├── 25-28: Normal_03 (4 files)
├── 29-32: Normal_04 (4 files)
├── 33-36: RNA_01 (4 files)
├── 37-40: RNA_02 (4 files)
├── 41-44: RNA_03 (4 files)
└── 45-48: RNA_04 (4 files)
```

#### Step 5: Automated Workflow Execution (12:00 PM)

**bioMate AI:** Detects cancer genomics samples, suggests workflow

```
AI Suggestion [12:00:15]:
"Detected: 4 tumor-normal pairs + 4 RNA samples
Recommended workflow: GATK4 Somatic Variant Calling + RNA-seq Pipeline
Estimated runtime: 18-24 hours
Estimated cost: $42.50 (compute)

[Start Workflow] [Customize] [Cancel]"

Researcher clicks: [Start Workflow] at 12:02:30
```

**Workflow Started:**
```
Galaxy Workflow: "Somatic_Variant_Pipeline_v2.3"

[12:02:31] Step 1/15: FastQC on all samples (parallel)
[12:25:18] Step 2/15: Trimmomatic adapter trimming
[13:05:45] Step 3/15: BWA-MEM alignment to hg38
[16:30:22] Step 4/15: GATK MarkDuplicates
[17:15:40] Step 5/15: GATK BaseRecalibrator
[18:45:12] Step 6/15: GATK HaplotypeCaller (germline)
[21:30:55] Step 7/15: Mutect2 somatic calling
[23:15:20] Step 8/15: FilterMutectCalls
...continuing overnight...
```

**Files Generated During Workflow:**
```
Galaxy:
/galaxy/database/files/
└── 003/
    ├── dataset_3001.dat  [Tumor_01_aligned.bam - 45 GB]
    ├── dataset_3002.dat  [Tumor_01_dedup.bam - 42 GB]
    ├── dataset_3003.dat  [Tumor_01_recal.bam - 42 GB]
    ├── dataset_3004.dat  [Tumor_01_vs_Normal_01.vcf.gz - 125 MB]
    └── ... (100+ intermediate files)

bioMate Database:
workflow_executions table:
┌────────┬─────────────────────────────────┬──────────┬────────────┐
│ job_id │ workflow_name                   │ status   │ started_at │
├────────┼─────────────────────────────────┼──────────┼────────────┤
│ W4523  │ Somatic_Variant_Pipeline_v2.3   │ running  │ 12:02:31   │
└────────┴─────────────────────────────────┴──────────┴────────────┘
```

#### Step 6: Next Day - Results Ready (Tuesday 8:00 AM)

```
[2025-10-31 06:45:12] Workflow completed successfully
[2025-10-31 06:45:15] Generating summary report...
[2025-10-31 06:45:45] Report ready: Cancer_Panel_Summary_20251030.pdf
[2025-10-31 06:45:50] Email sent to: researcher@university.edu
```

**Final Results:**
```
/var/lib/biomate/results/2025-10-30/Cancer_Panel_Run_20251027/
├── variants/
│   ├── Tumor_01_vs_Normal_01_somatic.vcf.gz  [12 MB]
│   ├── Tumor_01_vs_Normal_01_somatic.vcf.gz.tbi
│   ├── Tumor_01_vs_Normal_01_filtered.vcf.gz  [3.5 MB]
│   ├── Tumor_01_annotated.vcf  [45 MB, VEP annotations]
│   └── ... (4 tumor-normal pairs)
├── bam_files/
│   ├── Tumor_01_final.bam  [42 GB]
│   ├── Tumor_01_final.bam.bai
│   └── ... (8 BAM files total)
├── rna_quantification/
│   ├── RNA_01_gene_counts.tsv
│   ├── RNA_01_transcript_counts.tsv
│   └── ... (4 RNA samples)
├── qc_reports/
│   ├── multiqc_report.html
│   ├── fastqc_summary.pdf
│   └── alignment_stats.pdf
└── summary/
    ├── Cancer_Panel_Summary_20251030.pdf  [15 pages]
    ├── variant_summary.xlsx
    └── actionable_mutations.csv

Key Findings (from summary):
- Tumor_01: 3,245 somatic SNVs, 127 indels
- Tumor_02: 2,891 somatic SNVs, 98 indels
- Actionable mutations found: 15 (EGFR, KRAS, TP53, etc.)
- RNA-seq: 18,234 genes detected, 142 differentially expressed
```

---

## Scenario 3: Long-Read Sequencing - ONT PromethION

**Same Lab - Thursday Afternoon**

#### Step 1: PromethION Run In Progress (2:00 PM)

```
ONT PromethION 24:
Active Run: "Bacterial_Genomes_20251030"
Started: 2025-10-30 08:00:00
Runtime: 6 hours (continuing)
Active Pores: 8,523 / 10,000
Total Reads: 2.4M
Total Bases: 18.5 Gbp
N50: 12.5 kb
```

**Real-time Basecalling (Guppy):**
```
/mnt/promethion/data/Bacterial_Genomes_20251030/
├── fast5_pass/  [85 GB, 2.4M reads]
│   ├── barcode01/
│   ├── barcode02/
│   └── ... (12 barcodes)
└── fastq_pass/  [Basecalling in real-time]
    ├── barcode01/
    │   ├── FAU12345_pass_barcode01_0.fastq  [125 MB] [created 08:15:23]
    │   ├── FAU12345_pass_barcode01_1.fastq  [128 MB] [created 08:45:18]
    │   ├── FAU12345_pass_barcode01_2.fastq  [130 MB] [created 09:15:45]
    │   └── ... (continuing real-time)
    └── barcode02/
        └── ... (similar)
```

#### Step 2: Run Complete - Final Basecalling (6:00 PM)

```
[2025-10-30 18:00:15] Sequencing run stopped
[2025-10-30 18:00:20] Final statistics:
  - Total reads: 8.2M
  - Total bases: 72.3 Gbp
  - N50: 15.2 kb
  - Longest read: 185 kb
  - Mean quality: Q12.5
[2025-10-30 18:00:25] Starting final basecalling with Guppy HAC model...
[2025-10-30 20:15:40] Basecalling complete
[2025-10-30 20:15:45] Generating sequencing summary...
```

**Final Output:**
```
/mnt/promethion/data/Bacterial_Genomes_20251030/
├── sequencing_summary.txt  [450 MB]
├── final_summary.txt
└── fastq_pass/
    ├── barcode01/  [E.coli_strain_A]
    │   └── all_reads.fastq.gz  [2.8 GB, 1.2M reads, 9.5 Gbp]
    ├── barcode02/  [E.coli_strain_B]
    │   └── all_reads.fastq.gz  [2.6 GB, 1.1M reads, 8.8 Gbp]
    ├── barcode03/  [Salmonella_strain_A]
    │   └── all_reads.fastq.gz  [3.1 GB, 1.3M reads, 10.2 Gbp]
    └── ... (12 barcodes total)
```

#### Step 3: Import to bioMate (8:30 PM)

**Researcher:** Uploads via web UI

```
bioMate Dashboard → Import Data → ONT Sequencing

[20:30:15] Select: 12 fastq.gz files (one per barcode)
[20:30:45] Instrument: ONT_PromethION
[20:31:00] Parser: Direct (auto-selected)
[20:31:15] Options:
  ☑ Calculate N50
  ☑ Quality filtering (Q≥7)
  ☐ Length filtering
[20:31:30] Click: "Import"
```

**bioMate Processing:**
```
[2025-10-30 20:31:31] Batch import: 12 ONT samples
[2025-10-30 20:31:35] Worker 1: Parsing barcode01 (2.8 GB)...
[2025-10-30 20:31:35] Worker 2: Parsing barcode02 (2.6 GB)...
[2025-10-30 20:31:35] Worker 3: Parsing barcode03 (3.1 GB)...
[2025-10-30 20:31:35] Worker 4: Parsing barcode04 (2.9 GB)...

[2025-10-30 20:35:42] barcode01 complete:
  - Total reads: 1,245,234
  - Total bases: 9.5 Gbp
  - N50: 15.8 kb
  - Mean quality: Q12.8
  - Mean length: 7,624 bp

[2025-10-30 20:42:15] All samples parsed
[2025-10-30 20:42:20] Creating Galaxy datasets...
[2025-10-30 20:45:30] Upload complete
```

**Galaxy History:**
```
History: Bacterial_Genomes_ONT_20251030

Datasets:
├── 1: E.coli_A_barcode01 [2.8 GB] fastq.gz
├── 2: E.coli_A_metadata [150 KB] json
├── 3: E.coli_B_barcode02 [2.6 GB] fastq.gz
├── 4: E.coli_B_metadata [145 KB] json
└── ... (12 samples + 12 metadata files = 24 datasets)
```

#### Step 4: Assembly Workflow (9:00 PM)

```
bioMate AI Suggestion [21:00:12]:
"Detected: ONT bacterial genomes (12 samples)
Recommended: Flye Assembly + Medaka Polishing + Prokka Annotation
Estimated runtime: 8-12 hours
Estimated cost: $18.50

[Start Workflow]"

Researcher: Clicks [Start Workflow] at 21:05:00
```

**Overnight Processing:**
```
Galaxy Workflow: "Bacterial_Assembly_ONT_v1.5"

[21:05:15] Step 1/8: Quality filtering (NanoFilt Q≥7)
[21:25:30] Step 2/8: Length filtering (≥1kb)
[21:35:45] Step 3/8: Flye assembly (parallel, 12 samples)
[23:15:20] Step 4/8: Assembly QC (QUAST)
[00:45:12] Step 5/8: Medaka polishing (round 1)
[02:30:45] Step 6/8: Medaka polishing (round 2)
[04:15:22] Step 7/8: Prokka annotation
[05:45:30] Step 8/8: MultiQC report generation
[06:00:15] Workflow complete!
```

#### Step 5: Next Morning - Results (Friday 8:00 AM)

```
/var/lib/biomate/results/2025-10-30/Bacterial_Genomes_ONT/
├── assemblies/
│   ├── E.coli_A_assembly.fasta  [4.8 MB, 1 contig]
│   ├── E.coli_B_assembly.fasta  [4.9 MB, 2 contigs]
│   ├── Salmonella_A_assembly.fasta  [4.7 MB, 1 contig]
│   └── ... (12 assemblies)
├── polished/
│   ├── E.coli_A_polished.fasta  [4.8 MB]
│   ├── E.coli_A_polished.fasta.fai
│   └── ... (12 polished genomes)
├── annotations/
│   ├── E.coli_A_prokka/
│   │   ├── annotation.gff  [4.2 MB]
│   │   ├── annotation.gbk  [5.8 MB]
│   │   ├── proteins.faa  [1.4 MB]
│   │   └── genes.ffn  [4.1 MB]
│   └── ... (12 annotations)
├── qc/
│   ├── quast_report/
│   │   ├── report.html
│   │   └── summary.tsv
│   └── multiqc_report.html
└── summary/
    ├── Assembly_Summary_20251030.pdf
    └── genome_statistics.xlsx

Assembly Statistics:
┌──────────────────┬──────────┬──────────┬────────────┬──────────┐
│ Sample           │ Size     │ Contigs  │ N50        │ Genes    │
├──────────────────┼──────────┼──────────┼────────────┼──────────┤
│ E.coli_A         │ 4.82 Mb  │ 1        │ 4.82 Mb    │ 4,523    │
│ E.coli_B         │ 4.91 Mb  │ 2        │ 4.85 Mb    │ 4,612    │
│ Salmonella_A     │ 4.71 Mb  │ 1        │ 4.71 Mb    │ 4,381    │
│ ...              │ ...      │ ...      │ ...        │ ...      │
└──────────────────┴──────────┴──────────┴────────────┴──────────┘
```

---

## Scenario 4: High-Throughput Core Facility

**Lab Profile:**
- University core facility serving 50+ research groups
- 10-15 sequencing runs per week
- Multiple platforms: Illumina, ONT, PacBio
- Goal: Automated data delivery, usage tracking, billing

### Monday - Week Schedule (Multiple Runs)

#### Morning: Three Simultaneous Imports (8:00 AM)

```
bioMate Server - Active Imports [08:00-09:00]:

┌─────────┬──────────────────────────┬────────────┬──────────┬─────────────┐
│ Import  │ Instrument               │ Samples    │ Size     │ Status      │
├─────────┼──────────────────────────┼────────────┼──────────┼─────────────┤
│ #1      │ MiSeq_01 (16S_Project)   │ 96         │ 45 GB    │ Parsing...  │
│ #2      │ NovaSeq_01 (RNA-seq)     │ 48         │ 850 GB   │ Uploading   │
│ #3      │ MinION_03 (Diagnostics)  │ 8          │ 12 GB    │ Complete    │
└─────────┴──────────────────────────┴────────────┴──────────┴─────────────┘
```

**File Activity:**
```
/data/incoming/2025-10-30/
├── 08-00-15_MiSeq_16S_Microbiome/
│   ├── Sample_001_R1.fastq.gz
│   ├── Sample_001_R2.fastq.gz
│   └── ... (96 samples, 192 files)
├── 08-15-30_NovaSeq_RNAseq_Batch5/
│   ├── Sample_R01_R1_L001.fastq.gz  [8.5 GB]
│   ├── Sample_R01_R2_L001.fastq.gz  [8.5 GB]
│   └── ... (48 samples, 192 files)
└── 08-30-45_MinION_Clinical_Panel/
    ├── patient_001_barcode01.fastq.gz
    └── ... (8 samples)

Disk Usage: 907 GB
Transfer Status: 850/907 GB complete (93%)
Estimated completion: 09:15 AM
```

#### Processing Dashboard (9:30 AM)

```
bioMate Core Facility Dashboard
Date: 2025-10-30 09:30:00

Active Jobs:
┌────────┬──────────────────┬────────────────┬──────────┬──────────────┐
│ Job ID │ Project          │ Workflow       │ Progress │ ETA          │
├────────┼──────────────────┼────────────────┼──────────┼──────────────┤
│ J4521  │ Microbiome_16S   │ QIIME2_v2023   │ 45%      │ 11:30 AM     │
│ J4522  │ RNA_Batch5       │ DESeq2_v3.0    │ 12%      │ Tomorrow 2PM │
│ J4523  │ Clinical_Panel   │ Variant_Call   │ 78%      │ 10:15 AM     │
└────────┴──────────────────┴────────────────┴──────────┴──────────────┘

Resource Usage:
┌───────────────┬──────────┬──────────────┬─────────────┐
│ Resource      │ Used     │ Available    │ Percentage  │
├───────────────┼──────────┼──────────────┼─────────────┤
│ CPU Cores     │ 384/512  │ 128          │ 75%         │
│ RAM           │ 1.8/2.5  │ 0.7 TB       │ 72%         │
│ Storage       │ 145/200  │ 55 TB        │ 73%         │
└───────────────┴──────────┴──────────────┴─────────────┘

Queue:
- 3 jobs running
- 5 jobs queued
- 2 jobs waiting for data
```

#### User Data Delivery (Throughout Week)

**Automated Email Notifications:**

```
From: biomate-noreply@university.edu
To: researcher1@university.edu
Date: 2025-10-30 10:15:34
Subject: [bioMate] Clinical_Panel analysis complete - Job J4523

Dear Dr. Smith,

Your analysis "Clinical_Panel" has completed successfully.

Run Information:
- Job ID: J4523
- Submitted: 2025-10-30 08:45:20
- Completed: 2025-10-30 10:15:30
- Runtime: 1h 30m
- Samples: 8
- Workflow: Variant_Call_Clinical_v2.1

Results:
- Download Link: https://biomate.edu/results/J4523/download
- Expires: 2025-11-13 (14 days)
- Size: 2.3 GB

Files:
- variants/ (8 VCF files)
- alignments/ (8 BAM files)
- reports/ (QC and summary PDFs)
- raw_data/ (original FASTQ files)

Billing:
- Compute: $8.50
- Storage: $0.25/day
- Total: $8.75 (charged to grant account 12345)

---
bioMate Core Facility
https://biomate.university.edu
```

**Files Available for Download:**
```
https://biomate.edu/results/J4523/
├── Clinical_Panel_Results_20251030.zip  [2.3 GB]
│   └── Contains:
│       ├── variants/
│       │   ├── patient_001_variants.vcf.gz
│       │   ├── patient_001_variants_annotated.tsv
│       │   └── ... (8 patients)
│       ├── alignments/
│       │   ├── patient_001_aligned.bam
│       │   ├── patient_001_aligned.bam.bai
│       │   └── ... (8 patients)
│       ├── reports/
│       │   ├── QC_Summary.pdf
│       │   ├── Variant_Report.pdf
│       │   └── Coverage_Analysis.pdf
│       └── metadata/
│           ├── run_info.json
│           ├── workflow_parameters.json
│           └── sample_manifest.csv
└── README.txt

Download expires: 2025-11-13
```

---

## Scenario 5: Longitudinal Patient Monitoring

**Lab Profile:**
- Clinical diagnostics + research
- Weekly patient blood monitoring
- Integration with Electronic Health Records (EHR)
- Goal: Track patient trends, detect anomalies

### Patient Example: Diabetes Management (3-Month Timeline)

#### Week 1 - Baseline (2025-08-05)

```
Patient: P00054321 (John Doe, 58M)
Condition: Type 2 Diabetes
Tests: Chemistry panel, HbA1c, Lipid panel

Cobas C311 Results:
/mnt/cobas/results/2025-08-05/
└── Patient_P00054321_20250805_083015.csv

Test Results:
┌───────────┬─────────┬────────┬───────────┬────────┐
│ Test      │ Result  │ Unit   │ Ref Range │ Flag   │
├───────────┼─────────┼────────┼───────────┼────────┤
│ Glucose   │ 185     │ mg/dL  │ 70-100    │ HIGH   │
│ HbA1c     │ 8.2     │ %      │ <5.7      │ HIGH   │
│ Chol      │ 245     │ mg/dL  │ <200      │ HIGH   │
│ LDL       │ 165     │ mg/dL  │ <100      │ HIGH   │
│ HDL       │ 38      │ mg/dL  │ >40       │ LOW    │
│ Trig      │ 210     │ mg/dL  │ <150      │ HIGH   │
└───────────┴─────────┴────────┴───────────┴────────┘

bioMate Import [08:30:20]:
- Parsed and stored in database
- Galaxy dataset: patient_results_baseline_e8f2a3c1
- Flagged for physician review (4 abnormal values)
- EHR integration: Results pushed to hospital EMR
```

**Database Storage:**
```sql
patient_monitoring table:
INSERT INTO patient_monitoring (
    patient_id, test_date, test_code, result, unit, ref_range, flag, import_timestamp
) VALUES
    ('P00054321', '2025-08-05', 'GLU', 185, 'mg/dL', '70-100', 'HIGH', '2025-08-05 08:30:20'),
    ('P00054321', '2025-08-05', 'HbA1c', 8.2, '%', '<5.7', 'HIGH', '2025-08-05 08:30:20'),
    ...
```

#### Week 5 - Follow-up (2025-09-02)

```
Patient: P00054321
Status: On metformin + lifestyle changes

Cobas Results:
┌───────────┬─────────┬────────┬───────────┬────────┬──────────────┐
│ Test      │ Result  │ Unit   │ Ref Range │ Flag   │ Trend        │
├───────────┼─────────┼────────┼───────────┼────────┼──────────────┤
│ Glucose   │ 142     │ mg/dL  │ 70-100    │ HIGH   │ ↓ -43 (-23%) │
│ HbA1c     │ 7.1     │ %      │ <5.7      │ HIGH   │ ↓ -1.1       │
│ Chol      │ 215     │ mg/dL  │ <200      │ HIGH   │ ↓ -30 (-12%) │
│ LDL       │ 138     │ mg/dL  │ <100      │ HIGH   │ ↓ -27 (-16%) │
│ HDL       │ 42      │ mg/dL  │ >40       │ NORMAL │ ↑ +4 (+11%)  │
│ Trig      │ 175     │ mg/dL  │ <150      │ HIGH   │ ↓ -35 (-17%) │
└───────────┴─────────┴────────┴───────────┴────────┴──────────────┘

bioMate Processing [09:15:45]:
- Automatically compared to baseline (2025-08-05)
- Trend analysis: Significant improvement detected
- Generated trend report with charts
- Alert: "Patient showing good response to treatment"
- Physician dashboard updated
```

**Trend Visualization (Auto-generated):**
```
/var/lib/biomate/reports/patient_trends/
└── P00054321_trend_report_20250902.pdf

Content:
Page 1: Glucose Trend Chart
  [Chart showing: 185 → 142 mg/dL over 4 weeks]

Page 2: HbA1c Trend
  [Chart showing: 8.2% → 7.1% over 4 weeks]

Page 3: Lipid Profile Trends
  [Multi-line chart for Chol, LDL, HDL, Trig]

Page 4: Clinical Interpretation
  "Patient P00054321 shows significant improvement across all
   diabetes markers. Glucose reduced by 23%, HbA1c by 1.1 points.
   Recommend continuing current treatment plan."
```

#### Week 13 - 3-Month Follow-up (2025-11-04)

```
Comprehensive Panel Results:
┌───────────┬─────────┬────────┬───────────┬────────┬──────────────────────┐
│ Test      │ Result  │ Unit   │ Ref Range │ Flag   │ 3-Month Trend        │
├───────────┼─────────┼────────┼───────────┼────────┼──────────────────────┤
│ Glucose   │ 98      │ mg/dL  │ 70-100    │ NORMAL │ ↓ -87 (-47%) ✓       │
│ HbA1c     │ 6.2     │ %      │ <5.7      │ BORDER │ ↓ -2.0 ✓             │
│ Chol      │ 188     │ mg/dL  │ <200      │ NORMAL │ ↓ -57 (-23%) ✓       │
│ LDL       │ 95      │ mg/dL  │ <100      │ NORMAL │ ↓ -70 (-42%) ✓       │
│ HDL       │ 48      │ mg/dL  │ >40       │ NORMAL │ ↑ +10 (+26%) ✓       │
│ Trig      │ 135     │ mg/dL  │ <150      │ NORMAL │ ↓ -75 (-36%) ✓       │
└───────────┴─────────┴────────┴───────────┴────────┴──────────────────────┘

bioMate Analysis [11:45:20]:
- 3-month longitudinal analysis complete
- All markers improved significantly
- 5/6 values now in normal range
- Generated comprehensive report for endocrinologist
- Updated patient risk score: HIGH → MODERATE
```

**Complete Patient History Export:**
```
/var/lib/biomate/exports/
└── P00054321_longitudinal_report_2025-08-05_to_2025-11-04.xlsx

Sheets:
1. Summary Dashboard
2. All Test Results (chronological)
3. Trend Charts
4. Statistical Analysis
5. Risk Assessment
6. Treatment Timeline
7. Physician Notes Integration

Database Query Used:
SELECT
    test_date,
    test_code,
    result,
    unit,
    flag,
    LAG(result) OVER (PARTITION BY test_code ORDER BY test_date) as previous_result,
    ((result - LAG(result) OVER (PARTITION BY test_code ORDER BY test_date)) /
     LAG(result) OVER (PARTITION BY test_code ORDER BY test_date)) * 100 as percent_change
FROM patient_monitoring
WHERE patient_id = 'P00054321'
  AND test_date BETWEEN '2025-08-05' AND '2025-11-04'
ORDER BY test_date, test_code;
```

---

## Complete System File Structure Example

### bioMate Production Server - Snapshot (2025-10-30)

```
/var/lib/biomate/
├── data/
│   ├── incoming/              [Hot storage, 7-day retention]
│   │   └── 2025-10-30/
│   │       ├── 08-05-15_Cobas_QC/
│   │       ├── 09-32-12_Cobas_Patient/
│   │       ├── 11-02-56_Sysmex_CBC/
│   │       └── 20-31-35_ONT_Bacteria/
│   ├── processed/             [Parsed results, 30-day retention]
│   │   └── 2025-10/
│   │       └── week_44/
│   │           ├── clinical/
│   │           ├── research/
│   │           └── sequencing/
│   └── archive/               [Compressed, long-term]
│       └── 2025/
│           ├── Q1/
│           ├── Q2/
│           └── Q3/
├── results/                   [Analysis outputs]
│   └── 2025-10-30/
│       ├── Cancer_Panel_Run_20251027/
│       ├── Bacterial_Genomes_ONT/
│       └── Clinical_Diagnostics/
├── reports/                   [Generated reports]
│   ├── daily/
│   │   └── 2025-10-30_summary.pdf
│   ├── weekly/
│   │   └── 2025_week_44_report.pdf
│   └── patient_trends/
│       └── [patient_id]_trend_report.pdf
├── logs/                      [System logs]
│   └── 2025-10-30/
│       ├── instrument_imports.log
│       ├── workflow_executions.log
│       ├── api_access.log
│       └── errors.log
└── config/
    ├── instrument_connections.yaml
    ├── workflow_templates/
    └── user_permissions.json

/mnt/instruments/              [Mounted from instruments]
├── cobas/
│   ├── incoming/              [Monitored by FileWatcher]
│   └── archive/
├── sysmex/
│   ├── incoming/
│   └── archive/
└── novaseq/
    └── output/

/galaxy/                       [Galaxy instance]
├── database/
│   ├── files/                 [Dataset storage]
│   │   ├── 001/
│   │   ├── 002/
│   │   └── 003/
│   └── databases/             [PostgreSQL data]
├── config/
└── shed_tools/

S3 Bucket (s3://biomate-instruments/):
└── 2025/
    └── 10/
        └── 30/
            ├── QC_20251030_080015.csv
            ├── Patient_Batch_001_20251030_093142.csv
            ├── CBC_Batch_20251030_110245.txt
            ├── Tumor_01_S1_L001_R1_001.fastq.gz
            └── ... [All imported instrument files]
            └── metadata/
                └── [corresponding JSON metadata files]

PostgreSQL Database Tables:
┌─────────────────────────┬─────────────┬──────────────────────┐
│ Table                   │ Row Count   │ Size                 │
├─────────────────────────┼─────────────┼──────────────────────┤
│ instrument_imports      │ 15,234      │ 45 MB                │
│ test_results            │ 2,458,901   │ 1.2 GB               │
│ workflow_executions     │ 4,521       │ 125 MB               │
│ galaxy_datasets         │ 45,678      │ 890 MB               │
│ patient_monitoring      │ 125,456     │ 385 MB               │
│ audit_log               │ 1,245,890   │ 2.1 GB               │
└─────────────────────────┴─────────────┴──────────────────────┘
```

---

## Key Workflow Patterns

### 1. Automated Import Pattern

```
Instrument → Network Share → FileWatcher → Parser → Database → Galaxy → S3
     ↓            ↓              ↓            ↓         ↓         ↓        ↓
  Results    Transfer(5s)   Detect(1s)   Parse(10s)  Store(2s) Upload(5s) Archive(10s)
                                                         ↓
                                                    Notifications
                                                    (Email/Slack)
```

**Typical Timeline:**
- File created: T+0
- Detected: T+5s
- Parsed: T+15s
- Database stored: T+17s
- Galaxy dataset: T+22s
- S3 archived: T+32s
- User notified: T+35s

### 2. Manual Upload Pattern

```
Web UI → Upload → Validation → Parser → Processing → Notification
   ↓        ↓          ↓           ↓          ↓            ↓
User    Progress   Format     Extract    Workflow     Email
Select   Bar(%)    Check      Results    Execute      Link
```

### 3. High-Throughput Pattern

```
Multiple Instruments → Parallel Imports → Queue Management → Batch Processing
        ↓                      ↓                  ↓                 ↓
   Cobas (45)            Parser Pool          Priority          Workflow
   Sysmex (38)          (4 workers)            Queue            Executor
   Illumina (12)         Concurrent         (FIFO/Priority)    (Galaxy)
```

---

## Monitoring and Alerts

### Real-Time Dashboard Metrics

```
bioMate System Health Dashboard (Updated: 2025-10-30 14:35:00)

Instrument Connections:
┌────────────────┬──────────┬─────────────┬────────────────┐
│ Instrument     │ Status   │ Last Import │ Today's Count  │
├────────────────┼──────────┼─────────────┼────────────────┤
│ Cobas_C311     │ ● Online │ 09:32:12    │ 51 samples     │
│ Sysmex_XN      │ ● Online │ 11:02:56    │ 38 samples     │
│ NovaSeq_01     │ ● Online │ 11:52:30    │ 12 samples     │
│ MinION_03      │ ● Online │ 20:31:35    │ 8 samples      │
│ PromethION_24  │ ○ Idle   │ 18:15:20    │ 12 samples     │
└────────────────┴──────────┴─────────────┴────────────────┘

Import Queue:
- Processing: 2 files
- Queued: 0 files
- Failed: 0 files (24h)

Workflow Status:
- Running: 3 workflows
- Queued: 5 workflows
- Completed today: 8 workflows
- Failed today: 0 workflows

Storage:
- Raw data: 1.2 TB (today)
- Total storage: 145 TB / 200 TB (73%)
- S3 archived: 42 TB
- Backup status: ✓ Up to date

Alerts:
✓ All systems operational
✓ No failed imports in last 24h
✓ Storage capacity healthy (>20% free)
✓ All instrument connections active
```

---

## Conclusion

These scenarios demonstrate how bioMate integrates instrument connections into real-world laboratory workflows, providing:

1. **Automated data capture** from clinical and research instruments
2. **Standardized processing** through unified APIs
3. **Workflow integration** with Galaxy for analysis
4. **Data management** with database storage and S3 archiving
5. **Quality control** with automated flagging and reporting
6. **User notifications** via email/dashboard
7. **Longitudinal tracking** for patient monitoring
8. **Audit trails** for compliance

All files are timestamped, tracked, and accessible through the bioMate platform, providing complete traceability from instrument to result.
