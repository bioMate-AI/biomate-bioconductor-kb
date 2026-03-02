# BioMate for Drug Development
### A Platform Overview for Research Collaboration

---

## What BioMate Does

BioMate is an AI-native research platform that turns a plain-language description of an experiment into a fully configured, automatically quality-checked computational pipeline — and runs it. The scientist describes what they want to do; BioMate builds the workflow, checks whether the results meet scientific standards at each step, flags problems in real time with an explanation and a suggested fix, and records every decision in an audit trail.

The platform covers the full arc of drug discovery and development — from genomic target identification through preclinical PK/PD — without requiring the scientist to know which software tools to use, how to configure them, or how to interpret the QC metrics they produce.

---

## Capabilities by Drug Development Stage

### Stage 1 — Target Identification and Validation

- **Whole-genome and whole-exome sequencing** — variant calling, annotation, coverage QC (30× WGS, 80× WES/targeted)
- **RNA sequencing** — differential expression, splice analysis, quantification; alignment quality monitored at every step
- **Single-cell RNA sequencing** — cell type deconvolution, trajectory analysis, marker discovery; Cell Ranger output parsed and QC-gated automatically
- **GWAS / genome-wide association** — target prioritisation from population genetics
- **Epigenomics (ATAC-seq, ChIP-seq)** — chromatin accessibility, transcription factor occupancy, peak calling QC
- **Cryo-electron microscopy (cryo-EM SPA)** — 23-step pipeline from raw micrographs to near-atomic structure; QC gates at motion correction, CTF estimation, particle picking, 2D/3D classification, and final sharpening

### Stage 2 — Hit Discovery and Compound Quality

- **Compound structure QC** — validates chemical structure notation (SMILES) before any computational analysis runs; blocks invalid structures outright
- **Physicochemical profiling** — molecular weight, lipophilicity, hydrogen bond donors/acceptors, topological polar surface area, Lipinski and Veber rule compliance
- **Batch screening** — single compound or library of hundreds; returns worst-case metrics across the whole batch

### Stage 3 — ADMET and Safety Screening

- **hERG cardiotoxicity** — estimated IC₅₀ from molecular structure; hard stop at high-risk levels, advisory warning for moderate risk
- **Drug-induced liver injury (DILI)** — lipophilicity and molecular weight model; risk classified as low / medium / high with a probability score
- **Clinical toxicity (ClinTox)** — machine-learning overlay for clinical trial failure prediction (when model is installed)
- **Ames mutagenicity** — structural alert screening
- **Pharmacogenomics (PGx) coverage** — confirms that the sequencing data covers the key drug-metabolising genes (CYP2D6, CYP2C19, DPYD, TPMT, UGT1A1); hard stop if coverage is insufficient for clinical interpretation

**All four ADMET gates fire automatically** — the scientist does not configure them; the platform detects which type of analysis is running and applies the correct thresholds.

### Stage 4 — Lead Optimisation

- **Chemoproteomics pulldown** — enrichment ratio QC gate; confirms that the chemical probe is actually enriching the target before downstream analysis proceeds
- **Phosphoproteomics** — site localisation and quantification QC
- **Molecular docking** — AutoDock Vina-based binding pose prediction
- **QSAR model building** — quantitative structure-activity relationship modelling
- **Scaffold hopping** — structural analogue generation

### Stage 5 — Preclinical PK/PD

- **Non-compartmental analysis (NCA)** — using the PKNCA package (FDA- and EMA-accepted methodology); outputs AUC, Cmax, t½, volume of distribution, clearance, and bioavailability with uncertainty estimates
- **Population pharmacokinetics** — using nlmixr2 with the SAEM algorithm, the same estimation method as NONMEM; supports one- and two-compartment models and covariate effects
- **PK/PD modelling** — compartmental ODE simulation, Emax / sigmoid-Emax pharmacodynamic models, time-kill kinetics for anti-infectives
- **Preclinical toxicology** — VCOG-CTCAE adverse event grading, xenograft tumour response modelling, biodistribution analysis

### Stage 6 — Translational Biomarker Development

- **Plasma proteomics** — low-abundance enrichment, depletion QC, biomarker panel development
- **Transcriptomic biomarkers** — differential expression from patient cohorts
- **Single-cell stratification** — cell-type-specific pharmacodynamic response

### Stage 7 — Safety Surveillance

- **FAERS spontaneous report mining** — post-marketing adverse event signal detection
- **Drug interaction network analysis** — polypharmacy risk assessment

### Stage 8 — Drug Repurposing

- **Repositioning candidate scoring** — integrates existing ADMET, PK, and efficacy data to rank repurposing opportunities

---

## QC Governance — What Makes BioMate Different

Every workflow step is monitored against evidence-based quality thresholds. When a step produces results below threshold, the scientist sees:

1. The exact metric that failed and by how much
2. A plain-language explanation of what the failure means scientifically
3. Domain-specific troubleshooting steps (e.g. for a hERG failure: which structural features to modify and why)
4. The choice to apply AI-suggested parameter corrections and retry, or to override and proceed with a recorded justification

Three severity tiers are applied:
- **Blocking** — the result is not scientifically valid; the workflow pauses for a decision
- **Advisory** — the result is acceptable but warrants attention; the workflow continues with a flagged warning
- **Near-threshold** — the metric is within 10% of a threshold; an early warning before it becomes a problem

All decisions — including overrides — are written to an audit log that travels with the result.

**Named QC profiles** allow the threshold set to be adapted to the experimental context without bypassing governance. Current profiles include: standard drug-like compound, natural product, peptidomimetic, clinical PGx, research PGx, standard proteomics, phosphoproteomics, plasma biomarker proteomics, chemoproteomics, cryo-EM SPA standard, cryo-EM SPA phase plate, and 14 genomics/epigenomics profiles.

---

## Research Intelligence — Hypothesis, Protocol, and Literature

Before running a single analysis, BioMate can help a scientist think through the experiment. The platform's research agent is available throughout the conversation — not just at the workflow generation step.

**Literature-backed answers to scientific questions.** Ask anything: "What is the right ADMET screening strategy for a CNS compound series?", "What alignment rate is acceptable for degraded FFPE RNA?", "Which cryo-EM particle picker performs best on heterogeneous samples?" The research agent searches PubMed and ArXiv in real time, consults a curated benchmark knowledge base, and returns a synthesised answer with up to five numbered citations. Responses include a confidence indicator and a set of follow-up questions for deeper exploration.

**Hypothesis generation.** Describe an observation or a preliminary result and ask what hypotheses it suggests. The agent proposes testable hypotheses grounded in the literature, identifies supporting evidence and known confounders, and recommends which BioMate workflow would test each hypothesis — so the path from question to analysis is as short as one click.

**Protocol and methodology guidance.** Ask how to perform an experiment — sample preparation, assay format, sequencing depth, compound concentration range — and the agent returns step-by-step guidance drawn from published methods sections, domain scientific skills, and benchmark comparisons across tools. Recommendations are specific: it names what to do, why, and what the common failure modes are for that protocol.

**Scientific rationale embedded in every workflow.** When BioMate generates or recommends a workflow, the response includes a structured rationale panel that explains:
- *When to use this workflow* — the specific experimental contexts it is designed for
- *When not to use it* — limitations and contraindications
- *Data requirements* — input formats, minimum sample size, depth, reference versions
- *Key assumptions* — what the analysis implicitly assumes about the data
- *Common pitfalls* — documented failure modes with root cause and fix
- *Parameter recommendations* — specific parameter values with scientific justification for the current domain

**Benchmark evidence for tool selection.** When multiple tools could address the same problem, the research response includes a ranked comparison with performance metrics from published benchmark studies — F1-score, speed, memory, dataset type — and a link to the source paper so the scientist can assess relevance themselves.

---

## AI Assistance

- Describe any analysis in plain English and the platform generates the full pipeline, drawing on over 950 indexed workflows across genomics, proteomics, drug discovery, structural biology, and microbiology
- The AI explains which tools it selected and why, what the key assumptions are, and what the common failure modes look like for that specific analysis type
- Clarifying questions are offered non-blocking — the analysis starts while the dialogue continues
- A pilot run feature automatically tests parameters on a small subset before committing the full dataset

---

## Results, Visualization, and Download

After a workflow completes, BioMate organises outputs by scientific content type — visualizations, data tables, variant calls, sequence files, genomic annotations, and single-cell data objects — each shown with a count badge so the scientist can navigate directly to what matters.

**In-browser viewers — no downloads required for inspection.**

- *Image and plot viewer* — PNG, SVG, and interactive HTML plots (Plotly, Vega) render directly; zoom, pan, and export from the browser
- *Data table viewer* — CSV, TSV, and parquet files open in a sortable, filterable grid; suitable for compound screening results, PK parameter tables, and differential expression outputs
- *Variant viewer* — VCF files display in an interactive table with quality filtering, effect type classification, genotype columns, and transcript consequence annotations
- *Sequence viewer* — FASTA and FASTQ files show colourised nucleotide or amino acid content, GC content, open reading frame overlays, and multi-sequence alignment
- *Annotation viewer* — BED, GFF, and GTF files display genomic features with type filtering, coordinate navigation, and feature overlap detection
- *Single-cell browser* — H5AD and Loom objects open an interactive UMAP/t-SNE projection viewer with gene expression heatmaps, cluster colouring, and differential expression tables

All viewers run natively in the browser — no plugins, no Java, no external rendering services.

**Download options.**

- Individual files download in their native format with one click
- *Download All* creates a ZIP archive of every workflow output
- Category-scoped downloads let the scientist select, for example, only the visualization files or only the data tables
- Citation export produces a BibTeX file from every tool reference embedded in the workflow report — ready for a manuscript bibliography

**Auto-generated run report.** After any workflow, a report button produces a structured document covering the workflow name and parameters, methods (tool versions and settings actually used), QC results (which checks passed, which triggered warnings, any override decisions), output descriptions, and interpretation guidance. Available as a Markdown file for editing or an HTML file for sharing. The report is sanitised and self-contained — it can be emailed or attached to a lab notebook entry without any additional dependencies.

**Interactive post-run environment.** A Jupyter notebook session can be launched directly from the completed workflow, with all output files pre-loaded into the kernel. Scientists can run custom analysis code, generate additional plots, or apply statistical tests without re-executing the full pipeline.

---

## Compute

Runs locally, on a university HPC cluster (SLURM), or on AWS Batch. The scientist selects the environment once in settings; all subsequent runs use it without further configuration.

---

## Roadmap (Next 6–12 Months)

| Capability | Status |
|---|---|
| ML-based Ames mutagenicity model (neural net, not structural alerts) | In development |
| In vitro to in vivo extrapolation (IVIVE) for hepatic clearance prediction | In development |
| Population PK QC gates (CV% on key parameters, convergence diagnostics) | In development |
| NCA regulatory-format report output (FDA/EMA submission-ready) | Planned |
| Compound series tracking across optimisation iterations | Planned |
| Experimental data ingestion (IC₅₀ CSV, assay plate files, raw PK data) | Planned |

---

## What We Would Like to Understand From You

We would value your perspective on the following questions. There are no right answers — the goal is to understand whether the platform as described maps to how drug development research actually works in your setting.

**On coverage and fit:**

1. Looking at the stage-by-stage breakdown above — where does your work currently sit, and does the coverage feel complete for those stages? What is conspicuously absent?

2. The platform is strongest at the computational and data-analysis layer. Where in your workflow do the most consequential bottlenecks currently live — and are those computational, wet-lab, or something else?

3. For ADMET screening specifically: do you currently rely on RDKit-based physicochemical estimates, commercial tools (StarDrop, Schrodinger, OpenEye), or experimental assay data? What role would computational pre-screening play in your decision-making?

4. For PK/PD: is non-compartmental analysis something your team runs internally, or does it go to a dedicated pharmacokinetician? Would having it embedded in the same platform as the compound analysis change how early you run it?

**On quality governance:**

5. When an analysis step produces a result that is ambiguous or borderline — such as moderate hERG risk, or alignment rates that are acceptable but not ideal — how does your team currently handle the decision about whether to proceed? Is there a formal review process, or is it informal?

6. Are there QC thresholds that differ between your projects — for example, different standards for exploratory screening versus lead optimisation versus regulatory submission? If so, how are those differences managed today?

7. Would an automatically generated audit trail of all QC decisions be useful to you — for internal review, for collaboration with CROs, or for regulatory purposes — or would it create overhead?

**On integration and workflow:**

8. What software does your team use today for the analyses that overlap with what BioMate covers? What would it take to move even one of those steps onto a new platform?

9. Is your team comfortable with cloud compute, or is there a strong preference for on-premise / institutional cluster execution?

10. Who in your organisation would actually use this day to day — computational scientists, bench scientists, or both? What level of computational background should the platform assume?

**On research intelligence:**

11. When your team is designing a new experiment or troubleshooting a failed one, where do you currently go for guidance — literature, colleagues, a statistician, an internal knowledge base? Would having a literature-aware assistant embedded in the analysis environment change that behaviour, or would you still use your existing sources?

12. Is hypothesis generation something that feels useful to support computationally, or is it firmly in the domain of the scientist? What would a good AI-generated hypothesis response look like to you — or what would make it feel unhelpful?

**On results and output:**

13. After an analysis completes, what do scientists in your team typically do with the results — inspect them interactively, export to a notebook, drop them into a report template, hand them to a colleague? Which of those steps is the most friction-prone today?

14. The platform generates an auto-formatted run report covering methods, QC results, and output descriptions. Would that be useful for internal lab records, CRO handoffs, or manuscript preparation — or is there a report format you already use that it would need to match?

**On what is missing:**

15. What capability — if BioMate had it — would make the strongest case for adoption in your team?

16. Is there a category of analysis you run routinely that is not represented anywhere in this document?

---

## What Can Be Built on Top of BioMate

The platform is designed to be extended. Groups who collaborate with us get direct access to:

- **Custom workflow integration** — if your team has an in-house pipeline, script, or R package, it can be wrapped as a BioMate workflow and receive the same QC governance and AI assistance as everything else on the platform
- **Custom QC profiles** — domain-specific threshold sets for your assay formats, compound classes, or regulatory context; versioned, auditable, and portable across projects
- **API access** — programmatic workflow submission, result retrieval, and QC event streams; suitable for integration with LIMS, ELN, or compound management systems
- **AI assistant fine-tuning** — the workflow generation model can be primed with your organisation's standard operating procedures, preferred tools, and historical analysis patterns
- **Internal knowledge base integration** — the research agent can be connected to your organisation's internal document store, SOPs, and historical study reports, so literature-backed answers draw on institutional knowledge alongside public sources
- **Co-development** — capabilities on the roadmap (IVIVE, population PK QC, SAR tracking, regulatory report generation) can be prioritised and co-designed around your specific use cases

---

*Document version: March 2026*
