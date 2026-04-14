# BioMate — Product & Pilot Roadmap
**Date:** 2026-04-03  
**Source:** `business/BioMate Pilot Study Execution Model-v2-20260324.xlsx` (active working model) + platform development plan  
**Four dimensions:** Pilot evaluation model × Platform function & interface × Access & hardware integration × Quality improvement & cost reduction

---

## Executive Summary

**Near term (now – May 2026):** Five pilot directions are running or starting. Three are already open (Drug Discovery, RNA-seq, Cryo-EM). Two more open mid-April (Single-Cell, Multi-Omics). All five test the same five hypotheses: workflow quality ≥80%, QC defensibility ≥70%, time ≤30 min, pricing ≥60% willing to pay, zero hallucinated tools.

**Mid term (Jun – Dec 2026):** Multi-party collaboration MVP, expanded domain coverage, P0–P1 external benchmarks, programmatic API and notebook integrations, instrument direct-connect (sequencers, mass specs, robots). First Nature Methods paper preparation begins.

**Long term (2027–2028):** Publication arc (4 papers), federated execution, smart glasses / AR lab overlays, voice API, GA4GH standard engagement.

| Track | Now – May | Jun – Dec 2026 | 2027 + |
|---|---|---|---|
| **Pilot** | 5 directions (A–E) running | Expanded institutional pilots | Portfolio-level evidence → publications |
| **Platform** | Accession pre-step, QC gate, per-domain workflows | DAG view, collaboration, spatial/epigenomics | Federated execution, metadata inference |
| **Access & hardware** | REST API, Python client | Jupyter/RStudio/VS Code extensions, LIMS/EHR, sequencer connectors | Voice API, smart glasses (Meta Ray-Ban / HoloLens), robot integration |
| **Quality & cost** | Model tiering (Haiku/Sonnet/Opus), L0–L2 cache live | L3 QC cache, FAISS embeddings, Spot instances | Feedback-driven threshold tuning, 20% cost/run reduction target |

---

## How to Read This Document

Each phase runs four tracks in parallel:
- **Pilot track** — which domains are being evaluated, at which institutions, with which hypotheses
- **Platform track** — what new capabilities are being built, shared and domain-specific
- **Access & hardware track** — how BioMate reaches users beyond the browser: instruments, robots, smart glasses, institutional systems, programmatic integrations
- **Quality & cost track** — how output quality improves and per-run cost falls over time

The pilot track drives domain-specific platform priority. The access and quality tracks are independent long-horizon investments that compound across all domains.

---

## The Five Pilot Directions

The pilot study is structured as five parallel directions (A–E), each targeting a distinct domain and institutional partner. All five share the same five evaluation hypotheses. Directions A–C launched in late March / early April. Directions D–E follow in mid-April once their respective workflow sprints complete.

| Dir | Domain | Partner institution | Window | Platform readiness |
|---|---|---|---|---|
| **A** | Drug Discovery | Zhejiang People's Hospital — Dept. of Medicine | Mar 30 – Apr 8 | Ready (40/40 E2E checks pass) |
| **B** | RNA-seq / Precision Medicine | Texas Children's Hospital — Research Institute | Mar 30 – Apr 8 | Ready (if partner data transfer delayed, public GEO dataset used to keep pilot on schedule) |
| **C** | Cryo-EM + AI Structures | St. Jude Children's Research Hospital — Dept. of Chemical Biology & Therapeutics | Apr 2 – Apr 12 | Ready (if partner data transfer delayed, public EMDB benchmark dataset used to keep pilot on schedule) |
| **D** | Single-Cell Perturbation | UT Health — Center for Precision Health | Apr 7 – Apr 17 | Mostly ready (CRISPR subworkflow sprint ~90%, target Apr 15) |
| **E** | Multi-Omics (Proteomics + Metabolomics) | St. Jude Children's Research Hospital — Dept. of Chemical Biology & Therapeutics | Apr 7 – Apr 17 | Mostly ready (LC-MS API proxy wiring ~85%, target Apr 2) |

**Primary objective** (all directions): A non-bioinformatician researcher runs a publication-ready workflow on their own data in under 60 minutes.

---

## Five Evaluation Hypotheses (All Directions)

The same five falsifiable hypotheses are tested across every pilot direction. Evidence aggregates into a portfolio-level readout.

| # | Hypothesis | Metric | Target | How measured |
|---|---|---|---|---|
| **H1** | Workflow generation quality | % of workflows that run end-to-end without manual parameter correction | ≥ 80% | UX telemetry; count interventions per session; post-run micro-survey |
| **H2** | QC governance is scientifically defensible | % of pilot researchers rating QC output publication-ready or near publication-ready | ≥ 70% | Exit survey + domain expert qualitative review |
| **H3** | Time savings are meaningful | Average time from query submission to completed result | ≤ 30 min | Backend timestamp delta vs self-reported manual baseline |
| **H4** | Pricing is accessible | % of participants willing to pay $29/month from lab budget | ≥ 60% | Exit survey willingness-to-pay question |
| **H5** | AI does not hallucinate critical steps | Count of runs failing due to non-existent tool names or incompatible parameters | 0 | Nextflow log monitoring; command-not-found errors |

**Current evidence pre-pilot:**
- H1: Drug discovery 40/40 E2E checks pass; RNA-seq confirmed on public GEO datasets
- H2: QC thresholds cited to ICH S7B (hERG), FDA/EMA DILI guidance, ENCODE, GATK, EMDB standards
- H3: Estimated realistic range 25–90 min depending on compute tier; targeting ≤30 min
- H4: Price sensitivity rated moderate-to-high in strategic analysis; $29/month to be tested
- H5: L0 cache + L2 validation + unified tool index designed to prevent; 0 incidents in internal runs

---

## Immediate Pre-Pilot Readiness (April 2026)

Tasks from the execution plan and their current status:

| Priority | Task | Status | Owner |
|---|---|---|---|
| 1 | Legal / user consent | ✅ RESOLVED — ToS at registration; consent stored with timestamp and version | Founder |
| 2 | QC report export (PDF/HTML) | ~90% — final polish before partner launch | Frontend Eng |
| 3 | Exit survey | ✅ DONE — deployed at `/pilot-exit-survey`; post-run micro-survey live | Product Eng |
| 4 | Partner scope confirmation | Partial — Direction A confirmed; B–E outreach underway | BD / Founder |
| 5 | User manual (3-page quickstart) | ~90% — final review before launch | Product / GTM |
| 6 | LC-MS agent integration (Dir E) | ~85% — API proxy wiring; target Apr 2 | Bioinformatics Eng |
| 7 | CRISPR subworkflow (Dir D) | ~90% — sprint near complete; target Apr 15 | Bioinformatics Eng |
| 8 | Walkthrough video (3 min) | ~30% — script written; recording pending | GTM |
| 9 | Backend monitoring | ~95% — queue depth + AutoFix rates exposed in admin dashboard | Backend Eng |
| 10 | Drug discovery Docker + workflows | ✅ DONE — `biomate/biomni-drug-discovery-nf:latest`; 40/40 E2E pass | Bioinformatics Eng |

---

## Phase 1 — April–May 2026 | Active Pilot Execution

### Evaluation: Directions A–E Running in Parallel

**Direction A — Drug Discovery (Zhejiang People's Hospital)**

Use case: Target identification, lead optimisation, ADMET filtering on 10–20 compounds.

| Session | Task |
|---|---|
| S1 | ADMET profiling: hERG IC50, DILI, BBB for compound set; flag high-risk |
| S2 | IVIVE hepatic clearance: CLh and extraction ratio from in vitro CLint + fu_plasma |
| S3 | Pocket detection: binding site ranking on target PDB structure |
| S4 | Pharmacophore filtering: 2D/3D model from reference inhibitors; screen library |
| S5 | Assay upload + integrated ranking: ingest IC50 + hERG data; composite score |
| S6 | CRO export: generate top-N submission package in CRO-ready format |

Deliverable: QC audit log + exportable methods report. Evidence goal: time-to-result vs prior manual approach; ADMET pass rate.

---

**Direction B — RNA-seq / Precision Medicine (Texas Children's Hospital)**

Use case: Expression analysis on disease cohort data; publication-ready QC report.

Key workflows: nf-core/rnaseq with FFPE or fresh-frozen profile; DESeq2 / edgeR differential expression; pathway enrichment (GSEA, fgsea).

Deliverable: HTML/PDF methods report + QC audit log. Evidence goal: time-to-result; QC audit log rated publication-ready by researchers.

Fallback if partner data delayed: public GEO dataset (GSE68086 — FFPE RNA-seq, or similar).

---

**Direction C — Cryo-EM + AI Structures (St. Jude — Chemical Biology & Therapeutics)**

Use case: Process raw cryo-EM data through reconstruction; evaluate BioMate QC gate against EMDB deposition standards.

Key workflows: CryoSPARC SPA (motion correction → CTF → 2D classification → 3D refinement → FSC); protocol-aware QC gates (membrane protein vs. purified protein profiles).

Deliverable: Refined map + QC report. Evidence goal: time-to-map vs manual CryoSPARC session; QC vs EMDB deposition standards.

Fallback: EMDB-deposited public benchmark dataset.

---

**Direction D — Single-Cell Perturbation (UT Health — Center for Precision Health)**

Use case: scRNA-seq + CRISPR screen; annotated cell atlas + differential abundance by perturbation.

Key workflows: nf-core/scrnaseq; cell type annotation; CRISPR guide assignment; Mixscape or differential abundance testing.

Deliverable: Annotated cell atlas + differential abundance report. Evidence goal: time-to-cell-type annotation; QC pass rate.

Note: CRISPR subworkflow sprint target Apr 15. scRNA-seq workflow is fully ready now; CRISPR scope is month-2 for this direction.

---

**Direction E — Multi-Omics: Proteomics + Metabolomics (St. Jude — Chemical Biology & Therapeutics)**

Use case: Integrated proteomics and metabolomics from same samples; pathway-level QC report.

Key workflows: LC-MS proteomics (MaxQuant/DIA-NN + Perseus); LC-MS metabolomics (XCMS + HMDB annotation); multi-omics integration (MOFA+, mixOmics).

Deliverable: Exportable QC report + methods text. Evidence goal: time-to-report vs manual pipeline; QC vs lab standards.

Note: LC-MS API proxy wiring ~85% complete (target Apr 2); LC-MS cataloged and agent exists.

---

### Platform: Shared Cross-Domain Development (April–May 2026)

These are in-flight or immediately queued, driven by what all five pilot directions need:

**1. Public-database accession pre-step** ✅ Complete (April 2026)
SRA, GEO, ArrayExpress, PDB, EMDB, UniProt, RefSeq, Ensembl, PRIDE, ChEMBL, PubChem, dbSNP, ClinVar accessions are detected in any workflow parameter and resolved automatically — fetchngs for sequencing data, RCSB/EMDB HTTP for structures, UniProt API for protein sequences — before the main workflow launches.

**2. QC report export (PDF/HTML)** — near complete
Pilot-critical: all five directions require an exportable, publication-ready QC report as their primary deliverable. Format: HTML with inline figures + PDF render.

**3. Exit survey and post-run evidence capture** ✅ Complete
Multi-page exit survey at `/pilot-exit-survey`. Post-run micro-survey captures H1/H2/H3/H5 KPIs per session. Data feeds directly into hypothesis validation tracker.

**4. Per-pipeline billing and cost transparency** ✅ Complete
Per-turn cost tracking and per-pipeline billing. Administrators see what each run costs. Pilot participants see time-to-result timestamps automatically.

**5. Job completion notifications** — in queue
Email/webhook alert when a long-running workflow finishes or hits a QC gate requiring a human decision. Needed for cryo-EM and multi-omics directions where compute time is 30–90+ min.

**6. Backend monitoring (queue depth + AutoFix health)** ~95% complete
Queue depth and AutoFix rates now exposed in admin dashboard. Essential for operating five parallel pilots without blind spots.

---

### Platform: Domain-Specific Development (April–May 2026)

**Drug Discovery (Direction A):**
- ML-based Ames mutagenicity model (replacing binary rule-based classifier)
- IVIVE: full well-stirred model with protein binding correction
- NCA regulatory-format report (FDA/EMA-ready table output)
- Compound series tracking across multiple ADMET sessions (delta-SAR view)
- CRO export: WuXi AppTec / Evotec submission format (SMILES + composite score CSV)

**RNA-seq / Precision Medicine (Direction B):**
- FFPE RNA-seq protocol profile: lowered mapping threshold (≥60%), relaxed duplication flag
- Hi-C false-positive duplication gate fix
- WES somatic 150× auto-detection and coverage profile
- Sequencing saturation metric from CellRanger output

**Cryo-EM (Direction C):**
- Phase 1A-Quick: static expansion of AI specialist knowledge (cryo-EM specific guidance in system prompt)
- FSC 0.143 gold-standard gate
- Near-threshold warnings before hard QC failure
- Membrane protein vs. purified protein profile differentiation in QC UI

**Single-Cell Perturbation (Direction D):**
- CRISPR screen subworkflow completion (guide assignment, on/off-target scoring)
- scRNA-seq cardiac mito profile: elevated mitochondrial threshold for cardiomyocytes
- Mixscape integration for CRISPR perturbation differential abundance

**Multi-Omics: Proteomics + Metabolomics (Direction E):**
- LC-MS API proxy wiring completion (DIA-NN, MaxQuant, XCMS pathways)
- mzQC format integration: QC metrics written in HUPO-PSI standard alongside native output
- Phosphoproteomics profile: FDR + phosphosite localization gate
- HMDB accession pre-step: metabolite ID → compound structure → workflow input

---

## Phase 2 — May–July 2026 | Pilot Readout + Platform Expansion

### Evaluation: Evidence Collection and Hypothesis Scoring

By end of May, all five directions will have completed their pilot windows. The portfolio readout will score each of the five hypotheses against their targets.

**Evidence collection per direction:**

| Dimension | What is captured |
|---|---|
| H1 — Workflow quality | Runs attempted, runs without manual correction; post-run micro-survey per session |
| H2 — QC defensibility | Exit survey rating; domain expert qualitative review per QC report |
| H3 — Time-to-result | Backend timestamps: query submitted → workflow complete; self-reported baseline |
| H4 — Pricing | Exit survey willingness-to-pay question; institutional vs. individual responses |
| H5 — Hallucination | Nextflow log scan: command-not-found, invalid parameter, silent mismatch events |

**External benchmark evaluations to run in parallel (P0 suite):**
- BiomniEval1 (433 tasks, 7 bioinformatics task types) — establishes general capability baseline
- SGI-Bench (503 life science samples) — validates multi-domain routing
- Cross-domain routing benchmark (150 queries, 14 domains) — adversarial routing evaluation

---

### Platform: Shared Cross-Domain Development (May–July 2026)

**7. Collaborative multi-party workflow networking** — Priority build
The core differentiator that no competitor has. First version: a run initiated by one team (e.g. sequencing core) is handed off to a downstream team (e.g. bioinformatics) with full context — parameter record, QC decision log, and output files — transferred within BioMate. The receiving team opens the same run, sees upstream outputs as their inputs, and continues. No file transfers. No email. One unbroken audit trail.

**8. Workflow DAG view**
Visual representation of multi-step workflows as a directed acyclic graph. Each node shows: status, QC result, who approved, cost incurred. Multi-party runs highlight each team's segment.

**9. Data type system**
BioMate tracks what data type each workflow produces (FASTQ → BAM → VCF → annotated VCF) and uses this to suggest the next appropriate workflow. Prevents type mismatches and enables automatic chaining suggestions across directions.

**10. Parameter sweep and parallel branches**
Run the same workflow with N parameter combinations in parallel; compare outputs side-by-side. Target use cases: alignment tool comparison (STAR vs HISAT2), reference genome version comparison, ADMET model comparison.

**11. Error recovery and workflow resume**
When a run fails mid-pipeline, BioMate surfaces the error with a diagnostic explanation and offers to resume from the last successful checkpoint (Nextflow -resume). Users do not interact with Nextflow directly.

**12. Audit trail FAIR compliance**
Every completed run produces a machine-readable record: input parameter provenance, QC decisions with evidence citations, tool versions and container digests, output checksums. Sufficient for a third party to reproduce the exact analysis.

---

### Platform: Domain-Specific Development (May–July 2026)

**Drug discovery:**
- Population PK QC gate for NCA output validation
- Schrödinger Glide integration (for institutions with active license)
- AlphaFold DB search results feeding into docking workflow (structure → pocket → docking in one session)
- Boltz-2 / Chai-1 structure prediction with credential routing (NVIDIA NIM vs local)

**Genomics / transcriptomics:**
- Somatic variant calling: tumor purity and ploidy estimation gate before variant interpretation
- Spatial transcriptomics support (Visium, Xenium): spatial QC metrics
- WGS structural variant workflow: SV caller comparison (Manta vs DELLY vs GRIDSS)

**Cryo-EM:**
- Phase 1A-Full: CryoSPARC official documentation ingested into retrieval-augmented generation system
- Protocol-specific question answering with cited sources

**Single-cell:**
- Spatial transcriptomics joint analysis (10x Visium + scRNA-seq)
- CITE-seq / multiome (RNA + ATAC) joint workflow

**Multi-omics:**
- MOFA+ factor analysis across proteomics + metabolomics layers
- Metabolomics: XCMS full pipeline with HMDB annotation and pathway enrichment
- MassIVE accession pre-step for proteomics datasets

---

## Phase 3 — Q3–Q4 2026 | Expansion, Benchmarking, Publication Preparation

### Evaluation: Multi-Institutional Expansion + External Benchmark Suite

**Pilot expansion:**
- New institutional partners in domains with demonstrated pilot success (likely A and B first)
- Multi-party institutional pilot: upstream team (sequencing core) + downstream team (bioinformatics) + clinical interpretation team all on the same platform, same run
- Validate: end-to-end multi-party handoff, single shared audit trail, billing breakdown by team

**External benchmarks (P1 suite):**
- BixBench (53 scenarios) — general bioinformatics execution capability
- BioAgentBench — robustness under corrupted inputs, decoy files, prompt perturbation
- Prereq Recovery benchmark (40 multi-turn dialogues)

**Publication preparation:**
- Paper 1 (Nature Methods) target Month 9: "BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale"
- Core data: BioMate vs MultiQC confusion matrix on 5 public datasets; pilot H1/H2/H3 evidence from 5 directions; 20 usability sessions

---

### Platform: Shared Cross-Domain Development (Q3–Q4 2026)

**13. Role-based access and team workspaces**
Formal team roles: Data Submitter, Analyst, Reviewer, Administrator. Access controls on who can view, approve, override, and export within a run.

**14. Workflow catalog browsing UI**
Searchable catalog of all 2,400+ registered workflows — filterable by domain, tool, license requirement, data type. Each entry shows: description, required inputs, example output, estimated cost.

**15. Protocol library**
Shareable, versioned protocol templates. A lab defines "our RNA-seq protocol" once — with QC profile, tool choices, parameter defaults — and applies it consistently. Protocol versions are tracked; runs record which protocol version they used.

**16. Cross-run comparison**
Compare outputs from two or more runs (different parameters, samples, or pipeline versions) side-by-side.

---

### Platform: Domain-Specific Development (Q3–Q4 2026)

**Metagenomics:**
- Long-read metagenomics (Oxford Nanopore): assembly, binning (MetaFlye + VAMB)
- AMR gene detection profile: clinical vs. environmental sample thresholds
- Host decontamination gate

**Epigenomics:**
- ATAC-seq TSS enrichment gate per tissue type
- WGBS methylation: CpG coverage gate, bisulfite conversion efficiency check

**Metabolomics:**
- Untargeted LC-MS/MS: HMDB annotation, pathway enrichment
- HMDB accession pre-step integration
- QC profile: injection order normalization, TIC stability gate

**Lab automation:**
- LIMS integration gateway: BioMate reads sample metadata from connected LIMS on run initiation
- Automated sample routing: sample type from LIMS → workflow selected without user input

---

## Phase 4 — 2027 | Scale and Standards

### Evaluation: Population-Scale Studies + Standards Engagement

**HCA scRNA-seq reanalysis (Paper 3 — Nature target):**
- Download all 600+ Human Cell Atlas scRNA-seq datasets (~50M cells)
- Apply BioMate protocol-appropriate QC to every dataset
- Test hypothesis: metabolically active tissues (cardiac, kidney, hepatocyte) are systematically over-excluded when labs apply fresh-frozen mito thresholds to high-mito tissue

**Full benchmark suite (P2):**
- ScienceAgentBench (102 code generation tasks)
- PharmaBench (11 ADMET datasets, 52,482 entries)
- All 7 BioMate-unique benchmarks (QC governance, prereq recovery, routing, protocol thresholds, audit trail FAIR, drug discovery E2E, license gating)

**Standards engagement:**
- GA4GH BQES: submit BioMate governance model as reference implementation
- HUPO-PSI: contribute mzQC-based proteomics QC governance schema

---

### Platform: Shared (2027)

**17. Federated execution** — run workflows across local HPC, AWS Batch, and on-premise clusters from a single session; unified audit trail and cost tracking across environments

**18. Metadata-driven protocol inference** — train on 500k+ GEO samples to suggest the correct QC profile from sample metadata automatically; Paper 2 (Genome Biology) capability

**19. Longitudinal sample tracking** — track the same patient or sample across multiple runs over time; flag protocol inconsistencies between timepoints

---

## Access & Hardware Integration Track

This track is about taking BioMate beyond the browser — to the bench, the clinic, the instrument room, and the open-source community. It runs independently of the pilot schedule but benefits from pilot feedback on where friction is highest.

### I. Programmatic Access — API-First Foundation (Now)

Everything BioMate does is already behind an API. The priority is exposing it cleanly for external consumers.

**REST / streaming API**
The current `POST /api/chat/stream` and `POST /api/nextflow/execute` endpoints are the foundation. Publishing a versioned public API with OpenAPI documentation enables three classes of consumers: institutional pipelines that want to call BioMate programmatically, third-party tool developers, and open-core deployments.

**Python client library** (Q2 2026)
A lightweight `biomate-client` package: `pip install biomate-client`. Covers: submit a query, poll run status, fetch outputs, download QC report. Targets bioinformaticians who want to embed BioMate calls in Snakemake rules, Nextflow subworkflows, or analysis notebooks.

```python
from biomate import BioMateClient
client = BioMateClient(endpoint="https://app.biomate.ai", api_key="...")
run = client.run("Align these FASTQ files to hg38 and call variants", files=["sample.fastq.gz"])
run.wait()
report = run.qc_report()
```

**R client** (Q3 2026)
`install.packages("biomate")` — targets bioinformaticians in Bioconductor workflows. Wraps the same REST API; returns results as SummarizedExperiment or data.frame objects.

---

### II. Notebook & IDE Integration (Q2–Q3 2026)

**Jupyter extension**
A JupyterLab extension that embeds the BioMate chat panel as a sidebar. Users can highlight a code cell, right-click → "Explain with BioMate" or "Run as BioMate workflow." Results populate the next cell as a dataframe or file reference. Targets the large segment of academic users who already live in Jupyter.

**RStudio add-in**
Same concept for RStudio: BioMate panel in the IDE, results returned as R objects. Bioconductor KB integration means BioMate can suggest the next Bioconductor step when the user's current R analysis stalls.

**VS Code extension**
For bioinformaticians writing Nextflow or Snakemake pipelines: BioMate suggests the next process block, explains a cryptic error message, or spins up a test run against a small dataset. Not a general coding assistant — scoped specifically to workflow authoring and bioinformatics script debugging.

---

### III. Institutional Workflow Integration (Q2–Q4 2026)

**LIMS gateway**
Most institutional research labs operate a Laboratory Information Management System (LabVantage, STARLIMS, Benchling, SENAITE). BioMate's LIMS gateway reads sample metadata on run initiation — sample type, collection date, patient ID (de-identified), requested assay — and pre-fills workflow parameters automatically. No manual copy-paste. The gateway is bidirectional: BioMate writes QC result and analysis status back to the LIMS record when the run completes.

Connection model: REST webhook integration (LIMS calls BioMate on sample receipt) + polling adapter (BioMate polls LIMS for new samples on a schedule). Both modes supported.

**EHR / clinical system integration** (Q3 2026)
For hospital-based pilots (Direction A at Zhejiang, Direction B at Texas Children's): BioMate can receive a de-identified patient genomic order from the EHR (Epic MyChart Research, Cerner PowerChart) via HL7 FHIR, execute the appropriate workflow, and return structured results in FHIR DiagnosticReport format. This closes the loop from clinical order to analysis result without manual data transfer, and makes BioMate's audit trail part of the clinical record.

**Galaxy integration** (ongoing)
BioMate already runs on Galaxy infrastructure. The upgrade: BioMate becomes available as a native Galaxy tool that any existing Galaxy instance can install — treating it as a first-class tool rather than a separate application. Researchers on established institutional Galaxy deployments (USEGALAXY.EU, Galaxy Australia) get BioMate's governance layer without migrating off their current platform.

**Slack / Teams bot** (Q3 2026)
For teams that already live in Slack or Microsoft Teams: a BioMate bot that accepts natural-language queries in a channel, executes the workflow, and posts the QC report summary back to the thread. Long-running jobs post a completion notification when done. Targets the "someone needs a quick answer on this dataset" use case in collaborative lab environments.

---

### IV. Hardware Integration — Lab Instruments (Q3 2026 – 2027)

The goal: BioMate becomes the intelligence layer between a physical instrument and a researcher's analysis, eliminating the step where a researcher manually moves data from instrument to analysis platform.

**Sequencing instruments (Illumina, Oxford Nanopore)**
Integration model: BioMate monitors a watched folder (local or S3) for new run output. When a sequencing run completes, BioMate automatically detects the run type from the run manifest, selects the appropriate QC and analysis workflow (RNA-seq, WGS, amplicon, etc.), and initiates the run without user action. The researcher receives a notification with the QC summary and a link to the full report.

For Oxford Nanopore: MinKNOW generates real-time FAST5/POD5. BioMate's integration calls the Guppy/Dorado basecalling workflow as part of the auto-triggered pipeline.

**Mass spectrometers (Thermo, Bruker, Waters)**
Integration model: instrument software (Xcalibur, Compass, MassLynx) exports raw data to a watched folder. BioMate's LC-MS agent detects the file format, selects the correct processing workflow (DIA-NN for DIA, MaxQuant for DDA, XCMS for metabolomics), and launches the pipeline. On completion, the mzQC-formatted QC report is written back to the lab's data archive alongside the processed result files.

**Liquid handling robots (Opentrons, Hamilton, Tecan)**
Integration model: BioMate generates protocol scripts for liquid handling robots from natural-language descriptions. A researcher types "Set up a 96-well ELISA for these 48 samples in duplicate with 4 standard dilutions"; BioMate generates a validated Opentrons Python protocol file and optionally submits it to the robot directly via the Opentrons API. Completed plate layout is returned to BioMate for ingestion into the next analysis step.

This closes a loop that currently requires manual protocol writing, robot programming, and manual result entry — three separate steps with manual handoffs.

**Automated imaging systems (high-content screening, cryo-EM)**
For high-content screening platforms (Operetta, ImageXpress): BioMate monitors the image acquisition job, applies the appropriate segmentation and feature extraction workflow when acquisition completes, and returns a QC summary flagging acquisitions with low cell density, focus issues, or edge effects.

For cryo-EM (Direction C): BioMate monitors the EPU or SerialEM session, applies the real-time QC profile (CTF quality, motion score), and posts a mid-session report so the operator can abort a bad session early rather than discovering the problem during offline processing.

---

### V. Physical Interface — Smart Glasses & Voice (2027)

The wet lab is a hands-free environment. Smart glasses (Meta Ray-Ban, Google Glass Enterprise Edition 2, Microsoft HoloLens 2) and voice interfaces enable BioMate to be used without touching a keyboard — which is essential when a researcher's hands are occupied with pipettes, specimens, or sterile technique.

**Voice interface (Q3 2026 — prerequisite)**
Before glasses: a voice API mode where BioMate accepts spoken queries via microphone and responds in speech synthesis. Targets: lab coat pocket with earbuds, bench-mounted tablet, or fume hood with voice-only input. The primary use case is protocol lookup, parameter confirmation, and run status checks during active bench work.

**Smart glasses integration — first version (2027)**
Target hardware: Meta Ray-Ban smart glasses (available now, ~$300) or Google Glass Enterprise.

Interaction model:
1. Researcher says "BioMate, what buffer should I use for this protein at pH 7.4?" → spoken answer overlaid in the researcher's field of view
2. Researcher scans a QR code on a sample tube → BioMate pulls up the sample's current analysis status and QC flags
3. Researcher photographs a gel or plate → BioMate identifies the pattern, checks against expected result, and flags anomalies in real time

The glasses do not run BioMate — they are a thin input/output device. Speech is transcribed on-device and sent to BioMate API; the response is rendered as text overlay or spoken audio.

**AR overlay for cryo-EM and imaging (2027)**
More advanced: BioMate overlays QC annotations directly on the researcher's view of the microscope screen. Good regions highlighted in green, poor-quality regions flagged in red, particle count estimated in real time. Requires higher-end AR hardware (HoloLens 2 or Magic Leap) and close integration with the microscope control software.

---

## Quality Improvement & Cost Reduction Track

This track runs permanently. Quality and cost are both functions of where intelligence sits (model, cache, pre-computation) and how well the system learns from feedback.

### I. Model Selection Strategy — Intelligence Where It Matters (Now)

Not every step needs the most capable model. The current and target allocation:

| Task | Current model | Target | Rationale |
|---|---|---|---|
| Intent classification (routing) | Claude Haiku | Haiku | Fast, cheap, correct ≥95% of the time for routing |
| Semantic reranking of workflow candidates | Claude Haiku | Haiku | Ranking from a small candidate list; Haiku sufficient |
| Workflow generation + parameter advice | Claude Sonnet | Sonnet | Needs reasoning; Haiku too weak |
| QC decision explanation + remediation | Claude Sonnet | Sonnet | Scientific precision required |
| Complex multi-domain reasoning / novel queries | Claude Opus | Opus (on-demand) | Reserved for genuinely hard cases only |
| Open-answer benchmark scoring (LLM judge) | Claude Haiku | Haiku | Scoring is pattern-matching; Haiku cheaper |
| Accession classification | Regex (no LLM) | Regex | Zero cost; 100% deterministic |
| Prerequisite validation | Rule engine | Rule engine | Zero cost; deterministic |

**Cost lever**: Each Haiku call costs ~40× less than Opus. Routing every query through Haiku first (with Sonnet/Opus escalation only when needed) dramatically reduces per-session cost. Current architecture already does this for routing; the upgrade is adding an explicit complexity score to decide when to escalate.

---

### II. Caching — Pay Once, Reuse Many Times (Q2 2026)

Several BioMate operations are deterministic or near-deterministic given the same input: routing classification, workflow search, parameter validation, QC threshold lookup.

**L0 cache — exact query match**
If the exact query string has been seen before, return the cached workflow selection and parameters. Hit rate on repeated lab queries (same protocol, different samples) can be >60% in institutional settings.

**L1 cache — intent classification**
The intent classifier output (preferred_domains, penalized_domains, key_terms) is cached by query hash. Haiku is only called on cache miss. In practice, 20 common query patterns cover >80% of requests.

**L2 cache — workflow search results**
Search result sets are cached by (query_hash, domain_filter). Valid for 24 hours. Invalidated when the workflow catalog changes.

**L3 cache — QC thresholds**
Protocol profiles (FFPE, membrane protein, phosphoproteomics, etc.) are static — they change only when a new publication updates the evidence. Loaded at startup; no per-request LLM call needed for threshold lookup.

**Savings estimate**: caching reduces LLM call volume by an estimated 40–60% in production institutional settings with repeated similar queries.

---

### III. Pre-Computation and Indexing (Q2 2026)

**Workflow parameter pre-validation**
Parse and validate Nextflow parameter schemas at catalog registration time, not at execution time. Store the parsed schema in the DB. When a user submits parameters, validate against the stored schema in milliseconds — no file I/O, no subprocess.

**Embedding pre-computation**
Pre-compute semantic embeddings for all 2,400+ workflow descriptions and store in a vector index (FAISS or pgvector). Per-request search time drops from 200ms (Haiku API call) to <10ms (vector similarity). The Haiku reranker still runs on the top-10 candidates, but the initial retrieval is purely local.

**Knowledge base indexing**
The 2,280+ Bioconductor packages are already SQLite-indexed. Upgrade: add full-text search with TF-IDF weighting over package descriptions and vignette text so BioMate can answer "which Bioconductor package handles batch correction for scRNA-seq?" without an LLM call.

---

### IV. Feedback Loops — Quality That Improves With Use (Q2 2026 – ongoing)

**Per-session micro-survey**
After every workflow run, a 3-question feedback prompt: Was the workflow selection correct? Was the QC decision useful? Would you change any parameter? Responses train the routing classifier and QC threshold confidence scores over time.

**Expert review queue**
QC decisions that users override (Proceed against a WARN/FAIL gate) are flagged for periodic expert review. If the override was scientifically justified, the threshold or profile is updated. If the override was mistaken, it informs user education materials. This is how the protocol profiles become more accurate without manual curation.

**Benchmark regression detection**
The P0 benchmark suite (BiomniEval1, SGI-Bench, routing) runs on a weekly schedule in CI. If any score drops >5% from the prior week's baseline, the deployment is flagged and the responsible code change identified. Quality regressions are caught before users notice them.

**Error pattern analysis**
Nextflow log errors are classified automatically: command-not-found (hallucination), invalid parameter (schema error), resource exhaustion (compute configuration), tool version mismatch (container issue). Each class has a distinct remediation path. Aggregate error patterns drive prioritization of which tool integrations need hardening.

---

### V. Compute Cost Optimization (Q2 2026 – ongoing)

**Spot instance scheduling**
Non-interactive batch workloads (large RNA-seq cohorts, HCA reanalysis) run on AWS Spot instances at ~70% discount. BioMate's Nextflow executor already supports AWS Batch; the upgrade is a Spot-aware queue configuration with on-demand fallback for time-sensitive runs.

**Tiered compute routing**
Small runs (single sample, <2GB input) route to a lightweight local executor. Medium runs (10–100 samples) route to AWS Batch with moderate instance types. Large runs (cohort-scale, >100 samples) route to Batch with Spot + larger instance types. The tier is selected automatically based on input file size and estimated workflow resource requirements.

**Mock mode for development and testing**
Workflows include a `mock_mode` parameter that produces synthetic but structurally correct outputs without running actual tools. Used in CI, benchmark harness, and pilot sessions that do not yet have real data. Zero compute cost. Already implemented; ongoing improvement is expanding mock output fidelity so it catches more real-world edge cases.

**Cost attribution and budgets**
Per-user, per-project, and per-institution cost attribution already exists (Lago integration). The upgrade: budget caps with configurable alerts — a lab PI sets a monthly budget; BioMate alerts at 80% consumed and queues (rather than refuses) new runs when the cap is reached.

---

### VI. Quality Metrics (Ongoing)

The quality of BioMate's outputs is tracked continuously across four dimensions:

| Dimension | Metric | Current target | How tracked |
|---|---|---|---|
| Routing accuracy | Top-1 correct workflow selected | ≥80% on 150-query benchmark | Weekly CI benchmark run |
| QC defensibility | % of QC decisions rated publication-ready | ≥70% (pilot hypothesis H2) | Exit survey; expert review queue |
| Hallucination rate | Runs failing due to non-existent tool/parameter | 0 | Nextflow log classification |
| Prereq recovery | % of missing-input cases resolved in ≤2 turns | ≥85% | Prereq recovery benchmark |
| Time-to-result | Median time query→completed result | ≤30 min | Backend timestamps |
| Cost per run | Average LLM + compute cost per workflow completion | Reduce 20% per 6 months | Billing dashboard aggregation |

The last metric — cost per run — is a designed-in goal: as caching, pre-computation, and model selection improve, the per-run cost falls while quality stays flat or improves.

---

## Summary Timeline

```
                  PILOT                    PLATFORM                  ACCESS & HARDWARE       QUALITY & COST
2026
─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Mar 30–Apr 8      Dir A (Drug Discovery)   Accession pre-step live   REST API (live)         Model tiering live
                  Dir B (RNA-seq)                                                             (Haiku/Sonnet/Opus)
Apr 2–Apr 12      Dir C (Cryo-EM)
Apr 7–Apr 17      Dir D (Single-Cell)      LC-MS wiring              Python client (beta)    L0–L2 cache live
                  Dir E (Multi-Omics)      mzQC integration
Apr 15            CRISPR sprint done       FSC cryo-EM gate
                  → Dir D full scope
Apr (ongoing)                              QC export · User manual   R client (beta)         Spot instance routing
                                           ML Ames · IVIVE · NCA

May               All 5 pilots complete    DAG view (start)          Jupyter extension Q2    L3 QC threshold cache
                  H1–H5 portfolio readout
                  P0 benchmarks run

Jun – Jul                                  Multi-party handoff MVP   RStudio add-in          FAISS embeddings live
                                           Parameter sweep           VS Code extension       Feedback micro-survey
                                           Error recovery

Aug – Sep         Multi-party instit.      Role-based access         LIMS gateway            P1 benchmarks
                  pilot (expanded)         Protocol library          EHR/FHIR adapter        Weekly CI benchmarks
                                           Spatial transcriptomics   Sequencer connectors    Expert review queue

Oct – Dec                                  Paper 1 prep (Nat Meth)   Mass spec connectors    20% cost/run target
                                           Workflow catalog UI       Robot (Opentrons) API   Error pattern analysis
                                           Epigenomics/Metabolomics

2027
─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Q1–Q2             (Paper 1 submitted)      Federated execution       Voice API (public)      Feedback-driven
                  HCA reanalysis begins    Metadata inference        Smart glasses MVP       threshold tuning
                  P2 + all 7 benchmarks                              (Meta Ray-Ban)

Q3–Q4             Paper 2 (Genome Bio)     GA4GH BQES engagement     HoloLens AR overlay     Per-step cost
                  HCA reanalysis done      Drug disc: PGx/PK-PD      (cryo-EM)               optimization

2028
─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Q1–Q2             Paper 3 (Nature)         HCA systematic bias
Q3–Q4             Paper 4 (Nat Chem Bio)   GA4GH BQES ratified
```

---

## Appendix: Direction × Hypothesis Evidence Matrix

| | H1 Workflow quality ≥80% | H2 QC defensible ≥70% | H3 Time ≤30 min | H4 Pricing ≥60% | H5 Hallucination = 0 |
|---|---|---|---|---|---|
| **A Drug Discovery** | ADMET + docking + CRO sessions | ICH S7B / FDA/EMA citations | 6-session drug discovery pipeline | Lab budget question | Nextflow log monitoring |
| **B RNA-seq** | nf-core/rnaseq + DE + pathway | ENCODE / GATK thresholds | Public GEO dataset baseline | Core facility pricing test | Tool index validation |
| **C Cryo-EM** | CryoSPARC SPA full pipeline | EMDB deposition standards | vs. manual CryoSPARC session | Facility user pricing | Command validation |
| **D Single-Cell** | scRNA-seq + CRISPR assignment | ENCODE scATAC / mito profiles | vs. manual Seurat pipeline | Lab/student pricing | Workflow parameter check |
| **E Multi-Omics** | LC-MS proteomics + metabolomics | mzQC / lab SOP standards | vs. manual R pipeline | Core facility pricing | LC-MS API proxy test |

---

## Appendix: Source Documents

| Source | Role |
|---|---|
| `business/BioMate Pilot Study Execution Model-v2-20260324.xlsx` | Active pilot model: 5 directions, hypotheses, partner status, execution plan, risk log |
| `business/BioMate Pilot Study Execution Model-Active0323.xlsx` | Earlier version; confirms direction structure and scoring framework |
| `docs/pilot_study/20260324_INTERNAL_PILOT_TEST_PLAN.md` | Direction A session-level design and pass/fail criteria |
| `docs/pilot_study/20260325_INTERNAL_PILOT_VALIDATION_RUN_REPORT.md` | Direction A GO decision; internal validation results |
| `docs/papers/20260401_BENCHMARK_STRATEGY_REVISED.md` | External benchmark plan; P0/P1/P2 suites |
| `docs/papers/20260225_1545_MULTI_PAPER_PUBLICATION_STRATEGY.md` | Publication arc: Months 9/15/24/30 targets |
| `docs/20260403_COMPETITIVE_MOAT_BRIEFING.md` | Competitive framing behind feature priorities |
