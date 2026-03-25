# Research Collaboration Proposal
## BioMate AI × Dr. Zhandong Liu Lab — Baylor College of Medicine

*March 2026 · Confidential*

---

## The Opportunity

Dr. Liu's lab sits at the intersection of computational genomics, neurological disease, and AI-assisted discovery — exactly the research profile that BioMate was built to support. The lab runs sophisticated multi-modal analyses: whole-genome sequencing for rare disease diagnosis, transcriptomic outlier detection, single-cell RNA-seq atlases, chromatin profiling of MeCP2 biology, and pharmacological genomics. The bottleneck is not scientific ideas or data — it is the overhead of configuring, running, quality-checking, and reproducing computationally intensive analyses across a team that spans trainees at different experience levels.

BioMate removes that overhead. But a platform is only as credible as the domain it has been tested against. Rare disease genomics and neurological transcriptomics are among the most demanding validation contexts that exist for a bioinformatics platform — they require correct rare-variant configuration, clinical-grade QC thresholds, and reproducibility standards that publications demand. That is why a collaboration with this lab is valuable to both sides, not just to the lab.

---

## What BioMate Brings to the Collaboration

**1. A running platform you can use immediately**

BioMate is live. It runs nf-core/sarek for WGS/WES, nf-core/rnaseq for bulk RNA-seq, Cell Ranger–downstream scRNA-seq analysis, OUTRIDER/FRASER for aberrant expression and splicing, ChIP/CUT-style epigenomic pipelines, and LC-MS/MS proteomics analysis. No local installation, no queue management, no HPC allocation required — describe the analysis in plain language, upload the data, and receive results.

**2. QC governance that matches clinical genomics standards**

Every analysis step is monitored against evidence-based thresholds tagged by evidence tier (GOLD/SILVER/BRONZE). For WGS, this means 30× depth gates, GATK best-practice alignment QC, and variant annotation with population frequency filters appropriate for rare disease. For RNA-seq, this means brain-tissue–aware alignment metrics, rRNA fraction monitoring, and outlier detection significance thresholds grounded in DROP/OUTRIDER literature. For each analysis, the scientist sees what failed, why it matters scientifically, and the evidence behind the threshold — not just a number.

**3. A literature-aware AI assistant embedded in every session**

The BioMate research agent searches PubMed and ArXiv in real time and returns synthesised, cited answers to scientific questions during an analysis. When a variant of unknown significance appears in a rare disease patient, the analyst can ask what the literature says about that gene in that disease context — and get an answer with citations, within the same session, before deciding whether to escalate the candidate. When a splice junction appears as an outlier, the analyst can ask whether it has been reported in any other neurological disease cohort.

**4. Infrastructure and compute**

BioMate provides cloud compute on AWS Batch. For the collaboration, we will cover compute costs for agreed analyses — the lab provides the data and the scientific question, we provide the execution environment. For datasets with data residency requirements, analyses can be configured to run on institutional compute (SLURM) or cloud accounts the lab already controls.

**5. Fast customization for the lab's specific needs**

Based on gap analysis of the lab's published workflows, we have identified a short list of customization work we would complete before or during a pilot engagement:

- Full nf-core/cutandrun pipeline with spike-in calibration (for MeCP2 CUT&RUN analyses) — estimated 1 week of engineering
- nf-core/raredisease orchestration as a single end-to-end pipeline (SNV + SV + MT + repeat expansion, for LA-MARRVEL/RareCollab-aligned workflows) — estimated 2 weeks
- DROP orchestration layer integrating OUTRIDER + FRASER under shared configuration — estimated 1 week
- scAuto output adapter so BioMate picks up cleanly after the lab's own preprocessing — estimated 3 days
- Drosophila genome index (dm6) for Lemur and related work — estimated 2 days

These are builds we would do *for the collaboration* — not hypothetical future items. They would be completed before the lab runs analyses that depend on them.

---

## What We Ask From the Lab

A collaboration is not a free compute arrangement. What BioMate gets from working with a lab of this caliber is qualitatively different from what we get from general user feedback, and we want to be explicit about that.

**1. Validation data and ground-truth comparisons**

The lab runs established, well-characterized analyses — LA-MARRVEL, OUTRIDER/FRASER rare disease cohorts, MeCP2 bulk RNA-seq studies — where the correct answer is known or can be evaluated against published results. Running BioMate on those same analyses and comparing outputs gives us validation data we cannot generate internally: does BioMate produce the same variant calls, the same outlier genes, the same differential expression results as the lab's own pipelines? When outputs differ, why? That feedback directly improves the platform.

We ask the lab to designate 2–3 analyses per pilot month where BioMate results are compared against the lab's own pipeline output and the differences are documented. This does not require additional wet-lab work — these are analyses the lab is already planning to run.

**2. QC threshold feedback from domain experts**

BioMate's brain-tissue RNA-seq profile and rare disease QC profiles are calibrated to published guidelines. But the lab has run enough post-mortem brain RNA-seq and rare disease WGS to know where published guidelines are too strict, too permissive, or silent. We ask for structured feedback on which thresholds the lab would set differently and why — that feedback gets incorporated into the platform's evidence base, with the lab's name on the contribution if they choose.

**3. A co-developed use case for publication or conference**

The strongest form of collaboration is one where BioMate contributes to a real scientific result that the lab publishes or presents. That could be:

- Using BioMate to run a secondary analysis on an existing dataset as a methods comparison (the lab already has the results; BioMate's analysis is the comparison arm)
- Integrating BioMate into the preprocessing or QC layer of an in-progress manuscript where reproducibility and audit trail are a value-add
- Co-authoring a methods or tools paper that describes the BioMate platform in the context of a rare disease or neurogenomics use case, benchmarked against established tools

We are not asking the lab to restructure its research around BioMate. We are asking whether one ongoing project could be run through BioMate in parallel, producing either a comparison result or an audit-trail contribution that strengthens the paper's methods section.

**4. Introductions within the rare disease and neurogenomics community**

If the collaboration produces good results, we ask for the kind of referral that happens naturally in science: telling colleagues who face the same computational bottlenecks that BioMate is worth looking at. We are not asking for formal endorsements or co-marketing. We are asking for honest word-of-mouth from a lab that actually used the platform and found it credible.

---

## What a Pilot Would Look Like

**Duration:** 8 weeks

**Week 1–2: Setup and baseline**
- scAuto adapter built and tested with the lab's Cell Ranger–format outputs
- Cutandrun pipeline validated with a lab sample or EMDB benchmark data
- Lab's first 2–3 analyses submitted and compared against known results; discrepancies documented and routed to engineering immediately

**Week 3–6: Active use and feedback**
- Lab trainees and postdocs use BioMate for designated analysis types (bulk RNA-seq, WGS, scRNA-seq downstream)
- BioMate team reviews QC threshold feedback weekly and pushes updates
- Research intelligence agent tested against the lab's current literature review workflow for specific projects

**Week 7–8: Evaluation and path forward**
- Formal comparison of BioMate outputs vs. lab pipeline on agreed analyses
- Structured feedback from 2–3 people who used the platform regularly (not a survey — a 30-minute conversation)
- Decision on whether to continue, expand, or co-develop specific capabilities
- Discussion of publication or conference contribution if results are strong

**What the lab does not need to do:**
- Install or maintain any software
- Manage compute allocation or job queues
- Reformat data (we will build the adapters before the pilot starts)
- Commit to any outcome other than honest feedback

---

## Why Now

The LA-MARRVEL paper and RareCollab program represent exactly the kind of AI-in-the-loop rare disease genomics story that the field is now ready to act on — but the computational infrastructure underneath it (correct QC, reproducible variant calling, standardized RNA outlier detection) is still often done differently lab by lab, trainee by trainee. BioMate is positioned to be that infrastructure layer.

The pharmacological genomics work — connecting expression signatures to drug regulators — is live on bioRxiv and needs a platform home. BioMate's research intelligence agent is already doing parts of that task: literature-backed hypothesis generation from DE results. A collaboration that starts with "does BioMate's research agent reproduce what your custom NLP pipeline finds?" is a one-week experiment with a clear answer.

The field is moving fast. There will be other platform options in 12 months. Starting now means that any BioMate customization for the lab's workflows — rare disease orchestration, CUT&RUN spike-in calibration, scAuto adapter — is built around the lab's actual needs and the lab has input on how it is built.

---

## Proposed Next Step

A 60-minute session, in person or by video, covering:

1. Walk through one active analysis — the lab describes it, we show how BioMate would approach it, and we are honest about any gap
2. Review the customization list — confirm which builds are priorities and agree on a timeline
3. Agree on the 2–3 baseline comparison analyses that would define the pilot
4. Discuss whether there is a paper or project where BioMate's involvement would be genuinely useful

If the session produces a clear fit, we move immediately to Week 1 setup. If it does not, no further obligation for either side.

---

*BioMate AI · biomate.ai · March 2026*  
*For discussion with Dr. Zhandong Liu's lab — Baylor College of Medicine*
