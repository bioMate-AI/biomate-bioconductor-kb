# BioMate AI — Pilot Study User Guide

**Version 1.0 | March 2026**
**Audience: Life Science Researchers (Pilot Partners)**

---

> This guide walks you through three core tasks on the BioMate platform: submitting a research query, monitoring your workflow while it runs, and reading and exporting your QC report. No bioinformatics software experience is required.

---

## Page 1 — How to Submit a Query

### Logging In

1. Open your browser and go to **[biomate.ai](https://biomate.ai)**.
2. On the login screen, enter the **invite code** provided by your BioMate pilot coordinator. Invite codes look like `PILOT-TXCH-2026`.
3. Enter your institutional email address and click **Continue**. You will be sent a one-time verification link — click it to complete login. No password is needed.

You will land on the main chat interface.

---

### The Chat Interface

The BioMate interface has three areas:

- **Left sidebar** — your chat history and any saved sessions.
- **Centre panel** — the main chat window where you type queries and see the AI's responses.
- **Right panel** — appears after a workflow is generated; shows the workflow diagram, run status, and QC results.

To start a new analysis, click the **"+ New Chat"** button at the top of the left sidebar.

---

### Writing a Good Query

The more specific your query, the faster and more accurate BioMate's workflow will be. Think of it like briefing a very competent research assistant who has never seen your data before.

**What to include in your query:**

- The analysis type (e.g., RNA-seq differential expression, ADMET screening, proteomics QC)
- The data format you are working with (e.g., paired-end FASTQ files, PDB structure files, raw LC-MS/MS output)
- The reference organism or genome build, if applicable (e.g., human hg38, mouse mm10)
- Any specific tools you prefer, if you have a preference (e.g., STAR aligner, DESeq2, MaxQuant)

**Examples of effective queries:**

> **RNA-seq (Differential Expression):**
> "Run a differential expression analysis on paired-end RNA-seq FASTQ files from a pediatric ALL cohort. Use the human genome hg38 reference. Align with STAR, quantify with featureCounts, and run DESeq2 for differential expression between treatment and control groups. Follow with pathway enrichment using g:Profiler."

> **ADMET Screening (Drug Discovery):**
> "Perform ADMET property screening on 15 small-molecule candidates. Input is a file of SMILES strings. Predict absorption, distribution, metabolism, excretion, and toxicity. Flag compounds that fail standard Lipinski criteria or show predicted hERG toxicity."

> **Proteomics (LC-MS/MS):**
> "I have DIA-LC-MS/MS data processed through DIA-NN. Run BioMate QC to assess coefficient of variation across replicates, missing value rates, and dynamic range. Then run differential abundance analysis between two conditions and perform pathway enrichment."

**Examples of queries that are too vague:**

- "do my RNA-seq" — BioMate does not know what data you have, what species, or what comparison you want to make.
- "analyse my samples" — no data type, analysis goal, or parameters specified.

---

### Clarification Questions

After you submit your query, BioMate's AI may ask one or two follow-up questions before generating the workflow. This is normal — it ensures the workflow is built correctly for your specific data.

Common clarification questions include:

| Question | Why BioMate asks |
|---|---|
| "Is your sequencing data paired-end or single-end?" | Aligners need to know the library layout |
| "How many biological replicates do you have per condition?" | Affects statistical power and DESeq2 model design |
| "What organism is this data from? What genome build?" | Required to select the correct reference genome |
| "Do you have a specific FDR threshold in mind for differential expression?" | Sets the statistical significance cutoff |

Answer each question briefly and plainly. You do not need to use technical notation — BioMate understands plain language.

---

### What Happens Next

Once you have answered any clarification questions:

1. **BioMate generates a Nextflow workflow** — this typically takes 5–15 seconds. The workflow appears in the centre panel as a structured plan showing each step.
2. **Review the workflow** — read through the steps. You can ask BioMate to modify any step before running (e.g., "change the aligner from STAR to HISAT2").
3. **Confirm and launch** — when you are satisfied, click the blue **"Run Workflow"** button at the bottom of the workflow display. BioMate will submit the job to the compute cluster.

---

## Page 2 — How to Monitor Your Workflow

### The Active Runs Status Bar

At the top of every page, you will see the **Active Runs bar** — a narrow strip that shows you how many workflows you currently have running or queued. The labels mean:

| Label | What it means |
|---|---|
| **Running** | The workflow is actively executing on the compute cluster right now |
| **Queued** | The job has been submitted and is waiting for compute resources to become available |
| **Completed** | The workflow finished successfully; results are ready to view |
| **Failed** | The workflow stopped due to an error; the AutoFix engine may already be addressing it |

Click **"all runs"** in the status bar to expand the full Run Manager panel.

---

### The Run Manager Panel

The Run Manager lists every workflow you have submitted during this session. Each row shows:

| Column | What it means |
|---|---|
| **Name** | The short title BioMate assigned to your run, based on your query |
| **Status** | Current state (Running / Queued / Completed / Failed) |
| **Elapsed** | How long the workflow has been running (hours:minutes:seconds) |
| **Steps** | How many workflow steps have completed vs. total steps (e.g., 4 / 11) |
| **Actions** | Buttons to view results, view logs, or cancel the run |

---

### Why There Is No Progress Bar

You may notice there is no traditional percentage progress bar. This is intentional: Nextflow workflows execute many steps in parallel, and the order and duration of individual steps depends on your data size and cluster load. An estimated percentage would be misleading. Instead, the **Steps** counter gives you a reliable indicator of how far through the workflow you are.

For typical runs:

- Small datasets (< 5 GB): 10–30 minutes
- Medium datasets (5–50 GB): 30–120 minutes
- Large datasets (> 50 GB): 2–6 hours

---

### In-App Notifications

When a run completes or fails, a **toast notification** appears in the lower-right corner of the screen. It will say one of two things:

- **"Workflow completed — View results"** — click this to jump directly to the QC report in the right panel.
- **"Step failed — View & fix"** — click this to see the error log and what AutoFix is doing about it.

Notifications stay visible for 10 seconds. You can also find them in the **Notifications bell** (top right corner) at any time.

---

### The Workflow Artifact Panel (Right Side)

When a run is active, the right-side panel shows the workflow diagram with live status indicators on each step. At the top of this panel, three action buttons let you control the run:

| Button | When to use it |
|---|---|
| **Pause** | Use if you need to temporarily stop execution (e.g., you realise you submitted the wrong file). The workflow state is preserved; you can Resume it later. |
| **Resume** | Restarts a paused workflow from where it left off. |
| **Cancel** | Permanently stops and discards the run. Use this if you need to start over with different parameters. You will be asked to confirm before the run is cancelled. |

---

### QC Gates: What They Are and What to Do

BioMate monitors your workflow in real time against a set of **QC gates** — predefined quality thresholds based on published community standards. If your data does not meet a threshold mid-run, an **amber panel** appears in the right-side workflow panel.

The amber panel will say something like:

> **QC Gate Triggered — Mapping Rate**
> Observed: 62% of reads mapped | Threshold: ≥ 75% (ENCODE standard, SILVER evidence)
> This may indicate adapter contamination, a wrong genome reference, or low-quality input reads.

You have three choices:

1. **Apply suggestions** — BioMate automatically adjusts parameters (e.g., runs adapter trimming, re-aligns) and continues the workflow.
2. **Keep current** — Accept the observed value and continue anyway. Use this if you have a scientific reason to expect a lower mapping rate (e.g., highly divergent organism, spike-in controls).
3. **Cancel run** — Stop the workflow entirely to re-examine your input data before proceeding.

If you are unsure, choose **Apply suggestions**. BioMate will log what it changed so you can review it later.

---

### AutoFix: Automatic Error Recovery

If a workflow step fails for a technical reason (e.g., a tool crashes, a parameter is out of range), BioMate's **AutoFix engine** activates automatically. You do not need to do anything immediately.

AutoFix will:

1. Read the error log from the failed step
2. Identify the cause (e.g., incorrect file format, memory limit exceeded, deprecated parameter)
3. Correct the parameter or configuration
4. Restart the failed step and continue

You will receive a notification when AutoFix completes ("Step restarted successfully") or when it cannot recover ("Manual intervention needed — View logs"). In the latter case, contact your BioMate pilot coordinator with the run ID shown in the Run Manager.

---

## Page 3 — How to Read and Export Your QC Report

### Where to Find Your QC Results

When your workflow status shows **Completed**, the right-side panel switches automatically to the **QC Results view**. You can also reach it at any time by:

1. Clicking **"all runs"** in the Active Runs bar
2. Finding your completed run in the Run Manager
3. Clicking **"View results"** in the Actions column

---

### QC Evidence Levels: GOLD, SILVER, BRONZE

Every QC threshold in your report is labelled with an evidence level. This tells you how well-established the standard is in the scientific literature:

| Level | What it means | Example |
|---|---|---|
| **GOLD** | Universally accepted consensus; appears in major international guidelines or platform standards (e.g., ENCODE, GATK Best Practices) | ≥ 70% mapping rate for bulk RNA-seq (ENCODE) |
| **SILVER** | Widely used community standard; validated in multiple peer-reviewed studies but may have field-specific variation | CV < 20% across proteomic replicates |
| **BRONZE** | Established field heuristic; commonly applied in practice but not yet formalised in a guideline document | ≥ 1 million uniquely mapping reads per sample |

When citing QC thresholds in a publication, **GOLD** gates can be cited directly using the provided reference. **SILVER** gates should be cited with the associated paper. **BRONZE** gates should be described as lab-standard or field-standard heuristics.

---

### Reading the QC Gate Table

The QC Gate table is the central element of your report. Each row represents one quality check:

| Column | What it means |
|---|---|
| **Gate Name** | The name of the QC metric (e.g., "Read Mapping Rate", "Duplicate Rate", "Insert Size Distribution") |
| **Observed Value** | What BioMate measured in your actual data |
| **Threshold** | The pass/fail cutoff value |
| **Status** | PASS (green) or FAIL (red) |
| **Evidence Level** | GOLD / SILVER / BRONZE (see above) |
| **Citation** | The published standard or paper the threshold is drawn from, with a DOI link |

---

### When a Gate Is Flagged

A **FAIL** status on a QC gate is a scientific signal — it does not necessarily mean your experiment failed, but it means something in your data warrants attention before you proceed with interpretation.

Common flagged gates and what they mean:

| Flagged Gate | Likely scientific cause | What to do |
|---|---|---|
| Low mapping rate (< 75%) | Wrong genome reference, adapter contamination, or degraded RNA | Check that you specified the correct genome build; consider re-running with adapter trimming enabled |
| High duplicate rate (> 50%) | Low library complexity, over-amplification, or low input material | Note in methods; consider downsampling or re-sequencing with more input |
| Low inter-replicate correlation (r < 0.9) | Batch effect, sample mix-up, or biological outlier | Inspect PCA plot; consider removing outlier samples |
| High CV in proteomics (> 20%) | Technical variability across LC-MS/MS runs | Check instrument calibration records; re-run normalization |

BioMate provides a plain-language explanation for each flagged gate directly in the report, along with a suggested action.

---

### Exporting the QC Report

To download your report:

1. Scroll to the top of the QC Results panel.
2. Click the **"Export QC Report"** button (blue, top right of the panel).
3. A single HTML file will download to your computer. This file is self-contained — it includes all tables, charts, and citations and can be opened in any web browser without an internet connection.

The exported HTML report contains three sections:

- **Summary** — a one-paragraph overview of your analysis and overall QC pass/fail status.
- **QC Gate Table** — the full table described above, formatted for readability.
- **Methods Section Text** — a pre-written paragraph you can copy directly into a manuscript methods section. It describes the tools used, versions, parameters, and QC standards applied.

---

### Using the Methods Section Text

The **Methods Section Text** block in the exported report is designed to be publication-ready. It will look something like:

> *"RNA-seq reads were quality-controlled using FastQC v0.12.1. Adapter trimming was performed with Trim Galore v0.6.10. Reads were aligned to the human reference genome GRCh38 using STAR v2.7.11a with default parameters. Gene-level counts were generated with featureCounts v2.0.6. Differential expression analysis was performed using DESeq2 v1.42.0 with a significance threshold of adjusted p < 0.05. QC thresholds were applied per ENCODE RNA-seq standards (mapping rate ≥ 75%; duplicate rate ≤ 30%)."*

Copy this block verbatim into your manuscript. Adjust only if you deviated from the suggested parameters (BioMate will note any such deviations automatically).

---

### The Full Audit Log

Every BioMate run generates a complete **audit log** — a timestamped record of every step, parameter, tool version, QC gate evaluation, and AutoFix action taken during your analysis.

To access the audit log:

1. In the Run Manager, find your completed run.
2. Click **"View logs"** in the Actions column.
3. The audit log opens in a scrollable panel. You can also download it as a JSON file by clicking **"Download audit log"**.

**Why reviewers and editors care about the audit log:**

- It provides a complete record of computational reproducibility — any reviewer can see exactly what was run, with what parameters, at what time.
- It documents any automatic corrections made by AutoFix, so you can disclose them transparently in your methods.
- It serves as supporting evidence for journals that require data availability and reproducibility statements (e.g., Nature journals, PLOS, eLife).
- Regulatory or IRB reviewers examining a clinical or translational study can use the audit log as a provenance record for computational findings.

We recommend archiving the audit log alongside your raw data when you deposit data to a public repository (GEO, PRIDE, EMDB).

---

---

## Page 4 — Domain-Specific Workflows

This section provides step-by-step query templates and expected outputs for each of the five pilot research directions. Copy the query templates and replace the bracketed placeholders with your actual parameters.

---

### Direction A — Drug Discovery (Target Identification · ADMET · Lead Optimisation)

**What BioMate can do in a single session:**
- Survey literature and databases for candidate therapeutic targets
- Screen 10–20 compounds for ADMET liabilities before docking
- Dock surviving compounds against a target structure and return an integrated ranking
- Generate analogues of a hit compound with improved properties
- Predict retrosynthesis routes for proposed compounds

**Step 1 — Target literature survey**

Describe the target or disease; BioMate retrieves literature and database information.

```
I am working on [disease or target name].
Survey PubMed, DrugBank, and ChEMBL for known therapeutic targets:
what proteins are most frequently implicated, which have existing
inhibitors, and which have published crystal structures for docking?
Return a ranked target list with supporting evidence.
```

Expected output: Ranked target table with UniProt IDs, known inhibitor classes, structural data availability, and literature citations.

**Step 2 — ADMET screening**

Upload your compound file (SMILES format, one per line or as a CSV) and run the safety screen before docking.

```
I have [15] candidate small molecules [attach SMILES file or paste SMILES list].
Screen all of them for ADMET properties: flag any with predicted
hERG IC₅₀ below 10 µM, DILI risk HIGH, Ames mutagenicity positive,
or ClinTox flag. Return a table showing which compounds pass all gates
and which fail, with the specific failing metric for each.
```

Expected output: Table of all compounds, pass/fail status per gate, evidence level (GOLD/SILVER/BRONZE), and threshold citation. Compounds that pass proceed to docking; failed compounds are flagged but not discarded.

**Step 3 — Virtual screening and docking**

After ADMET filtering, dock the passing compounds.

```
Dock the [N] ADMET-passing compounds against [target name or PDB ID: XXXX].
Use AutoDock Vina. Return the top 10 ranked by docking score,
with poses and binding energies. Show me the integrated ranking
combining ADMET score and docking score.
```

Expected output: Ranked compound table with docking scores, binding energies, integrated ranks, and 3D pose visualisation.

**Step 4 — Lead optimisation (optional)**

```
My best compound [SMILES] docks well but has hERG IC₅₀ = 3 µM.
Generate 15 analogues that improve cardiac safety while keeping
the core scaffold and cLogP below 4. Score each for synthetic
accessibility. Predict retrosynthesis routes for the top 5.
```

Expected output: Analogue table with predicted ADMET profiles, synthetic accessibility scores, and retrosynthesis route feasibility for top candidates.

---

### Direction B — RNA-seq and Precision Medicine

**What BioMate can do in a single session:**
- Process FASTQ files through alignment, QC, and differential expression
- Run pathway enrichment and gene set analysis
- Characterise drug mechanism of action from treated vs. control RNA-seq
- Identify molecular subtypes and survival associations in patient cohorts

**Step 1 — Standard bulk RNA-seq pipeline**

```
I have paired-end bulk RNA-seq from [N treated] and [N control] samples.
Reference genome: [GRCh38 / mm10 / other].
Run alignment with STAR, QC with FastQC and MultiQC,
quantification with featureCounts, and differential expression
with DESeq2 (FDR < 0.05). Follow with GO and KEGG pathway
enrichment on the top DE genes. Apply the standard polyA
QC profile.
```

Expected output: QC report (MultiQC), DE gene table with log₂FC and FDR, GO/KEGG enrichment table, and methods section text for manuscript.

**Step 2 — Drug MoA characterisation from patient RNA-seq**

```
I have RNA-seq from [N patients treated with drug X] and
[N untreated controls]. Run differential expression with DESeq2,
identify dysregulated pathways, and search LINCS CMap for approved
drugs with a similar transcriptomic signature. Return a ranked
mechanism-of-action hypothesis and a list of drugs that produce
a concordant expression signature.
```

Expected output: DE results, pathway summary, LINCS CMap drug-signature matches ranked by similarity score, and mechanism hypothesis narrative.

**Step 3 — Patient cohort stratification**

```
I have a bulk RNA-seq expression matrix from [N patients]
with clinical outcome data [attach CSV]. Find molecular subtypes
using consensus clustering (k=2 to 6), then test whether subtypes
differ in [overall survival / progression-free survival]
using Kaplan-Meier and log-rank test.
```

Expected output: Cluster assignments, silhouette scores for k selection, Kaplan-Meier survival plot, and log-rank p-values.

---

### Direction C — Cryo-EM and AI Structures

**What BioMate can do in a single session:**
- Run CryoSPARC standard single-particle analysis (SPA) pipeline
- Predict protein structure with AlphaFold3 for targets without published data
- Detect and rank binding pockets on a solved or predicted structure
- Assess druggability of candidate pockets

**Step 1 — CryoSPARC standard SPA**

```
I have cryo-EM micrographs from a single-particle dataset
for [protein name]. Run CryoSPARC standard SPA: motion correction
(MotionCor2), CTF estimation (CTFFIND4), reference-free 2D
classification, 3D ab initio reconstruction, and non-uniform
refinement. Target resolution < 3.5 Å. Apply EMDB deposition
QC standards.
```

Expected output: Refined map (MRC format), gold-standard FSC curve, resolution estimate (FSC 0.143 criterion), per-class 2D class averages, and QC report.

**Step 2 — Structure prediction and pocket detection**

```
I have a novel protein target [paste FASTA sequence].
No published structure exists. Predict its 3D structure
with AlphaFold3, assess prediction confidence (pLDDT),
detect binding pockets with fpocket, and rank pockets
by druggability score. I want to know which pocket to target
before designing compounds.
```

Expected output: AlphaFold3 structure (PDB format), pLDDT confidence map, pocket table ranked by druggability score (volume, hydrophobicity, pocket score).

---

### Direction D — Single-Cell Perturbation

**What BioMate can do in a single session:**
- Process Cell Ranger output through normalisation, clustering, and annotation
- Test differential cell-type abundance between conditions (miloR)
- Infer cellular trajectories and lineage relationships
- Analyse CRISPR screen results (MAGeCK) to identify essential genes

**Step 1 — scRNA-seq downstream analysis**

```
I have 10x Genomics single-cell RNA-seq from [N treated]
and [N control] samples. Cell Ranger output is ready.
Run Seurat/Scanpy normalisation, PCA, UMAP embedding,
and Leiden clustering. Annotate cell types against
[Human Cell Atlas / tissue-specific reference].
Test which cell types differ in abundance between treated
and control using miloR.
```

Expected output: UMAP coloured by cell type and condition, cell-type proportion table, miloR differential abundance results, and methods text.

**Step 2 — CRISPR screen analysis (MAGeCK)**

```
I have a pooled CRISPR knockout screen [attach FASTQ files
or count table]. Library file is [attached]. Control samples:
[sample names]. Treated samples: [sample names]. This is a
[negative / positive] selection screen. Run MAGeCK count,
MAGeCK test (RRA), and pathway enrichment on the significant
hits (FDR < 0.05). Return the ranked essential gene list.
```

Expected output: Per-guide count table (with QC: mapped reads %, Gini index), gene-level RRA scores and FDR (negative + positive selection), significant hits table, and pathway enrichment on CRISPR hits.

---

### Direction E — Multi-Omics (Proteomics + Metabolomics)

**What BioMate can do in a single session:**
- Process MaxQuant or DIA-NN proteomics output to normalised protein matrix
- Run XCMS peak picking on raw LC-MS/MS files for untargeted metabolomics
- Test differential abundance for proteins and metabolites separately
- Integrate both layers: protein-metabolite correlation and joint pathway enrichment

**Step 1 — Proteomics differential abundance**

```
I have label-free quantification proteomics data from
[MaxQuant proteinGroups.txt / DIA-NN report.tsv].
Sample annotation is [attached CSV: sample_name, condition, replicate].
Run QC (missing value filter, replicate CV check),
log₂-normalise to median, and test differential abundance
between [treated] and [control] (FDR < 0.05, |FC| > 1.5).
Return a volcano plot and the significant protein list.
```

Expected output: QC report (proteins identified, missing values %, replicate CV), normalised matrix, DA results table, HTML volcano plot, and methods text.

**Step 2 — Untargeted metabolomics**

```
I have untargeted LC-MS/MS data as .mzML files [attach or provide path].
Sample metadata: [attached CSV]. Positive ion mode.
Run XCMS peak picking (centWave), align retention times,
fill missing peaks, annotate features against HMDB (10 ppm),
and test differential abundance between [treated] and [control].
Return an annotated feature table and pathway enrichment.
```

Expected output: Peak table, annotated feature table (metabolite name, HMDB ID, ppm error), DA results, pathway enrichment (KEGG).

**Step 3 — Multi-omics integration**

```
I have completed both proteomics and metabolomics analyses
for the same samples (results from Steps 1 and 2 above).
Integrate both layers: compute protein-metabolite correlations
(Pearson |r| > 0.7 across samples), identify co-regulated
protein-metabolite pairs, and run joint KEGG pathway
enrichment. Return a joint HTML report.
```

Expected output: Protein-metabolite correlation network table, shared pathway enrichment (KEGG), and a self-contained multi-omics HTML report.

---

## Page 5 — Frequently Asked Questions

**Q: How long does a typical workflow take?**

| Workflow | Dataset size | Typical run time |
|---|---|---|
| ADMET screen (10–20 compounds) | < 1 MB | 5–15 minutes |
| RNA-seq (alignment + DE, 6 samples) | 5–20 GB | 45–90 minutes |
| scRNA-seq (Seurat, 4 samples) | 10–40 GB | 60–120 minutes |
| CRISPR screen (MAGeCK) | 1–5 GB | 20–45 minutes |
| Proteomics + metabolomics | 5–30 GB | 60–150 minutes |
| CryoSPARC SPA | 50–300 GB | 3–8 hours |

**Q: Do I need to upload data to BioMate's servers?**

For the pilot, data is processed on cloud infrastructure managed by BioMate. A Data Use Agreement governs all data handling. If your institution requires on-premise processing, contact your pilot coordinator — we support private cloud deployment.

**Q: What if BioMate picks the wrong tool for my analysis?**

After BioMate generates the workflow plan (before clicking "Run Workflow"), you can ask it to use a different tool: *"Change the aligner from STAR to HISAT2"* or *"Use edgeR instead of DESeq2."* BioMate will revise the workflow before running.

**Q: What if a workflow fails?**

BioMate's AutoFix engine attempts automatic recovery for common failure types (parameter errors, memory limits, deprecated tool versions). If AutoFix cannot recover, you receive a notification with the error log and a plain-language explanation. Contact your pilot coordinator if manual intervention is needed.

**Q: Can I run multiple workflows simultaneously?**

Yes. BioMate runs submitted workflows in parallel on cloud infrastructure. The Run Manager shows all active and completed runs in a single view. There is no need to wait for one run to finish before submitting another.

**Q: How do I cite BioMate in a publication?**

Use the Methods Section Text from your QC report. It includes all tool names, versions, and parameter settings. For the BioMate platform itself, cite: *BioMate AI (biomate.ai), accessed March 2026.* A citable preprint will be available in Q2 2026.

**Q: Is the pilot free?**

Yes. Compute costs during the pilot are covered by BioMate. There is no charge for participating in the pilot programme.

---

*For questions or technical support during the pilot, contact your BioMate pilot coordinator or email [pilot-support@biomate.ai](mailto:pilot-support@biomate.ai).*

*BioMate AI LLC | biomate.ai | Pilot Program 2026 | v2.0 March 2026*
