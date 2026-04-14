# BioMate User Manual
**Version:** April 2026  
**Audience:** Researchers, structural biologists, bioinformaticians, drug discovery scientists

---

## Table of Contents

1. [What Is BioMate?](#1-what-is-biomate)
2. [Quick Start — Your First Analysis in 5 Minutes](#2-quick-start)
3. [How to Talk to BioMate](#3-how-to-talk-to-biomate)
4. [Inputs — What You Can Upload](#4-inputs)
5. [Understanding Workflow Cards](#5-workflow-cards)
6. [Running a Workflow](#6-running-a-workflow)
7. [Outputs and Visualization](#7-outputs-and-visualization)
8. [Tracking Intermediate Steps](#8-tracking-intermediate-steps)
9. [Domain Tutorials](#9-domain-tutorials)
   - [9A. Cryo-EM — Single Particle Analysis](#9a-cryo-em)
   - [9B. Cryo-EM — Specialized Protocols](#9b-cryo-em-specialized-protocols)
   - [9C. Drug Discovery](#9c-drug-discovery)
   - [9D. Structural Biology — Structure Prediction & Docking](#9d-structural-biology)
   - [9E. Genomics — Variant Calling & RNA-seq](#9e-genomics)
10. [Licenses and Credentials](#10-licenses-and-credentials)
11. [Tips and Best Practices](#11-tips-and-best-practices)

---

## 1. What Is BioMate?

BioMate is a conversational AI platform for structural biology and life sciences research. You describe what you want to do in plain language, and BioMate:

- **Understands your scientific goal** — interprets your experiment, not just keywords
- **Selects the right workflow** — from a library of 200+ validated bioinformatics pipelines
- **Validates your inputs** — checks prerequisites before committing compute resources
- **Runs the analysis** — executes on cloud or local HPC infrastructure
- **Shows you the results** — interactive visualizations, downloadable files, audit-ready reports

BioMate is designed to reason like a domain expert. It knows when to use saposin versus MSP nanodisc, when to apply local refinement, when a functional assay is required before cryo-EM, and how to choose between AlphaFold3 and Chai-1 based on your license situation.

---

## 2. Quick Start

### Step 1 — Describe your experiment

Type what you want to do. BioMate understands scientific language:

> "I have raw cryo-EM movies of a membrane transporter in saposin nanodisc. I want to determine its structure."

> "I need to dock 20 drug candidates into the ATP-binding pocket of my kinase structure."

> "Run variant calling on these tumor/normal WGS samples with Mutect2."

### Step 2 — Answer any clarifying questions

BioMate may ask one or two questions to make the right choice:

> "Is this a single-particle analysis dataset, or are you working with in-situ / in-cell samples for tomography?"

Answer briefly. BioMate will not ask redundant questions if you already gave the information.

### Step 3 — Review the workflow card

BioMate presents a workflow card showing:
- Pipeline name and description
- Parameters (with your values pre-filled)
- Input file slots
- Expected outputs
- Any prerequisites or license requirements

Adjust parameters directly in the card if needed.

### Step 4 — Upload files (if not already uploaded)

Drag and drop files into the upload area, or provide cloud storage paths (S3, Google Drive).

### Step 5 — Confirm & Run

Click **Confirm & Run**. BioMate validates inputs, then launches the pipeline. You can watch real-time progress and inspect outputs as they arrive.

---

## 3. How to Talk to BioMate

BioMate is designed for natural, scientific language. You do not need to memorize workflow names.

### Effective query patterns

| Instead of... | Say... |
|---|---|
| "run cryosparc_standard_spa" | "I have K3 movies of a GPCR-Gi complex in MSP nanodisc. Determine the structure." |
| "run alphafold3" | "Predict the structure of this protein with its ATP ligand co-folded in." |
| "run sarek" | "Germline variant calling on these WGS FASTQ files from a trio (proband + parents)." |

### Providing context upfront saves time

The more you tell BioMate upfront, the fewer clarifying questions it asks:

**Minimal (will prompt):**
> "Process my cryo-EM data."

**Complete (runs directly):**
> "I have 2000 raw movies (.tif) from a 300 kV Titan Krios, 0.83 Å/pix, of CaV1.2 in GDN detergent (~400 kDa). Run standard SPA and give me the final map."

### What BioMate handles automatically

- Choosing between multiple valid pipelines for your goal
- Setting default parameters appropriate for your sample
- Flagging when a functional assay is required before data collection
- Detecting when your query is ambiguous (e.g., "variant calling" — germline or somatic?)

---

## 4. Inputs

### File types accepted

| Category | Formats |
|---|---|
| Raw cryo-EM movies | `.tif`, `.mrc`, `.eer` |
| Electron density maps | `.mrc`, `.map` |
| Protein structures | `.pdb`, `.cif`, `.mmcif` |
| Sequences | `.fasta`, `.fa` |
| Short reads | `.fastq`, `.fastq.gz`, `.bam`, `.cram` |
| Variant files | `.vcf`, `.vcf.gz` |
| Small molecules | `.sdf`, `.mol2`, SMILES strings |
| Tables / metadata | `.csv`, `.tsv`, `.xlsx` |
| Mass spectrometry | `.mzML`, `.mzXML` |

### Providing inputs

**Upload via drag-and-drop** — paste or drag files into the chat window.

**Reference existing files** — if you ran a previous BioMate workflow, outputs from that run are available as inputs to subsequent workflows. Just say "use the structure from my last run."

**Cloud paths** — provide S3 (`s3://bucket/key`) or other cloud storage URIs directly in your message.

**Accession numbers** — for public data, give the accession directly:
> "Download SRR1518169 and run germline variant calling."
> "Fetch PDB:6DDF and dock these compounds into the active site."

### Multiple inputs

For multi-sample workflows, you can upload multiple files at once or specify a folder path. BioMate will process them as a batch.

---

## 5. Workflow Cards

When BioMate selects a workflow, it presents a **workflow card** before running anything.

### Anatomy of a workflow card

```
┌─────────────────────────────────────────────────────────────┐
│  CryoSPARC Standard SPA                         [cryo_em]  │
│  23-step single-particle analysis pipeline                  │
├─────────────────────────────────────────────────────────────┤
│  PARAMETERS                                                 │
│  ● pixel_size          0.649 Å/pix          [required]      │
│  ● voltage             300 kV               [required]      │
│  ● total_dose          60 e⁻/Å²             [required]      │
│  ● symmetry            C1                   [optional]      │
│  ● molecular_weight_kda  45                 [optional]      │
├─────────────────────────────────────────────────────────────┤
│  INPUTS                                                     │
│  ● movies_path         ↑ Upload or provide path [required]  │
│  ● gain_ref            ↑ Upload gain reference  [optional]  │
├─────────────────────────────────────────────────────────────┤
│  PREREQUISITES                                              │
│  ✅ CryoSPARC license — provided                           │
│  ✅ Sample validated by NS-EM                               │
├─────────────────────────────────────────────────────────────┤
│  OUTPUTS                                                    │
│  • Final sharpened map (.mrc)                               │
│  • FSC curve                                                │
│  • Local resolution map                                     │
│  • QC report (.json)                                        │
│  • Model-ready half-maps                                    │
└─────────────────────────────────────────────────────────────┘
         [Edit Parameters]              [Confirm & Run]
```

### Editing parameters

Click **Edit Parameters** or describe the change in chat:

> "Change the pixel size to 0.83 and set symmetry to C4."

> "Use 40 e⁻/Å² total dose — this sample is radiation-sensitive."

BioMate will update the card and confirm before running.

### Prerequisites

Blocked prerequisites (red ✗) must be resolved before the Run button enables:
- **Missing input files** — upload or provide a path
- **License required** — see [Section 10](#10-licenses-and-credentials)
- **Functional assay not confirmed** — for some protocols (e.g., pore-forming protein SPA), BioMate requires you to confirm a lysis/transport assay passed before proceeding

---

## 6. Running a Workflow

### Execution modes

| Mode | When used | Speed |
|---|---|---|
| **Mock / Dry-run** | No data provided, or explicitly requested | Instant — synthetic outputs for testing |
| **Local** | Small datasets, development | Minutes to hours |
| **Cloud (AWS Batch)** | Large datasets, GPU-intensive steps | Scales automatically |

BioMate selects the mode automatically based on your data size and available resources. You can override: *"Run this locally"* or *"Submit to cloud."*

### What happens after you click Run

1. **Input validation** — checks file formats, sizes, and parameter ranges
2. **Pipeline launch** — workflow starts executing step by step
3. **Live progress** — steps appear as they complete, with timing
4. **Intermediate outputs** — files become available as each step finishes (you don't have to wait for the full pipeline)
5. **Completion** — final outputs collected, QC report generated, download links appear

### Pausing and resuming

If a run is interrupted, BioMate can resume from the last completed step. Say:
> "Resume my interrupted cryo-EM run."

BioMate will pick up where it left off without reprocessing completed steps.

---

## 7. Outputs and Visualization

### Output types

| Type | How BioMate shows it |
|---|---|
| **Protein structure** (.pdb, .cif) | Interactive 3D viewer — rotate, zoom, color by chain/property |
| **Electron density map** (.mrc) | Density map viewer — 2D slice navigation, contour control |
| **FSC curve** | Interactive chart — resolution at 0.143 threshold highlighted |
| **Tables** (.csv, .tsv, .json) | Sortable, searchable table viewer |
| **Images** (.png, .jpg, .svg) | Inline image display |
| **Sequences** (.fasta) | Sequence viewer with annotation |
| **Reports** (.json, .html) | Formatted summary with key metrics |

### Downloading outputs

Every completed run has a **Download** panel with:
- **Individual files** — click any output to download
- **Full package** — download all outputs as a ZIP
- **Cloud sync** — copy to your S3 bucket with one command (shown in Download Commands panel)

### Output files by pipeline category

**Cryo-EM SPA:**
- `final_map_sharpened.mrc` — submission-ready map
- `fsc_curve.png` + `fsc_data.csv` — gold-standard FSC at 0.143
- `local_resolution.mrc` — per-voxel resolution estimate
- `half_map_A.mrc`, `half_map_B.mrc` — for deposition (EMDB)
- `molprobity_report.txt` — structure validation
- `qc_report.json` — machine-readable QC summary

**Drug Discovery (docking):**
- `docked_poses.sdf` — ranked poses with scores
- `binding_affinity.csv` — ΔG estimates per compound
- `admet_report.csv` — ADMET panel results

**Genomics (variant calling):**
- `variants.vcf.gz` — filtered variant calls
- `multiqc_report.html` — per-sample QC metrics
- `annotated_variants.tsv` — functional annotation

**Structure prediction:**
- `predicted_structure.pdb` — top model
- `confidence_scores.json` — per-residue pLDDT / PAE matrix

---

## 8. Tracking Intermediate Steps

### Step timeline

During execution, BioMate shows a step-by-step timeline:

```
✅ Import movies            3.2 s
✅ Patch motion correction  4m 12s
✅ CTF estimation           1m 58s
⟳ Particle picking         running...  [2m elapsed]
○ 2D classification        pending
○ Ab-initio reconstruction pending
...
```

### Inspecting intermediate outputs

You can access outputs from any completed step before the pipeline finishes:
- Click the step name to see available files
- Download intermediate particles, CTF plots, or 2D class images
- Use intermediate maps to decide whether to continue or adjust parameters

### Asking questions mid-run

While a workflow runs, you can ask BioMate questions:
> "How many particles were picked in step 5?"
> "Show me the CTF quality plot."
> "The 2D classes look poor — should I change the box size?"

BioMate will inspect the current run state and advise.

### QC gates

Some pipelines have automatic QC gates that pause execution and require your input:

- **Reconstitution QC** (cryo-EM): "NS-EM shows nanodisc diameter 12.5 nm, within acceptable range (8-12 nm). Proceed with grid prep?" → You confirm.
- **Functional assay gate** (pore-forming protein): "Has the ANTS/DPX lysis assay confirmed >50% pore activity?" → You confirm.
- **Low yield warning**: "Only 32,000 particles passed 2D selection. Minimum for <3 Å is 200,000. Continue or adjust picking parameters?"

---

## 9. Domain Tutorials

---

### 9A. Cryo-EM — Single Particle Analysis

#### What BioMate can do

- Full 23-step CryoSPARC SPA pipeline from raw movies to deposition-ready map
- Automatic parameter selection based on molecular weight and sample type
- Particle picking: blob picker → TOPAZ deep learning (trained on your data)
- 2D and 3D classification, ab-initio reconstruction
- Non-uniform refinement, local CTF refinement, local resolution estimation
- Map sharpening and FSC validation
- Structure validation (MolProbity)

#### Typical query

> "I have 3,000 movies (.tif) of my 120 kDa ion channel in GDN detergent. 300 kV, 0.83 Å/pix, 50 e⁻/Å², total 50 frames. Run full SPA and get me a structure."

#### Key parameters to specify

| Parameter | Why it matters |
|---|---|
| **Pixel size (Å/pix)** | Most critical — set at collection, cannot be corrected later |
| **Voltage (kV)** | Always 300 or 200 — affects CTF model |
| **Total dose (e⁻/Å²)** | 50-60 standard; 40-45 for radiation-sensitive samples |
| **Molecular weight (kDa)** | BioMate uses this to set box size and defocus range |
| **Symmetry** | C1 default; set C2/C4/etc. only if you know the symmetry |

#### Pixel size guide

| Sample | Typical pixel size |
|---|---|
| Protein < 60 kDa | 0.649 Å/pix |
| Most membrane proteins, complexes 60-500 kDa | 0.83 Å/pix |
| Large complexes 500-1500 kDa | 1.06 Å/pix |
| Viral capsids, ribosomes > 1500 kDa | 1.30 Å/pix |

#### What to expect as output

After a typical run (2,000-5,000 movies, 300K particles):
- 3D map at 2.5-4 Å resolution
- FSC plot with 0.143 crossing
- Local resolution map (highlights flexible regions)
- Sharpened map ready for model building in Coot/PHENIX

#### License requirement

CryoSPARC requires a license. BioMate will prompt you to provide your license key the first time. Once saved, it's used automatically.

---

### 9B. Cryo-EM — Specialized Protocols

#### Saposin Nanodisc SPA (membrane proteins < 60 kDa)

**When to use:** Your target is a small membrane protein (transporter, channel subunit, receptor) that cannot be studied in detergent because it's too small to give good 2D classes.

**Example:**
> "I'm studying MFSD2B, a 45 kDa lipid transporter. I've reconstituted it in saposin nanodisc. Run SPA."

**What's different from standard SPA:**
- Pixel size locked to 0.649 Å/pix (BioMate enforces this)
- Dose set to 60 e⁻/Å² (small particles need more signal)
- Reconstitution QC step: BioMate validates your NS-EM nanodisc size (~10 nm) and SEC profile before proceeding
- TOPAZ deep learning picker trained on your dataset (blob picker alone misses small particles)

**Reconstitution protocol** BioMate provides as output:
- Saposin A expression and purification guidance
- γ-cyclodextrin lipid delivery parameters
- Bio-Beads detergent removal conditions
- Grid prep recommendations (UltrAuFoil, 1.5 s blot at 10°C)

---

#### GPCR-G Protein Complex SPA

**When to use:** Studying a G protein-coupled receptor in complex with a G protein (Gi, Gs, Gq, etc.) or arrestin. These complexes are ~120-150 kDa and require specific stabilization.

**Example:**
> "I have μ-opioid receptor in complex with Gi1, stabilized with scFv16, in MSP1D1ΔH5 nanodisc. Determine the structure. I'm using DAMGO as the agonist."

**What's different:**
- BioMate validates complex assembly: scFv16 presence, nucleotide-free confirmation (apyrase treatment), SEC stoichiometry
- Dual local refinement: BioMate runs separate focused refinements on the receptor TM bundle and the G protein to maximize resolution at both domains
- Supports biased agonism studies (compare G protein vs arrestin structures side-by-side)

**Assembly protocol** BioMate provides:
- Sf9 baculovirus expression for both GPCR and G protein
- Apyrase treatment timing and concentration
- scFv16 molar ratio and incubation
- MSP1D1ΔH5 nanodisc reconstitution (why ΔH5 not full MSP1D1)

---

#### Multi-Drug Atlas (pharmacology studies)

**When to use:** You want to compare drug binding across multiple compounds (e.g., 7 drugs binding the same ion channel, or 4 PAMs acting at the same allosteric site).

**Example:**
> "I have cryo-EM datasets of CaV1.2 with and without 7 different calcium channel blockers. Generate a drug atlas showing where each drug binds."

**What BioMate does:**
- Processes all datasets (apo + each drug) through identical SPA pipelines
- Generates drug-minus-apo difference maps, thresholded at ±3σ
- Validates ligand density occupancy (reports if a drug has <60% occupancy)
- Outputs a side-by-side comparison atlas

**Critical requirement:** All datasets must be collected with identical parameters (same pixel size, defocus range, dose). BioMate will warn you if parameters differ.

---

#### Cryo-ET (In-Situ / In-Cell Structures)

**When to use:** Your protein cannot be purified (membrane-embedded, cytoskeletal, part of a cellular machinery), or you want to study it in its native cellular context.

**Example:**
> "I have tilt series of FIB-milled lamellae from cells expressing my kinase. Run subtomogram averaging."

**Pipeline steps:**
- Tilt series import and quality assessment
- Tilt alignment (AreTomo2)
- Tomogram reconstruction (weighted back-projection)
- Subtomogram averaging

**Output:** Averaged subtomogram map, angular distribution plot, FSC.

---

#### Conformational Heterogeneity (3DVA)

**When to use:** Your protein has flexible regions, multiple conformational states, or you suspect functional intermediate states (e.g., a transporter in inward-facing vs outward-facing conformation).

**Example:**
> "I processed my spliceosome dataset and got a 3.5 Å structure. Now I want to resolve the different activation states in the same particle stack."

**What BioMate does:**
- Takes your existing refined particle stack as input (no re-collection needed)
- Runs 3D variability analysis (3DVA) with PCA of particle orientations
- Outputs 5-6 discrete state volumes showing the conformational trajectory
- You can then independently refine any state that looks interesting

---

### 9C. Drug Discovery

#### Typical information flow

```
Target protein structure (or predict one)
        ↓
Binding site detection (P2Rank/fpocket)
        ↓
Compound library (SDF / SMILES list)
        ↓
Docking (DiffDock / AutoDock Vina / Glide)
        ↓
ADMET screening (hERG, DILI, Ames, BBB, etc.)
        ↓
Lead optimization (REINVENT4 generative design)
        ↓
MD simulation (GROMACS) → binding affinity (MM-GBSA)
```

#### Asking BioMate to run the full pipeline

> "I have an AlphaFold model of my kinase. Screen these 50 compounds for binding to the ATP site, filter out hERG liabilities, and rank the survivors."

BioMate will chain the workflows automatically: pocket detection → docking → ADMET panel → ranked output.

#### Structure prediction before docking

If you don't have an experimental structure:
> "Predict the structure of this protein sequence (FASTA attached), then dock these ligands into the most likely binding pocket."

BioMate will choose the prediction tool based on your situation:
- **AlphaFold3** — state-of-the-art, handles ligand co-folding (requires institutional account)
- **Boltz-2** — open-weights, comparable accuracy for many targets
- **Chai-1** — no account required, good for rapid screening

#### ADMET screening

> "Run the full ADMET panel on these 200 compounds."

Outputs: hERG IC₅₀ prediction (cardiac safety), DILI hepatotoxicity score, Ames mutagenicity, blood-brain barrier permeability, oral bioavailability estimate, metabolic stability. Results in a ranked table.

#### Generative lead optimization

> "Take my top docking hit and generate 50 analogs optimized for better BBB penetration while keeping the core scaffold."

REINVENT4 will design novel molecules using reinforcement learning, filtered for drug-likeness (Lipinski) and novelty.

#### MD simulation and binding affinity

> "Run 100 ns MD simulation for my top 3 compounds in the ATP binding site and calculate binding affinity."

GROMACS pipeline outputs:
- RMSD/RMSF stability plots
- MM-GBSA ΔGbind estimate (kcal/mol)
- Binding pose trajectory (visualized in BioMate)

#### Licensed tools

| Tool | License type |
|---|---|
| Schrödinger Glide | Schrödinger license server (institutional) |
| MOE Covalent Docking | Chemical Computing Group license |
| AMBER pmemd.cuda | AMBER license agreement |

BioMate will prompt for license details. Open-source alternatives (GROMACS, AutoDock Vina, DiffDock) are always available without licenses.

---

### 9D. Structural Biology — Structure Prediction & Docking

#### Predict a protein structure

> "Predict the structure of this sequence."

or

> "Predict the structure of this kinase co-folded with its ATP ligand."

BioMate asks (if not clear): does an experimental structure already exist in the PDB? If yes, it retrieves it rather than predicting.

#### Compare two structures

> "Compare the apo and drug-bound structures of my channel. What's the RMSD? Where is the largest conformational change?"

Output: superposition image, RMSD per residue, TM-score, highlighted deviation regions.

#### Docking

> "Dock verapamil into the central cavity of this CaV1.2 structure."

Outputs: top 5 poses ranked by score, 3D interactive view of each pose, predicted binding affinity.

#### Allosteric site mapping

> "Find all potential drug binding sites on this GPCR structure."

P2Rank scores all surface pockets; BioMate highlights the most druggable sites by volume and conservation.

---

### 9E. Genomics — Variant Calling & RNA-seq

#### Germline variant calling

> "Run germline variant calling on these WGS FASTQ files from a trio (proband SRR1234, father SRR1235, mother SRR1236)."

Pipeline: nf-core/sarek (GATK HaplotypeCaller) → de novo variant detection → VCF with inheritance patterns.

Outputs: filtered VCF, annotated TSV (gene, consequence, gnomAD frequency), MultiQC HTML report.

#### Somatic variant calling (tumor/normal)

> "Somatic variant calling on these matched tumor/normal WGS samples."

Pipeline: Mutect2 (matched pair) → filtering → SBS mutational signatures. TMB calculated automatically.

Note: Always provide matched normal if available. Tumor-only mode has higher false discovery rate.

#### RNA-seq differential expression

> "I have RNA-seq data from 3 treated and 3 control samples. Find differentially expressed genes."

Pipeline: nf-core/rnaseq → DESeq2 or edgeR → volcano plot, heatmap, GO enrichment.

Outputs: DE gene table (log2FC, adjusted p-value), pathway enrichment, PCA plot.

---

## 10. Licenses and Credentials

Some tools require institutional or personal licenses. BioMate manages these through a credential store.

### Setting up a license

When BioMate detects a tool that needs a license:
1. A **license gate** appears in the workflow card
2. Click **Add License** and enter your credentials (license key, server URL, or Docker auth token)
3. Credentials are stored securely and reused for future runs
4. You can manage credentials in **Settings → Licenses**

### License-required tools

| Tool | What you need |
|---|---|
| **CryoSPARC** | License key from Structura Biotechnology. Each user must have their own. |
| **Schrödinger Glide** | License server URL (institutional floating license) |
| **MOE** | License server URL (Chemical Computing Group) |
| **AlphaFold3** | Docker account registered at alphafold.ebi.ac.uk |
| **AMBER pmemd** | AMBER license agreement + activation |

### Free / open-source alternatives

BioMate always offers an open-source path:
- CryoSPARC → RELION (fully open-source SPA)
- Schrödinger Glide → AutoDock Vina or DiffDock
- AlphaFold3 → Boltz-2 (MIT license) or Chai-1 (Apache 2.0, no registration)
- AMBER → GROMACS

---

## 11. Tips and Best Practices

### Tell BioMate more, not less

The more scientific context you give, the better BioMate performs. Include:
- Molecular weight or complex composition
- Sample preparation method (nanodisc type, detergent, stabilizer)
- Data collection parameters (if already collected)
- The scientific question (structure, mechanism, drug binding, heterogeneity)

### Never skip the functional assay

For membrane proteins, GPCRs, and pore-forming proteins:
- **Confirm your sample is functional** before committing to cryo-EM data collection
- BioMate will ask: "Has your transport/current/lysis assay passed?"
- Non-functional samples produce poor 2D classes regardless of data quality

### Validate your sample by NS-EM first

For nanodisc reconstitution and complex assembly:
- NS-EM (negative stain EM) takes 1-2 hours and prevents wasted cryo-EM sessions
- BioMate's reconstitution QC step can analyze your NS-EM image automatically
- Expected nanodisc size: saposin ~10 nm, MSP1D1ΔH5 ~9 nm

### More particles = better resolution (always)

| Target resolution | Minimum particles |
|---|---|
| 4-5 Å (secondary structure visible) | 50,000 |
| 3-4 Å (side chains) | 100,000 |
| < 3 Å (high resolution) | 200,000+ |

If you have fewer particles, BioMate will suggest re-collection options or alternative picking strategies.

### For multi-drug studies: collect apo first

Collect the apo (ligand-free) dataset before any drug datasets. Use the apo structure to:
1. Validate your collection parameters
2. Generate a template for template-based picking in drug datasets
3. Establish the reference for difference map subtraction

All datasets must use identical collection parameters for valid difference maps.

### Use intermediate outputs to make decisions

You don't have to wait for the full pipeline. After step 9 (2D classification):
- If 2D classes show clear secondary structure → continue
- If 2D classes are featureless → stop, adjust concentration, or change blot conditions
- If particle count is low → re-pick with TOPAZ

Ask BioMate: *"The 2D classes from step 9 look blurry. What should I try?"*

### Keep datasets organized with descriptive names

BioMate stores run history. Name your runs descriptively:
> "saposin_nanodisc_mfsd2b_0649_60dose_apr2026"

This makes it easy to reference previous runs and resume them.

---

## Appendix — Common Failure Modes and Solutions

| Symptom | Likely cause | What to do |
|---|---|---|
| 2D classes are featureless / circular | Sample aggregated, wrong concentration, or poor ice | Optimize concentration by NS-EM; try lower protein concentration |
| CTF estimation fails | Thick ice, wrong pixel size entered | Check pixel size in acquisition metadata; re-collect thinner |
| Very few particles picked | Blob picker parameters wrong for your particle size | Switch to TOPAZ; adjust particle diameter estimate |
| Resolution plateaus at 4-5 Å | Too few particles, or preferred orientation | Collect more data; try tilted stage collection |
| Poor local resolution at one domain | Domain is flexible | Run focused local refinement with a soft mask on that domain |
| Drug difference map shows no density | Low occupancy, or wrong normalization | Check drug concentration relative to Kd; ensure identical collection params |
| Pipeline fails at GPU step | GPU memory exceeded | Reduce batch size or switch to larger instance type |
| Structure validation fails (MolProbity > 2.5) | Map resolution insufficient for model building, or clashes | Collect more data; run additional real-space refinement cycles |

---

*BioMate is developed by the BioMate team. For support, contact the platform team or file an issue in the project repository.*
