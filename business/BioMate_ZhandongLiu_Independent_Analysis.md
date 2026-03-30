# Independent Analysis: Liu Lab Experiment Design, Workflow, and Real Gaps
*Based on direct reading of published papers: RareCollab (arXiv 2602.04058), AI-MARRVEL (NEJM AI 2024), PolyAMiner-Bulk (Cell Reports Methods 2024), SEAGAL (Bioinformatics 2023)*
*March 2026 — internal document*

---

## 1. What the Lab Actually Does: The Real Workflow

The Liu lab is not a bioinformatics pipeline lab. They are an **AI interpretation lab** for rare disease diagnosis. Their entire research contribution sits at the interpretation and reasoning layer — the layer that runs *after* sequence data has been processed. This distinction is fundamental.

### 1.1 DNA Variant Data Flow

VCF files arrive **pre-processed from the Baylor Genetics clinical sequencing lab**. The Liu lab does not run variant calling. They do not configure GATK. They receive VCF + HPO phenotype terms and feed them into AI-MARRVEL (v1.1.2) for annotation, which itself is their own tool. The only "QC" involved is that variants are filtered by standard allele frequency, quality flags encoded in the VCF by the clinical lab's pipeline — these are input features to AI-MARRVEL, not thresholds the lab tunes.

### 1.2 RNA-seq Data Flow

RareCollab (2026) describes their actual preprocessing in one sentence:

> *"RNA fastq files were first converted into bam files by using nextflow rnaseq (3.22.2). Then, nextflow drop pipeline (development version) was applied for the downstream analysis, including OUTRIDER for aberrant expression analysis, FRASER for aberrant splicing analysis and GATK for ASE analysis."*

That is the complete description. No parameter tuning. No QC threshold derivation. No mention of FastQC, duplication rates, mapping rate thresholds, or coverage checks. They run nf-core rnaseq and nf-core DROP as black boxes with defaults. The **development version** of nf-core DROP is significant — it is an unreleased version they depend on.

### 1.3 APA Analysis (PolyAMiner-Bulk)

PolyAMiner-Bulk (2024) uses STAR for alignment — default parameters, no specification. Their algorithmic QC is **internal to their tool**: the C/PAS-BERT model filters candidate cleavage sites, the beta-binomial test applies a default adj p < 0.05 threshold, cluster distance defaults to 30 bp, softclipped adenosine thresholds are hardcoded with defaults. No sample-level QC (read depth minimums, duplication rates) is described anywhere in the paper. The tool itself IS the quality filter for APA calls — but that is algorithmic, not a configurable threshold the analyst derives.

### 1.4 Spatial Transcriptomics (SEAGAL)

SEAGAL (2023) describes QC in one line: *"removes genes observed in less than ten spots and spots with less than 150 UMI counts."* Two hardcoded defaults. Input is SpaceRanger output (10X Visium). Nothing else is configured.

### 1.5 The Interpretation Layer (Where the Lab Operates)

RareCollab's Integration Engine is described as **"explicitly human-in-the-loop: clinicians and analysts can flexibly adjust tier thresholds or evidence-combination rules without retraining the underlying models."** This is where expert time actually goes. An analyst reviews which variants are in Tier 1 vs. Tier 2, adjusts thresholds when an unusual case type (e.g., atypical presentation, noncoding variant, novel disease gene) does not fit the defaults, and decides when to override the model's confidence level.

This is the real expert bottleneck: not configuring a pipeline, but deciding what to do when the model's automated tiers do not match clinical intuition.

---

## 2. What the Lab Evaluates and How

### 2.1 Their evaluation paradigm

The lab evaluates AI systems on **diagnostic accuracy**: does the correct causative variant appear in the top-1 or top-5 ranked candidates? The primary metrics across all papers are:
- Top-k recall (k = 1, 3, 5, 10) of diagnostic variants
- Precision at a confidence threshold (for reanalysis workflows)
- Balanced accuracy against modality-specific baseline tools (OUTRIDER, FRASER, ontology-similarity scores)

No evaluation of pipeline efficiency, QC quality, or configuration burden appears in any of their publications. These are not questions they study — because they are not questions their work creates.

### 2.2 Parameters they set as defaults and never tune

| Tool | Parameter | Value | Ever tuned? |
|---|---|---|---|
| nf-core rnaseq | Everything | Pipeline defaults | No evidence of tuning |
| nf-core DROP | Everything | Pipeline defaults (dev version) | No evidence of tuning |
| PolyAMiner-Bulk | Cluster distance | 30 bp | Mentioned as user-adjustable; no evidence they tune it |
| PolyAMiner-Bulk | Softclipped adenosine % | 75–90% by length | Hardcoded defaults; described as adjustable |
| PolyAMiner-Bulk | Statistical threshold | adj p < 0.05 (BH) | Hard default in all published analyses |
| SEAGAL | Min spots per gene | 10 | Hardcoded |
| SEAGAL | Min UMI per spot | 150 | Hardcoded |
| AI-MARRVEL | All feature weights | Trained random forest | Not manually tuned; learned from data |
| RareCollab Integration Engine | Tier thresholds | Defaults based on clinical guidelines | **Manually adjusted per case by analysts** |

### 2.3 Parameters they ignore entirely

- **Mapping rate thresholds**: No minimum mapping rate threshold described in any paper
- **Duplication rate**: Not mentioned
- **Sequencing depth requirements**: PolyAMiner-Bulk mentions the tool handles low coverage; no depth gate described
- **Batch effects**: RareCollab uses 131 samples from 7+ clinical sites; batch correction not mentioned as a step
- **Library size normalization**: SEAGAL applies log-scaled CPM; no alternative considered

---

## 3. The Real Gaps: Where Work Is Manual and Time-Consuming

Based on reading the actual methods — not assumptions — these are the genuine bottlenecks:

### Gap 1: Multi-step pipeline orchestration per case

For each rare disease patient workup, the following must be run in sequence:
1. nf-core rnaseq (BAM files)
2. nf-core DROP development version (OUTRIDER, FRASER, GATK ASE)
3. AI-MARRVEL annotation (VCF from clinical lab → annotated variant table)
4. RareCollab integration (combining RNA outlier output + variant annotation + HPO phenotypes)
5. Optionally: PolyAMiner-Bulk (same BAM files, run separately → APA results)

These are currently run as separate pipeline commands. There is no integrated orchestrator. For 5–15 cases per month, this is substantial setup overhead — not QC configuration overhead, but **command execution and file management overhead**.

### Gap 2: Data flow between pipeline steps

The outputs of nf-core rnaseq (BAM/count matrices) are not automatically formatted as inputs for nf-core DROP, and DROP's OUTRIDER/FRASER outputs are not automatically formatted for RareCollab's RNA Lab. Each handoff between steps requires knowing the correct file paths, formats, and parameter flags. This is where trainees lose time — not configuring QC thresholds, but navigating file system handoffs between tools.

### Gap 3: Custom tool integration without an orchestrator

PolyAMiner-Bulk runs on the same BAM files produced by nf-core rnaseq, but it is a separate Python tool that must be invoked separately. SEAGAL runs on SpaceRanger output. Neither is integrated with nf-core DROP or with RareCollab. A case requiring APA analysis (e.g., a patient with splicing-related neurological disease) currently requires running PolyAMiner-Bulk as an additional manual step and then manually connecting its results to the case narrative.

### Gap 4: Dependency on a development-version pipeline

The RareCollab paper explicitly states they used `nextflow drop pipeline (development version)`. This is an unreleased version. Any external collaborator or tool attempting to replicate this workflow must access and pin the same development version — a reproducibility risk that nf-core versioning alone does not solve.

### Gap 5: Integration Engine tier adjustments are not persistent

When an analyst adjusts RareCollab's tier thresholds for a specific case (e.g., relaxing Tier 1 criteria for a patient with an unusual presentation or a gene with incomplete HPO annotation), that decision is not captured and reapplied to the next similar case. If the same analyst encounters another patient with a similarly atypical presentation, they make the threshold judgment again from scratch. This is where session memory has real, specific value.

### Gap 6: Case-level report aggregation

After running all steps, results from OUTRIDER (expression outliers), FRASER (splice outliers), AI-MARRVEL (variant rankings), and optionally PolyAMiner-Bulk (APA) must be brought together into a case report. This is currently assembled manually. A unified case report generation — with all tool outputs co-located and cross-referenced — would save significant time in the clinical narrative step.

---

## 4. What the Previous BioMate Proposal Got Wrong

### 4.1 The QC framing is incorrect for this lab

The proposal stated:
- *"QC threshold derivation per new sample type: 1-2 hours without BioMate → automatic with BioMate"*

**This is false.** The lab derives no QC thresholds. They use nf-core defaults. No paper describes any threshold derivation. This benefit does not exist for this lab.

- *"Versioned QC profiles: identical configuration enforced"*

**Not a pain point.** nf-core pipelines are already versioned. The issue is the development-version DROP dependency, which is a *compatibility* problem, not a QC configuration problem.

- *"Methods documentation: auto-generated after every run"*

**Not a significant pain point.** nf-core pipelines already generate MultiQC reports and pipeline execution reports. Their methods are documented through software versioning.

### 4.2 The "2-4 hours for WGS pipeline setup" claim is wrong

WGS VCF files arrive from Baylor Genetics' clinical sequencing lab. The Liu lab does not run variant calling. The annotation step (AI-MARRVEL) takes minutes to configure if you know the tool. The real time cost is not setup — it is result interpretation and Integration Engine threshold adjustment.

### 4.3 Arm C (literature assistant) may partially overlap with RareCollab's existing capability

RareCollab already has a **Literature Lab**: *"The retrieval specialist first assembles a focused set of gene- and rare disease-relevant publications based on titles and abstracts. The synthesis specialist then evaluates how closely reported human cases and model organism phenotypes match the current patient phenotypes."*

A BioMate literature assistant during analysis needs to provide something RareCollab's Literature Lab does not already do — or the study will show redundancy rather than complementarity. This needs to be framed more carefully: BioMate's literature assistant is available during the analysis setup and interpretation phases (before and after RareCollab), while RareCollab's Literature Lab operates internally during variant prioritization.

---

## 5. What the Proposal Should Actually Say

### The real efficiency story

The efficiency gain for this lab is not in QC configuration. It is in **pipeline orchestration for multi-modal case management**. A trainee today must:
1. Know nf-core rnaseq syntax and run it on the patient fastq
2. Know where the BAM files went and pass them to nf-core DROP (development version)
3. Know how to feed DROP outputs into RareCollab's RNA Lab
4. Receive VCF from the clinical lab and run AI-MARRVEL annotation
5. Combine all of the above in RareCollab
6. If APA is relevant, run PolyAMiner-Bulk separately on the same BAMs

Steps 1–6 could be one BioMate query: *"Run a complete rare disease workup for this patient: we have WES VCF and RNA-seq fastq files."* The efficiency gain is in **orchestration**, not QC.

### The real session memory story

The analyst making tier threshold adjustments in RareCollab's Integration Engine — *"for this case type, be more lenient on Tier 2 candidates with RNA support even if variant databases don't confirm pathogenicity"* — is the decision that should persist across sessions. This is highly specific and valuable for the rare disease domain where unusual presentations recur across related cases.

### The literature assistant story, corrected

BioMate's literature assistant value is in the **pre-analysis setup phase** (what pipeline should I run for this patient's phenotype? what QC parameters does the literature recommend for this tissue type?) and the **post-RareCollab interpretation phase** (understanding an OUTRIDER outlier gene in the context of the patient's phenotype). It is not competing with RareCollab's internal Literature Lab; it is operating at different points in the workflow.

---

## 6. Revised Framing for the Study Proposal

| Claim to change | From | To |
|---|---|---|
| QC threshold derivation | "1-2 hours manual → automatic" | Remove entirely |
| WGS pipeline setup | "2-4 hours → 5 minutes" | Reframe: "5-step orchestration → one query" |
| QC documentation | "auto-generated" as key benefit | Remove; replace with "unified case report" |
| Versioned QC profiles | Key benefit | Remove; not a pain point |
| Concordance arm | "BioMate vs. lab's custom pipeline" | "BioMate orchestrating the same nf-core tools they already use → near-identical by design; value is in demonstrating the orchestration, not the outputs" |
| Literature assistant | Implied competitor to existing methods | Complementary: pre-analysis and post-RareCollab phases only |
| Session memory | Generic "QC threshold carry-forward" | Specific: RareCollab Integration Engine tier adjustment persistence |

---

*Based on: RareCollab arXiv:2602.04058; AI-MARRVEL NEJM AI 2024 (PMC11221788); PolyAMiner-Bulk Cell Reports Methods 2024 (PMC9900750); SEAGAL Bioinformatics 2023 (PMC9948987)*
