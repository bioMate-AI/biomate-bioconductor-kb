# BioMate Platform — User Tutorials & Feature Guide

**Date:** 2026-04-22  
**Audience:** Scientists, bioinformaticians, drug discovery researchers, CRO/compliance users  
**Purpose:** Step-by-step tutorials for every major use case, with tips drawn from the Claude reference design and production implementation.

---

## Table of Contents

1. [How to Read This Guide](#1-how-to-read-this-guide)
2. [Interface Overview](#2-interface-overview)
3. [Tutorial 1 — nf-core Read QC (beginner)](#3-tutorial-1--nf-core-read-qc-beginner)
4. [Tutorial 2 — ADMET Drug Property Prediction](#4-tutorial-2--admet-drug-property-prediction)
5. [Tutorial 3 — WGS Germline Variant Calling (GATK4)](#5-tutorial-3--wgs-germline-variant-calling-gatk4)
6. [Tutorial 4 — Cryo-EM Single-Particle Analysis](#6-tutorial-4--cryo-em-single-particle-analysis)
7. [Tutorial 5 — RNA-seq Differential Expression](#7-tutorial-5--rna-seq-differential-expression)
8. [Tutorial 6 — Drug Discovery CRO Campaign](#8-tutorial-6--drug-discovery-cro-campaign)
9. [Feature Guide — Phase Panel Deep Dive](#9-feature-guide--phase-panel-deep-dive)
10. [Feature Guide — QC Auto-Loop](#10-feature-guide--qc-auto-loop)
11. [Feature Guide — Parameter Overrides](#11-feature-guide--parameter-overrides)
12. [Feature Guide — Workflow Disambiguation](#12-feature-guide--workflow-disambiguation)
13. [Feature Guide — Watcher / Detach Mode](#13-feature-guide--watcher--detach-mode)
14. [Feature Guide — AI Findings & Methods Report](#14-feature-guide--ai-findings--methods-report)
15. [Feature Guide — Blocking Errors & License Gates](#15-feature-guide--blocking-errors--license-gates)
16. [Tips Reference Card](#16-tips-reference-card)

---

## 1. How to Read This Guide

Each tutorial follows the same structure:

- **What you'll accomplish** — the scientific output
- **What to type** — exact example query to start with
- **What BioMate does** — what to expect in the UI
- **Step-by-step walkthrough** — numbered, with screenshots described
- **Tips** — highlighted with `💡 Tip:` and sourced from the reference design

Design reference scenarios used in this guide:
- `nfcore` — fastp multi-accession QC (beginner)
- `admet` — ADMET property prediction (drug discovery)
- `gatk` — WGS germline GATK4 (genomics)
- `cryosparc` — CryoSPARC SPA reconstruction (structural biology)

---

## 2. Interface Overview

BioMate uses a **three-column layout**:

```
┌──────────────┬──────────────────────────────┬───────────────────────┐
│  Sidebar     │  Chat column                 │  Workflow panel       │
│  (left)      │  (center)                    │  (right, ~500px)      │
│              │                              │                       │
│  Navigation  │  Conversation thread         │  Phases + steps       │
│  History     │  AI responses                │  Run controls         │
│  Threads     │  Disambiguation cards        │  QC gates             │
│              │  Findings summaries          │  Output files         │
└──────────────┴──────────────────────────────┴───────────────────────┘
```

**Sidebar** — collapses to a 56px icon rail when the workflow panel is open (hover to expand labels).

**Chat column** — where you ask questions and see AI responses. The pre-execution summary appears here with a workflow card before the run starts.

**Workflow panel** — auto-opens when the AI identifies a workflow. Contains:
- **Panel header** — workflow name, domain kicker (e.g., `Genomics`), subtitle (`N processes · N phases`), live progress bar
- **Phase list** — phases A→E, each collapsible; only the active phase auto-expands
- **Settings strip** — global parameters (collapsed by default, click to expand)
- **Run footer** — one primary button: `Confirm & Run` / `Stop` / `Run Again`
- **Watcher bar** — shows whether the job is attached (SSE) or detached (AWS Batch)

💡 **Tip:** The panel width is adjustable (420–640px). Narrow it if you need more chat space for long AI responses.

---

## 3. Tutorial 1 — nf-core Read QC (beginner)

### What you'll accomplish

Quality-control and adapter-trim raw sequencing reads from two SRA accessions, producing a MultiQC report.

### What to type

```
Run fastp QC on SRR14265340 and SRR14265341
```

or with a local file:

```
Run fastp quality control on my uploaded reads file
```

### What BioMate does

1. Routes the query to `nf-core · fastp QC` (multi-accession QC pipeline)
2. Auto-fills accessions `SRR14265340, SRR14265341` from the query
3. Opens the Workflow panel with **2 phases** and **4 steps**

### Step-by-step walkthrough

**Step 1 — Review parameters before running**

The panel opens at the footer with `Confirm & Run` active. Above it, expand the **Workflow Settings** strip (click the gear row) to see:

| Parameter | Auto-filled value |
|-----------|-------------------|
| SRA accessions | SRR14265340, SRR14265341 |
| Output directory | `results/fastp_<date>/` |
| Max CPUs | 8 |

💡 **Tip:** Parameters are auto-filled from your query. If you included a species or quality threshold in your message (e.g., "Q30 threshold 85%"), BioMate will pre-populate those fields too. You don't need to fill them manually.

**Step 2 — Confirm & Run**

Click `Confirm & Run` in the footer. The button changes to `Stop` and Phase A auto-expands.

**Phase A — Download & Stage:**
- `SRA Prefetch` (running) — downloads both accessions from NCBI SRA
- `fasterq-dump` (pending) — converts `.sra` to `.fastq.gz`
- QC gate: `download_success = 100%`

**Phase B — Quality & Adapter Trim** (pending, collapsed):
- `fastp (per accession)` — adapter trimming per sample
- `MultiQC` — aggregate report

💡 **Tip:** Only the **active phase** auto-expands. Click any other phase header to expand it and see its steps. This keeps the panel compact on long pipelines.

**Step 3 — Watch live progress**

The panel header shows a progress bar: `2/4 steps · 50%`. Each step chip updates in real time:
- `pending` → grey pill
- `running` → cyan animated pill ("Running")
- `completed` → green pill ("Done")
- `failed` → red pill

**Step 4 — After run completes**

The run footer shows `Run Again`. Three links appear above it:

- **View Results** — browse output files per step (MultiQC HTML, trimmed FASTQ summary, log files)
- **AI Analysis** — Claude Haiku generates a scientific interpretation of the QC metrics
- **Download All** — ZIP archive of all outputs

💡 **Tip:** The **AI Analysis** link is worth clicking even for routine QC. It flags samples with unusual adapter contamination, low Q30 rates, or GC bias — things that MultiQC surfaces as numbers but doesn't diagnose.

---

## 4. Tutorial 2 — ADMET Drug Property Prediction

### What you'll accomplish

Predict absorption, distribution, metabolism, excretion, and toxicity properties of a small molecule. BioMate will automatically check hERG, DILI, Ames, and Ro5 compliance and re-run with modified parameters if any gate fails.

### What to type

```
Run ADMET prediction for aspirin
```

or with a specific compound:

```
Run ADMET prediction for CC(=O)Oc1ccccc1C(=O)O — check hERG and DILI
```

or with a custom endpoint list:

```
ADMET analysis for my compound (SMILES: CN1C=NC2=C1C(=O)N(C(=O)N2C)C), focus on CYP3A4 and hepatotox
```

### What BioMate does

1. Extracts SMILES from the query (or the compound name via lookup)
2. Routes to `ADMET Property Prediction` (single-phase, single-step pipeline)
3. Auto-fills SMILES, endpoint list, and output directory
4. Opens the panel; Phase A (`ADMET Prediction`) is ready to run

### Step-by-step walkthrough

**Step 1 — Review the auto-filled SMILES**

Expand the **Settings strip** and confirm:

| Parameter | Value |
|-----------|-------|
| SMILES | `CC(=O)Oc1ccccc1C(=O)O` (aspirin) |
| Endpoints | `absorption, hERG, CYP, hepatotox` |
| Model | `admet-ai v2.1` |

💡 **Tip:** If you typed a compound name instead of a SMILES string, BioMate resolves it via PubChem. You can verify the structure by clicking the SMILES value — a 2D structure preview appears.

**Step 2 — Confirm & Run**

One phase, one step. The step runs in ~30 seconds on CPU.

**Step 3 — The QC gate**

Phase A has a QC gate: `hERG IC50 > 10 µM` (safe = above threshold). If aspirin passes (it does — IC50 ≈ 390 µM), the run completes normally.

**What happens if a QC gate fails:**

For a hERG-active compound, the gate trips and an **AutoLoop card** appears inline under the phase:

```
⚠ QC gate tripped: hERG_ic50 = 2.4 µM (threshold > 10 µM)
Attempt 1 of 3

Proposed fix:
  • Reduce logP by 0.5 — add polar substituent at R3
  • Aronov 2008: hERG block correlates with logP > 3.7
  • SMILES variant: [modified SMILES shown]

[Accept & Rerun]  [Dismiss]
```

Click **Accept & Rerun** to rerun with the suggested modification. The loop runs up to 3 times.

💡 **Tip:** The auto-loop citation (Aronov 2008, Lammert 2010, Kazius 2005) is sourced from the knowledge base. If you're preparing a regulatory document, those references belong in your methods section — the **Methods Report** download pre-formats them.

**Step 4 — View findings**

After completion, the chat shows a **Findings card** with:
- Per-endpoint table (absorption, hERG, CYP1A2/2C9/3A4, Ames, DILI score, Ro5 violations)
- Pass/fail badges per gate
- Literature-backed interpretation from Claude
- Link to download the full prediction CSV

---

## 5. Tutorial 3 — WGS Germline Variant Calling (GATK4)

### What you'll accomplish

Align paired-end reads to hg38, mark duplicates, apply base quality score recalibration, and call germline variants with HaplotypeCaller. Output: filtered VCF with Ts/Tv validation.

### What to type

```
Call germline variants on SRR123456 with GATK4, hg38
```

or with local files:

```
Run GATK4 germline variant calling on my uploaded tumor-normal paired FASTQ files, reference hg38, capture kit SureSelect_v7
```

### What BioMate does

1. Routes to `WGS Germline — GATK4` (3 phases, 8 steps)
2. Auto-fills: accession `SRR123456`, genome `hg38`, aligner `bwa-mem2`, caller `HaplotypeCaller`
3. Opens the panel with the run footer showing `Confirm & Run`

### Step-by-step walkthrough

**Phase A — Alignment** (3 steps)

| Step | What it does |
|------|-------------|
| FastQC | Read quality assessment |
| BWA-MEM2 Align | Align paired reads to hg38 (16 threads) |
| Sort + Index BAM | Coordinate-sort and index the BAM |

QC gate: `mapping_rate > 95%`

💡 **Tip:** If your mapping rate comes back at 88%, don't rerun immediately — check whether the reads are from a targeted capture kit. If so, click **Adjust via Chat** (appears under the failed step) and type "the reads are from WES, not WGS — exome capture SureSelect v7". BioMate will add the interval list to Phase B's BQSR step.

**Phase B — Preprocessing** (3 steps)

| Step | What it does |
|------|-------------|
| MarkDuplicatesSpark | PCR duplicate removal (parallelized) |
| BaseRecalibrator | Build BQSR model using dbSNP v155 |
| ApplyBQSR | Apply base quality correction |

No QC gate on Phase B — it runs straight through.

**Phase C — Variant Calling** (2 steps)

| Step | What it does |
|------|-------------|
| HaplotypeCaller | Call variants in GVCF mode |
| VariantFiltration | Hard-filter SNVs (QD/FS/MQ) and indels |

QC gate: `ts_tv_ratio between 2.0–2.1`

💡 **Tip:** A Ts/Tv ratio outside 2.0–2.1 for whole-genome data usually means either contamination or reference mismatch. If the gate trips, click the gate metric in the panel — a citation appears explaining the expected range by technology (WGS vs. WES vs. targeted panel) and BioMate proposes which filter thresholds to relax.

**After run — outputs**

- `variants.vcf.gz` + index
- `multiqc_report.html` (FastQC + Picard metrics aggregated)
- Methods report (auto-generated, includes BWA-MEM2 version, GATK4 version, dbSNP build)

---

## 6. Tutorial 4 — Cryo-EM Single-Particle Analysis

### What you'll accomplish

Process raw micrographs through the full CryoSPARC SPA pipeline: motion correction → CTF estimation → particle picking → 2D classification → 3D reconstruction → FSC validation. Output: sharpened 3D density map.

### What to type

```
Run single-particle reconstruction on EMPIAR-10025 with 1.3 Å/px
```

or with uploaded micrographs:

```
Process my cryo-EM micrographs: pixel size 1.3 Å, 300 kV, uploaded .mrc files in the /cryo-data/ folder
```

### What BioMate does

1. Routes to `CryoSPARC SPA` (5 phases, 23 steps)
2. Auto-fills: `pixel_size=1.30`, `accel_kv=300`, `input=s3://cryo-data/empiar-10025/*.mrc`
3. Opens the panel — 5 phases visible; Phase A starts in pending state

### Step-by-step walkthrough

**Phase A — Motion Correction + CTF** (5 steps, auto-loop ON)

| Step | Tool | Key params |
|------|------|-----------|
| MotionCor2 | Motion correction | patch_x=5, patch_y=5, max_shift=20Å |
| Gctf | CTF estimation | defocus range 0.5–4.0 µm |
| CTFFind4 | CTF cross-check | box_size=512 |
| CTFFilter | Filter micrographs by CTF quality | — |
| CTFQualityGate | QC gate | — |

QC gates: `ctf_fit_quality > 0.2`, `astigmatism < 500Å`

💡 **Tip:** CryoEM data quality is highly dataset-dependent. If `ctf_fit_quality` is marginal (0.15–0.25), don't immediately reject the dataset — click the **AI Analysis** button after Phase A completes. Claude will assess whether the quality is sufficient for 8–10Å resolution or whether you need to re-collect.

**Phase B — Particle Picking** (4 steps, auto-loop ON)

| Step | Tool |
|------|------|
| Topaz Train | Train neural network picker on your data |
| Topaz Pick | Apply picker to all micrographs |
| Extract | Extract particle boxes |
| Rebalance | Balance particle set |

QC gate: `particle_count > 50k`

💡 **Tip:** Topaz Train is the longest step (~30–60 min on GPU). You can **detach the watcher** (click "Detach" in the watcher bar) and close the browser — the job continues on AWS Batch. Reconnect later by opening the same chat session and clicking "Reconnect watcher".

**Phase C — 2D Classification** (5 steps, auto-loop OFF)

This phase has no QC gate — manual inspection is required. After completion, expand Phase C and click `ctf_diagnostic.png` → **View** to inspect class averages.

💡 **Tip:** 2D class selection is the one step where human judgment is essential. After Phase C completes, use the **Adjust via Chat** feature: "I see ice contamination in classes 12, 17, 23 — exclude those and re-run 2D with the remaining 78 classes". BioMate will update the Extract parameters and re-queue Phase C without rerunning Phases A–B.

**Phase D — 3D Reconstruction** (5 steps, auto-loop ON)

| Step | Tool |
|------|------|
| Ab-Initio (3 classes) | Generate initial 3D model |
| Heterogeneous Refine | Sort particles into conformational classes |
| Homogeneous Refine | Polish the best class |
| Non-Uniform Refine | Account for structural variability |
| Local Refinement | Focus refinement on a sub-region |

QC gate: `gsfsc_resolution < 4.0Å`

**Phase E — FSC Validation** (4 steps, auto-loop ON)

| Step | Tool |
|------|------|
| FSC Mask | Generate tight mask around protein |
| Gold-Standard FSC | Resolution by 0.143 FSC criterion |
| Validation Report | EMDB validation checks |
| B-Factor Sharpen | Enhance high-frequency features |

QC gate: `gsfsc_0143 < 3.5Å`

💡 **Tip:** The gold-standard FSC 0.143 criterion is the EMDB submission standard. If your map resolves to 4.1Å (just missing the gate), the auto-loop proposes increasing the number of particles in Non-Uniform Refine or adjusting the B-factor. Check the **Methods Report** — it pre-fills the EMDB submission methods section with the actual resolution and all tool versions.

---

## 7. Tutorial 5 — RNA-seq Differential Expression

### What you'll accomplish

Align RNA-seq reads, quantify gene expression, and run differential expression analysis between conditions. Output: DESeq2 results table, volcano plot, pathway enrichment.

### What to type

```
Run RNA-seq differential expression between control and treatment groups — 3 replicates each, mouse mm10
```

or with uploaded files:

```
Differential expression analysis: my FASTQ files are uploaded, conditions are ctrl (samples 1-3) vs treated (samples 4-6), reference genome mm10
```

### Step-by-step walkthrough

**Phase A — Alignment & Quantification**

| Step | Tool | Notes |
|------|------|-------|
| FastQC | Read QC | |
| STAR Align | RNA-seq alignment | mm10 + GENCODE M35 annotation |
| featureCounts | Gene-level quantification | |

QC gate: `mapping_rate > 80%` (RNA-seq is lower than WGS due to splicing)

💡 **Tip:** RNA-seq mapping rates of 80–90% are normal for mouse/human. If you're analyzing a non-model organism, type "my organism is [species] — use the GFF3 annotation I've uploaded" before confirming the run. BioMate injects the custom GFF3 path into the STAR and featureCounts parameters.

**Phase B — Differential Expression**

| Step | Tool | Notes |
|------|------|-------|
| DESeq2 | Normalization + DE testing | lfcShrink applied by default |
| Volcano plot | Visualization | adj. p < 0.05, |LFC| > 1 |
| PCA | Sample-level QC | |

QC gate: `n_sig_genes between 50–5000` (flags suspiciously flat or noisy results)

💡 **Tip:** If the QC gate flags >5000 significant genes, it usually means the contrast formula is wrong (e.g., comparing wrong condition labels). Click "Adjust via Chat" and type "the condition column is called 'group' not 'treatment' in my metadata". BioMate will update the DESeq2 formula and rerun Phase B without re-aligning.

**Phase C — Pathway Enrichment**

| Step | Tool |
|------|------|
| clusterProfiler | GO + KEGG enrichment |
| pathview | KEGG pathway diagrams |
| Report | Auto-generated methods section |

After completion, the **AI Analysis** generates a biological narrative: which pathways are upregulated, which transcription factors are likely involved, and relevant literature.

---

## 8. Tutorial 6 — Drug Discovery CRO Campaign

### What you'll accomplish

Manage a full DMTA (Design–Make–Test–Analyse) loop for a lead optimization campaign: upload assay data → rank compounds → export a CRO submission CSV → validate the ADMET model → generate an IND section.

### What to type

```
Start a new drug discovery campaign — I have IC50 and hERG data for 47 compounds against KRAS G12C
```

or to open an existing campaign:

```
Show my KRAS G12C campaign — propose the next synthesis round
```

### What BioMate does

BioMate opens the **CRO Compliance Workspace** — a tabbed panel separate from the standard workflow viewer:

| Tab | Function |
|-----|----------|
| **Dashboard** | Compound ranking table, DMTA loop status, campaign round |
| **Validation** | ADMET/PBPK model validation (EMA/FDA-citable) |
| **Audit** | 21CFR11-style audit trail of all ranking decisions |
| **Auto-Retrain** | Bayesian optimizer loop status and proposal generation |
| **IND** | Auto-assembled nonclinical overview (CTD Module 2.6.1) |

### Step-by-step walkthrough

**Setting up a new campaign**

1. Type the campaign-start query above
2. BioMate opens the **Campaign Wizard** (no other panels)
3. Fill in: target protein, optimization goal (e.g., "improve IC50, keep hERG safe"), number of starting compounds
4. Upload your assay CSV: columns `compound_id, smiles, assay_type, value_uM, assay_date`
5. Click **Create Campaign** — BioMate parses, normalizes, and ranks all compounds

**Dashboard — Understanding the compound table**

| Column | Meaning |
|--------|---------|
| Rank | Composite score order (higher = better) |
| Composite score | Weighted combination of IC50 efficacy + safety penalties |
| AD status | `in_domain` = model is reliable for this compound; `out_of_domain` = flag for caution |
| Round proposed | Which DMTA round this compound was first proposed |

💡 **Tip:** `out_of_domain` doesn't mean the compound is bad — it means the model hasn't seen similar chemistry before. These compounds often warrant wet-lab confirmation before adding to the synthesis order. Click the AD flag for a similarity distance visualization.

**Proposing the next synthesis round**

Type: `Propose next round` or click the **Propose Next Round** button in the Auto-Retrain tab.

BioMate runs the Bayesian optimizer and proposes 10–20 SMILES for synthesis:
- Each proposal includes predicted IC50, hERG IC50, confidence interval, and applicability domain status
- Proposals flagged with DILI risk or Ro5 violations are highlighted in yellow

Review the proposals, select or deselect, then click **Export CRO Order** (CSV formatted for WuXi AppTec, Pharmaron, or Enamine).

💡 **Tip:** The CRO export format is vendor-specific. BioMate currently supports WuXi `compound_request_v3.csv`, Pharmaron `quote_request.xlsx`, and Enamine `REAL_Space_order.csv`. Select your vendor in the export dialog before downloading.

**Validation tab — EMA/FDA-citable model report**

After ≥20 compounds with assay results:
1. Click the **Validation** tab
2. Click **Run Validation**
3. BioMate runs PBPK and ADMET validation against the training set
4. Report shows: AAFE, within_2fold%, AFE, and Pearson r — the metrics required by EMA CHMP/CVMP guidance

💡 **Tip:** Regulatory agencies require model validation before using computational predictions in an IND. The BioMate validation report is formatted to EMA M&S guideline (2018) and FDA Physiologically Based Pharmacokinetic Analyses (2018). Download it as a PDF and attach it to your IND submission package.

**IND tab — Auto-generated regulatory document**

Type: `Generate IND section for my lead compound [compound_id]`

BioMate assembles CTD Module 2.6.1 (Pharmacology Written Summary) using:
- PBPK simulation results (§2.6.1.1 — PK narrative)
- ADMET predictions with validation metrics (§2.6.1.2 — Safety narrative)
- Clinical trial simulation parameters (§2.6.1.5 — Dosing rationale)

Each section includes 2–4 sentences of FDA regulatory prose generated by Claude, followed by tabular data.

💡 **Tip:** The IND assembly uses your actual model validation metrics as backing evidence. If the validation AAFE is >2 (poor), the narrative will flag this as a limitation rather than hiding it — this is intentional. Regulatory reviewers prefer honest uncertainty quantification over inflated claims.

---

## 9. Feature Guide — Phase Panel Deep Dive

### Phase structure

Every workflow is organized into named phases (A, B, C, …):

```
Phase A — Motion Correction + CTF                    [Running]  ─── ●
  ├── Step: MotionCor2                                [Done]
  ├── Step: Gctf                                     [Done]
  ├── Step: CTFFind4                                 [Running ...]
  ├── Step: CTFFilter                                [Pending]
  └── Step: CTFQualityGate                           [Pending]
       QC: ctf_fit_quality > 0.2 | astigmatism < 500Å
       [Auto-loop: ON]

Phase B — Particle Picking                           [Pending]  ─── ○
Phase C — 2D Classification                          [Pending]  ─── ○
```

### Actions per step

Each step row exposes context-sensitive actions:

| Step status | Available actions |
|-------------|-------------------|
| `pending` | **Skip** — skip this step and mark downstream as pending |
| `running` | *(no action — let it finish)* |
| `completed` | **Rerun** — re-execute from this step; **View outputs** — preview output files |
| `failed` | **Adjust** — edit params and rerun; **Skip** — bypass the failed step |

### Phase-level actions

At the bottom of each expanded phase:

- **Run phase** — starts the first pending step in this phase (useful after editing params)
- **Skip phase** — opens a confirmation dialog listing all downstream phases that will be affected

💡 **Tip:** Use **Skip phase** when you've already run this phase manually and want BioMate to pick up from a later phase. The confirmation dialog shows the downstream impact so you don't accidentally skip a prerequisite.

### Outputs per step

Completed steps show their output files inline:

| Icon | File type | Actions |
|------|-----------|---------|
| 📄 | Table (CSV, TSV, STAR) | View (in-panel preview) / Download |
| 🗂 | Folder | Browse |
| 🖼 | Image (PNG, MRC) | View (preview modal) / Download |

---

## 10. Feature Guide — QC Auto-Loop

### How it works

When a phase has `autoloop: true` and a QC gate fails, BioMate does not just fail the run — it:

1. Evaluates which parameter is most responsible for the gate failure
2. Looks up remediation literature (e.g., Aronov 2008 for hERG, EMDB standards for resolution)
3. Proposes adjusted parameters with a citation
4. Shows the **AutoLoop card** inline in the phase

### The AutoLoop card

```
⚠ QC gate tripped: hERG_ic50 = 2.4 µM  (threshold > 10 µM)
Attempt 2 of 3

Proposed fix:
  • Reduce logP by adding –OH at C4 (logP 3.8 → 2.9)
  • Reference: Aronov, J Med Chem 2008, Table 2
  • Modified SMILES: [modified structure]

[✓ Accept & Rerun]   [✗ Dismiss]
```

### Accept vs. Dismiss

- **Accept** — rerun the phase with the proposed modifications; attempt counter increments
- **Dismiss** — proceed without the auto-fix; the QC gate verdict is recorded in the audit log as "dismissed"

💡 **Tip:** If you've hit attempt 3/3 and the gate still fails, the loop stops and shows the best result achieved. At this point, use **Adjust via Chat** to ask a more targeted question: "What structural modifications would most improve hERG safety while keeping IC50?". Claude will reason about the SAR rather than just applying a mechanical fix.

### Configuring auto-loop per phase

The **Auto-loop toggle** appears at the bottom of each phase that supports it. Toggle it off if you want to review QC results manually before deciding whether to rerun.

---

## 11. Feature Guide — Parameter Overrides

### Two ways to override parameters

**Path A — Inline panel editor (before run):**
1. Expand the **Settings strip** (gear row at the bottom of phase list)
2. Click any parameter value to edit it inline
3. Press Enter or click away to save

**Path B — Via chat (before or after run):**
Type a message referencing the parameter, e.g.:
```
Change the pixel size to 1.15 Å and the acceleration voltage to 200 kV
```
BioMate updates the parameters in the panel and shows a toast confirming the change.

**Path C — Adjust via chat (mid-run, per step):**
1. Click **Adjust** on any step (in `failed` or `completed` state)
2. The step's parameters appear in a modal
3. Edit and click **Rerun from this step** — BioMate reruns from that step forward without restarting completed earlier steps

💡 **Tip:** Parameter changes made via chat are recorded in the audit log with a timestamp and the user message that triggered them. This is essential for 21CFR11 compliance — every parameter change has a human-readable justification automatically.

### Parameter types

| Visual indicator | Meaning |
|-----------------|---------|
| `*` asterisk | Required — run is blocked until filled |
| `note: auto-filled from query` | Extracted from your message |
| `(optional)` | Has a default; override only if needed |

---

## 12. Feature Guide — Workflow Disambiguation

### When disambiguation fires

BioMate fires a disambiguation card when:
- The query matches ≥2 workflows with scores within 3.0 points of each other
- No single workflow has a "high confidence" match

### The disambiguation card

```
┌─────────────────────────────────────────────────────────┐
│  I found two close matches for "variant calling":       │
│                                                         │
│  ● WGS Germline — GATK4               similarity 91%   │
│    Short-variant calling on hg38/hg19                   │
│                                                         │
│  ● nf-core · sarek (somatic)          similarity 88%   │
│    Tumor-normal somatic variant calling                 │
│                                                         │
│  Which pipeline would you like to run?                  │
└─────────────────────────────────────────────────────────┘
```

Click the card for the pipeline you want.

💡 **Tip:** If you see a disambiguation card when you expected a direct answer, add one clarifying word to your query: "**germline** variant calling" vs. "**somatic** variant calling". BioMate uses domain-specific keywords to skip the disambiguation gate entirely.

### Forcing a specific workflow

If you know the exact workflow name, include it:
```
Run nf-core sarek somatic variant calling on my tumor-normal pair
```
BioMate matches directly without showing a disambiguation card.

---

## 13. Feature Guide — Watcher / Detach Mode

### What the watcher is

The watcher is a real-time SSE (Server-Sent Events) stream from the BioMate backend to your browser. While it's attached, step status updates appear instantly.

### Watcher bar states

Located at the bottom of the run footer:

| State | Display | What it means |
|-------|---------|---------------|
| Attached | `● Attached · live SSE` | Real-time updates active |
| Detached | `○ Watcher detached · job on AWS Batch` | Job running; no live updates |

### When to detach

For long-running jobs (CryoEM 3D reconstruction, GROMACS MD simulation, WGS on large cohorts), you don't need to keep the browser open. Click **Detach** in the watcher bar:

1. The job continues on AWS Batch uninterrupted
2. You can close the browser tab safely
3. On your next visit, open the same chat session — BioMate restores the run state from the database

### Reconnecting

Click **Reconnect** in the watcher bar (visible when detached). The panel re-subscribes to the SSE stream and shows the current state of all steps.

💡 **Tip:** If you're running a workflow that takes >2 hours (e.g., CryoEM full SPA, GROMACS production MD), **always detach explicitly** rather than letting the browser time out. Explicit detach sets `watcher_mode = 'batch'` in the database — reconnect is one click. A browser crash without explicit detach leaves the watcher state ambiguous.

---

## 14. Feature Guide — AI Findings & Methods Report

### Findings

After a run completes, the chat shows a **Findings card** with Claude's scientific interpretation:

- Structured summary of the key result (e.g., "Mapping rate 97.4% — high-quality library")
- Anomalies and flags (e.g., "Sample 3 has elevated adapter contamination: 8.2%")
- Scientific context from the literature (e.g., "Ts/Tv ratio 2.08 is consistent with hg38 SNV expectations; Broad Institute 2023")
- Suggested next steps

💡 **Tip:** The Findings card is generated by Claude Haiku with the actual output files as context, not a canned response. If the result is unexpected, ask a follow-up: "Why does sample 3 have high adapter contamination?" Claude will reason about the data.

### Methods Report

Click **Download Methods Report** after run completion. The report is auto-generated and contains:

- Tool names and versions (e.g., BWA-MEM2 2.2.1, GATK 4.6.2.0)
- Parameter values used in the run
- Reference genome and annotation versions
- QC gate thresholds and verdicts
- For drug discovery: model validation metrics (AAFE, within_2fold%)

The format is publication-ready: paste directly into a manuscript Methods section or attach to a regulatory submission.

💡 **Tip:** The Methods Report is generated from actual execution metadata, not templates — tool versions reflect what ran in the Docker container, not what was configured. This eliminates version-mismatch errors in publications.

### Download QC Audit Log

Click **Download QC Audit Log** for a full timestamped audit trail:

```jsonl
{"event":"gate_eval","phase":"A","metric":"ctf_fit_quality","value":0.31,"threshold":0.2,"verdict":"pass","ts":"2026-04-22T14:23:01Z"}
{"event":"gate_eval","phase":"D","metric":"gsfsc_resolution","value":4.8,"threshold":4.0,"verdict":"fail","ts":"2026-04-22T18:44:12Z"}
{"event":"autoloop_proposed","phase":"D","attempt":1,"proposal":"increase n_particles to 250k","ts":"2026-04-22T18:44:13Z"}
{"event":"autoloop_accepted","phase":"D","attempt":1,"ts":"2026-04-22T18:44:20Z"}
{"event":"gate_eval","phase":"D","metric":"gsfsc_resolution","value":3.7,"threshold":4.0,"verdict":"pass","ts":"2026-04-22T20:11:33Z"}
```

This log is 21CFR11-compliant: every decision point has a timestamp, the user action (accepted/dismissed), and the data value at the time of decision.

---

## 15. Feature Guide — Blocking Errors & License Gates

### Blocking errors

If a workflow has unfilled required parameters, the panel shows a **blocking alert** at the top (not a transient toast):

```
⚠ Missing required parameters — run is disabled

  • max_memory: not set (required)
  • genome: not set (required — expected 'hg38' or 'hg19')

[Fix now]   [Confirm anyway]
```

**Fix now** — scrolls the settings strip to the first missing parameter and highlights it.

**Confirm anyway** — overrides the block (only available if BioMate can infer a safe default).

💡 **Tip:** Most blocking errors disappear if you add the missing information to your original query. Instead of retyping, click **Adjust via Chat** and type "use 128 GB memory and hg38" — BioMate updates both parameters at once without reopening the wizard.

### License gate

Some tools require external credentials (CryoSPARC license, GATK bundle S3 bucket access):

```
🔑 License required — CryoSPARC

  This workflow requires a CryoSPARC license.
  If you have one, add it in Settings → Credentials → CryoSPARC.

[Configure]
```

Click **Configure** to go directly to the credential entry form.

💡 **Tip:** CryoSPARC licenses are tied to an email address. BioMate validates the license string before enabling the run button — you won't submit a job only to fail at the container startup stage.

---

## 16. Tips Reference Card

A quick reference of all tips from this guide:

| Tip | Context |
|-----|---------|
| Parameters auto-fill from your query; add measurements in your message to pre-populate numeric fields | All workflows |
| The active phase auto-expands; click other phase headers to expand them | Phase panel |
| AI Analysis is worth clicking even for routine QC — it flags anomalies the numbers don't explain | After any run |
| Auto-loop citations belong in your Methods section; Methods Report pre-formats them | ADMET, CryoEM |
| For cryo-EM mapping rates <80%, check whether you're using a custom annotation before re-collecting | CTF phase |
| Detach the watcher for jobs >2 hours; explicit detach guarantees one-click reconnect | Long runs |
| `out_of_domain` compounds need wet-lab confirmation, not exclusion | CRO campaigns |
| CRO export format is vendor-specific; select your vendor before downloading | Drug discovery |
| The IND narrative includes honest uncertainty — reviewers prefer quantified limitations | IND assembly |
| Add "germline" or "somatic" to your query to skip disambiguation | Variant calling |
| Phase-level Skip shows downstream impact before you confirm | Phase panel |
| Parameter changes via chat are auto-documented in the audit log | All workflows |
| QC auto-loop stops at attempt 3; use Adjust via Chat for SAR-level reasoning after that | ADMET auto-loop |
| Methods Report uses actual container tool versions, not configured defaults | All workflows |
| Blocking alerts persist until fixed; they're not toasts that disappear | Missing params |

---

*Document created: 2026-04-22. For bugs or feature requests, see the in-app feedback link or file an issue at the internal tracker.*
