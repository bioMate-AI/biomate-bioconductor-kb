# BioMate × SYSUCC: capabilities and use cases (BD briefing, English)

Date: 2026-10-30
Audience: BioMate business-development team preparing for the first meeting with the Director of the Information Center, Sun Yat-sen University Cancer Center (SYSUCC, 中山大学肿瘤防治中心), Guangzhou.
Chinese version: [20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md](20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md)

---

## How to use this document

This is the **first meeting**, arranged through our Chinese agency. It has two goals: **briefly introduce what BioMate offers**, and **learn what the hospital expects**. No live demo is planned. Plan for about one third talking and two thirds listening.

| If you need… | Read |
| --- | --- |
| Background, if you are new to biomedicine and drug development | Sections 1–2 |
| What BioMate is and what it can do | Sections 3–7 |
| How hospital data fit in | Section 8 |
| What to say in the meeting | Sections 9–11 |
| Wording to use carefully, and a one-page summary | Sections 12–13 |

You do not need to present everything. Pick what fits the conversation.

**The one sentence to remember:**

> **BioMate is an AI research platform that turns the hospital's own data into research results and capabilities that keep improving — from everyday lab and omics analysis to drug development — with every result traceable to its data, method and model version.**
>
> 院内数据驱动、可持续学习的肿瘤科研与药物研发平台

---

## 1. Background

### 1.1 Drug development in five minutes

A new medicine typically takes 10–15 years and passes through the stages below. Most candidates fail along the way, mainly because they do not work well enough or are not safe enough. Anything that makes each stage faster and better informed is valuable.

| Stage | Plain-language question | Typical work | Where a cancer hospital helps |
| --- | --- | --- | --- |
| **1. Target identification** | Which molecule in the tumor should we attack? | Analyze patient tumor data (DNA, RNA, single cells, tissue images) to find the genes or proteins that drive the cancer. | Hospitals own patient tumor samples and outcomes. This is their strongest contribution. |
| **2. Hit discovery** | Which candidates can act on that target at all? | Design or screen many candidates, first on the computer and then in the lab. | Lab assays and patient-derived tumor models. |
| **3. Lead optimization** | How do we make the best candidate stronger and safer? | Repeated cycles of design → make → test → learn. | Experimental results, including failures, from organoids, cells and animals. |
| **4. Preclinical development** | Is it safe enough, and how does the body handle it? | Toxicity testing, pharmacokinetics (PK) and animal studies. | Translational laboratories and animal models. |
| **5. Clinical research** | Does it work in patients, at what dose, and for whom? | Phase I–III trials and biomarker studies. | SYSUCC runs many oncology trials. |

### 1.2 Drug types: a general platform

BioMate is not tied to one type of drug ("modality"). Representative drug types it provides computation for:

| Drug type | What it is | Example computation in BioMate |
| --- | --- | --- |
| **Small molecules** | Classic pill-type drugs, such as erlotinib, a lung-cancer drug that blocks the EGFR protein | Docking, ADMET and toxicity prediction, property and potency models, pharmacokinetics |
| **Peptides** (linear and cyclic) | Short chains of amino acids; cyclic peptides are closed into a ring for stability and selectivity | Peptide design, peptide–target structure modelling, binding-energy estimation, stability and permeability assessment |
| **Proteins and antibodies** | Large protein drugs, including antibodies, nanobodies and engineered formats | Protein structure prediction, antibody design (e.g. nanobody, scFv, bispecific), developability assessment, glycosylation-site prediction, antibody pharmacokinetics |

The same research process (evidence → design → evaluation → learning from experiments → provenance) applies to each drug type, using methods appropriate to it.

### 1.3 Glossary

| Term | Meaning in one line |
| --- | --- |
| Target | The protein or gene a drug is designed to act on. |
| Hit / lead / candidate | A hit shows some activity; a lead is the most promising one being improved; a candidate is one considered for development. |
| IC50 | The concentration needed to block 50% of activity. **Lower means more potent.** Units matter: 1 µM = 1,000 nM. |
| ADMET | Absorption, distribution, metabolism, excretion and toxicity: whether a molecule can become a usable drug. |
| hERG | A heart ion channel. Blocking it can cause dangerous heart-rhythm problems, so it is a standard early safety check. |
| Docking | A computer simulation of how a molecule fits into a target's pocket; a prediction used to prioritize candidates. |
| PK (pharmacokinetics) | How drug concentration in the body changes over time (half-life, exposure). |
| Assay | A laboratory experiment that measures something, such as potency or toxicity. |
| Organoid / PDX | An organoid is a mini-tumor grown from a patient's cells; a PDX is a patient's tumor grown in a mouse. |
| Omics | Large-scale molecular measurements: genomics (DNA), transcriptomics (RNA), proteomics (proteins), metabolomics (metabolites). |
| Single-cell / spatial | Measurements of individual cells, and of where cells sit in a tissue section. |
| Workflow | A validated, reusable sequence of analysis steps, for example "raw sequencing data → quality control → gene expression → differential genes". |
| Model training / fine-tuning | Updating an AI model's internal parameters ("weights") with new data so that it predicts better for a task. |
| Holdout set | Data deliberately kept out of training and used only to test a model fairly. |
| Knowledge base / retrieval | Giving the AI access to documents (SOPs, papers, protocols) when it answers. Useful, but different from training. |
| Provenance | The record of where a result came from: data, method, parameters, model version and who ran it. |

---

## 2. About the customer

This section summarizes public information gathered in October 2026. Figures marked "self-reported" come from the hospital's own publicity. Detailed sources: [drug-development collaborations and ambitions](research/20261030_SYSUCC_DRUG_DEVELOPMENT_COLLABORATIONS_AND_AMBITIONS.md) and [research data showcases](20261029_SYSUCC_DATA_TO_DRUG_DEVELOPMENT_SHOWCASES.md).

### 2.1 SYSUCC at a glance

- One of China's leading cancer hospitals and research centers, in Guangzhou, with the **State Key Laboratory of Oncology in South China** (华南恶性肿瘤防治全国重点实验室). Campuses in Yuexiu and Huangpu, with a new Tianhe campus (中山大学肿瘤医学科学中心) under development.
- Best known for **nasopharyngeal carcinoma (NPC, 鼻咽癌)**, immuno-oncology clinical trials, colorectal and gastrointestinal cancers, and EBV (Epstein–Barr virus) research, which is closely linked to NPC.
- Faculty publish widely in genomics, single-cell and spatial biology, pathology, immunology, biomarkers and clinical trials.
- **Research assets described in publications:**
  - a genomic cohort of about 1,000 Chinese colorectal-cancer patients;
  - NPC single-cell and spatial atlases;
  - patient-derived organoids;
  - pathology images;
  - blood-based biomarker studies;
  - a tumor biobank linked to hospital records;
  - a research-data deposit platform (RDD), running since 2017.

  These show what their teams work on. They do not tell us what data are available to us.

### 2.2 Its role in drug development: China's leading clinical-trial center

SYSUCC is primarily **the place where new cancer drugs are tested and proven in patients**. It is not mainly a company-style drug discoverer.

- **Scale (self-reported):**
  - more than 500 partner companies;
  - 1,237 industry-sponsored trials and 2,117 investigator-initiated trials (IITs) in the last five years, enrolling more than 10,000 patients a year;
  - a Phase I ward with 33 beds and more than 160 active early-phase projects, over 80% of them new-to-world drugs.

  The president says the hospital helps bring 5–10 new cancer drugs or indications to market each year, about a quarter of China's total.
- **Landmark trials:** SYSUCC investigators led all three first-line Phase 3 trials of PD-1 immunotherapies in advanced NPC: Junshi's toripalimab (JUPITER-02, the basis for its US FDA approval), Hengrui's camrelizumab and BeiGene's tislelizumab. They also ran investigator-led Phase 3 trials with Innovent and Hengrui drugs, published in The Lancet and JAMA.
- **The current wave is antibody-drug conjugates (ADCs) and bispecific antibodies.** SYSUCC leads first-in-human and pivotal trials for many Chinese innovators, for example:
  - Lepu's MRG003, approved in China for NPC in October 2025;
  - KeyMed's CMG901, licensed to AstraZeneca;
  - Kelun's sac-TMT, published in NEJM;
  - Biokin, MediLink, Simcere and Alphamab assets.
- **Main drug types in their work:** PD-1/PD-L1 immunotherapy, ADCs, bispecific antibodies, cell therapy (TCR-T, CAR-T, TIL-like cells), and EBV vaccines and antibodies. Small molecules appear in trials but are not where the hospital originates drugs.

### 2.3 Its own drug origination: early, focused on EBV and cell therapy

- **EBV programs** (Professor Zeng Musheng's team):
  - a 2025 Nature paper identified **R9AP as the EBV receptor**, a new target for vaccines and antibodies;
  - a preventive EBV vaccine was licensed to Zhifei for RMB 100 million plus royalties, with an IND filing expected in 2027;
  - a therapeutic EBV mRNA vaccine, a panel of more than 50 human EBV antibodies and an EBV ADC are preclinical. The team said publicly in 2026 that some of these are **still seeking financing and partners**.
- **Cell therapy:**
  - Fanen Bio (泛恩生物), founded by SYSUCC professor Zhou Penghui, develops personalized TCR-T cell therapies and holds an NMPA IND;
  - the Biotherapy Center runs several TCR-T, TIL-like and CAR-T trials;
  - SYSUCC has GMP cell-production facilities.
- **Other licensing:** a gut bacterium that enhances immunotherapy, licensed to Junshi (up to RMB 500 million in milestones, 2022), plus many small transfers of biomarker models, devices and software.
- **Organoids:** a Phase 3 randomized trial of organoid-guided therapy in breast cancer, and organoid drug-sensitivity assays.

### 2.4 Strategy and expectations

- **"1249" strategy (2024):** become a world-top cancer center by 2035, benchmarked against MD Anderson. One of its nine outcome goals is **innovative drugs and devices with the hospital's own intellectual property**.
- **15th Five-Year Plan: "IIT-IND dual track"** (IIT-IND 双轨). Investigator-initiated studies are meant to lead to INDs filed by the hospital itself, so it moves from testing others' drugs toward developing its own.
- **Leadership view:** the president, Xu Ruihua, has said Chinese pharma must move "from me-too/me-better to first-in-class."
- **Policy support:** Guangdong, Guangzhou and Huangpu provide significant funding for clinical trials, IITs (e.g. up to RMB 300,000 per completed IIT in Huangpu), cell and gene therapy, and hospital-to-company technology transfer.

**Is first-in-class their expectation?** It is a stated ambition, especially in EBV and immunotherapy, but it is early and resourced far below their clinical-trial engine. Their real strength today is clinical development, translational biomarkers and their own EBV and cell-therapy discoveries.

### 2.5 What this means for BD

- **Lead with what they do every day:**
  - early-phase clinical trials (dose-escalation design, pharmacokinetic modelling);
  - investigator-initiated trials and their biomarker sub-studies (sequencing, single-cell, spatial, ctDNA analysis);
  - research data analysis across departments.
- **Then connect to their ambition:** the "IIT-IND dual track" and their own EBV and cell-therapy assets. BioMate can help turn their discoveries into development-ready evidence, such as target structure, antibody and candidate analysis, organoid drug-response analysis and evidence packages.
- **Avoid opening with** "we design first-in-class small molecules for you." It does not match how they work today.

### 2.6 The person: Director of the Information Center

The Director is an IT and data-infrastructure leader, not a laboratory scientist or drug-development expert. SYSUCC is **already experienced with AI**. In 2025 the information center publicly sought an AI platform foundation, and a university report describes an existing DeepSeek-based oncology assistant and model development on internal data.

What they are likely to care about:

1. **Data control and security:** where data are stored, where AI models run, who can access what, and audit trails. BioMate will be deployed **on-premises**. The hospital's specific security and compliance requirements are something we **learn from them** (section 11.1).
2. **Serving many research teams:** a platform used across departments and faculty groups, not a tool for one project.
3. **Turning data into an institutional asset:** research data, analysis methods and models should become reusable capabilities.
4. **Fit with existing systems:** their AI platform, DeepSeek deployment, GPU/HPC computing and hospital systems. They will not want another isolated chatbot.
5. **Visible research value:** reproducible, publishable results; more research output per team.

**Positioning:** BioMate **complements** their AI platform. It adds a **research execution and learning layer** for faculty: it runs real scientific analyses and computations on the hospital's data, with drug development as its deepest capability. It is not a clinical chatbot and does not replace their DeepSeek assistant. BioMate can use the open models they already run.

---

## 3. BioMate in brief

**30-second pitch:**

> General AI assistants can talk about science. BioMate *does* the science. A researcher describes the goal in plain language; BioMate selects an established method, runs the actual analysis or computation on their data, checks the data and the result, and records exactly what was done. It covers everyday research data — sequencing, single-cell, proteomics, flow cytometry, imaging, clinical cohorts — and goes all the way to drug design. When the lab produces new results, BioMate can learn from them with a new, separately tested model version. The hospital keeps control of its data and models.

Platform facts you can quote:

- **More than 4,000 indexed scientific workflows and more than 12,000 tool records** across about 36 biomedical domains. About **1,100 workflows have recorded real-execution validation**.
- **On-premises deployment:** installed inside the hospital, running on its own servers and compute.
- **Model-agnostic:** works with multiple AI models, including open-weight models such as DeepSeek and Qwen.
- **Full provenance:** every result records its input files, parameters, method, model version and run.
- **One research workspace:** projects, files, analyses, models and reports stay together, so researchers and reviewers can hand work over and reproduce it.

---

## 4. Core abilities

These six abilities apply across everything BioMate does.

| Ability | What it means for a researcher | What it means for the information center |
| --- | --- | --- |
| **1. Scientific method selection** | Ask in plain language; BioMate selects an appropriate established method and parameters and explains why. | Standardized, documented methods instead of ad-hoc scripts. |
| **2. Real execution** | Analyses, pipelines and computations actually run and produce result files. | Computation runs on governed infrastructure, with results stored in the project. |
| **3. Data validation** | Units are normalized, impossible values are rejected, and identity conflicts are detected and explained. | Cleaner institutional data and fewer silent errors. |
| **4. Learning from experiments** | New lab results update prediction models and change the next experiment proposal. | Each experiment becomes a reusable institutional asset. |
| **5. Governed model adaptation** | A model trained on hospital data gets its own version, is compared with the previous version on untouched data, and is accepted or rejected. | Hospital-owned models with version history, evaluation records and rollback. |
| **6. Provenance and collaboration** | Every value is traceable, measured and predicted results stay separated, and reviewers can reproduce results. | Audit trail, access control and reproducibility. |

---

## 5. Four function modules

The BioMate home page asks *"What are you trying to do?"* and offers four modules. This is the simplest way to explain the platform to a non-specialist. The examples are actual example tasks shown in the product.

### 5.1 Search & evidence

**A cited answer over literature, databases and patents.**

| Track | Example tasks |
| --- | --- |
| Literature | "What is the evidence linking this target to disease?" · "Why do inhibitors of this target usually fail on selectivity?" |
| Databases | "Pull every reported structure for this target." · "Which trials targeted this pathway, and what were their endpoints?" |
| Patents | "Who holds composition-of-matter claims on this scaffold?" · "Are my generated candidates inside anyone's claims?" |
| Internal records | "Which datasets and sample groups are available in this project?" · Searching the team's own previous analyses and conclusions |

### 5.2 Data analysis

**Work on your own data, or try a prepared sample dataset.**

| Track | Example tasks |
| --- | --- |
| Ad-hoc compute | "Summarise this assay table and plot potency against logP." · "Reshape this plate readout into long format and save it." |
| Validated workflows | Ready-made analyses by domain (section 6), for example: |
| — Transcriptomics | Differential expression with pathway enrichment · single-cell clustering and cell-type annotation · multi-omics integration |
| — Genomics | Variant calling with clinically relevant variants flagged · variant burden between responders and non-responders · contamination and relatedness checks |
| — Functional genomics | CRISPR screen hit calling, cross-condition comparison and QC |
| — Structural biology | Cryo-EM processing to a density map · structure prediction with confidence · model-versus-map comparison |
| — Proteomics | Differential protein abundance · proteome–transcriptome reconciliation · batch quality assessment |
| — Clinical | Cohort stratification and endpoint testing · biomarker panels and risk-prediction models · analysis sections for submissions |
| — Drug discovery | ADMET screening · docking a series against a target · explaining why a hit series fails on a property |
| Sample data | Ready examples, e.g. flow-cytometry immunophenotyping, ELISA antibody titers, histology nuclei segmentation, ChIP-seq and ATAC-seq, proteomics QC, metabolomics, survival analysis, CAR-T construct design |

### 5.3 Molecule design & generate

**Propose candidates — molecules, peptides, proteins — then optimise and rank them.** Each track has examples for all three drug types.

| Track | Small molecule | Peptide | Protein / antibody |
| --- | --- | --- | --- |
| Generate | Generate candidates with drug-like properties; scaffold-hop; grow a fragment | Design cyclic peptides against a binding site; stapled-peptide analogues; permeable macrocycles | Design nanobodies against an epitope; graft CDRs onto a human framework; redesign an enzyme pocket |
| Predict & filter | Predict binding; dock and check poses; relative binding free energy | Predict binding and serum stability; permeability; aggregation risk | Predict developability liabilities; flag expression and stability risks |
| Optimise | Potency without losing solubility; keep hERG safe; fix metabolic liabilities | Improve serum stability; balance potency and solubility | Improve developability; humanise while keeping affinity; raise thermostability |
| Rank | Rank by developability; which pass every safety gate; triage into make-now and park | Rank on affinity, stability and permeability together | Rank on developability and expression risk |

### 5.4 Models

**Train, adapt or optimise a model on your data.**

| Track | Example tasks |
| --- | --- |
| Train | "Train a potency predictor on our in-house assay data." · "Train a solubility model from our historical plate data." · "Train an hERG classifier and gate the design loop on it." |
| Adapt | "Fine-tune this property predictor on our measured compounds." · "Adapt the generative model to our chemical series." |
| Optimise | "Run the design–make–test loop under a 96-assay budget." · "Propose the next round and refit on the results." |

---

## 6. Research support across instruments and data types

Beyond drug development, BioMate supports the everyday research of faculty teams. It has validated workflows for the data produced by common laboratory instruments and platforms. A research group brings the files its instrument produces; BioMate runs the appropriate analysis, quality control and statistics, and produces figures and a methods description.

| Instrument / platform | Data | What BioMate does | Example research use at a cancer hospital |
| --- | --- | --- | --- |
| **NGS sequencers** | Raw sequencing reads | Demultiplexing; RNA-seq; whole-exome/genome and tumor–normal somatic variant calling; copy number; ChIP-seq, ATAC-seq; DNA methylation; small RNA; immune repertoire (TCR/BCR) | Tumor mutation profiles, expression subtypes, epigenetic regulation |
| **Single-cell and spatial platforms** (e.g. 10x Chromium, Visium, MERFISH) | Single-cell matrices, spatial data | QC, clustering, cell-type annotation, markers, spatial domains and cell-neighbourhood analysis, deconvolution | Tumor microenvironment and immune cell maps |
| **Flow and mass cytometry** (FACS, CyTOF, imaging mass cytometry) | FCS files, CyTOF data, IMC images | Gating, immunophenotyping, subset quantification, QC | Immune monitoring in immunotherapy studies |
| **Mass spectrometry** | Proteomics (label-free, DIA), metabolomics, lipidomics | Protein quantification, differential abundance, chemoproteomics pull-down, LC-MS peak picking and metabolite analysis | Tumor proteomes, serum metabolic biomarkers, drug target engagement |
| **NMR** | NMR spectra | Untargeted NMR metabolomics | Metabolic profiling |
| **qPCR and digital PCR** | Cq values, droplet data | ΔΔCq normalization, relative quantification, droplet classification | Gene-expression validation; mutation quantification |
| **Plate readers, ELISA, screening** | Plate readouts, ODs, standard curves | Standard curves and titers, plate QC and hit calling, dose–response curve fitting | Serology (e.g. EBV antibody titers, relevant to NPC), drug sensitivity screens |
| **Microscopy and cell imaging** | Images | Cell Painting profiling, cell-cycle phase quantification, calcium imaging, nuclei segmentation | Phenotypic drug screening, cell biology studies |
| **Digital pathology scanners** | Whole-slide images (H&E, IHC) | Nuclei segmentation and tissue quantification | Quantitative tissue phenotypes linked to molecular data |
| **Cryo-EM / cryo-ET** | Micrographs, tomograms | Single-particle reconstruction, conformational heterogeneity, tomography, model-versus-map checks | Structures of tumor targets and complexes |
| **Western blot and gels** | Blot images | Band quantification | Protein expression validation |
| **Biophysics** (e.g. ITC) | Binding measurements | Binding thermodynamics | Confirming candidate binding |
| **Arrays** (methylation, NanoString, microarray) | Array data | Normalization and differential analysis | Methylation and expression signatures |
| **Clinical and cohort data** | Cohort tables, follow-up | Survival analysis (Kaplan–Meier, Cox), responder stratification, biomarker panels, risk models | Prognostic and predictive biomarker research |

Researchers also get:

- **Evidence with citations:** literature, database and patent questions answered with sources (section 5.1).
- **Reproducible outputs:** reports, figures and methods sections from verified results, for manuscripts, grants and submissions.
- **Reuse across teams:** a workflow set up for one group's instrument data becomes a standard method for the next group.

For the information center, this means one governed platform serving many departments' instruments and data types, instead of scattered scripts and desktop software.

---

## 7. Drug-development support

Drug development is BioMate's deepest capability. For SYSUCC, present it in the order that matches their actual role (section 2).

### 7.1 Where BioMate fits SYSUCC's drug development

| SYSUCC activity | How BioMate helps |
| --- | --- |
| **Early-phase (Phase I) trials** | Dose-escalation design and simulation (e.g. BOIN), pharmacokinetic and PBPK modelling, exposure–response and dose-optimization analysis |
| **Investigator-initiated trials and biomarker sub-studies** | Validated analysis of trial biomarker data (RNA-seq, single-cell, spatial, ctDNA and variants), survival and responder analyses, reproducible reports |
| **Their own discoveries (EBV, cell therapy), the "IIT-IND dual track"** | Target and protein structure work (structure prediction, cryo-EM), antibody design and developability, a first-in-human dose check for biologics, source-linked evidence packages for development |
| **Organoid and drug-sensitivity testing** | Dose–response fitting, plate QC, drug-combination synergy, and learning from each new batch of results |
| **T-cell and immune research** | Immune-repertoire analysis, tumor-reactive T-cell identification from single-cell data, HLA typing and epitope prediction |
| **Early discovery for new targets** | Candidate design and evaluation for small molecules, peptides or antibodies, when their teams want to start a new program |

### 7.2 Abilities by stage

| Stage | What BioMate does | Example output |
| --- | --- | --- |
| **Target identification** | Combines public disease–target evidence with the hospital's own tumor data (mutations, expression, single-cell, spatial). Shows supporting and conflicting evidence, with adjustable criteria. | A transparent target shortlist with reasons and sources. |
| **Drug-type selection** | Compares whether a target suits a small molecule, a peptide or a protein/antibody, based on target location, binding surface and tissue context. | A justified choice of drug type. |
| **Candidate design** | Generates candidates for the chosen drug type (section 5.3): small molecules, linear or cyclic peptides, antibodies and other proteins. | Candidate sets with explicit chemistry or sequence. |
| **Evaluation and ranking** | Docking, structure prediction, binding estimation, ADMET and toxicity, developability, comparison against a known reference drug. | A ranked candidate table with the evidence behind each score. |
| **Experimental learning loop** | Imports new lab results, validates units and identities, updates the model and proposes the next, diverse batch of experiments. | A next-round proposal that responds to real data. |
| **Model adaptation on hospital data** | Trains a new model version on authorized hospital assay data, evaluates it on a fixed holdout, compares it with the previous version and promotes it only with reviewer approval. | A model version card with before/after metrics. |
| **Pharmacology (PK/PD)** | Standard non-compartmental PK analysis, population PK, exposure–response, PBPK and tumor-growth-inhibition analyses. | Half-life, exposure and dose–response summaries. |
| **Safety and translational evidence** | Extracts measured findings from study reports with species, units and sources. Keeps measured and predicted values separate and lists evidence gaps. | A source-linked evidence package for reviewers. |
| **Clinical research support** | Biomarker–treatment interaction analysis, cohort feasibility questions, exposure–response research. | Reproducible research analyses for investigators (research use only). |

### 7.3 Three kinds of "learning"

The Director will understand this distinction and appreciate it:

1. **Predictor retraining:** a property or potency prediction model is retrained on the hospital's assay data. This is a real new model version and the clearest example of "learning from hospital data."
2. **Generator adaptation:** a molecule or peptide generator receives real training updates, producing new model checkpoints with evaluation records.
3. **Knowledge adaptation:** SOPs, protocols and expert corrections become a knowledge base and rules used when answering. This is valuable institutional customization, and we describe it as a knowledge base, not as model training.

---

## 8. How hospital data fit in

### 8.1 A general platform first, with their data as the entry point

Do not pitch BioMate only through datasets we think SYSUCC has. That is too narrow, and it can sound presumptuous. BioMate is a **general research platform** (sections 5–7). Whatever data a research team produces — from a sequencer, a cytometer, a mass spectrometer, a microscope, a plate reader or a clinical cohort — is an entry point into these modules. Use the hospital's published strengths (NPC, immuno-oncology, colorectal cancer, single-cell and spatial biology, pathology, biomarkers) only as conversation examples, and let the hospital tell us which data and teams matter.

### 8.2 What the hospital gets from using its own data on the platform

General AI models learn from public data. The hospital has something the public internet does not: **data from its own patients, samples and experiments.** On BioMate, these data produce six kinds of reusable hospital assets, all of which can remain **private to the hospital**:

1. **Research results:** analyses, figures and methods for papers and grants, produced faster and reproducibly.
2. **Standardized institutional methods:** workflows for each instrument and data type, reusable across departments.
3. **Hospital-specific evidence:** which targets, biomarkers and cell states matter in *their* patient populations.
4. **Experimental training labels:** measured activity, safety and response, *including failures*.
5. **Adapted models:** prediction and design models tuned on their own data, with version history.
6. **Institutional know-how:** SOPs, protocols, analysis templates and expert corrections, captured as a knowledge base and reusable workflows.

Using the platform with hospital data does **not** mean the data go into a global BioMate model. Rights to datasets, models and results are defined in the collaboration agreement.

### 8.3 How their data types map to BioMate modules

| Hospital data type (examples) | Typical source | BioMate modules | Example outcome |
| --- | --- | --- | --- |
| Sequencing: DNA, RNA, epigenome, immune repertoire | Core facility sequencers | Data analysis → validated workflows | Mutation profiles, expression subtypes, immune repertoires |
| Single-cell and spatial | 10x, spatial platforms | Data analysis; Search & evidence | Tumor microenvironment maps, cell-specific targets |
| Proteomics and metabolomics | Mass spectrometry, NMR | Data analysis | Protein and metabolic biomarkers |
| Immune monitoring | Flow and mass cytometry | Data analysis | Immune-subset changes during immunotherapy |
| Pathology and imaging | Slide scanners, microscopes | Data analysis | Quantified tissue and cell phenotypes |
| Serology and lab assays | ELISA, plate readers, qPCR | Data analysis; Models | Titers, dose–response curves, validated measurements |
| Drug-response experiments | Organoids, cell lines, PDX | Models; Molecule design | Updated prediction models and next-experiment proposals |
| Clinical cohorts and trials | Research databases, trial data | Data analysis (clinical) | Survival, responder and biomarker analyses |
| Protocols, SOPs, prior reports | Departments, research office | Search & evidence (internal records) | A searchable institutional knowledge base |

### 8.4 Example use cases across research and drug development

| # | Area | Use case | What they get |
| --- | --- | --- | --- |
| 1 | Everyday research | **Standard omics analysis** for a faculty group's sequencing or single-cell data | Reproducible results, figures and methods text for a paper |
| 2 | Everyday research | **Immune monitoring** from flow-cytometry data in an immunotherapy study | Standardized gating and immune-subset statistics |
| 3 | Everyday research | **Biomarker discovery** from proteomics, metabolomics or serology | Candidate biomarker panels with validation statistics |
| 4 | Everyday research | **Pathology quantification** from whole-slide images | Quantitative tissue features linked to molecular and clinical data |
| 5 | Everyday research | **Clinical cohort analysis**: survival, response stratification, risk models | Investigator-ready analyses |
| 6 | Target discovery | **Target prioritization** from tumor omics plus public evidence | A transparent, cohort-specific target shortlist |
| 7 | Target discovery | **Tumor microenvironment targets** from single-cell and spatial data | Targets on the right cells; immune mechanisms |
| 8 | Drug design | **Candidate design** for a chosen target: small molecule, peptide or antibody | Ranked candidates for their lab to test |
| 9 | Drug design | **Drug repurposing** from tumor signatures and drug-response data | Testable repurposing hypotheses |
| 10 | Experimental learning | **Learning from dose–response experiments** in organoids or cells | An updated prediction model and the next experiments |
| 11 | Translational | **PK/PD and safety evidence** from preclinical studies | Pharmacology summaries and source-linked evidence packages |
| 12 | Institutional | **Private model adaptation and knowledge workspace** | Versioned hospital models and a searchable institutional knowledge base |

### 8.5 If they ask where to start

Two natural starting points; let their priorities decide:

- **Broad adoption:** a few faculty groups use the Data analysis module on their own instrument data. This shows value quickly across departments.
- **Deep capability:** one drug-response program, such as organoid or cell assays with concentrations, controls, replicates and failures. This shows most clearly how their data become a better institutional model and a better next experiment.

---

## 9. Introducing BioMate in the meeting (about 10 minutes, no demo)

### 9.1 Suggested flow

| Minutes | Topic | Key message |
| --- | --- | --- |
| 2 | Who we are and the one-sentence message (section 3) | 院内数据驱动、可持续学习的肿瘤科研与药物研发平台 |
| 3 | The four modules (section 5), with one or two examples each | One platform for search, analysis, design and models. |
| 2 | One example story from section 9.2 | BioMate *does* the science and learns from experiments. |
| 3 | Fit with the hospital: on-premises, their DeepSeek and compute, hospital-owned data and models, many teams on one platform | It complements their AI platform; it does not replace it. |

Then move to the questions in section 11.1.

### 9.2 Two example stories (tell them; no screen needed)

**Everyday research:**

> A faculty group finishes a single-cell sequencing study of tumor samples. Instead of waiting weeks for a bioinformatician, a researcher asks BioMate to run quality control, identify cell types and compare treatment responders with non-responders. BioMate runs a validated workflow, checks the data, and returns results, figures and a methods paragraph for the paper. Every step is recorded, and the same workflow is reused by the next group.

**Drug development:**

> A team studying a tumor type asks which targets look most promising. BioMate combines their tumor data with public evidence and returns a shortlist with reasons and sources. For the chosen target it designs and evaluates candidates — a small molecule, a peptide or an antibody, whichever suits the target. The lab tests the best candidates in organoids. BioMate imports the results, checks them, trains a new version of its prediction model, tests it against the old one on data neither has seen, adopts it only if it is better, and proposes the next experiments. The data and the models stay in the hospital.

### 9.3 If they ask to see it

Offer a **follow-up session with their research faculty**, with a live walkthrough tailored to a research area they choose. That follow-up is also the natural place to discuss a specific collaboration.

---

## 10. Why BioMate, and not only DeepSeek, ChatGPT or Claude?

The Director already runs DeepSeek. Expect the question: *"Why can't our DeepSeek do this?"*

**Short answer:** DeepSeek, GPT and Claude are excellent *reasoning engines*. BioMate is the *scientific workbench around the engine*: established methods, real computation, data validation, learning from experiments and an audit trail. BioMate can use the hospital's DeepSeek as its model, so it adds to their existing investment instead of competing with it.

| What the hospital needs | General LLM on its own | BioMate |
| --- | --- | --- |
| Running real analyses on instrument data (sequencing, cytometry, mass spec, images) | Can explain methods or write one-off code; does not run validated pipelines | 4,000+ indexed workflows that run on hospital compute |
| Correct numbers from data (PK, potency, unit conversion) | Calculates in text or writes one-off code; results can vary between runs | Runs the established scientific method; the same input gives the same output |
| Catching bad data (impossible values, wrong units, duplicate IDs) | Inconsistent | Built-in validation that rejects bad data and explains why |
| Keeping predicted and measured results separate, with correct species and source | Can blur them in summaries | Explicit provenance labels on every value |
| Learning from new experiments | Does not retrain; each chat starts over | Versioned model updates, tested on untouched data, with accept/reject |
| Reproducibility and audit | Chat history only | Inputs, parameters, method, model version and run record |
| Institutional memory | Per-user conversations | Shared projects, versioned models and reusable workflows |

We are running a side-by-side comparison on precisely scored research tasks with leading open-weight models (DeepSeek, Qwen, GLM, Kimi). Engineering will share the measured results and caveats. Quote only numbers from that report.

**How to say it respectfully:** "Your DeepSeek platform is a strong foundation. BioMate adds the research execution and learning layer on top of models like it."

---

## 11. Conversation guide

### 11.1 Questions to ask the Director

**Research priorities and expectations**

1. Which departments and research teams would benefit most from a research platform? Which disease areas are priorities, for example NPC, colorectal cancer or immunotherapy?
2. What do they expect from a platform like this? What has their current AI platform not yet solved for researchers?
3. Which kinds of research data are most common across the hospital: sequencing, single-cell, proteomics, cytometry, imaging, pathology, clinical cohorts?
4. How do research teams analyze data today: core facilities, in-house bioinformaticians, outsourced services or their own scripts?
5. Is there drug-research activity with **measured lab results**, such as organoid or cell drug-response assays, including failures? *This is the most valuable input for experimental learning.*
6. How does the hospital measure success for AI projects: publications, research throughput, platform adoption or grant support?

**Drug development** (adapt to how much the Director knows; these may be better for a follow-up with the research office or Phase I team)

7. For the "IIT-IND dual track", which kinds of support would help most: trial design, biomarker analysis, data management or development evidence for their own assets?
8. In early-phase trials and IITs, where are the bottlenecks today: protocol design, statistics, biomarker analysis or data management? Which tools do teams use for dose escalation and PK modelling?
9. Can biomarker data generated in industry-sponsored trials be reused by the hospital for its own research, and under what governance?
10. Which teams lead the hospital's own drug discoveries (e.g. EBV vaccines and antibodies, cell therapy)? Would they be interested in a follow-up conversation?

**Infrastructure, security and compliance**

11. What does the current AI platform look like (DeepSeek deployment, GPU/HPC), and how should a new capability connect to it?
12. What are the hospital's data-security and compliance requirements for an on-premises research platform, for example network zones, security classification, account and audit rules, and rules on genomic data?

**External network and database access.** Ask about this explicitly; it affects what the platform can do on day one.

13. Will the on-premises platform have **internet access for external information search**, such as literature search (PubMed and similar) and web search?
14. Will it be able to query **external scientific databases**? Examples: protein structures (PDB, AlphaFold DB), proteins and genes (UniProt, Ensembl), compounds and bioactivity (ChEMBL, PubChem), target–disease evidence (Open Targets), clinical trials (ClinicalTrials.gov) and drug labels.
15. If direct access is restricted, which option fits their rules?
    - a controlled outbound gateway or proxy that allows only approved addresses;
    - local mirrors of selected public databases, updated periodically;
    - fully offline operation with a pre-installed knowledge base.
16. Do the same rules apply to model inference? Will all models run locally (e.g. their DeepSeek), or may non-patient queries use external model services?
17. Can software updates and container images be delivered from outside, or must every update be transferred manually and reviewed?

Why it matters, so BD can explain it simply: BioMate's own workflows, tools, built-in knowledge base and locally deployed models work inside the hospital network. External access adds **up-to-date** literature and public-database lookups. Without it, the same capabilities can use local mirrors that are refreshed on a schedule. In every option, outbound requests would contain only public-information queries, such as a gene name or a compound identifier, not patient data. The hospital decides which option is used.

**Next steps**

18. Which faculty teams should we talk to next?

### 11.2 Likely questions and suggested answers

| They ask | Suggested answer |
| --- | --- |
| "Does our data leave the hospital?" | "BioMate is deployed on-premises, so your data and models stay on your infrastructure. We would like to understand your security and compliance requirements and configure external access (literature search, public databases) to match your rules. We will provide a data-flow diagram for your review." |
| "Does it need internet access?" | "Its core workflows, tools, knowledge base and local models run inside your network. Internet or database access adds up-to-date literature and public-database lookups; if that isn't allowed, we can use local mirrors refreshed on a schedule. Which would fit your rules?" |
| "Can it run on our DeepSeek and our GPUs?" | "Yes, BioMate is model-agnostic and supports open-weight models. Connecting to your deployment and compute is part of the setup we would plan together." |
| "Who in the hospital would use it?" | "Any research team with data to analyze: sequencing, single-cell, proteomics, cytometry, imaging, pathology or clinical cohorts. Drug-research teams can also use its design and model-training modules." |
| "Will our data train your models for other customers?" | "Not by default. Hospital data and models trained on them remain hospital assets. Rights are written into the agreement." |
| "How accurate is it?" | "Analyses use established, validated methods. For models trained on your data, we measure accuracy on your own held-out data before and after every update, and a model is adopted only when it meets criteria we agree with you." |
| "Can it discover a new drug?" | "It accelerates and documents the research cycle: target choice, candidate design, evaluation and learning from experiments. Laboratory and clinical validation remain essential; BioMate makes each cycle faster and better informed." |
| "Can doctors use it for treatment decisions?" | "No. BioMate is a research platform, not a clinical decision system." |
| "How is this different from a generic AI platform?" | Section 10: validated scientific workflows, real computation, data validation, learning from experiments and provenance. |
| "What would you need from us?" | "To begin, an understanding of your research priorities and requirements, and an introduction to one or two research teams. Data access comes later, starting from a data catalogue and sample schema rather than a bulk export." |

### 11.3 Next steps to aim for

The first meeting succeeds if we leave with:

- **A clear picture of their expectations:** research priorities, deployment and compliance requirements, network and database access rules, and how they measure success.
- **An introduction to one or two research teams** for a follow-up session with a live walkthrough.
- **A contact on the information-center side** for technical questions about on-premises deployment.
- **An agreed follow-up date.**

A specific collaboration or pilot comes later: one research program, one permitted dataset, a scientific owner and an IT owner, success criteria and a timeline. Mention it only if they raise it.

### 11.4 After the meeting: record what aligned

This document deliberately covers a broad scope. The hospital's feedback decides which parts we develop next. Fill this in right after the meeting.

| Area | Their interest (high / some / none / not discussed) | What they said | Existing tools or providers they mentioned | Follow-up / who to meet |
| --- | --- | --- | --- | --- |
| Research data analysis across instruments (section 6) | | | | |
| Search & evidence / institutional knowledge base | | | | |
| Phase I and IIT support (trial design, PK, biomarker analysis) | | | | |
| Their own discoveries (EBV, cell therapy), "IIT-IND dual track" | | | | |
| Organoid and drug-response learning loop | | | | |
| Molecule design (small molecule, peptide, antibody) | | | | |
| Model training on hospital data | | | | |
| Deployment, security and network access requirements | | | | |
| Other needs they raised that we did not cover | | | | |

---

## 12. Wording guide

Precise wording earns trust with a technical IT audience.

| Avoid | Say instead |
| --- | --- |
| Making promises about their compliance rules before hearing them. | "BioMate is deployed on-premises. What security and compliance requirements should we design for?" |
| "Thousands of validated workflows." | "More than 4,000 indexed workflows; about 1,100 with recorded real-execution validation." |
| "The docking score proves the drug binds." | "Docking is a computational prediction that prioritizes candidates for lab testing." |
| "The model will definitely improve with your data." | "We measure improvement on your untouched data, and updates that don't improve are not adopted." |
| "We fine-tune the AI with your documents." | "Your SOPs become a knowledge base." Use "we train a new model version" only for real model training on assay data. |
| "Our designed candidates are validated drugs." | "Research-stage candidates; binding and efficacy are confirmed experimentally." |
| "We beat GPT, Claude and DeepSeek." | "On these specific tested tasks, BioMate produced these results," quoting the comparison report. |
| "Clinical decision support" or "treatment recommendations." | "Research use." |
| "We will help you discover first-in-class drugs." | "We support your clinical and translational research, and help turn your own discoveries into development-ready evidence." |
| Naming SYSUCC datasets as if we already have them. | "Published work suggests your teams work on X. Is that an area where they need analysis support?" |

---

## 13. One-page cheat sheet

**Who:** Director of the Information Center, SYSUCC. An IT and data leader who already runs a DeepSeek-based oncology assistant and is building an AI platform foundation.

**The hospital:** China's leading oncology clinical-trial center (NPC, immunotherapy, ADCs; 160+ Phase I projects; 2,000+ IITs in five years). Its own drug origination is early, focused on EBV vaccines and antibodies and on cell therapy. Its strategy is the "IIT-IND dual track", moving toward its own innovative drugs.

**Message:** 院内数据驱动、可持续学习的肿瘤科研与药物研发平台. An AI research platform for faculty: the hospital's own data become research results and capabilities that keep improving, with full traceability.

**Position:** a complement to their AI platform. BioMate is the research execution and learning layer; it is model-agnostic and works with open models.

**Four modules:** Search & evidence · Data analysis · Molecule design & generate · Models.

**Breadth:** validated workflows for sequencing, single-cell and spatial, proteomics and metabolomics, cytometry, imaging and pathology, lab assays, cryo-EM and clinical cohorts. Drug design for small molecules, peptides and proteins/antibodies.

**Three proof points:**

1. **It does the science:** established methods and real computation, not only text.
2. **It learns from experiments:** each new model version is tested on untouched data, then accepted or rejected.
3. **It is governed and on-premises:** deployed inside the hospital, with provenance, access control, version history and documented data flows.

**Ask about network access:** internet for literature and web search? External scientific databases? If not, a controlled gateway, local mirrors or fully offline?

**Meeting format:** first meeting, no demo. About 10 minutes of introduction, then listen.

**Leave with:** their expectations and requirements, an introduction to one or two research teams, an IT contact and a follow-up date.
