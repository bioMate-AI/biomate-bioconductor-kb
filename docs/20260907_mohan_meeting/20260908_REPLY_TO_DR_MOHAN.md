# Reply to Dr. Mohan — BioMate AI

**Prepared for Dr. Mohan's review (via Andrew) · September 2026**

Thank you for the discussion. This note responds to your request for evidence of relevant prior work and your question on target selection, and sketches how a collaboration could unfold. It proposes no new laboratory work, cost, or IP terms at this stage; any data the Lab shares would be existing published or on-request cohort data, under the Lab's terms and any required Data Use Agreement.

---

## 1 · Demonstrated methods and their potential SLE relevance

Peer-reviewed work with Dr. Yaoyun Zhang (Founder & CEO; former faculty, UTHealth SBMI) as corresponding or co-first author. These establish the **methods** — the team's academic record. They do **not** by themselves validate BioMate's platform in SLE, nor establish experimental or commercial validation; the candidate SLE applications are stated as hypotheses, and testing them is the subject of the pilot (Section 4).

| Method (peer-reviewed) | Journal (year), role | Candidate SLE / LN application — *hypothesis* |
|---|---|---|
| Generative therapeutic-molecule design (DiffDTM) | IEEE Trans. AI (2024), corresponding | Candidate molecules against a **validated** lupus target |
| Multi-modal subtyping + genetics-anchored (Mendelian-randomization) causal analysis | eClinicalMedicine — Lancet Discovery Science (2023), corresponding | Molecular **endotyping**; prioritizing **causal** targets over passengers |
| Biomarker-panel discovery | npj Mental Health Research (2023), co-first | Autoantibody / urine–serum **biomarker panels** for activity or response |
| Interpretable, cross-site reproducible ML | Neuropsychopharmacology (2023), corresponding | Signatures that **transfer** across independent lupus cohorts |

*(Also available on request: an Alzheimer's-progression prognosis model, iScience 2024; preprints in 3D molecular modeling and a large polysomnography model.)*

**A note on domain and motivation.** These publications, though methodologically relevant, sit mainly in the **mental-health and clinical-neuroscience** domain — they establish the methods, not lupus-specific experience. My move into immunology is deliberate and personal: I live with chronic autoimmune disease myself, and building rigorous, reproducible tools for this field is a commitment I have a direct stake in.

---

## 2 · Proven vs. in-development

**Proven** (peer-reviewed on research datasets — not SLE platform validation): the four methods above.

**In development** (not offered as finished; not part of the pilot): an **immune analysis system** (an instruction-tuned foundation model with added knowledge and evidence channels — at present a rigorous, null-controlled screen over measured data), and a **cyclic-peptide (macrocycle) design** capability that turns a validated target into candidate molecules, optimizing potency, selectivity, and permeability from the outset — the computational front end of the target→molecule step (the step handled by an external partner in the ALCAM/CD6 → itolizumab arc). Any design still requires standard wet-lab and in-vivo validation.

---

## 3 · How targets are selected (your question)

Not a single channel such as pathway analysis. Several complementary lines of evidence — **anchored on human genetics** — each scored against its own matched negative control, with druggability as a final filter, returning an **interpretable per-target evidence breakdown** rather than a black-box score. Proteomic and autoantibody evidence — the Lab's data type — is one of the channels. The detailed methodology is proprietary and can be shared under confidentiality.

---

## 4 · A complementary pilot (low-risk, on the Lab's own data)

Scoped to **complement** the Lab's discovery and wet-lab program, not duplicate it. The Lab identifies markers and targets from patient cohorts; BioMate adds a reproducible computational layer on top — **causal target-confidence** (which markers are genetics-supported drivers vs. passengers) and **responder / mechanism stratification** (whether baseline profiles predict which of the ≥4 approved LN mechanisms — FcRn, BAFF/APRIL, type-I interferon, B-cell depletion — fits a patient): the "which therapy for which patient" gap.

- **Data — the Lab's own cohorts:** the pilot runs directly on the Lab's lupus-nephritis data — a published cohort plus patient-level data available on **reasonable request**. Using **two or more** of the Lab's cohorts lets us validate **cross-cohort** (leave-cohort-out), so a finding is representative rather than single-cohort-biased. (Generic public datasets we can already access on our own; the pilot's value is specifically in the Lab's data, which is what a collaboration uniquely enables.)
- **Work (4–6 weeks):** reproduce the Lab's published primary analysis (parity) → apply the confidence + stratification layer → test **cross-cohort transfer** across the Lab's cohorts.
- **Success = go / refine / stop**, pre-registered: a signal counts only if it is significant against a matched null **and** replicates across cohorts. A null result is a valid, reported outcome.
- **Cost:** BioMate-borne compute only; no lab cost or IP transfer.
- **Data-request process — a question for the Lab:** does a brief email to the corresponding author suffice, or is a data request form / Data Use Agreement / IRB determination needed? We will complete whatever the Lab and the University of Houston require.

---

## 5 · How the collaboration could unfold

Three stages, each gating the next — computational and low-commitment first, deepening only as value is shown:

1. **Your data — validate and deepen.** Establish BioMate's added value, reproducibly, on the Lab's **published** cohorts, then deepen on the Lab's patient-level data available **on request** — used throughout as **held-out validation**, not as material to train a platform on.
2. **New data — the Houston Omics Collaborative.** Where a gap is identified, generate new paired molecular data through the Houston Omics Collaborative (e.g., SOMAscan proteomic profiling) on purpose-built samples, to sharpen stratification and target confidence.
3. **The dry–wet loop — toward therapy.** For a validated target, BioMate designs candidate molecules (the drug-side complement); wet-lab and in-vivo results feed back to refine both the target model and the designs — an iterative **design–build–test–learn** cycle toward therapy development.

---

## 6 · Data and intellectual property

Only published and reasonable-request cohort data, under the Lab's terms and any required Data Use Agreement; no ownership split is proposed now. Should the work continue, staged protections (NDA, DUA, MTA if samples are exchanged, and a sponsored-research agreement distinguishing background from project-generated IP) would be put in place **before any nonpublic data or materials move**, consistent with University of Houston policy.

---

## 7 · Proposed next step

If this direction aligns with your interests, we would welcome a short Zoom between the Mohan Lab and BioMate teams to select the Lab cohorts for the pilot — including the process for sharing the on-request data — and to agree the feasibility question, baseline analysis, success criteria, and deliverable.
