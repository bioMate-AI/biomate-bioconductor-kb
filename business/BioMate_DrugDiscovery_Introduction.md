# BioMate for Clinical Drug Discovery Research
### A Platform Overview for the Department of Medicine — Zhejiang People's Hospital

---

## Executive Summary

BioMate is an AI-native drug discovery platform designed to work alongside clinicians and physician-scientists. A researcher describes the task — screen candidate compounds for a specific target, evaluate which drugs from an existing regimen are best tolerated by a patient population, or identify new therapeutic candidates for a disease of interest — and BioMate runs the full computational pipeline, applies clinical-grade quality checks, and returns results with a complete audit trail, all within one session.

The platform does not require a bioinformatics background. It speaks the language of the science, not the command line. For a department whose primary work is patient care and clinical research rather than software engineering, BioMate is the bridge between cutting-edge computational chemistry and the clinical question at hand.

The pipeline covers target identification through literature and database mining, ADMET toxicity and pharmacokinetics profiling, virtual screening and compound ranking, and iterative lead optimisation guided by assay data. Every result is accompanied by an exportable methods report and a complete quality audit log — ready for a research manuscript or an internal review committee.

---

## What BioMate Does

**Natural language pipeline execution.** Describe the scientific question; BioMate runs the pipeline. Tool selection, parameter configuration, environment management, and result organisation are handled automatically. A clinical researcher does not need to know which docking engine, which ADMET predictor, or which molecular dynamics package to use — BioMate selects and configures these based on the question and the target.

**Target identification from clinical evidence.** Starting from a disease of interest, a gene, or a published clinical finding, BioMate surveys biomedical literature, protein databases, and drug-target interaction networks to identify and prioritise candidate targets. For targets where structural data exists, it maps the binding site and assesses druggability. For novel targets, AlphaFold3 structure prediction is applied automatically.

**ADMET profiling — the clinical safety screen.** Before any compound advances in a campaign, BioMate evaluates its toxicological and pharmacokinetic profile against a full panel of endpoints: cardiac liability (hERG), liver toxicity (DILI), mutagenicity (Ames), clinical toxicology flags (ClinTox), intestinal permeability (Caco-2), and blood-brain barrier penetration. Thresholds are grounded in published clinical guidelines and labelled by evidence tier. When a compound fails, BioMate explains which metric failed, what the measured value was, and what the guideline threshold is — and asks whether to proceed.

**Virtual screening and compound ranking.** Compound libraries are pre-filtered by physicochemical properties and pharmacophore rules before docking, eliminating obviously unsuitable candidates before expensive computation. Docking runs AutoDock Vina and DiffDock in parallel. Results are merged with ADMET scores into an integrated compound ranking. The top candidates are returned with a rationale for their ranking.

**Generative lead design and analogue suggestion.** Starting from a hit compound, BioMate generates analogues constrained to improved property ranges — for example, reducing cardiac liability while preserving binding affinity. It predicts retrosynthesis routes with AiZynthFinder to ensure proposed compounds can actually be synthesised, and flags compounds with impractical routes before they reach the ordering decision.

**Drug MoA characterisation from clinical RNA-seq.** For departments with access to patient RNA-seq data from drug-treated samples, BioMate can characterise how a drug perturbs gene expression: differential expression analysis, pathway enrichment, and LINCS CMap matching to identify which known drugs produce a similar transcriptomic signature. This supports mechanism-of-action hypotheses and drug repurposing investigations.

**Iterative optimisation with assay data.** When wet lab or CRO assay results return, they are uploaded to BioMate in a structured CSV. BioMate updates the compound ranking and runs multi-objective Bayesian optimisation to propose the next synthesis batch — balancing potency, selectivity, and ADMET profile in a Pareto-optimal design. Each round is informed by all accumulated experimental evidence.

**CRO-ready compound export.** The proposed compound set is exportable directly in formats accepted by major contract research organisations (WuXi AppTec, Pharmaron, Enamine), with per-compound scientific rationale, ADMET pre-filter results, and commercial availability checks. The step from BioMate output to a synthesis order is a single export.

**Complete audit trail and methods report.** Every session produces a timestamped audit log: tools used, parameters set, QC outcomes, and any analyst override decisions. This log is auto-formatted as a computational methods section — ready to include in a research manuscript without manual write-up.

---

## Discovery Pipeline Coverage

### Target Identification and Characterisation

BioMate combines literature synthesis (PubMed, bioRxiv, clinical trial registries), drug-target interaction networks (DrugBank, ChEMBL, DGIdb), and AI-based target prioritisation to surface candidates relevant to a specific disease or patient population. For targets with existing structural data, pocket detection and druggability assessment run automatically. For novel targets, AlphaFold3 structure prediction is applied and the AlphaFold Human Proteome database is searched for structural relatives.

### ADMET Filtering and Compound Triage

ADMET profiling runs on every compound before computationally expensive docking steps, eliminating candidates with unacceptable toxicity or pharmacokinetics early. The panel covers cardiac, hepatic, mutagenic, and clinical toxicology endpoints, plus permeability and CNS penetration where relevant. Compounds that fail are clearly labelled with the failing metric, the evidence source, and the threshold — not just a pass/fail flag.

### Virtual Screening and Hit Identification

For compound libraries of 10 to several thousand compounds, BioMate performs pharmacophore pre-filtering, similarity-based pre-screen, and multi-engine docking (Vina + DiffDock), returning an integrated ranked list. ADMET gate results and docking scores are combined into a single compound view. Top hits are returned with poses and ranking rationale.

### Lead Optimisation

REINVENT4 generative design and matched molecular pair analysis drive analogue generation. AiZynthFinder retrosynthesis route prediction screens out compounds with impractical synthesis paths. Binding free energy calculations with GROMACS MM-GBSA re-rank the shortlist before synthesis decisions. Off-target selectivity can be evaluated by running anti-target rescoring against homologous structures.

### Iterative Campaigns and MoA Characterisation

Assay results from the lab or a CRO are ingested, mapped to campaign compounds, and used to update the multi-objective Bayesian optimisation model. For mechanistic questions — how does a drug candidate alter cell biology — the drug MoA pipeline produces a differential expression and pathway enrichment report from patient RNA-seq data and cross-references LINCS CMap for mechanism hypothesis generation.

---

## Quality and Reproducibility

BioMate applies evidence-graded QC at each pipeline stage. Named profiles cover standard oral small molecules, CNS-penetrant compounds, fragment-based campaigns, and oncology series. Custom profiles can be defined for a specific disease area or patient population.

Every run produces a complete audit log ready to serve as the computational methods section of a research paper. All QC thresholds are cited to their source — ICH S7B (hERG cardiac liability), FDA/EMA DILI guidance, Lipinski and Veber physicochemical rules, ChEMBL benchmark distributions, or published clinical guidelines — so a reviewing editor or committee can verify the evidence behind each quality decision.

---

## Pilot Evaluation Framework

For the initial collaboration, the evaluation is structured around three measurable outcomes:

| Metric | Target | Measurement |
|---|---|---|
| Workflow quality (H1) | ≥ 80% of queries run end-to-end without manual parameter correction | Platform telemetry + post-run survey |
| Time-to-result (H2) | Query submission to complete result in ≤ 30 minutes for a 10–20 compound screen | Backend timestamp log |
| QC defensibility (H3) | ≥ 70% of results rated publication-ready (score 4–5 / 5) | Researcher exit survey |
| Hallucination incidents (H5) | 0 — every command maps to a real installed tool | Exit survey + backend monitoring |

The deliverable at the end of the pilot is a QC audit log and an exportable methods report for the compounds analysed — ready for direct inclusion in a manuscript or internal research record.

---

## What We Would Like to Understand From You

1. What is the current focus of your department's drug-related research — identifying new therapeutic targets, evaluating approved drugs for new indications, or optimising lead compounds for a specific disease?

2. For a recent clinical project involving a drug or compound series, how was the computational analysis handled — internally, through a bioinformatics core, or outsourced? What was the biggest bottleneck?

3. Do you have patient cohort data (RNA-seq, proteomics, or clinical outcomes) that could be used to profile drug mechanism of action or identify response predictors? What would it take to make that data available for computational analysis?

4. When your department evaluates a drug candidate for clinical relevance — cardiac safety, liver toxicity, metabolic stability — what tools or databases are currently used, and who is responsible for that evaluation?

5. Is there a specific disease target, compound set, or clinical hypothesis that you would want to run through BioMate in an initial session — so you can compare BioMate's output directly against what you already know?

6. What would need to be true — in terms of result quality, explanation clarity, and audit documentation — for BioMate to become a routine part of your department's research workflow?

---

## Appendix — Example Queries

These illustrate how researchers interact with BioMate. Replace bracketed values with your own parameters.

**Target survey for a specific disease**
```
I am working on [gastric adenocarcinoma]. Survey the published literature
and drug-target databases for candidate therapeutic targets: what proteins
are most frequently implicated, which have known inhibitors, and which
targets have published structural data for docking?
```

**ADMET evaluation of a compound set**
```
I have 12 candidate compounds [SMILES list] that we are considering for
a [KRAS-mutant colorectal cancer] programme. Evaluate all 12 for ADMET:
flag any with cardiac liability (hERG IC₅₀ < 10 µM), high DILI risk,
or mutagenicity risk. Return a ranked table and show me which passed all gates.
```

**Drug repurposing from patient RNA-seq**
```
I have bulk RNA-seq from [15 hepatocellular carcinoma patients treated with
sorafenib] and [15 untreated controls]. Run differential expression with
DESeq2, identify significantly dysregulated pathways, and search LINCS CMap
to identify approved drugs that produce a similar transcriptomic signature —
potential candidates for combination or repurposing.
```

**Virtual screening on a clinical target**
```
I have a target protein [UniProt ID or PDB ID] implicated in [disease].
Screen these [50] candidate small molecules against it: first apply ADMET
filtering, then dock the passing compounds with AutoDock Vina, and return
the top 10 ranked by integrated score. Include the docking pose for each.
```

**Lead optimisation from a flagged compound**
```
I have a lead compound [SMILES] with good target binding but a hERG IC₅₀
of 3 µM. Generate 20 analogues that improve cardiac safety while keeping
the core pharmacophore intact. Score each for synthetic accessibility and
flag any with impractical retrosynthesis routes.
```

**Assay data upload and next-round proposal**
```
I received IC₅₀ data from the CRO for the 15 compounds from our last
round [CSV attached]. Update the campaign ranking and propose the next
10 compounds for synthesis — optimised for potency, hERG safety, and
metabolic stability simultaneously.
```

---

*March 2026 · BioMate AI · Research collaboration overview*
