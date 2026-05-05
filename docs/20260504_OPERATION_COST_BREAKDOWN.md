# BioMate Operation Cost Breakdown
**Date:** 2026-05-04  
**Audience:** Engineering + Finance  
**Purpose:** End-to-end cost per use case (LLM + compute + networking + storage) and long-term platform fixed costs, grounded in actual infrastructure from the codebase

---

## Methodology

All per-use-case costs are computed from:
- **LLM pricing** from `cost_calculator.py`: Claude Sonnet 4.5 at $3.00/$15.00 per MTok (input/output); Claude Haiku 4.5 at $0.25/$1.25 per MTok; Gemini 3 Flash at $0.075/$0.30 per MTok
- **EC2 on-demand prices** from `EC2_INSTANCE_PRICING` in `cost_calculator.py` (us-west-2)
- **BioMate markup**: 2.2× CPU instances, 2.0× GPU instances (on-demand), 1.6× GPU instances (Spot)
- **S3/networking** from AWS published pricing (us-west-2)
- **All costs represent AWS COGS** — what BioMate actually pays — plus the BioMate charge (what the user is billed)

Costs are shown as:
- **AWS COGS**: actual cost to BioMate
- **BioMate charge**: what appears on the user's invoice

---

## Part 1: Use Case Operational Cost Breakdowns

---

### Use Case 1: RNA-seq Differential Expression (nf-core/rnaseq)

**Scenario:** 6 paired-end FASTQ files (3 conditions × 2 replicates), 50 GB total, human GRCh38, STAR + DESeq2

#### LLM Costs

| Call | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| Intent routing (1 turn) | Sonnet 4.5 | 3,500 | 800 | $0.023 |
| Parameter extraction | Sonnet 4.5 | 5,200 | 1,200 | $0.034 |
| Results analysis / findings | Sonnet 4.5 | 12,000 | 3,500 | $0.089 |
| Methods report section | Sonnet 4.5 | 8,000 | 4,500 | $0.092 |
| **LLM subtotal** | | | | **$0.238** |

#### Compute Costs (AWS Batch, Nextflow parallel tasks)

| Step | Instance | Duration | AWS COGS | BioMate charge (2.2×) |
|---|---|---|---|---|
| STAR genome index | c6i.4xlarge | 30 min | $0.340 | $0.748 |
| FastQC (6 samples, parallel) | c6i.large × 3 | 8 min | $0.034 | $0.075 |
| Trim Galore (6 samples) | c6i.large × 3 | 12 min | $0.051 | $0.112 |
| STAR alignment (6 samples) | c6i.2xlarge × 6 | 20 min | $0.680 | $1.496 |
| featureCounts | c6i.xlarge | 10 min | $0.028 | $0.062 |
| DESeq2 + MultiQC | c6i.large | 8 min | $0.011 | $0.024 |
| **Compute subtotal** | | **~1.5 h wall-clock** | **$1.144** | **$2.517** |

#### Networking Costs

| Item | Volume | AWS COGS |
|---|---|---|
| S3 PUT (50 GB input, user-uploaded prior) | 0 GB new | $0 |
| S3 GET during tasks (same region, via VPC endpoint) | 50 GB | $0 |
| S3 PUT results (5 GB) | 5 GB | $0 |
| User downloads results (5 GB egress) | 5 GB | $0.45 |
| S3 API requests (PUT/GET operations) | ~5,000 reqs | $0.03 |
| **Networking subtotal** | | **$0.48** |

#### Storage Costs

| Item | Size | COGS/month |
|---|---|---|
| Input FASTQs (S3 Standard) | 50 GB | $1.15/mo |
| Output results (BAMs archived, counts/reports kept) | 8 GB | $0.18/mo |
| Nextflow work dir (auto-cleaned post-run) | 0 | $0 |
| **Storage subtotal** | | **$1.33/mo ongoing** |

#### Summary

| Component | AWS COGS | BioMate charge |
|---|---|---|
| LLM | $0.238 | $0.286 (1.2×) |
| Compute | $1.144 | $2.517 |
| Networking | $0.480 | $0.480 |
| Storage (first month) | $1.330 | $1.600 |
| **Total (first month)** | **$3.192** | **$4.883** |
| **Total (per run, excl. storage)** | **$1.862** | **$3.283** |

**Assessment:** Well within Starter tier ($50/mo included compute). A lab running 10 RNA-seq experiments per month would spend ~$33 in compute charges.

---

### Use Case 2: CryoEM Structure Determination (2 TB dataset)

**Scenario:** 2 TB raw micrograph movies (K3 camera, ~80,000 frames), full CryoSPARC SPA pipeline from import through 3D refinement, targeting sub-3 Å resolution

#### LLM Costs

| Call | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| Intent routing (1-2 turns) | Sonnet 4.5 | 4,000 | 900 | $0.026 |
| Parameter extraction (movies_path, pixel_size, voltage, etc.) | Sonnet 4.5 | 6,500 | 1,500 | $0.042 |
| Resolution & quality findings (FSC curves, CTF fit) | Sonnet 4.5 | 18,000 | 5,000 | $0.129 |
| Structural analysis (EMDB comparison, map quality) | Sonnet 4.5 | 12,000 | 4,000 | $0.096 |
| Methods section (cryoEM-specific) | Sonnet 4.5 | 10,000 | 5,500 | $0.113 |
| CryoEM image QC (Gemini 3 Flash, micrograph thumbnails) | Gemini Flash | 40,000 | 2,000 | $0.004 |
| **LLM subtotal** | | | | **$0.410** |

#### Compute Costs

| Step | Instance | Duration | AWS on-demand COGS | AWS Spot COGS (~30% of OD) | BioMate on-demand (2.0×) | BioMate Spot (1.6×) |
|---|---|---|---|---|---|---|
| Import movies + CTF (CTFFIND4) | g5.4xlarge | 3 h | $4.87 | $1.45 | $9.74 | $2.32 |
| Motion correction (MotionCor2) | g5.12xlarge | 8 h | $45.38 | $13.54 | $90.76 | $21.67 |
| Particle picking (TOPAZ) | g5.12xlarge | 17 h | $96.42 | $28.78 | $192.84 | $46.04 |
| 2D classification (1M particles) | g5.12xlarge | 8 h | $45.38 | $13.54 | $90.76 | $21.67 |
| Ab initio 3D reconstruction | g5.12xlarge | 4 h | $22.69 | $6.77 | $45.38 | $10.83 |
| 3D refinement (homogeneous) | g5.12xlarge | 8 h | $45.38 | $13.54 | $90.76 | $21.67 |
| CTF refinement + polishing | g5.4xlarge | 3 h | $4.87 | $1.45 | $9.74 | $2.32 |
| **Compute subtotal** | | **~43 h wall-clock** | **$264.99** | **$79.07** | **$529.98** | **$126.52** |

> **Spot AWS COGS derivation:** g5.12xlarge Spot in us-west-2 runs at approximately $1.70/hr (30% of the $5.672/hr on-demand rate, based on historical Spot pricing). Spot prices fluctuate; re-verify quarterly. The 1.6× BioMate markup on Spot COGS is the source of truth for billing; the "AWS Spot COGS" column is $BioMate\_Spot \div 1.6$.

> **Note:** The g5.12xlarge has 4× A10G GPUs, 48 vCPU, 192 GB RAM. BioMate charges instance-cost passthrough (Section 5 of billing design), NOT triple-charge. Spot availability for GPU instances in us-west-2 is typically 70-80% — large cryo labs should plan for ~20% on-demand fallback.

#### Networking Costs

| Item | Volume | AWS COGS |
|---|---|---|
| S3 GET (2 TB micrographs, same-region VPC endpoint) | 2 TB | $0 |
| S3 GET (intermediate checkpoints during long run) | 500 GB | $0 |
| S3 PUT (outputs: final map, half-maps, reports) | 5 GB | $0 |
| VPC inter-AZ data transfer (if Batch in different AZ than S3) | 500 GB | $5.00 |
| User downloads (final map ~200 MB + report ~5 MB) | 0.2 GB | $0.018 |
| **Networking subtotal** | | **$5.02** |

> **Important:** Ensure Batch compute environment is in the same AZ as the S3 bucket (or use S3 VPC Gateway Endpoint). Inter-AZ transfer at $0.01/GB becomes significant at 2 TB scale.

#### Storage Costs

| Item | Size | COGS/month | Notes |
|---|---|---|---|
| Raw micrographs (S3 Standard) | 2,000 GB | $46.00/mo | Move to S3-IA after 30 days: $25/mo |
| Intermediate particle stacks | 1,500 GB | $34.50/mo | Delete after run completion |
| Final maps + half-maps + reports | 5 GB | $0.12/mo | Keep indefinitely |
| **Storage subtotal** | | **$80.62/mo (first month)** | **$25.12/mo if archived** |

#### Summary

| Component | AWS COGS (Spot run) | AWS COGS (On-demand run) | BioMate charge (Spot) | BioMate charge (On-demand) |
|---|---|---|---|---|
| LLM | $0.41 | $0.41 | $0.492 | $0.492 |
| Compute | **$79.07** | **$264.99** | $126.52 | $529.98 |
| Networking | $5.02 | $5.02 | $5.020 | $5.020 |
| Storage (first month) | $80.62 | $80.62 | $96.74 | $96.74 |
| **Total (first month)** | **$165.12** | **$351.04** | **$228.77** | **$632.23** |
| **Per run (excl. storage)** | **$84.50** | **$270.42** | **$132.03** | **$535.49** |

**Assessment:** Spot runs make Premium tier ($300 included credit) viable for one 2 TB CryoEM run per month. On-demand requires Team tier ($800 included) or overage billing. Labs processing multiple datasets monthly should negotiate Enterprise with reserved GPU capacity.

---

### Use Case 3: Drug Discovery Workflow Chain (ADMET → PBPK → Clinical Trial Simulation)

**Scenario:** 200 lead compounds screened through three sequential workflows with auto-loop QC between each stage, producing an IND-ready PK summary. Auto-loop runs ~1.5× on average due to QC gate failures on the first pass.

#### Stage A — ADMET Screening (200 compounds)

| Component | AWS COGS | BioMate charge |
|---|---|---|
| Routing + extraction LLM | $0.034 | $0.041 |
| ADMET compute (c6i.2xlarge × 25 min, RDKit + ML) | $0.160 | $0.352 |
| Auto-loop QC (hERG/DILI/Ames gate, 1 remediation) | — | — |
| QC check LLM (Haiku, threshold comparison) | $0.003 | $0.004 |
| QC remediation rerun compute | $0.080 | $0.176 |
| Findings LLM (top 50 compounds ranked) | $0.060 | $0.072 |
| **Stage A subtotal** | **$0.337** | **$0.645** |

#### Stage B — PBPK Simulation (top 10 compounds)

| Component | AWS COGS | BioMate charge |
|---|---|---|
| Chained routing LLM (reads ADMET output) | $0.018 | $0.022 |
| PBPK ODE solve (c6i.xlarge × 20 min) | $0.057 | $0.125 |
| Allometric scaling + lung ODE | included | included |
| QC gate (AUC extrap ≤20%, 1 remediation avg) | $0.028 | $0.062 |
| Findings LLM (PK curves, Cmax/AUC/t½ table) | $0.068 | $0.082 |
| **Stage B subtotal** | **$0.171** | **$0.291** |

#### Stage C — Clinical Trial Simulation / BOIN Dose Escalation (top 3 compounds)

| Component | AWS COGS | BioMate charge |
|---|---|---|
| Chained routing LLM | $0.012 | $0.014 |
| BOIN simulation (c6i.large × 12 min) | $0.017 | $0.037 |
| BOIN QC gate (MTD coherence check) | $0.006 | $0.013 |
| Findings LLM (dose table, toxicity probabilities) | $0.052 | $0.062 |
| **Stage C subtotal** | **$0.087** | **$0.126** |

#### Chain Orchestration + Report

| Component | AWS COGS | BioMate charge |
|---|---|---|
| Inter-stage data passing (S3 JSON reads) | $0 | $0 |
| IND §2.6.1 narrative (Sonnet, all 5 sections) | $0.562 | $0.674 |
| Regulatory compliance check (Haiku) | $0.005 | $0.006 |
| DOCX assembly (Galaxy backend, no Batch) | $0 | $0 |
| Total networking (JSON outputs, tiny) | $0.005 | $0.005 |
| **Orchestration subtotal** | **$0.572** | **$0.685** |

#### Chain Summary

| Stage | AWS COGS | BioMate charge |
|---|---|---|
| A — ADMET | $0.337 | $0.645 |
| B — PBPK | $0.171 | $0.291 |
| C — Clinical Trial | $0.087 | $0.126 |
| Orchestration + Report | $0.572 | $0.685 |
| **Total chain** | **$1.167** | **$1.747** |

**Assessment:** Under $2 BioMate charge for a complete 3-stage IND-preparation pipeline. Cost is ~50% LLM, ~50% compute. Starter tier can run this 28× per month within included credits.

---

### Use Case 4: Regulatory / IND Report Writing (LLM-intensive, minimal compute)

**Scenario:** User has already run the drug discovery workflows. They request BioMate to generate the complete FDA §2.6.1 Written Summary and §2.7.2 Summary of Clinical Pharmacology Studies. No new Batch jobs needed — Galaxy backend assembles from existing S3 results.

#### LLM Costs (the dominant cost driver)

| Section | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| §2.6.1.1 — Overview & Objectives | Sonnet 4.5 | 18,000 | 5,500 | $0.054 + $0.083 = $0.137 |
| §2.6.1.2 — Pharmacokinetics narrative | Sonnet 4.5 | 28,000 | 9,000 | $0.084 + $0.135 = $0.219 |
| §2.6.1.3 — Pharmacodynamics narrative | Sonnet 4.5 | 22,000 | 7,500 | $0.066 + $0.113 = $0.179 |
| §2.6.1.4 — Metabolism | Sonnet 4.5 | 18,000 | 5,000 | $0.054 + $0.075 = $0.129 |
| §2.6.1.5 — Excretion & interactions | Sonnet 4.5 | 15,000 | 4,500 | $0.045 + $0.068 = $0.113 |
| §2.7.2 clinical summary (tables) | Haiku 4.5 | 25,000 | 8,000 | $0.006 + $0.010 = $0.016 |
| Regulatory compliance check pass | Haiku 4.5 | 10,000 | 2,000 | $0.003 + $0.003 = $0.006 |
| Iterative revision (user requests 2 edits avg) | Sonnet 4.5 | 10,000 | 3,000 | $0.030 + $0.045 = $0.075 |
| **LLM subtotal** | | **~146K tokens total** | | **$0.874** |

#### Compute Costs

| Item | Cost |
|---|---|
| Galaxy backend (always-on EC2 sunk cost) | $0 incremental |
| DOCX assembly via python-docx | $0 (runs on Galaxy EC2) |
| S3 GET (existing results, same region) | $0 |
| DOCX egress (user download, ~2 MB) | $0.0002 |
| **Compute + networking subtotal** | **~$0** |

#### Summary

| Component | AWS COGS | BioMate charge |
|---|---|---|
| LLM | $0.874 | $1.049 |
| Compute | $0 | $0 |
| Networking | $0.001 | $0.001 |
| **Total** | **$0.875** | **$1.050** |

**Assessment:** Report writing is almost entirely LLM cost. BioMate's ~$1 COGS per full IND report is very healthy — users on Premium get ~285 reports per month within AI token allowance. The margin on report writing is high; this is a feature worth emphasizing in sales.

---

### Use Case 5: Single-Cell RNA-seq + Permutation Tests (Seurat 5)

**Scenario:** 500K cells × 33K genes (pre-processed count matrix, ~10 GB .h5ad file), Leiden clustering, cell type annotation, marker gene identification with 1,000-permutation FindMarkers test

#### LLM Costs

| Call | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| Routing + extraction | Sonnet 4.5 | 4,200 | 900 | $0.026 |
| Cell type annotation (comparing markers to known DB) | Sonnet 4.5 | 18,000 | 5,000 | $0.129 |
| Trajectory analysis findings | Sonnet 4.5 | 10,000 | 3,500 | $0.083 |
| Methods + figure legends | Sonnet 4.5 | 8,000 | 4,000 | $0.084 |
| **LLM subtotal** | | | | **$0.322** |

#### Compute Costs

| Step | Instance | Duration | AWS COGS | BioMate charge (2.2×) |
|---|---|---|---|---|
| QC + preprocessing (doublet removal, normalization) | m6i.2xlarge | 30 min | $0.192 | $0.422 |
| PCA + graph construction | m6i.4xlarge | 20 min | $0.256 | $0.563 |
| Leiden clustering + UMAP | m6i.4xlarge | 45 min | $0.576 | $1.267 |
| Marker gene identification (Wilcoxon) | m6i.4xlarge | 30 min | $0.384 | $0.845 |
| **Permutation FindMarkers (1,000 perms, 10 clusters)** | **m6i.8xlarge** | **3 h** | **$4.608** | **$10.138** |
| Trajectory (Monocle3/scVelo) | m6i.4xlarge | 45 min | $0.576 | $1.267 |
| **Compute subtotal** | | **~5.8 h wall-clock** | **$6.592** | **$14.502** |

> **Warning:** The current `EC2_INSTANCE_PRICING` dict in `cost_calculator.py` does not include r6i (memory-optimized) instances. Single-cell permutation tests on 500K cells need ≥256 GB RAM. If the m6i.8xlarge (128 GB) is insufficient, the job may OOM. **Action required**: add r6i instance types to `cost_calculator.py` and configure them in the Batch compute environment.

#### Networking Costs

| Item | Volume | COGS |
|---|---|---|
| S3 GET (10 GB count matrix, same region) | 10 GB | $0 |
| S3 PUT (Seurat object 8 GB, UMAP plots 500 MB) | 8.5 GB | $0 |
| User downloads (plots + tables, ~200 MB) | 0.2 GB | $0.018 |
| **Networking subtotal** | | **$0.02** |

#### Storage Costs

| Item | Size | COGS/month |
|---|---|---|
| Input count matrix (S3) | 10 GB | $0.23/mo |
| Output Seurat RDS object | 8 GB | $0.18/mo |
| UMAP/TSNE plots, CSVs | 0.5 GB | $0.012/mo |
| **Storage subtotal** | | **$0.42/mo** |

#### Summary

| Component | AWS COGS | BioMate charge |
|---|---|---|
| LLM | $0.322 | $0.386 |
| Compute | $6.592 | $14.502 |
| Networking | $0.020 | $0.020 |
| Storage (first month) | $0.420 | $0.504 |
| **Total (first month)** | **$7.354** | **$15.412** |
| **Per run (excl. storage)** | **$6.934** | **$14.908** |

**Assessment:** Permutation tests dominate cost (~68% of compute). Premium tier ($300 credit) handles ~20 such runs per month. The 3h high-memory step is the key optimization target — consider a pre-run estimate that warns users permutation testing is expensive.

---

### Use Case 6: Whole Genome Sequencing / Variant Calling (nf-core/sarek)

**Scenario:** Tumor–normal pair, 30× coverage, 200 GB FASTQ (2 × 100 GB), human GRCh38, GATK HaplotypeCaller + Mutect2, VEP annotation

#### LLM Costs

| Call | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| Routing + extraction | Sonnet 4.5 | 5,000 | 1,200 | $0.033 |
| Variant findings (pathogenicity, ClinVar, gnomAD) | Sonnet 4.5 | 22,000 | 6,000 | $0.156 |
| Methods section | Sonnet 4.5 | 9,000 | 4,500 | $0.095 |
| **LLM subtotal** | | | | **$0.284** |

#### Compute Costs

| Step | Instance | Duration | AWS COGS | BioMate charge (2.2×) |
|---|---|---|---|---|
| BWA-MEM alignment (normal, 100 GB FASTQ) | c6i.8xlarge | 3.5 h | $4.760 | $10.472 |
| BWA-MEM alignment (tumor, 100 GB FASTQ) | c6i.8xlarge | 3.5 h | $4.760 | $10.472 |
| GATK MarkDuplicates (× 2) | c6i.4xlarge | 1 h | $1.360 | $2.992 |
| GATK BaseRecalibrator (× 2) | c6i.4xlarge | 1.5 h | $2.040 | $4.488 |
| HaplotypeCaller — germline | c6i.8xlarge | 4 h | $5.440 | $11.968 |
| Mutect2 — somatic | c6i.8xlarge | 3 h | $4.080 | $8.976 |
| VEP annotation + filter | m6i.2xlarge | 1 h | $0.384 | $0.845 |
| MultiQC + report | c6i.large | 0.25 h | $0.021 | $0.046 |
| **Compute subtotal** | | **~14 h wall-clock (parallel)** | **$22.845** | **$50.259** |

#### Networking Costs

| Item | Volume | COGS |
|---|---|---|
| S3 GET (200 GB FASTQ, same region) | 200 GB | $0 |
| S3 PUT (2 × 80 GB BAM + indices) | 160 GB | $0 |
| S3 PUT (VCF, reports) | 2 GB | $0 |
| User downloads (VCF + reports, ~1.5 GB) | 1.5 GB | $0.135 |
| VPC inter-AZ if misaligned | 200 GB | $2.00 (avoidable) |
| **Networking subtotal** | | **$0.14–$2.14** |

#### Storage Costs

| Item | Size | COGS/month | Notes |
|---|---|---|---|
| Raw FASTQs (keep for reanalysis) | 200 GB | $4.60/mo | Archive to S3-IA after 90 days: $2.50/mo |
| Aligned BAM files (× 2) | 160 GB | $3.68/mo | Archive to Glacier after 6 months: $0.64/mo |
| VCF + annotation reports | 2 GB | $0.046/mo | Keep indefinitely |
| **Storage subtotal** | | **$8.33/mo** | **$3.19/mo if archived** |

#### Summary

| Component | AWS COGS | BioMate charge |
|---|---|---|
| LLM | $0.284 | $0.341 |
| Compute | $22.845 | $50.259 |
| Networking | $0.140 | $0.140 |
| Storage (first month) | $8.330 | $9.996 |
| **Total (first month)** | **$31.599** | **$60.736** |
| **Per run (excl. storage)** | **$23.269** | **$50.740** |

**Assessment:** WGS is a routine clinical bioinformatics workload — $50/run is competitive with commercial cloud bioinformatics providers (DNAnexus/Illumina BaseSpace charge $60-120 for similar pipelines). Premium tier handles ~5 tumor-normal WGS runs per month.

---

### Use Case 7: High-Throughput ADMET Screening (1,000 Compounds, Pharma/CRO)

**Scenario:** Medicinal chemistry team submits 1,000 SMILES, requests full ADMET panel (hERG, DILI, Ames, Ro5, metabolic stability, solubility), auto-loop remediates failing compounds, generates a CRO compliance package.

#### LLM Costs

| Call | Model | Input tokens | Output tokens | COGS |
|---|---|---|---|---|
| Routing + extraction | Sonnet 4.5 | 4,500 | 1,000 | $0.029 |
| Auto-loop QC round 1 (hERG + DILI failures: avg 30%) | Sonnet 4.5 | 15,000 | 4,000 | $0.105 |
| Auto-loop QC round 2 (re-screen 300 remediated) | Haiku 4.5 | 8,000 | 2,000 | $0.005 |
| Findings (top 100 ranked compounds, SAR summary) | Sonnet 4.5 | 20,000 | 6,000 | $0.150 |
| CRO compliance package (tabulated results, signatures) | Sonnet 4.5 | 18,000 | 5,000 | $0.129 |
| Regulatory flag check | Haiku 4.5 | 5,000 | 1,000 | $0.003 |
| **LLM subtotal** | | | | **$0.421** |

#### Compute Costs

| Step | Instance | Duration | AWS COGS | BioMate charge (2.2×) |
|---|---|---|---|---|
| ADMET screening batch 1 (1,000 compounds, parallel × 10 workers) | c6i.xlarge × 10 | 15 min | $0.425 | $0.935 |
| Auto-loop remediation (300 compounds resubmitted) | c6i.xlarge × 3 | 8 min | $0.068 | $0.150 |
| CRO compliance assembly (Galaxy backend) | on Galaxy EC2 | — | $0 | $0 |
| **Compute subtotal** | | **~23 min wall-clock** | **$0.493** | **$1.085** |

#### Networking Costs

| Item | Volume | COGS |
|---|---|---|
| SMILES input (text, <1 MB) | negligible | $0 |
| Results JSON (1,000 compound table, ~10 MB) | 0.01 GB | $0.001 |
| CRO compliance PDF download (~5 MB) | 0.005 GB | $0.0005 |
| **Networking subtotal** | | **~$0.002** |

#### Summary

| Component | AWS COGS | BioMate charge |
|---|---|---|
| LLM | $0.421 | $0.505 |
| Compute | $0.493 | $1.085 |
| Networking | $0.002 | $0.002 |
| Storage (results JSON, 30 days) | $0.002 | $0.003 |
| **Total per 1,000-compound screen** | **$0.918** | **$1.595** |

**Assessment:** Under $2 per 1,000-compound ADMET screen is highly competitive (commercial ADMET services charge $5-50/compound). Pharma CRO clients running 10 screens/month would spend ~$16 in BioMate charges — leave headroom for large Starter/Premium subscription upsells.

---

## Part 2: Long-Term Platform Fixed Costs

These are costs BioMate incurs regardless of user activity — the always-on infrastructure.

### 2.1 Always-On EC2 Instances

| Instance | IP | Role | Assumed type | On-demand/mo | Reserved 1yr/mo |
|---|---|---|---|---|---|
| Main app server | 52.42.49.175 | Galaxy backend + Node.js frontend + all SQLite DBs | m6i.2xlarge | **$280/mo** | $168/mo |
| Billing server | 35.86.137.71 | Lago (API, PostgreSQL, Redis, PDF) + Java billing | m6i.xlarge | **$140/mo** | $84/mo |
| **EC2 subtotal** | | | | **$420/mo** | **$252/mo (reserved)** |

> **Action:** Move both to 1-year reserved instances for $168/mo savings. At current usage, converting to Reserved is safe.

### 2.2 ElastiCache Redis

| Cluster | Endpoint | Usage |
|---|---|---|
| Billing cache | biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com | Real-time billing counters, quota reservations |

| Node type | On-demand/mo | Reserved 1yr/mo |
|---|---|---|
| cache.t3.micro (1 vCPU, 0.5 GB) | $12/mo | $7/mo |
| cache.r6g.large (2 vCPU, 13 GB) — if high write volume | $121/mo | $73/mo |

Current usage (billing counters only) likely fits `cache.t3.micro`. Upgrade to `cache.r6g.large` only if >100 concurrent active users. **Estimated: $12/mo.**

### 2.3 S3 Storage (Platform-Level, Growing)

| Bucket / Purpose | Current size | Growth rate | COGS/month |
|---|---|---|---|
| `biomate-nextflow-work` — workflow outputs | ~500 GB (est.) | +50 GB/mo per active user | $11.50/mo base |
| Dev-sync cache (galaxy_ai_tools.db 259 MB, etc.) | ~2 GB | static | $0.046/mo |
| Custom AMI snapshots (ami-08fe495be97a3dbf4) | ~10 GB | static | $0.50/mo |
| ECR container images | ~5 GB | +1 GB/mo | $0.50/mo |
| **S3 subtotal (baseline, no user data)** | | | **$12.55/mo** |

> **Important:** User data is billed back to users (per the billing system). Platform-level S3 is only dev-sync, AMI, and ECR.

### 2.4 AWS Lambda

| Function | Trigger rate | Invocation cost/mo | Duration cost/mo |
|---|---|---|---|
| `biomate-batch-billing` | Per Batch job state change | Free (< 1M free tier) | ~$0.01 |
| `biomate-s3-billing` | Per S3 object put/delete | Free (< 1M free tier) | ~$0.01 |
| **Lambda subtotal** | | | **~$0.02/mo** |

### 2.5 AWS Batch Infrastructure (Always-On Components)

| Component | Cost |
|---|---|
| VPC NAT Gateway (Batch jobs to internet) | $0.045/hr × 730 = **$32.85/mo** + data processing |
| NAT Gateway data processing ($0.045/GB) — est. 50 GB/mo API calls | $2.25/mo |
| Application Load Balancer (if used) | $5.84/mo + usage |
| EventBridge rule (batch-billing trigger) | Free (< 14M events free) |
| **Batch infra subtotal** | | **~$41/mo** |

> **Important:** NAT Gateway is the hidden cost sink in Nextflow-on-Batch architectures. Every Nextflow status poll, every Docker pull, every package install goes through NAT. Use S3 VPC Gateway endpoints and ECR VPC interface endpoints to eliminate most of this traffic.

### 2.6 CloudWatch Logs & Metrics

| Resource | Volume | COGS/month |
|---|---|---|
| Log ingestion (Galaxy + Node.js + Lambda) | ~5 GB/mo | $2.50/mo |
| Log storage (30-day retention) | ~150 GB-month | $4.50/mo |
| Custom metrics (billing counters, job counts) | ~50 metrics | $12/mo |
| CloudWatch alarms | 10 alarms | $1.00/mo |
| **CloudWatch subtotal** | | **~$20/mo** |

### 2.7 External SaaS Services

| Service | Pricing model | Estimated COGS/month |
|---|---|---|
| Lago (self-hosted on EC2) | EC2 cost only (see 2.1) | $0 incremental |
| Stripe | 2.9% + $0.30 per transaction | Scales with revenue |
| Email (SES) | $0.10/1,000 emails | ~$1/mo (10K emails) |
| Domain + Route 53 | $0.50/zone + queries | ~$2/mo |
| SSL (ACM) | Free | $0 |
| **SaaS subtotal** | | **~$3/mo + Stripe % of revenue** |

### 2.8 LLM API Base Costs (Platform-Level, Not User-Attributed)

Some LLM calls are platform overhead, not attributable to a specific user's workflow:

| Call type | Frequency | Monthly volume | COGS/mo |
|---|---|---|---|
| Health checks / test prompts | 10/day | 300 calls | $0.03 |
| Benchmark evaluations (BixBench, routing eval) | Weekly | 200 calls avg | $0.20 |
| Admin AI queries (debugging, log analysis) | Ad-hoc | ~50 calls | $0.05 |
| **Platform LLM subtotal** | | | **~$0.28/mo** |

### 2.9 Long-Term Fixed Cost Summary

| Category | On-demand/mo | Optimized/mo (reserved + best practices) |
|---|---|---|
| EC2 (main + billing) | $420 | $252 (reserved) |
| ElastiCache Redis | $12 | $7 (reserved) |
| S3 (platform-level only) | $13 | $13 |
| Lambda | $0.02 | $0.02 |
| AWS Batch infra (NAT, etc.) | $41 | $15 (VPC endpoints eliminate most NAT) |
| CloudWatch | $20 | $20 |
| External SaaS | $3 | $3 |
| Platform LLM overhead | $0.28 | $0.28 |
| **Total fixed (excl. Stripe)** | **$509/mo** | **$310/mo** |

---

## Part 3: Infrastructure Gaps and Risks Found

The infrastructure scan identified several gaps that affect both cost and reliability:

### Gap 1: Memory-optimized instances missing from Batch config (r6i family)

*Correction from earlier draft: The claim that "all databases are SQLite on one EC2" was wrong. BioMate runs AWS RDS PostgreSQL `biomate-postgres` (v15.17, AES-256/KMS, 7-day automated backup, hourly snapshots, 418K rows migrated from Docker on 2026-04-29). Eleven migration files (0000–0010) define user auth, sessions, audit logs, MFA, telemetry, and chat history tables. SQLite is only used for Galaxy's internal workflow engine (`universe.sqlite`) and the read-only AI tools search index (`galaxy_ai_tools.db`) — both are intentional and appropriate uses of SQLite.*

The actual gap: the Batch compute environment does not include **r6i (memory-optimized) instances**. Single-cell runs requiring >128 GB RAM (e.g., Seurat 5 on 500K cells) will OOM on the current instance list which tops out at m6i.8xlarge (128 GB).

| Instance | vCPU | RAM | On-demand | BioMate charge |
|---|---|---|---|---|
| r6i.4xlarge | 16 | 128 GB | $1.008/hr | $2.22/hr |
| r6i.8xlarge | 32 | 256 GB | $2.016/hr | $4.44/hr |
| r6i.16xlarge | 64 | 512 GB | $4.032/hr | $8.87/hr |

**Action:** Add r6i.4xlarge, r6i.8xlarge, r6i.16xlarge to `EC2_INSTANCE_PRICING` in `cost_calculator.py` and to the Batch compute environment allowed instance types. Tag them for memory-heavy workflows (single-cell, large permutation tests).

### Gap 2: No Spot compute environment — with full architecture for stable Spot usage

All Batch jobs currently run on-demand. Spot is not simply "add Spot and hope" — GPU Spot interruptions are real (g5 instances see 5–15% interruption rates in us-west-2). The following architecture makes Spot viable for Nextflow workloads:

**1. Nextflow resume makes Spot safe at the task level.**  
Nextflow caches each task's output in S3 by a hash of its inputs. When a Spot job is interrupted and retried, Nextflow's `-resume` flag skips already-completed tasks, reading their outputs from S3. This is the foundational mechanism — no custom checkpointing code needed for standard Nextflow workflows.

**2. Batch job retry on interruption.**  
Set `attempts: 3` in all Batch job definitions. AWS Batch automatically re-queues Spot-interrupted jobs. Combined with Nextflow `-resume`, a job interrupted at step 15 of 20 will retry and pick up from step 15.

**3. Mixed Spot/on-demand fleet with CAPACITY_OPTIMIZED strategy.**  
Configure the GPU Batch compute environment with:
- `allocationStrategy: SPOT_CAPACITY_OPTIMIZED` — picks Spot pools with the most available capacity, minimizing interruption probability
- `bidPercentage: 60` — bid up to 60% of on-demand price (Spot typically clears at 30%; 60% bid is near-zero risk of not winning while still saving ~40%)
- Instance diversification: allow g5.xlarge, g5.2xlarge, g5.4xlarge, g5.12xlarge, g4dn.xlarge, g4dn.4xlarge — Batch picks the cheapest available

**4. On-demand fallback after N interruptions.**  
Add an EventBridge rule that counts `SPOT_CAPACITY_EXCEEDED` events per `job_id`. If a single job has been interrupted ≥3 times, the `batch_event_handler.py` Lambda calls `update_job_queue` to reroute to the on-demand queue for that invocation. Cost for the on-demand fallback is charged at 2.0× markup as usual.

**5. Which workflows can use Spot.**  

| Workflow type | Spot suitable? | Why |
|---|---|---|
| CryoEM (CryoSPARC) | Yes, with caution | CryoSPARC writes project checkpoints to disk (not S3); mount EFS or use large local NVMe to preserve state across Spot restarts |
| nf-core workflows (rnaseq, sarek, etc.) | Yes | Nextflow `-resume` handles this natively |
| Protein dynamics (GROMACS, MDAnalysis) | Yes, with checkpoint intervals | Configure GROMACS `-cpt 30` for 30-min checkpoints; each checkpoint written to S3 |
| ADMET/PBPK (short, <30 min) | Not worth it | Spot overhead exceeds savings for runs <30 min |
| IND report writing (LLM only) | N/A | No Batch job |

**6. CryoSPARC-specific Spot handling.**  
CryoSPARC does not use Nextflow and checkpoints to its local project directory. Use an EFS mount (us-west-2 EFS standard: $0.30/GB-month) attached to the Batch job. CryoSPARC's own checkpoint mechanism (written every completed job) survives Spot interruption as long as the EFS volume persists. Estimated EFS cost for a 2 TB CryoEM project: ~$50/mo during active processing, delete after completion.

**Implementation steps (in order):**
1. Create `biomate-gpu-spot` Batch compute environment with SPOT_CAPACITY_OPTIMIZED + instance list above
2. Create `biomate-gpu-spot-queue` pointing at the new environment, with `biomate-gpu-ondemand-queue` as fallback
3. Update `nextflow_executor.py`: for GPU workflows, submit to `biomate-gpu-spot-queue` by default; add `user_compute_mode` param to allow on-demand override
4. Update `batch_event_handler.py`: detect `SPOT_CAPACITY_EXCEEDED` and increment interruption counter in Redis; after 3 interruptions, reroute
5. Add EFS mount to CryoSPARC job definition

### Gap 3: NAT Gateway costs will explode with user growth

Currently estimated at $41/mo. At 100 concurrent users running Nextflow jobs, NAT data processing costs can reach $200-500/mo.

**Action:** 
1. Add S3 Gateway VPC Endpoint (free) — eliminates S3 traffic through NAT
2. Add ECR Interface VPC Endpoint ($7.30/mo) — eliminates Docker pull traffic through NAT

### Gap 4: Billing tables not yet added to the existing RDS instance

*Correction: PostgreSQL RDS `biomate-postgres` is operational with 11 migrations deployed (users, sessions, audit logs, MFA, telemetry, chat history). The infrastructure is there.*

The gap is narrower: the billing-specific tables (`billing_job_runs`, `billing_daily_usage`, `billing_monthly_snapshots`, `billing_llm_events`, `billing_invoices_cache`) defined in `20260504_BILLING_AND_MONITORING_DESIGN.md` have not been added as migrations yet. All billing state currently lives in Redis (volatile, 35-day TTL) and Lago (external SaaS, no per-run cost breakdown).

**Action:** Add migrations 0011–0016 to `frontend/migrations/` using the SQL schema from the billing design doc. These slot directly into the existing Drizzle ORM + RDS setup. No new infrastructure needed — just new tables in the database that already exists and is already encrypted, backed up, and SOC2-compliant.

---

## Part 4: Unit Economics by Tier

Combines per-run costs with fixed infrastructure overhead at different user scales.

### Assumptions
- Fixed cost at current scale: $310/mo (optimized)
- BioMate takes 20% margin target (charge = COGS / 0.80)
- Stripe fee: 2.9% + $0.30 per subscription payment

| Tier | Monthly fee | Compute COGS included | LLM COGS included | Fixed overhead allocation | Gross margin target |
|---|---|---|---|---|---|
| Academic (free) | $0 | $6.80 (at 2.2×) | $0.42 (at 1.2×) | $31 (60 users sharing) | −$38/user/mo |
| Starter | $49 | $22.70 | $4.17 | $15 | +$7/user/mo |
| Premium | $199 | $136.40 | $20.80 | $8 | +$34/user/mo |
| Team | $599 | $363.60 | $83.33 | $5 | +$147/user/mo |

**Break-even point:** ~45 paying users at Starter tier fully covers $310/mo fixed cost.

**Key insight:** Academic tier is loss-making at $38/user/month. The cost is mostly the fixed EC2 overhead allocated per user. Capping Academic at 1 concurrent run and 2h max job duration limits COGS to ~$7.22/user/mo (compute + LLM combined), making it close to break-even once fixed costs are spread across enough paid users.

---

## Part 5: Cost Optimization Priorities

Ranked by impact:

| Priority | Action | Monthly savings | Effort |
|---|---|---|---|
| 1 | Reserve main EC2 + billing EC2 (1yr) | $168/mo | Low — 1-click |
| 2 | Add S3 VPC Gateway Endpoint | $15-100/mo (scales with traffic) | Low — 30 min |
| 3 | Enable Spot compute environment for GPU jobs | 60-70% on GPU runs | Medium — 2 days |
| 4 | S3 lifecycle rules: auto-archive old BAM/MRC to Glacier | $20-200/mo per 100 active users | Low — 1 day |
| 5 | Haiku for routing/classification, Sonnet only for synthesis | ~40% on LLM per session | Low — model swap in galaxy-assistant.ts |
| 6 | Enable Claude prompt caching for system prompt | 90% reduction on cached input tokens | Medium — 1 day |
| 7 | Add r6i instances to Batch for single-cell workloads | Prevents OOM failures (reliability, not cost) | Medium — 1 day |
| 8 | RDS Serverless v2 for billing tables | ~$0-15/mo (replaces need for Redis for non-realtime data) | High — migration |

---

*This document covers BioMate's operational costs as of 2026-05-04. All figures use published AWS us-west-2 pricing. Spot prices are estimates based on historical averages and may vary. Re-validate GPU Spot prices quarterly as market rates shift with A10G availability.*
