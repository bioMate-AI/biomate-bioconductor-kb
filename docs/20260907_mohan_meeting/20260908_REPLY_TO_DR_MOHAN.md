# Reply to Dr. Mohan — BioMate AI

**2026-09-08 · prepared for Dr. Mohan's review (via Andrew).**

Thank you for the discussion. In response to the request for evidence of relevant prior work — and to the question
on how targets are selected — this note sets out (1) demonstrated, peer-reviewed capabilities, (2) how those
methods could transfer to SLE (stated honestly as a hypothesis), (3) what is proven versus still in development,
(4) how target selection works across multiple evidence channels, and (5) a single low-risk feasibility study on
already-published data. It proposes no new laboratory work, sample exchange, cost, or IP terms at this stage.

## 1 · Demonstrated, peer-reviewed capabilities
With Dr. Yaoyun Zhang (Founder & CEO; former faculty, UTHealth SBMI) as corresponding or co-first author:
- **Generative therapeutic-molecule design** — *A Unified Conditional Diffusion Framework for Dual Protein
  Targets-Based Bioactive Molecule Generation* (DiffDTM). **IEEE Transactions on AI, 2024** *(corresponding
  author)* — de-novo design of molecules against defined targets.
- **Multi-modal subtyping + genetics-anchored (Mendelian-randomization) causal analysis** — *Identifying underlying
  patterns in Alzheimer's disease trajectory.* **eClinicalMedicine (The Lancet Discovery Science), 2023**
  *(corresponding author)* — disease subtypes/trajectories with genetic evidence for causal drivers.
- **Biomarker-panel discovery** — *Optimizing multi-domain hematologic biomarkers for unipolar vs. bipolar
  depression.* **npj Mental Health Research, 2023** *(co-first author)* — ML optimization of a blood-biomarker panel
  to separate clinically similar groups.
- **Interpretable, cross-site reproducible clinical ML** — *Assisting schizophrenia diagnosis using clinical EEG
  and interpretable graph neural networks.* **Neuropsychopharmacology, 2023** *(corresponding author)* — models
  that hold up across independent sites.

*(Additional related work — an Alzheimer's-progression prognosis model, iScience 2024; and preprints in 3D
molecular modeling and a large polysomnography model — available on request.)*

These establish that the underlying **methods** — molecular design, biomarker discovery, multi-modal subtyping,
genetics-anchored causal analysis, cross-site reproducibility — are real and reduced to practice. They have **not**
yet been applied to lupus; that is the subject of Sections 2 and 5.

## 2 · Potential relevance to SLE / lupus nephritis (a hypothesis, not yet validated)
| Demonstrated method | Candidate SLE / LN application (unvalidated) |
|---|---|
| Multi-modal subtyping + trajectory modeling | Molecular **endotyping** / disease-activity trajectory |
| Genetics-anchored (MR) causal analysis | Integrating lupus genetics (HLA/GWAS) with proteomic + autoantibody data to prioritize **causal** targets |
| Biomarker-panel discovery | Autoantibody / urine–serum **proteomic biomarker panels** for activity or response |
| Generative molecular design | Designing candidate molecules against a **validated lupus target** |
| Cross-site reproducible ML | Signatures that **transfer** across independent lupus cohorts |

None of these is yet directly validated in SLE — establishing whether they add measurable value on the Lab's data
is exactly what the feasibility study (Section 5) would determine.

## 3 · Proven vs. in-development
**Proven (peer-reviewed):** generative molecule design; biomarker-panel discovery; multi-modal subtyping;
genetics-anchored causal analysis; interpretable cross-site models.

**In development (current programs, not offered as finished, not part of the near-term study):**
- *Immune analysis system* — a system (an instruction-tuned foundation model with added knowledge and evidence
  channels) that integrates transcriptomic, proteomic, and human-genetic evidence to stratify patients by
  mechanism and to prioritize targets, with reproducibility built in (matched negative controls, leave-cohort-out
  transfer). In its present maturity it is a rigorous, null-controlled screen over measured data; extending it to
  SLE specifically is active work.
- *Cyclic-peptide (macrocycle) therapeutic design* — a generative capability that turns a validated target into
  candidate cyclic-peptide molecules, optimizing potency, selectivity, and cell permeability from the outset; the
  computational front end of the target→molecule step (the step handed to an external partner in the ALCAM/CD6 →
  itolizumab arc). Any design requires standard wet-lab and in-vivo validation before it is a development candidate.

## 4 · How targets are selected (in response to your question)
Target selection does not rely on a single channel such as pathway analysis. It integrates **several complementary
lines of evidence — anchored on human genetics** — under rigorous statistical controls, and returns an
**interpretable rationale for each nominated target** rather than a black-box score. The detailed methodology is
proprietary and can be shared under an appropriate confidentiality agreement.

## 5 · A proposed feasibility study (one step, low-risk, published data only)
- **Data:** one already-**published** Lab lupus-nephritis cohort with clinical annotations (e.g., a published
  urine/serum proteomic or autoantibody dataset), used under the Lab's terms. **No new samples, no lab work, no
  unpublished data.**
- **Duration:** four to six weeks.
- **Work:** reproduce the published primary analysis (parity/reproducibility), then apply the stratification and
  target-selection methodology — with the per-target evidence breakdown — to test for additional structure.
- **Deliverable:** a concise technical report, with any added-value signal characterized honestly (**including a
  null result if that is the outcome**) and a clear go/no-go recommendation.
- **Cost & commitment:** none beyond BioMate-borne compute; no lab cost, sample transfer, funding request, or IP
  transfer.

## 6 · Data, intellectual property, and next steps
For this study, only **published** data is used, under the Lab's terms; no ownership split is proposed at this
stage. Should it warrant continuation, protections would be built in stages **before any nonpublic data or
materials move** — mutual NDA, a nonbinding term sheet, a Data Use Agreement, an MTA if samples are exchanged, and
ultimately a research/sponsored-research agreement — distinguishing background from project-generated IP, consistent
with University of Houston policy and any funding terms.

**Proposed next step:** your confirmation that the demonstrated work is credible and the direction is of interest,
and identification of a suitable published dataset for the feasibility study.
