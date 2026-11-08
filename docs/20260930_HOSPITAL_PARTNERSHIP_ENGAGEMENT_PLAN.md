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
| **Target quality × peptide-fit** (verified) | 5 — SYSUCC-owned EBV-entry receptors R9AP/EphA2 are causal, **extracellular**, peptide-precedented (R9AP19–30) and structure-enabled (EphA2 PDB 7CZE); LMP1–TRAF is the intracellular moonshot | 4 — verified lead **IL-23/IL-23R** is causal + extracellular; CD226/B7-family are flat surface PPIs; mostly correlative beyond IL-23 |
| **Wet-lab validation strength** | 5 — world's largest NPC biobank, PDX/organoids, functional assays | 4 — patient-PBMC/Tfh-B help + mesangial-cell + murine models; assays already running for UTAA91 |
| **Data for prioritization/stratification** | 5 — million-scale NPC cohorts, proteogenomic subtyping, single-cell atlases | 3 — real SLE/RA/Sjögren cohorts + biologic-response data, but no confirmed biobank/registry/omics |
| **Clinical / translational path** | 5 — NMPA anti-tumor New-Drug trial center + GCP Phase-I unit (~50% drug-to-approval) | 3 — national drug-trial base; strong for autoimmune cell-therapy, peptide path less proven |
| **Strategic fit to our thesis** | 4 — oncology peptide is credible but a crowded modality space; NPC niche is differentiated | 5 — immune-mediated disorders is our stated core; complementary modality to their CAR-Vδ1T |
| **Engagement friction** | 3 — elite, in-demand institution; world-class internal bioinformatics (must position purely on modality) | 4 — provincial leader, likely more accessible; already partners externally (PersonGen), open to modality collaborators |
| **Cross-border data/IP risk (HGRAC)** | 4 — mitigated: our Chinese entity holds the collaboration domestically; cohort data stays in-country | 4 — mitigated same way; PBMC/sample assays already run in-country |

**Read:** SYSUCC scores highest on raw target/validation/clinical assets; **Soochow scores highest on strategic fit and accessibility**. Neither dominates — the recommendation is a **staged two-track engagement**, leading with the one that best matches our near-term de-risking need.

### Recommendation
- **Lead near-term with Soochow (autoimmune)** as the *first* active collaboration: it matches our stated core (immune-mediated disorders), the targets are our own thesis's home turf, engagement friction is lower, validation assays already exist and run in-country (lower HGRAC friction than cohort-data export), and their UTAA91 program means they already think in pathogenic-cell/PPI terms — our peptide is an easy-to-frame complementary modality.
- **Pursue SYSUCC in parallel as the higher-ceiling oncology track**, opening on the single most differentiated, least-crowded target the whole survey produced: the **EBV LMP1–TRAF/TRADD PPI in NPC**, where SYSUCC is the world leader and the interface is genuinely undruggable by small molecules/antibodies.
- Both are **modality-side** collaborations — we bring design + compute + closed loop, never an analysis platform (both have strong internal bioinformatics; SYSUCC world-class).

---

## 2 · The concrete first ask (per partner)

Keep the opening ask small, specific, and validation-anchored — one target, one cheap assay, one cohort question.

*(Lead targets below are the verified, publication-mined picks — see the two survey docs' §5/§7 corrections. Earlier drafts led with mis-attributed targets; those are retired.)*

### Soochow (rheumatology) — first ask
1. **Lead target: IL-23 / IL-23R interface** — the **only** node where the group has *causal in-vivo* evidence (their IL-23p19 mAb reversed nephritis in MRL/lpr mice, PMID 40620119). A cytokine–receptor flat PPI, no cell penetration needed. Backups (their own surface/secreted targets): **CD226 (DNAM-1)–CD155** and **soluble B7-H1/H2/H5** in Sjögren's.
2. **Head-to-head validation offer:** we deliver a macrocyclic IL-23p19/IL-23R binder → competition ELISA/SPR → run it against their mAb in the *same MRL/lpr readout they've already validated*. Apples-to-apples.
3. **One stratification question** from their SLE/pSS cohort (which subset the node is most active in) to prioritize before design.

### SYSUCC (oncology) — first ask
1. **Lead target: EBV-entry receptor R9AP ↔ gH/gL** (Zeng/Zhong, *Nature* 2025) — SYSUCC-owned, causal, extracellular, with a **published blocking peptide (R9AP19–30)** to anchor design. Co-lead: **EphA2 ↔ gH/gL** (structure-enabled, PDB 7CZE). Second track: **ITGA2/collagen-IV** for recurrent radioresistant NPC.
2. **Validation:** run our delivered macrocycle panel in the Zeng lab's existing **EBV-entry blockade assay** (primary NPECs + B cells) + BLI vs gH/gL; ITGA2 track uses their rNPC PDX/organoid + spatial platform (radiosensitisation readout).
3. **Structure co-development note:** R9AP–gH/gL has no published crystal — offer joint structure determination as an early deliverable (EphA2 already has 7CZE for immediate generator conditioning).
   *(LMP1–TRAF NF-κB is the differentiated intracellular moonshot — staged, not the opener; MAT2A dropped as wrong-modality.)*

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

**Cross-border (China HGRAC — mitigated by our Chinese agency/entity)**
- [ ] China's **Human Genetic Resources Administration** rules restrict export of Chinese patient genetic data/samples. **We have a Chinese agency/entity** — so the collaboration can be structured **domestically**: the Chinese entity holds the collaboration, samples/data stay in-country, and validation runs in the partner's labs. This substantially de-risks HGRAC vs a pure foreign-party structure. *(Caveat: HGRAC can still trigger review where foreign parties or foreign-controlled entities are involved — confirm the exact structure with counsel, but this is now a manageable compliance step, not the top structural blocker.)*
- [ ] Prefer **in-country wet-lab validation** (keeps samples domestic) — favors both partners since the assays run in their labs anyway; the Chinese entity is the contracting party.
- [ ] Only **target biology + de-identified assay results** need cross the border to feed our generator — the moat data, not raw human genetic resources.

---

## 5 · Outreach sequencing

1. **Warm-path check.** No known direct warm intro to either institution in our network (our BD warmth is TMC/Houston, per `user_uthealth_faculty_background`). Check for any second-degree academic connection (co-authors, society contacts) before cold outreach; otherwise lead through a credible academic/clinical intro.
2. **Soochow first** (lower friction, core-thesis fit): approach **Wu Jian's** group (dept director + UTAA91 PI + Research Center director) with the complementary-modality framing — "add a reversible PPI-blocker modality to your validated-target pipeline."
3. **SYSUCC in parallel** (higher ceiling): approach via the NPC/State-Key-Lab axis with the **LMP1-PPI** opener — the one target where we bring something their world-leading program can't get from small molecules or antibodies.
4. **Message discipline** (per `feedback_no_method_disclosure`): externally state *what we deliver* (designed, validated cyclic-peptide candidates against their target, with a closed optimization loop) + a light credibility tag — **not** the tool stack (PepGLAD/DPO/permeability scorer) or method recipe. Keep the "how" internal.

---

## 6 · Open decisions (founder)

1. **Lead partner** — recommendation is Soochow-first / SYSUCC-parallel; confirm or reprioritize.
2. **Lead target per partner (verified)** — Soochow: **IL-23/IL-23R** (only causal + assay-ready); SYSUCC: **R9AP/EphA2 EBV-entry receptors** (causal, extracellular, EphA2 structure-enabled). LMP1–TRAF and the correlative surface targets are staged/backup.
3. **Budget** — approve one ~$15–25k CRO round per partner for Phase-0, or gate on a signed collaboration first.
4. **HGRAC** — mitigated via our Chinese entity (structure domestically); confirm exact structure with counsel.

---

*Depends on the two survey briefs; update this plan after founder review of those. No wet-lab or compute has been committed — this is the engagement/decision layer only.*
