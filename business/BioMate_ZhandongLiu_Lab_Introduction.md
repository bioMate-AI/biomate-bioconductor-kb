# BioMate for Neurogenomics & Computational Biology Research
### A Platform Overview for Dr. Zhandong Liu's Lab — Baylor College of Medicine

---

## Executive Summary

BioMate is an AI-native life science research platform. A researcher describes an analysis in plain language; BioMate selects the right tools, configures them for the data type and scientific context, runs the workflow, and returns consolidated results with a full audit trail — all in one session.

For a lab working across rare disease genomics, neurological transcriptomics, chromatin profiling, single-cell analysis, and spatial transcriptomics, BioMate provides a single environment for all computational work. The platform is extensible: the lab's own tools — such as PolyAMiner-Bulk and SEAGAL — can be integrated into BioMate, gaining the same natural language interface, literature assistance, and session memory as everything else on the platform.

BioMate does not replace the lab's existing interpretation and AI systems. It operates as the execution layer beneath them, and grows with the lab's needs.

---

## What BioMate Does

**Natural language workflow execution.** Describe the analysis; BioMate runs it. No pipeline scripts, no parameter lookup, no environment management. The platform handles tool selection, configuration, execution, and output organization automatically.

**Multi-modal coverage.** A single session can span multiple data types and analysis steps — variant calling on WGS, transcriptomic outlier detection on paired RNA-seq, and alternative polyadenylation analysis on the same samples — with results linked in a unified output.

**Integrated literature assistance.** BioMate's research agent is available throughout every session. Ask about a result, a gene, a protocol decision, or a finding — the agent retrieves and synthesizes relevant literature in real time, within the same interface as the analysis.

**Session memory.** BioMate carries analyst decisions and context forward across sessions. Choices made while analyzing one patient or cohort are available at the start of the next, reducing re-orientation time and preventing repeated work.

**Extensibility.** Research groups integrate their own tools and pipelines into BioMate. Custom tools become first-class platform workflows, accessible by natural language and covered by the same quality monitoring and audit trail.

**Reproducibility.** Every run produces a complete audit log — tool versions, parameters, quality outcomes, and any analyst decisions — written to serve directly as a computational methods section.

---

## Domain Coverage

### Rare Disease Genomics

BioMate covers the full rare disease genomics workflow: germline variant calling on WGS and WES, structural variant detection, variant annotation and prioritization, and transcriptomic outlier detection for aberrant expression and splicing. Multi-modal analyses — combining DNA variant evidence with RNA-seq outlier signals — run in a single session and produce a joint patient case report.

### Neurological Transcriptomics

For bulk RNA-seq in neurological research, BioMate handles alignment, quality assessment, differential expression, pathway enrichment, splice analysis, and cell-type deconvolution. The platform applies configurations appropriate for challenging sample types such as post-mortem brain tissue. Alternative polyadenylation analysis — including integration with PolyAMiner-Bulk — is supported on the same RNA-seq data.

### Single-Cell and Spatial Transcriptomics

From Cell Ranger or SpaceRanger output, BioMate runs the full downstream analysis: normalization, clustering, cell-type annotation, differential abundance testing, trajectory inference, and multi-sample integration with appropriate statistical frameworks. Spatial transcriptomics analysis, including integration with SEAGAL for spatial gene association detection, is covered in the same environment.

### Chromatin Profiling

BioMate supports CUT&RUN and CUT&Tag experiments: alignment with spike-in normalization, peak calling, and differential binding analysis between conditions. Results can be connected to paired RNA-seq within the same session for joint epigenomic and transcriptomic interpretation.

### Pharmacological Genomics

For work connecting transcriptomics to drug action, BioMate links expression signatures to pharmacological regulators and searches the biomedical literature for compound-disease connections. Target validation through molecular docking and ADMET screening are also available for early-stage compound analysis.

---

## Quality and Reproducibility

Every analysis is monitored against evidence-based quality thresholds appropriate for the data type and experimental context. Quality issues are surfaced with plain-language explanations and clear options — the analyst sees what happened and decides how to proceed, with every decision recorded.

BioMate ships with named quality profiles for whole-genome and whole-exome sequencing, post-mortem brain RNA-seq, single-cell analysis, and CUT&RUN/CUT&Tag experiments. Custom profiles can be added for lab-specific sample types or publication standards.

---

## Pilot Evaluation Framework

For the initial trial, the evaluation is structured around three measurable outcomes that the lab and BioMate agree on in advance:

| Metric | Target | Measurement |
|---|---|---|
| Workflow quality | ≥ 80% of submitted analyses complete without manual parameter correction | Platform telemetry per session |
| Time-to-result | From query submission to complete, review-ready result in ≤ 30 minutes for standard bulk RNA-seq pipelines | Backend timestamp log vs. lab's current baseline |
| QC defensibility | ≥ 70% of outputs rated publication-ready or near publication-ready by a lab member with domain expertise | Structured exit form after each session |

Zero hallucinated tool names or non-existent parameters are acceptable — every command BioMate issues maps to a real installed tool. The deliverable from the trial week is a complete QC audit log and methods report for each analysis run, ready to include in a paper without modification.

---

## What We Would Like to Understand From You

1. Which analysis types consume the most time for trainees and postdocs in your lab — and where does manual effort most often slow a project down?

2. For rare disease patients with both genomic and transcriptomic data, what does the current analysis workflow look like, and where is most of the manual effort?

3. Your lab has developed PolyAMiner-Bulk and SEAGAL. How are these currently integrated into broader analysis workflows — and would having them accessible through a unified platform environment be useful?

4. When a new trainee joins and needs to run an existing analysis type, how long before they can do it independently, and what are the common failure points?

5. Is there an active or recently completed analysis you would want to run through BioMate as a first test, so you can compare the output against a known result?

6. What would need to be true for BioMate to become a routine part of how your lab runs computational analyses?

---

## Appendix — Example Queries

These illustrate how analysts interact with BioMate. Replace bracketed values with your own parameters.

**Rare disease trio analysis**
```
I have WGS data for a rare disease patient and their unaffected parents.
Run germline variant calling, annotate variants, and flag de novo
candidates with predicted loss-of-function impact in any neurodevelopmental gene.
Output a prioritised variant table.
```

**Neurological bulk RNA-seq cohort**
```
I have bulk RNA-seq from 20 Rett syndrome and 20 control post-mortem
brain samples. Run alignment and QC, then run differential expression
and GO pathway enrichment on the top hits. Flag any samples that fail
QC before running DE.
```

**Aberrant splicing in a patient cohort**
```
I have RNA-seq from 15 patients with a suspected splicing mutation in
gene X and 30 matched controls. Run aberrant splicing detection and show
which splice junctions differ significantly, ranked by effect size.
```

**Single-cell analysis**
```
I have 10x scRNA-seq from 8 Alzheimer's and 8 control cortex samples.
Cell Ranger output is ready. Cluster, annotate against the Human Cell
Atlas brain reference, and test which cell types differ in abundance
between cases and controls.
```

**CUT&Tag chromatin analysis**
```
I have CUT&Tag data for MeCP2 in neurons vs. astrocytes with IgG controls
and spike-in normalization. Run alignment, spike-in calibration, peak
calling, and differential binding between the two cell types.
```

**Alternative polyadenylation**
```
I have bulk RNA-seq from 10 patient and 10 control samples. Run
PolyAMiner-Bulk to identify genes with differential APA between groups
and visualize the top hits.
```

---

*March 2026 · BioMate AI · Research collaboration overview*
