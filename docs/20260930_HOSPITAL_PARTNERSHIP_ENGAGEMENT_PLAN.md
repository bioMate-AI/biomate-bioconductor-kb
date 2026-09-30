# Hospital Partnership Engagement Plan — Cyclic-Peptide Drug-Development Collaboration

**Date:** 2026-09-30
**Purpose:** Turn the two standalone hospital surveys into an actionable engagement plan — rank the two candidate partners, define the concrete first ask for each, scope a Phase-0 joint project, and consolidate the IP/data-governance diligence checklist. This is the BD action layer on top of the survey briefs.
**Scope note:** Independent of the ACT accelerator application (item 3) and its IO target set (PD-L1 / CD47-SIRPα / LLM-novel). This plan operates only on the **hospital-partner-nominated, disease-specific** targets. The two are non-overlapping and can run in parallel.
**Sources (self):**
- `docs/20260930_HOSPITAL_SURVEY_SYSUCC_CYCLICPEPTIDE_COLLAB.md` (SYSUCC, oncology)
- `docs/20260930_HOSPITAL_SURVEY_SOOCHOW_RHEUM_CYCLICPEPTIDE_COLLAB.md` (Soochow, rheumatology/immunology)

> **Honesty contract.** Rankings are judgement calls flagged as such; every hospital fact traces to the survey briefs (which are individually cited). Cross-border data/IP constraints (China HGRAC) are stated up front, not buried.

---

## 0 · One-paragraph thesis

We are the **generative cyclic-peptide design + closed-loop engine**; a hospital partner supplies **(1) a mechanistically-validated druggable target, (2) patient data to prioritize/stratify it, (3) the wet-lab/functional assay that closes our design→make→test→learn loop, and (4) a translational/clinical path.** Two strong candidates emerged: **SYSUCC** (oncology — world-leading NPC target biology + PDX/organoids + Phase-I unit) and **Soochow 1st Affiliated rheumatology** (autoimmune — intracellular/PPI target discoveries + patient-PBMC assays + rare in-house cell-therapy/GMP). They are **complementary, not either/or**: different disease axes, different targets, and each de-risks a different part of our platform.

---

## 1 · Partner comparison & ranking (judgement)

Scored 1–5 on the four things we need from a partner plus engagement friction. **Higher = better for us.**

| Criterion | SYSUCC (oncology) | Soochow rheum (autoimmune) |
|---|---|---|
| **Target quality × peptide-fit** | 5 — LMP1–TRAF/TRADD is a textbook flat intracellular PPI; EBV-entry receptors are clean extracellular interfaces | 4 — Tfh/Tph–B costimulatory PPI + intracellular TWEAK-HOIP-HuR are strongly peptide-shaped; slightly less structurally resolved |
| **Wet-lab validation strength** | 5 — world's largest NPC biobank, PDX/organoids, functional assays | 4 — patient-PBMC/Tfh-B help + mesangial-cell + murine models; assays already running for UTAA91 |
| **Data for prioritization/stratification** | 5 — million-scale NPC cohorts, proteogenomic subtyping, single-cell atlases | 3 — real SLE/RA/Sjögren cohorts + biologic-response data, but no confirmed biobank/registry/omics |
| **Clinical / translational path** | 5 — NMPA anti-tumor New-Drug trial center + GCP Phase-I unit (~50% drug-to-approval) | 3 — national drug-trial base; strong for autoimmune cell-therapy, peptide path less proven |
| **Strategic fit to our thesis** | 4 — oncology peptide is credible but a crowded modality space; NPC niche is differentiated | 5 — immune-mediated disorders is our stated core; complementary modality to their CAR-Vδ1T |
| **Engagement friction** | 3 — elite, in-demand institution; world-class internal bioinformatics (must position purely on modality) | 4 — provincial leader, likely more accessible; already partners externally (PersonGen), open to modality collaborators |
| **Cross-border data/IP risk (HGRAC)** | 3 — large patient-cohort data is HGRAC-sensitive; work on target biology not raw genetic export | 3 — same constraint; PBMC/sample-based assays stay in-country, lower friction than data export |

**Read:** SYSUCC scores highest on raw target/validation/clinical assets; **Soochow scores highest on strategic fit and accessibility**. Neither dominates — the recommendation is a **staged two-track engagement**, leading with the one that best matches our near-term de-risking need.

### Recommendation
- **Lead near-term with Soochow (autoimmune)** as the *first* active collaboration: it matches our stated core (immune-mediated disorders), the targets are our own thesis's home turf, engagement friction is lower, validation assays already exist and run in-country (lower HGRAC friction than cohort-data export), and their UTAA91 program means they already think in pathogenic-cell/PPI terms — our peptide is an easy-to-frame complementary modality.
- **Pursue SYSUCC in parallel as the higher-ceiling oncology track**, opening on the single most differentiated, least-crowded target the whole survey produced: the **EBV LMP1–TRAF/TRADD PPI in NPC**, where SYSUCC is the world leader and the interface is genuinely undruggable by small molecules/antibodies.
- Both are **modality-side** collaborations — we bring design + compute + closed loop, never an analysis platform (both have strong internal bioinformatics; SYSUCC world-class).

---

## 2 · The concrete first ask (per partner)

Keep the opening ask small, specific, and validation-anchored — one target, one cheap assay, one cohort question.

### Soochow (rheumatology) — first ask
1. **Nominate ONE target node** from their own discoveries where reversible PPI blockade is therapeutically sufficient (not requiring cell depletion). Lead candidate: the **Tfh/Tph ↔ B-cell costimulatory interface** (ICOS–ICOSL / CD40–CD40L-type), because they already run the patient-PBMC / Tfh-B help assay for UTAA91 — the assay is in place. Backup: the **intracellular TWEAK–HOIP–HuR** LN axis (needs cell-penetrant macrocycle; higher risk, higher novelty).
2. **One stratification question** from their SLE/RA/Sjögren cohort (e.g., which subset the nominated node is most active in) — lets us prioritize before design.
3. **Agreement to run the round-1 functional assay** on a CRO-synthesized peptide panel we deliver.

### SYSUCC (oncology) — first ask
1. **Confirm the LMP1–TRAF/TRADD (or LMP1–TRADD) interface** as a nominated target and share/point to the structural basis they'd condition validation on.
2. **One NPC organoid/PDX or primary-sample assay** they'd run on our delivered peptide panel (binding + functional NF-κB readout).
3. **Cohort/subtype prioritization** — which NPC proteomic subtype carries the LMP1/NF-κB dependency (their 240-patient proteogenomic data), so we design for the right subpopulation.

---

## 3 · Phase-0 joint-project scope (division of labor)

A minimal, low-cost first loop that proves the collaboration works before scaling.

| Stage | Us (BioMate) | Partner (hospital) |
|---|---|---|
| **P0.1 Target lock** | Target-confidence pass + structural conditioning setup | Nominate + validate the node; share structural/assay basis |
| **P0.2 Prioritize** | Ingest cohort/subtype signal → design spec | Supply the stratification question + cohort readout |
| **P0.3 Generate** | Run generator → verify (affinity/permeability/SA/safety) → Pareto shortlist | — |
| **P0.4 Synthesize** | Spec + fund the **peptide CRO** (third party) | — |
| **P0.5 Test** | — | Run binding + functional assay on the panel |
| **P0.6 Learn** | Ingest assay results → DPO-retrain generator; report | Co-author readout |

**Cost anchors (to confirm against the macrocycle round-1 estimate):** the wet-lab flywheel round for the macrocycle program was previously scoped at **~$15–25k for an IP-clean CRO round** (`project_macrocycle_closedloop`). Phase-0 should be scoped to one such round per partner so a "no" is cheap.

---

## 4 · Consolidated diligence & IP / data-governance checklist

Merged from both surveys' open items, plus the cross-border constraints that apply to *any* China-hospital collaboration.

**Data / cohort diligence**
- [ ] Confirm cohort sizes + whether a formal **biobank/registry** exists (both surveys flag this as unverified for Soochow; SYSUCC biobank is confirmed, scope of access is not).
- [ ] Confirm which **assays are already running** vs need building (Soochow UTAA91 PBMC assay = in place; SYSUCC organoid/PDX drug-screen = published capability).
- [ ] SYSUCC publication author-orderings/DOIs flagged in the survey → confirm before any external citation.
- [ ] Soochow: resolve the **程韬 = "Cheng Peng"** identity and the Ke-Rui/田洁 Breg **name-collision** (likely Jiangsu University, not Soochow); treat the "5-patient SLE CAR-T" claim as **unverified** (real series is Erlangen/Schett).

**IP structure**
- [ ] Define ownership of **co-generated wet-lab assay data** that feeds our DPO generator — this is our moat; must be contractually ours (or jointly owned with a license) before data flows back.
- [ ] Composition-of-matter IP on generated peptides — our design; confirm no partner claim on molecules we generate.
- [ ] Peptide CRO agreements (synthesis) kept separate and IP-clean.

**Cross-border (China HGRAC — critical, applies to both)**
- [ ] China's **Human Genetic Resources Administration** rules restrict export of Chinese patient genetic data/samples and require approval for foreign-party collaborations using them. Structure the collaboration so **target biology and assay results** (not raw human genetic resources) cross the border, and/or run compute in-country. Get this scoped with counsel *before* any cohort data is shared — it is the single biggest structural risk.
- [ ] Prefer **in-country wet-lab validation** (keeps samples domestic) — favors both partners since the assays run in their labs anyway.

---

## 5 · Outreach sequencing

1. **Warm-path check.** No known direct warm intro to either institution in our network (our BD warmth is TMC/Houston, per `user_uthealth_faculty_background`). Check for any second-degree academic connection (co-authors, society contacts) before cold outreach; otherwise lead through a credible academic/clinical intro.
2. **Soochow first** (lower friction, core-thesis fit): approach **Wu Jian's** group (dept director + UTAA91 PI + Research Center director) with the complementary-modality framing — "add a reversible PPI-blocker modality to your validated-target pipeline."
3. **SYSUCC in parallel** (higher ceiling): approach via the NPC/State-Key-Lab axis with the **LMP1-PPI** opener — the one target where we bring something their world-leading program can't get from small molecules or antibodies.
4. **Message discipline** (per `feedback_no_method_disclosure`): externally state *what we deliver* (designed, validated cyclic-peptide candidates against their target, with a closed optimization loop) + a light credibility tag — **not** the tool stack (PepGLAD/DPO/permeability scorer) or method recipe. Keep the "how" internal.

---

## 6 · Open decisions (founder)

1. **Lead partner** — recommendation is Soochow-first / SYSUCC-parallel; confirm or reprioritize.
2. **Lead target per partner** — Soochow: costimulatory PPI (assay-ready) vs TWEAK-HOIP-HuR (novel, harder); SYSUCC: LMP1-PPI is the clear opener.
3. **Budget** — approve one ~$15–25k CRO round per partner for Phase-0, or gate on a signed collaboration first.
4. **HGRAC counsel** — engage before any cohort data is requested.

---

*Depends on the two survey briefs; update this plan after founder review of those. No wet-lab or compute has been committed — this is the engagement/decision layer only.*
