# Sending Your First Query to BioMate

BioMate accepts natural-language questions and converts them into fully parameterised
bioinformatics workflows. You do not need to know which tools to use or how to configure
them — describe the experiment, and BioMate takes it from there.

---

## What BioMate Can Do

BioMate covers more than 20 scientific domains, including:

| Category | Domains |
|---|---|
| Transcriptomics | Bulk RNA-seq, single-cell RNA-seq (10x Chromium, Smart-seq2), single-nucleus RNA-seq, spatial transcriptomics |
| Epigenomics | ATAC-seq, ChIP-seq, CUT&RUN, Hi-C, bisulfite sequencing |
| Genomics | WGS (germline/somatic), WES, CRISPR screens (MAGeCK, Perturb-seq) |
| Structural biology | Cryo-EM single-particle analysis, cryo-ET, AlphaFold3 structure prediction, molecular docking |
| Proteomics | LC-MS/MS DDA, DIA-NN data-independent acquisition, phosphoproteomics, chemoproteomics |
| Drug discovery | SMILES/ADMET QC, hERG / DILI toxicity screening, pharmacogenomics (PGx), population PK/PD |
| Multi-omics | CITE-seq, multi-modal integration, trajectory analysis |
| Metagenomics | Shotgun metagenomics (human gut, soil, marine, clinical pathogen) |

---

## How to Write a Good Query

BioMate needs four things to build an accurate workflow:

1. **Organism** — human, mouse, zebrafish, etc.
2. **Sample type or tissue** — PBMC, hippocampus, liver organoid, etc.
3. **Number of samples** (and experimental design if applicable)
4. **Goal** — what biological question you are answering, or which specific analysis you need

The more of these you include, the less BioMate needs to ask you before it can proceed.

---

## Five Example Queries

### 1 — Bulk RNA-seq differential expression

```
I have 12 PBMC bulk RNA-seq samples from COVID-19 patients and healthy controls
(3 timepoints × 4 patients). I want differential expression analysis with pathway
enrichment.
```

**Why it works:** Organism is implicit (human PBMCs), sample count is explicit, the
2-factor design (timepoint × condition) is clear, and the goal specifies both DE and
enrichment. BioMate will select STAR + DESeq2 + clusterProfiler and configure a
paired-sample design matrix automatically.

---

### 2 — Structure prediction + docking

```
Run AlphaFold3 structure prediction for the human PCNA protein (UniProt P12004),
then dock aspirin against the predicted structure.
```

**Why it works:** The tool (AlphaFold3) and ligand (aspirin) are named explicitly, the
UniProt accession removes any ambiguity about which isoform, and the two-step pipeline
(predict → dock) is stated in the right order. BioMate chains AlphaFold3 with DiffDock
and passes the predicted PDB directly.

---

### 3 — Single-cell clustering and trajectory

```
I have 10x Chromium scRNA-seq data from 50,000 mouse hippocampal neurons. I need
clustering, cell type annotation, and trajectory analysis.
```

**Why it works:** Technology (10x Chromium), cell count, tissue, and species are all
present, plus an ordered list of three analyses. BioMate assigns the `scrna_neuronal`
QC profile automatically (relaxed mitochondrial threshold appropriate for neurons) and
selects Cell Ranger → Scanpy → scVI → Monocle3.

---

### 4 — CRISPRi Perturb-seq screen

```
Process my CRISPRi Perturb-seq data: I have a 500-guide library targeting 200 genes,
approximately 100,000 cells. Run MAGeCK hit calling and scVI perturbation modeling.
```

**Why it works:** Screen type (CRISPRi), library scale (500 guides / 200 genes), cell
count, and both analysis tools are stated. BioMate applies the `scrna_perturbation` QC
profile which adds guide library coverage (≥70%) and doublet fraction gates on top of
standard scRNA-seq checks.

---

### 5 — Cryo-EM single-particle analysis

```
Perform cryo-EM single-particle analysis on my TRPV1 dataset: 2,000 micrographs,
300 kV, 1.06 Å/pixel, expect approximately 3.5 Å resolution.
```

**Why it works:** Instrument parameters (voltage, pixel size) are included so BioMate
can set correct CTF estimation bounds. The particle count prediction lets BioMate estimate
compute time. Expected resolution informs the refinement stopping criterion.

---

## What Happens When BioMate Asks a Clarifying Question

If your query is ambiguous, BioMate may reply with one or more follow-up questions before
generating a workflow — for example:

> "Are your RNA-seq libraries strand-specific (e.g., dUTP / reverse-stranded)?"

You can answer the question in the same chat window. The workflow will be generated after
the clarification is resolved.

> **Note:** Clarifying questions are non-blocking. If you are confident in your initial
> description, you can click "Generate Workflow Anyway" to proceed immediately. The
> questions will be attached to the workflow card for reference.

---

## Supported Input File Formats

BioMate workflows accept the following raw data formats:

| Data type | Accepted formats |
|---|---|
| Short-read sequencing | FASTQ (.fastq.gz), FASTQ.gz pairs |
| Aligned reads | BAM, CRAM (with index) |
| Proteomics / mass spec | mzML, mzXML, raw Thermo .raw (converted) |
| Structural biology | mmCIF / CIF, PDB, mzML |
| Small molecules | SDF, SMILES strings, MOL2 |
| Gene expression matrices | 10x MEX (barcodes/matrix/features), H5AD, CSV, TSV |
| Tabular metadata | CSV, TSV, Excel (.xlsx) |
| Variant calls | VCF (bgzipped + tabixed) |

File paths or S3 URIs can be passed when you have data already staged on the platform.
For new uploads, use the file attachment button in the chat input bar.
