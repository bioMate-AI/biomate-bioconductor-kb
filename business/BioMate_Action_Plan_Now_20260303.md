# BioMate AI — Action Plan: What To Do Now
*Handoff document for Engineering Team and Domain Experts · March 2026*
*Sequenced by dependency and business priority*

---

## How to Read This Document

Every task is labeled with:
- **Owner**: Engineering / Domain Expert / Founder
- **Effort**: honest size estimate
- **Status**: ❌ Not started · ⚠️ Partial · ✅ Done

Tasks are grouped into sprints. Sprint 0 must finish before any external beta user is invited. Sprints 1–3 follow in priority order. The Ongoing section runs in parallel with all sprints.

---

## Sprint 0 — Beta Stabilization
*Week 1–2 · Blocking: no external users until all 5 items are complete*

| # | Task | Owner | Effort | Status |
|---|---|---|---|---|
| 0.1 | Build `POST /api/export/qc_report` endpoint — returns PDF or HTML summary of a workflow run (QC gate outcomes + audit log table + metric values) | Engineering | 3 days | ❌ |
| 0.2 | Add cohort dimension to billing dashboard: cost per active user per month (current billing tracks per-query, not per-user cohort) | Engineering | 2 days | ⚠️ |
| 0.3 | Write user documentation — 3 short pages: (1) how to send a query, (2) how to run a workflow, (3) how to read QC output | Product | 2 days | ❌ |
| 0.4 | Record 3-min screen-capture walkthrough: query → workflow generated → workflow running → QC gate result | Founder | 1 day | ❌ |
| 0.5 | Instrument error-rate dashboard: crash rate, timeout rate, HTTP 5xx rate — must be visible before external users arrive | Engineering | 1 day | ⚠️ |

**Gate:** Every item ✅ before the first external beta invitation goes out.

---

## Sprint 1 — Drug Discovery Beta
*Month 1–3 · Priority #1*

**Why first:** The drug discovery platform is the most complete (12 phases end-to-end), the market is largest ($1.7B → $16.5B at 30% CAGR), and Texas Priority-A pharma/biotech targets are already identified and warm.

### Engineering

| # | Task | Effort | Notes |
|---|---|---|---|
| 1.E1 | Wire `LC-MS-agent` into the main platform: connect its endpoints through the Galaxy API proxy so users can invoke LC-MS proteomics analysis from the chat interface | 1 week | Agent already exists in `LC-MS-agent/`; this is integration work only, not new development |
| 1.E2 | Add AlphaFold3 server API call as a pre-docking step: `structure_prediction (AF3) → molecular docking (DiffDock / AutoDock Vina)` — the output structure from AF3 becomes the receptor input for docking | 1 week | Use AlphaFold3 public server API; no local GPU required for this step |
| 1.E3 | Add `survival_analysis` subworkflow: Kaplan-Meier curves + log-rank test + Cox proportional hazards regression using R `survival` package | 1 week | Reuse Bioconductor tool wrapper pattern from `bioconductor_skill/`; this workflow is also needed in Sprint 2 for RNA-seq |

### Domain Expert — Drug Discovery / Clinical PK

| # | Task | Notes |
|---|---|---|
| 1.D1 | Find a public ProteomeXchange (PXD) dataset: must have MaxQuant output files + clinical or compound metadata → will serve as benchmark dataset for Paper 4 methods section | Search ProteomeXchange for PRIDE datasets tagged "MaxQuant" + "clinical" or "pharmacoproteomics" |
| 1.D2 | Validate ADMET QC thresholds: review current hERG / DILI / Ames / ClinTox gates in the platform against published CPIC guidelines and FDA guidance documents; flag any gate that cannot be cited | Thresholds are in `backend/lib/galaxy/jobs/qc_trace_monitor.py` |
| 1.D3 | Make first contact with a wet lab pharma partner: approach one of — Baylor College of Medicine HGSC, Baylor Genetics, UT Southwestern Simmons Cancer Center — propose a 4-week pilot running ADMET + docking on 10–20 real compounds | The goal is a testimonial + a named reference for Paper 4 |

### Founder

| # | Task | Notes |
|---|---|---|
| 1.F1 | Send invite-code emails to 5 Priority-A Texas drug discovery targets: Baylor Genetics, NeuroX1 (Austin), BCM Quantitative & Computational Biosciences, GENAC (San Antonio), ARPA-H Dallas Hub participants | Use outreach templates from `marketing/outreach_templates.py` when available |
| 1.F2 | File provisional patent: hybrid LLM inference system + QC governance framework (USPTO provisional application) | Provisional protects for 12 months; costs ~$1,600 with attorney. Do not delay past Month 3. |

**Sprint 1 success gate:** 3 external users have completed at least 1 full drug discovery workflow end-to-end; QC audit log exported; at least 1 provides written feedback.

---

## Sprint 2 — RNA-seq & Cryo-EM Beta
*Month 2–4 · Priority #2 and #3 run in parallel*

**Why together:** Both platforms are functionally complete — the remaining gaps are specific and sized. Running them in parallel maximizes the number of beta users acquired before Month 4.

### Engineering — RNA-seq

| # | Task | Effort | Notes |
|---|---|---|---|
| 2.E1 | Add `patient_stratification` workflow bundle: (a) unsupervised consensus clustering via `ConsensusClusterPlus` R package, (b) PAM50 molecular subtype wrapper, (c) connector from DE results into survival groups → Kaplan-Meier (reuse 1.E3) | 2 weeks | ConsensusClusterPlus is in Bioconductor; add it as a tool wrapper |
| 2.E2 | Add immune cell deconvolution step: wrap CIBERSORT R package (or BayesPrism) alongside existing `deconRNAseq` tool; add as an optional step after DE in the RNA-seq workflow | 1 week | CIBERSORT requires license for commercial use; use BayesPrism as default (open source) |
| 2.E3 | Build GEO/TCGA data connector: given a GEO accession or TCGA project ID, auto-fetch the count matrix + clinical metadata and load it into a BioMate workflow session | 1 week | Use `GEOquery` R package + TCGA data via `TCGAbiolinks`; both are Bioconductor packages already in the catalog |

### Engineering — Cryo-EM

| # | Task | Effort | Notes |
|---|---|---|---|
| 2.E4 | Provision AWS g6.2xlarge instance with CryoSPARC v5 license for EMPIAR dataset benchmarking | 1 day (DevOps) | Cost ~$50–100/dataset; CryoSPARC academic license already held (`f312a30e-63fc-11f0-8e36-e3c932851287`); see `docs/CRYOSPARC_CLOUD_SETUP_GUIDE.md` |
| 2.E5 | Add AlphaFold3 structure fitting post-cryo-EM refinement: after `SHARPEN` step, call AF3 API for atomic model fitting into density map; report model-to-map cross-correlation score in QC output | 1 week | This closes the "cryo-EM structure → drug design" loop |
| 2.E6 | Add MolProbity and EMRinger model quality score parsing into the cryo-EM QC pipeline — these are standard structure validation metrics expected in any cryo-EM publication | 1 week | MolProbity runs via web API or local CCP4 installation; EMRinger is part of PHENIX |

### Domain Expert — RNA / Clinical Oncology

| # | Task | Notes |
|---|---|---|
| 2.D1 | Identify FFPE tumor RNA-seq cohort from TCGA: BRCA, LUAD, or COAD (all have FFPE samples + survival outcome data) → will be used to run the `rnaseq_ffpe` QC profile and demonstrate patient stratification | Access via TCGA portal or `TCGAbiolinks` R package |
| 2.D2 | Validate `rnaseq_ffpe` QC profile thresholds with a clinical bioinformatician from a hospital genomics lab; document any threshold that needs adjustment with a citation | Profile is in `qc_trace_monitor.py` under `QC_NAMED_PROFILES` |
| 2.D3 | Approach one of these labs for closed beta: MD Anderson Bioinformatics & Computational Biology dept, UT Southwestern Lyda Hill Bioinformatics, UTHealth McWilliams School of Biomedical Informatics | Offer: free Enterprise tier for 6 months + co-authorship credit in Paper 1 |

### Domain Expert — Structural Biology

| # | Task | Notes |
|---|---|---|
| 2.D4 | Run EMPIAR-10061 (TRPV1 channel, 3.8Å reference resolution) through the BioMate cryo-EM SPA pipeline; document: achieved resolution, QC gate outcomes, runtime vs. manual CryoSPARC | This is the primary benchmark for Paper B |
| 2.D5 | Identify and recruit a structural biologist co-author for Paper B (cryo-EM benchmark paper in `research_repos/cryo_em_benchmark_paper/`) — must have published ≥1 cryo-EM structure and be familiar with CryoSPARC | Target: UT Southwestern UTSW Cryo-EM core staff or BCM structural biology faculty |

### Founder

| # | Task | Notes |
|---|---|---|
| 2.F1 | Apply to NVIDIA Inception program — provides compute credits, enterprise network access, and co-marketing opportunities | Application is free; takes ~2 weeks to process |
| 2.F2 | Submit BioMate as a Galaxy Labs instance — formal partnership with the Galaxy Project builds distribution clout with 50K+ researchers in the community | Submit via Galaxy Labs application form |
| 2.F3 | Email 5 Priority-A RNA/clinical Texas targets: MD Anderson, UT Southwestern Simmons Cancer Center, UTHealth McWilliams, BCM HGSC, Texas Children's Hospital Research | Personalized email referencing their specific publications |
| 2.F4 | Email 2 Priority-A cryo-EM targets: UT Southwestern Lyda Hill Bioinformatics (has a cryo-EM core facility), Houston Methodist Research Institute | Angle: "reproducible, QC-governed cryo-EM with full audit log — submit-ready data package" |

**Sprint 2 success gate:** EMPIAR-10061 benchmarking complete with documented results; 2 RNA-seq beta users onboarded; 1 cryo-EM collaborator confirmed.

---

## Sprint 3 — Single-Cell Perturbation Pipeline
*Month 4–8 · Priority #4*

**Why last:** This is the largest gap (3–4 weeks of engineering, no existing CRISPR screen pipeline) and the market is newer. Build it after Sprints 1–2 are delivering beta evidence.

### Engineering

| # | Task | Effort | Notes |
|---|---|---|---|
| 3.E1 | Build MAGeCK hit calling wrapper: MAGeCK MLE (maximum likelihood) + RRA (robust rank aggregation) for identifying essential genes from CRISPR screens; integrate with existing `analyze_crispr_genome_editing` tool | 2 weeks | MAGeCK is available via Bioconda; wrapper follows the same pattern as existing tool wrappers |
| 3.E2 | Add CRISPResso2 guide assignment and edit outcome classification (insertion/deletion/substitution) as a pre-processing step before MAGeCK | 1 week | CRISPResso2 is available via PyPI and Bioconda |
| 3.E3 | Build scVI perturbation modeling workflow: guide assignment → cell filtering → differential abundance testing → perturbation state inference using `scvi-tools` (Norman et al. approach) | 2 weeks | `scvi-tools` is already available; this implements the Perturb-seq computational analysis |
| 3.E4 | Add trajectory inference: Monocle3 wrapper (R, Bioconductor) + scVelo wrapper (Python) for RNA velocity analysis | 1 week | Both are in the tool catalog; need workflow wrappers |
| 3.E5 | Create `scrna_perturbation` named QC profile: guide library coverage gate (≥70% cells assigned a guide), transfection efficiency gate, DoubletFinder doublet detection | 3 days | Add to `QC_NAMED_PROFILES` in `qc_trace_monitor.py`; write `TestSingleCell_Perturbation` test class |

### Domain Expert — Functional Genomics / CRISPR

| # | Task | Notes |
|---|---|---|
| 3.D1 | Identify a public Perturb-seq dataset for internal pipeline development: Norman et al. 2019 CRISPRi dataset (Addgene) or any dataset from the scPerturb harmonized repository (Nature Methods 2024) | Used to develop and test the MAGeCK + scVI pipeline before external users |
| 3.D2 | Define QC thresholds for Perturb-seq: guide library coverage floor, minimum transfection efficiency, expected doublet rate — reference the Compressed Perturb-seq paper (Genentech, Nature Biotech 2024) for values | Thresholds become the `scrna_perturbation` QC profile |
| 3.D3 | Approach Rice University Treangen Lab or MD Anderson functional genomics group as first external single-cell/Perturb-seq beta user | Angle: "reproducible CRISPR screen analysis — re-run by any authorized user with identical results" |

### Founder

| # | Task | Notes |
|---|---|---|
| 3.F1 | Approach Texas Medical Center (TMC) Innovation Hub for a consortium partnership spanning all 4 directions — one institutional agreement covers drug discovery, RNA, cryo-EM, and single-cell teams simultaneously | This is the highest-leverage business development action in Sprint 3 |
| 3.F2 | Open the public free tier: post to r/bioinformatics, nf-core Slack (#general and #workflow), Galaxy community forum, Twitter/X @BiomateAI | Target: 500 registered users within 30 days of public launch |

**Sprint 3 success gate:** MAGeCK + scVI pipeline runs end-to-end on a public Perturb-seq dataset; 1 external single-cell beta user onboarded.

---

## Ongoing — Business, Papers, and Network
*Runs in parallel with all sprints*

### Business (Founder)

| # | Task | Timeline | Notes |
|---|---|---|---|
| O.B1 | NPS + session tracking: install Hotjar or Mixpanel before the first external beta user is invited | Week 1 (Sprint 0) | Must be live at the same time as user docs (0.3) |
| O.B2 | Pro upgrade campaign: email all existing invited users with a time-limited Pro offer; target 25 paying users by Month 2 and 78 (break-even) by Month 4 | Month 1 | Break-even = 78 Pro × $29/mo = $2,247 MRR |
| O.B3 | 30-day cohort analysis at Month 3: retention rate, sessions per user, workflow completion rate, churn — first real business evidence | Month 3 | Run the analysis; write a 1-page findings memo |
| O.B4 | Seed round materials: prepare deck + data room when: 50+ active users, 3+ paying users, NPS ≥ 30 | Month 9 | Do not start earlier — investors want evidence, not projections |

### Papers (Domain Experts + Founder)

| # | Paper | Key Gap to Close | Target Venue | Target Date |
|---|---|---|---|---|
| O.P1 | **Paper 1** — QC governance stack | Recruit single-cell co-author (most critical); write methods section using 5 benchmark datasets in `research_repos/biomate_qc_governance_paper/` | Nature Methods | Month 9 bioRxiv preprint |
| O.P2 | **Paper 4** — Drug Discovery QC | Recruit clinical PK / pharmacoproteomics co-author; write methods section once LC-MS is wired (1.E1) | Nature Chemical Biology | Month 12 bioRxiv preprint |
| O.P3 | **Paper B** — Cryo-EM benchmark | Write methods section after EMPIAR-10061 run (2.D4); recruit structural biology co-author (2.D5) | Nature Communications or J. Struct. Biol. | Month 15 bioRxiv preprint |

### Network / Consortium (Engineering + Founder)

| # | Task | Owner | Effort | Notes |
|---|---|---|---|---|
| O.N1 | Create `biomate_dataset_registry.json`: public dataset accessions (GEO, EMPIAR, ProteomeXchange) linked to BioMate QC audit certificates | Engineering | 1 week | This is the technical foundation of the "BioMate Research Network" |
| O.N2 | Export QC threshold database to GitHub as open-source JSON: take `QC_NAMED_PROFILES` and threshold constants from `qc_trace_monitor.py`, generate a human-readable, citable JSON file | Engineering | 3 days | Community can contribute new evidence citations via pull requests |
| O.N3 | Design 3 cross-domain workflow templates: (A) "RNA-seq biomarker → drug target" (DESeq2 → GSEA → TxGNN repurposing), (B) "Cryo-EM structure → drug design" (refinement → AF3 fitting → DiffDock), (C) "CRISPR screen → drug target" (MAGeCK hits → ADMET screening) | Engineering + Domain Experts | 1 week each | These templates are the connectors that create dependency between teams |

---

## Summary Timeline

| Sprint | When | Engineering Focus | Domain Expert Focus | Founder Focus |
|---|---|---|---|---|
| **Sprint 0** | Week 1–2 | QC report export; error dashboard; billing cohort | — | User docs; video walkthrough |
| **Sprint 1** | Month 1–3 | LC-MS wire; AlphaFold3 pre-docking; survival workflow | Validate ADMET thresholds; identify PXD dataset; contact wet lab partner | Patent filing; Priority-A drug discovery emails |
| **Sprint 2** | Month 2–4 | Patient stratification; GEO connector; EMPIAR provisioning; AF3 cryo-EM fitting; MolProbity | FFPE threshold validation; EMPIAR-10061 run; RNA beta user recruitment | NVIDIA Inception; Galaxy Labs; RNA + cryo-EM outreach emails |
| **Sprint 3** | Month 4–8 | MAGeCK + scVI pipeline; trajectory inference; perturbation QC profile | Perturb-seq dataset; CRISPR QC thresholds; functional genomics beta user | TMC consortium; public beta launch |
| **Ongoing** | All | Dataset registry; QC DB export; cross-domain templates | Paper 1+4+B manuscripts; co-author recruitment | NPS tracking; break-even campaign; cohort analysis; seed prep |

---

## Critical Path

```
Sprint 0 (stabilization)
    → Sprint 1 (Drug Discovery beta — first paying users)
        → Sprint 2 (RNA + Cryo-EM beta — parallel)
            → Sprint 3 (Single-Cell — pipeline build first, then users)
                → Public beta + seed round prep (Month 9)
```

**The single most important action this week:** Complete Sprint 0.1 (QC report export) and 0.5 (error dashboard), so the platform is demonstrably stable enough to show to external users. Everything else depends on this.

---

*BioMate AI LLC · biomate.ai · March 2026 · Internal — Not for distribution*
