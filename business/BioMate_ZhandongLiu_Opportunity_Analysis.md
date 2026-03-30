# BioMate × Dr. Zhandong Liu Lab — Internal Opportunity Analysis

**Audience:** BioMate product/engineering (internal only; not for the PI)  
**Context:** Google Scholar record and lab workflows as of March 2026  
**Purpose:** Honest fit assessment — what we can deliver today vs. what we would need to build to match their full stack.

---

## 1. Where BioMate Adds Immediate Value

BioMate is most credible where the lab already depends on **nf-core-class pipelines**, **transcriptomic aberration detection**, or **literature-aware interpretation** — i.e. the same substrate as LA-MARRVEL, RareCollab, MARRVEL-MCP-adjacent workflows, and their neuro / multi-omics programs.

### A. WGS/WES processing for rare disease

Their LA-MARRVEL and RareCollab stories assume a clean path from **WGS/WES → variant calls → downstream ranking or agentic reasoning**. The lab already runs **nf-core/sarek**; the friction is rarely “running Nextflow” and more often **correct rare-disease configuration** (depth, joint calling assumptions, annotation tiers, somatic vs germline posture). BioMate’s natural-language execution plus **QC governance** (e.g. depth gates such as **30× WGS**, annotation / threshold presets aligned to clinical genomics practice) reduces repeated expert setup and makes reruns auditable — the processing layer that sits *before* MARRVEL / LLM reranking.

### B. RNA outlier detection (OUTRIDER + FRASER)

**OUTRIDER** and **FRASER** are central to how they combine **WGS/WES with RNA-seq** for Mendelian diagnosis (RareCollab, LA-MARRVEL-style pipelines). BioMate already exposes these as **QC-governed subworkflows** with spiked / literature-informed gates (including rare-disease-oriented GOLD-level expectations). That is the **transcriptomic aberration arm** of their stack: expression and splicing outliers that feed candidate genes into MARRVEL or agentic workflows — without each trainee re-deriving thresholds from papers.

### C. Bulk RNA-seq for neurological studies

Their **MeCP2 / Rett**, **acute MeCP2 loss**, and **Alzheimer’s multi-omics** work lean heavily on **bulk RNA-seq** for DE and pathway context. **nf-core/rnaseq** in BioMate gives them a standardized, reproducible backbone; pairing it with **ENCODE-aligned QC governance for brain-relevant contexts** speeds every new cohort and makes cross-study comparison less ad hoc.

### D. Literature + transcriptomics integration

Their **2026 bioRxiv** tool linking **differential expression to biomedical literature** to surface **pharmacological gene regulators** is functionally adjacent to what BioMate’s **research intelligence agent** is built for: turning DE tables and gene lists into **evidence-grounded hypotheses** without maintaining a separate custom NLP stack. For that paper’s intent, BioMate is a **productized shortcut** rather than a one-off pipeline.

### E. Multi-omics (Alzheimer’s, MetaboLINK-style programs)

**Alzheimer’s (RNA-seq + proteomics + metabolomics)** and **MetaboLINK (metabolomics + longitudinal multi-omics)** do not require a single mythical “multi-omics button”; they need **reliable per-layer execution** and clear handoffs. BioMate can run **RNA-seq, proteomics (LC-MS/MS differential abundance), and metabolomics-oriented QC/analysis paths** as separate, governed steps and chain outputs — appropriate for labs that already integrate statistically outside the platform.

### F. CUT&RUN / chromatin occupancy (MeCP2-centric work)

**MeCP2 binding and chromatin remodeling** (e.g. **Science Translational Medicine** splicing modulation, **Neuron** acute loss work) depend on **chromatin profiling**, often **CUT&RUN** in the field. BioMate’s **epigenomics-style path** (e.g. **Bowtie2 + SEACR/MACS3 peak calling**) covers **occupancy and peak-based interpretation** comparable to many CUT&RUN analyses in practice. **Caveat:** this is **not** a full **nf-core/cutandrun** clone (spike-in calibration and pipeline-specific defaults differ); see Section 2.

### G. scRNA-seq downstream (complement to scAuto)

**Lemur** and other **scRNA-seq** programs use **scAuto** (their pipeline) for Cell Ranger–class preprocessing. BioMate does not need to replace scAuto: it can **consume Cell Ranger outputs** (or equivalent matrices) for **clustering, annotation, differential abundance, trajectory** via **Seurat / Scanpy / Cell Ranger–compatible flows**. Positioning: **extension after scAuto**, not a fork of their internal tool.

### H. Chemoproteomics / PROTAC target validation

The **MYC-targeting PROTAC** work (**ACS Chemical Biology**) rests on **LC-MS/MS**, **differential abundance**, and **pathway-level interpretation**. BioMate’s **proteomics QC, DEP/limma-style differential analysis, and enrichment** maps cleanly onto **target engagement and degradation validation** — the quantitative layer under the chemistry story.

### Explicit non-fit (internal honesty)

**ClinPreAI** (postpartum depression from **multimodal EHR**) is **clinical ML on administrative/clinical data**, not omics execution. BioMate is **not** the natural home for that line of work unless the scope expands far beyond current Galaxy/nf-core positioning.

---

## 2. Engineering Gaps to Close (Opportunities)

Framed as build work that would **unlock more value** for this lab specifically — not as excuses.

1. **nf-core/cutandrun-class pipeline** — They use **CUT&RUN** with **spike-in calibration**, **SEACR**, and normalization assumptions that differ from generic ChIP-seq. Today, **ChIP-seq–oriented** coverage exists; a **cutandrun-first** pipeline with the right controls and defaults would remove the remaining gap for MeCP2-centric chromatin papers. **Rough effort: ~1 week.**

2. **nf-core/raredisease end-to-end** — The full **YAML-driven rare disease stack** (SNV/indel + CNV + SV + MT + repeat expansions in one orchestrated product) is **not** wired as a single first-class BioMate workflow. **OUTRIDER** and **FRASER** exist as pieces, but the **orchestrating rare-disease genome pipeline** is the missing spine for LA-MARRVEL / RareCollab-style “everything in one place” narratives. **Rough effort: ~2 weeks.**

3. **nf-core/drop full orchestration** — **DROP** packages **OUTRIDER + FRASER** with **gene model and counting constraints** that matter for aberration calling. BioMate has the **components**; it lacks the **DROP-equivalent orchestration layer** (config, dependencies, and QC narrative as one pipeline). **Rough effort: ~1 week.**

4. **scAuto output adapter** — A thin **input contract**: accept **scAuto / custom pipeline** exports (**h5ad**, **Seurat RDS**, or documented matrix + metadata bundles) as **first-class inputs** to downstream BioMate steps — so the lab never has to re-export or hack formats. **Rough effort: ~3 days.**

5. **Model organism indices (Drosophila)** — **Lemur** and **Drosophila scRNA-seq** need **dm6** (or current FlyBase reference) **genome + annotation** for **RNA-seq and scRNA-seq** indexing. If BioMate’s default indices skew vertebrate-centric, adding **D. melanogaster** removes a silent blocker for that publication line. **Rough effort: ~2 days.**

---

## Summary table (lab workflow × BioMate)

| Workflow / theme | Lab stack | BioMate today | Gap |
|------------------|-----------|---------------|-----|
| WGS/WES (general) | nf-core/sarek | Strong | Rare-specific orchestration (raredisease) |
| Rare RNA aberrations | DROP / OUTRIDER / FRASER | OUTRIDER + FRASER subworkflows | DROP orchestration |
| Bulk RNA-seq | nf-core/rnaseq | Strong | — |
| CUT&RUN | nf-core/cutandrun | ChIP-seq–like path | cutandrun-specific pipeline |
| scRNA-seq | scAuto + Lemur | Post–Cell Ranger downstream | scAuto I/O adapter; dm6 |
| Multi-omics | RNA + proteomics + metabolomics | Per-layer + chaining | Deeper pre-built joint templates (optional) |
| NL genomics query | MARRVEL-MCP (their NL UI) | BioMate chat + tools | Compete/coexist on UX and KB, not on “having NL” alone |

---

*Internal document. Do not distribute to external partners or PIs without review.*
