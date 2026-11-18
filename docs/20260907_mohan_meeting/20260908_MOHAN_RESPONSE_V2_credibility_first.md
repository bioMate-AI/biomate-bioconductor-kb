# BioMate AI — demonstrated capabilities, relevance to SLE, and a proposed feasibility study

**2026-09-08 · prepared for Dr. Chandra Mohan's review (via Andrew).**

This document responds directly to the request made at our meeting: evidence of relevant, credible prior work,
and a clear account of what has been demonstrated versus what remains to be validated. It is deliberately narrow.
It presents (1) peer-reviewed capabilities already demonstrated, (2) how those methods could transfer to SLE and
lupus nephritis — stated honestly as a hypothesis, not a claim, (3) a clean separation of proven work from
in-development programs, and (4) a single, low-risk, four-to-six-week feasibility study on already-published data
that would let both parties evaluate BioMate's added value before any larger commitment. It intentionally does not
propose new laboratory work, sample exchange, costs, or intellectual-property terms at this stage.

---

## 1 · Demonstrated, peer-reviewed capabilities (the evidence)

The following peer-reviewed work — with Dr. Yaoyun Zhang (Founder & CEO, BioMate AI; former faculty, UTHealth
School of Biomedical Informatics) as corresponding or co-first author — establishes the core computational methods
relevant to this collaboration. Each entry notes the capability it demonstrates.

- **Generative therapeutic-molecule design.** *A Unified Conditional Diffusion Framework for Dual Protein
  Targets-Based Bioactive Molecule Generation* (peer-reviewed DiffDTM). **IEEE Transactions on Artificial
  Intelligence, 2024** — *Dr. Zhang, corresponding author* ([IEEE Xplore 10497533](https://ieeexplore.ieee.org/document/10497533/);
  preprint [arXiv:2306.13957](https://arxiv.org/abs/2306.13957)). *Demonstrates:* de-novo design of bioactive
  molecules against defined protein targets — the "validated target → candidate molecule" capability.

- **Multi-modal patient subtyping with genetics-anchored (Mendelian-randomization) causal analysis.**
  *Identifying underlying patterns in Alzheimer's disease trajectory: a deep-learning approach and
  Mendelian-randomization analysis.* **eClinicalMedicine (The Lancet Discovery Science), vol. 64, 2023** —
  *Dr. Zhang, corresponding author* ([PMID 37811490](https://pubmed.ncbi.nlm.nih.gov/37811490/);
  [DOI 10.1016/j.eclinm.2023.102247](https://doi.org/10.1016/j.eclinm.2023.102247)). *Demonstrates:* discovery of
  disease subtypes / trajectories from multi-modal data, coupled with genetic (MR) evidence for causal drivers — a
  Lancet-family, peer-reviewed record of exactly the stratification-plus-genetics methodology relevant here.

- **Biomarker-panel discovery for differential diagnosis.** *Optimizing multi-domain hematologic biomarkers and
  clinical features for the differential diagnosis of unipolar vs. bipolar depression.* **npj Mental Health
  Research, 2023** — *Dr. Zhang, co-first author* ([PMID 38609642](https://pubmed.ncbi.nlm.nih.gov/38609642/)).
  *Demonstrates:* machine-learning optimization of a blood-biomarker panel to separate clinically similar groups —
  directly analogous to autoantibody / proteomic biomarker panels for disease activity or subgroup.

- **Interpretable, cross-site reproducible clinical ML.** *Assisting schizophrenia diagnosis using clinical EEG and
  interpretable graph neural networks (real-world, cross-site).* **Neuropsychopharmacology, 2023** — *Dr. Zhang,
  corresponding author* ([PMID 37491671](https://pubmed.ncbi.nlm.nih.gov/37491671/)). *Demonstrates:* models that
  are interpretable and that hold up across independent sites — the reproducibility discipline that a feasibility
  study on the Mohan Lab's own cohort would put to the test.

*(Additional related peer-reviewed work — an Alzheimer's-progression prognosis model in* iScience *2024
([PMID 39040055](https://pubmed.ncbi.nlm.nih.gov/39040055/)) — and preprints in 3D molecular modeling
([arXiv:2302.00855](https://arxiv.org/abs/2302.00855)) and a large polysomnography model
([PMID 39711704](https://pubmed.ncbi.nlm.nih.gov/39711704/)) are available on request.)*

**What this record does and does not establish.** It establishes that the underlying *methods* — generative
molecular design, biomarker discovery, multi-modal subtyping, genetics-anchored causal analysis, and reproducible
cross-site modeling — are real, peer-reviewed, and reduced to practice. It does **not** claim these methods have
been applied to lupus or autoimmune disease; that application is the subject of Section 2 and the proposed study.

---

## 2 · Potential relevance to SLE and lupus nephritis (a hypothesis, not yet validated)

The methods above map naturally onto open problems in SLE/LN. Each mapping below is stated as a **hypothesis to be
tested**, not a demonstrated result in autoimmune disease:

| Demonstrated method | Candidate SLE / LN application (unvalidated) |
|---|---|
| Multi-modal subtyping + trajectory modeling | Molecular **endotyping** of lupus patients / prediction of disease-activity trajectory |
| Genetics-anchored (MR) causal analysis | Integrating lupus genetics (HLA / GWAS) with proteomic and autoantibody data to prioritize **causal** targets over passengers |
| Biomarker-panel discovery | Autoantibody / urine–serum **proteomic biomarker panels** for activity or treatment response |
| Generative molecular design | Designing candidate molecules against a **validated lupus target** |
| Interpretable, cross-site reproducible ML | Producing signatures that **transfer** across independent lupus cohorts rather than fitting one |

The honest position: none of these has yet been directly validated in SLE. Establishing whether they add measurable
value on the Mohan Lab's kind of data is precisely what the feasibility study in Section 4 is designed to determine.

---

## 3 · Proven vs. in-development vs. hypothesis

To keep the distinction explicit and avoid overstatement:

| Proven (peer-reviewed) | In development (current programs, not yet published/validated) | Hypothesis (to be tested with the Mohan Lab) |
|---|---|---|
| Generative molecule design; ML biomarker-panel discovery; multi-modal subtyping; genetics-anchored (MR) causal analysis; interpretable cross-site models | An immune-focused multi-omic foundation model; a cyclic-peptide (macrocycle) therapeutic-design capability | That these methods add measurable, reproducible value on SLE / LN cohorts specifically |

The two in-development programs are noted for completeness and longer-term context; they are **not** being offered
as finished capabilities, and they are **not** part of the proposed near-term study.

### The two in-development programs, in brief

**Immune foundation model.** This program is building a multi-omic model that integrates transcriptomic,
proteomic, and human-genetic evidence into a single, batch-invariant representation of immune biology — one from
which candidate targets can be prioritized (weighted toward human-genetic support, which raises the prior that a
target is a true driver) and patients stratified by mechanism or endotype rather than by disease activity alone.
Its defining discipline is reproducibility: candidates are ranked against matched negative controls and checked by
leave-cohort-out transfer, so a signal is only credited if it holds on cohorts it was not fit to. In its present
maturity the model is best understood as a rigorous, null-controlled *screen over measured perturbation and omics
data* — strongest where the underlying measurements are rich — rather than a finished predictor; extending it to
de-novo target prediction and, specifically, to SLE and lupus nephritis is active work. That extension is precisely
what the feasibility study in Section 4 is designed to begin testing, honestly and at low risk. *(In development;
not yet validated in autoimmune disease.)*

**Cyclic-peptide (macrocycle) therapeutic-design model.** This program is building a generative design capability
that turns a *validated* target into candidate cyclic-peptide molecules — a modality able to engage the
protein–protein interfaces and intracellular regulators that dominate immune biology yet resist both small
molecules (which cannot grip flat, extended surfaces) and antibodies (which act only outside the cell). The design
optimizes potency and selectivity jointly with **cell permeability and drug-like properties from the outset** — the
step at which most macrocycle programs fail — so that the output is a candidate built to be testable rather than one
that stalls late. It is intended as the computational front end of the target→molecule path: the step that, in the
Mohan Lab's own experience with the ALCAM/CD6 program, was carried out by an external partner. Any resulting design
is a starting point that would require standard wet-lab and in-vivo validation before it could be considered a
development candidate. *(In development; a design capability, not a validated therapeutic.)*

---

## 4 · A proposed feasibility study (one step, low-risk, published data only)

A single, tightly-scoped study to let Dr. Mohan evaluate BioMate's added value at essentially zero risk or cost.

- **Data:** one already-**published** Mohan Lab lupus-nephritis cohort with clinical annotations (e.g., a published
  urine/serum proteomic or autoantibody dataset), used strictly under the lab's terms. **No new samples, no
  laboratory work, no unpublished data.**
- **Duration:** four to six weeks.
- **Work:** (1) reproduce the published primary analysis to establish parity and reproducibility; (2) apply
  BioMate's stratification and biomarker methodology to test for additional structure — candidate endotypes or a
  signature evaluated explicitly for cross-cohort stability; (3) deliver an interpretable, fully documented pipeline.
- **Deliverable:** a concise technical report — methods, the reproducibility check, any added-value signal
  characterized honestly (**including a null result if that is the outcome**), and a clear go/no-go recommendation
  for anything larger.
- **Cost and commitment:** none beyond BioMate-borne compute. No lab cost, no sample transfer, no funding request,
  no intellectual-property transfer.
- **Success criterion:** a defensible, reproducible answer to "does this add value?" — the value of the study is a
  sound decision, not a guaranteed positive result.

This directly addresses the question raised at the meeting — whether BioMate's computational work can produce
reproducible results that add measurable value to the Mohan Lab's established expertise — in a form that commits
neither party to anything beyond a short, published-data exercise.

---

## 5 · Data, intellectual property, and next steps (kept deliberately light)

For the feasibility study, only **published** data is used, under Dr. Mohan's terms. No ownership split is proposed
at this stage, and none is needed for a published-data exercise.

Should the study warrant continuation, the appropriate protections would be built in stages **before any nonpublic
data or materials change hands** — a mutual NDA, a nonbinding collaboration term sheet, a Data Use Agreement, a
Material Transfer Agreement if samples are ever exchanged, and ultimately a research or sponsored-research
agreement. These would distinguish each party's **background IP** from **project-generated IP**, and would define
inventorship, ownership, publication rights, and commercialization rights, consistent with University of Houston
policy and any applicable funding terms. The intent is a transparent, staged, co-authored program — with terms
agreed at the outset of each stage rather than presumed in advance.

**Proposed next step:** Dr. Mohan's confirmation that the demonstrated work is credible and the direction is of
interest, and identification of a suitable published dataset for the four-to-six-week feasibility study.
