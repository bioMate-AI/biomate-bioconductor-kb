# αvβ6-RLT program — translational validation (stage 3), pathology, and team/ACT decisions

**Date:** 2026-10-15 · Captures the strategy discussion for the ACT application: whether pathology is relevant
now, how/who/where to run the in-vivo/dosimetry/pathology validation ("stage 3"), and team-composition decisions
(pathologist vs nuclear-medicine/radiochemistry). Context: BioMate's ACT asset = **one prioritized cancer target,
integrin αvβ6, pursued as a targeted radioligand therapy (Lu-177; Ga-68 imaging companion)** for PDAC / cold-GI.

## 1. Is pathology relevant at this stage?
**Cite-now, do-later — not on the current critical path.**
- **Now (ACT translational evidence): cite, don't generate.** αvβ6 overexpression in PDAC / cold-GI is already
  well-documented by IHC in the literature, and the Ga-68-Trivehexin clinical work correlates PET uptake with
  αvβ6 IHC. Reference that existing evidence for the ACT "translational evidence" box — no new slides required.
- **Near-term lead work: not relevant.** Designing/synthesizing/validating the peptide binder is chemistry +
  structure (binding, selectivity, metal-coordination triage). Pathology gates none of it.
- **Later: becomes central** — (a) therapeutic-index/dosimetry (αvβ6 on some normal epithelia → on-target/
  off-tumor risk via normal-tissue IHC); (b) in-vivo validation (tumor-model histology + autoradiography↔IHC
  correlation). BioMate's own WSI/digital-pathology tooling applies at this stage (quantitative αvβ6 scoring).

## 2. Stage 3 — the in-vivo / dosimetry / pathology validation: how / who / where
**It is an ordered sequence; do the cheap front end first.**
1. **Radiolabeling + radiochem QC** — DOTA conjugation, Ga-68 (imaging) / Lu-177 (therapy) chelation, radiochemical
   purity + stability. Gate for everything else.
2. **In-vitro cell binding / internalization** — αvβ6-positive (e.g. BxPC-3 PDAC) vs αvβ6-negative lines; affinity,
   specificity, internalization. Cheapest real data; de-risks before any animal work.
3. **In-vivo biodistribution + PET/SPECT** — αvβ6+ tumor xenograft mice; tumor uptake, tumor-to-background, and
   **kidney uptake** (dose-limiting organ for peptides).
4. **Dosimetry + normal-tissue uptake** — therapeutic-index story.
5. **Pathology correlation** — tumor + normal-tissue αvβ6 IHC + **ex-vivo autoradiography** (signal co-locates with
   αvβ6+ tissue). The pathology step.
6. *(Later)* **Therapy study** — Lu-177 construct, tumor-growth inhibition.

**Who / where (Texas Medical Center first):**
- **Radiochem + small-animal imaging core (steps 1–4):** academic cores, not a self-built hot lab. **MD Anderson**
  (Cyclotron Radiochemistry Facility + Cancer Systems Imaging / Nuclear Medicine; deep radiotheranostic program),
  **UT Southwestern** (strong molecular-imaging + cyclotron + radiochemistry), **UTHealth Houston** (alumni network),
  **Baylor**. **MDA collaborators = the entry point.** Alternatively a **radiopharma CRO** (Invicro, Charles River,
  MI Bioresearch, Sofie/iThera-type) as a paid service for steps 1–4.
- **Pathology / IHC (step 5):** a pathology core (academic or CRO) + clinical collaborators (**MDA / SYSUCC**) for
  patient tumor tissue; BioMate WSI tooling for analysis.
- **Isotopes:** Ga-68 generator on-site; Lu-177 commercial (ITM, Novartis/AAA, SHINE) at the therapy step.

**Achievable ACT-phase slice (what to pitch as "validation during the program"):**
radiolabel (1) → in-vitro αvβ6+/– cell binding (2) → one in-vivo biodistribution/imaging run in an αvβ6+
xenograft (3), through a **TMC radiochem + small-animal imaging core (MDA the obvious fit)**, with clinical
collaborators lined up for the tissue/IHC correlation later. Cheap front end (weeks for labeling + cell binding);
first real in-vivo evidence; a specific, credible line for the ACT conversation.

## 3. Team decision — pathologist for the ACT application?
**No pathologist on the formal team for ACT.** Rationale:
- ACT rewards a **focused, defined asset**, not a broad roster. A tight team owning the near-term critical path
  (peptide chemistry, binding/selectivity, radiolabeling) is more credible than padding with not-yet-critical roles.
- Pathology is **not on the ACT-phase critical path** (that scope doesn't execute pathology work).
- Cover the pathology dimension **without a seat**: (a) cite existing αvβ6-in-PDAC IHC literature for target
  expression; (b) name pathology/patient-selection as a *later* step with a **collaborator to be engaged**
  (MDA/UTH/SYSUCC). A listed-but-idle team member reads as filler to reviewers.
- A pathologist remains genuinely additive (target expression, patient selection, autoradiography↔IHC, and it
  pairs with BioMate's digital-pathology strength) — bring one in as a **collaborator/advisor**, elevate toward
  a core role at the clinic/companion-diagnostic stage.

## 4. The near-term team gap — nuclear medicine / radiochemistry
**This is the more critical near-term add for a radioligand asset.** It splits into two sub-roles, usually found
together in one molecular-imaging program (so one well-placed collaborator can cover both):
1. **Radiochemist / radiopharmaceutical chemist** — DOTA conjugation, Lu-177/Ga-68 chelation, radiochemical QC
   (the near-term-critical skill).
2. **Nuclear-medicine physician / molecular-imaging scientist** — biodistribution, PET/SPECT, dosimetry, clinical path.

**Where (Texas-first, via your network):** MD Anderson (Cyclotron Radiochemistry + Cancer Systems Imaging /
Nuclear Medicine) — MDA collaborators are the entry point; UT Southwestern (molecular imaging + cyclotron);
UTHealth Houston / Baylor (alumni network); SYSUCC (nuclear medicine + Ga-68; confirm Lu-177 therapy capability).

**Engagement model:** **academic co-investigator / collaborator** via a core facility (sponsored-research or MTA),
*not* a hire — gives facility + expertise + grant-team credibility at ACT stage. A senior nuclear-medicine figure
as advisor/SAB adds weight.

**Honest cautions:**
- No specific named individual recommended here — fit depends on relationships/interest. The profile: a
  radiopharmaceutical chemist with peptide/chelator experience + a molecular-imaging PI with integrin/RGD-tracer
  experience. **The TMC network (warm intro via MDA collaborators) is the real asset.**
- The **Notni / TU Munich** group (Trivehexin developers) are the **patent holders / IP counterparty — not a recruit.**

**Practical next step:** one question to the MDA contact — *"who runs radiopharmaceutical chemistry / preclinical
theranostic imaging here, and would they co-investigate an αvβ6 Lu-177 program?"* A single warm intro likely covers
both sub-roles in one lab.

## Summary of decisions
- Pathology: **cite literature now, collaborator (not team seat) for the forward plan.**
- Stage 3: **academic radiochem + small-animal imaging core (MDA-first), cheap front end first; ACT-phase slice =
  radiolabel → in-vitro binding → one xenograft biodistribution run.**
- Team for ACT: **no pathologist seat; add nuclear-medicine/radiochemistry as an academic co-investigator** —
  the real near-term gap.
