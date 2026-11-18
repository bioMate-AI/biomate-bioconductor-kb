# The Life Cycle of a Drug Target — How a Candidate Becomes an *Acknowledged* Target

*Reference framework, 2026-09-11. Synthesized from our target-identification survey
(`20260817_TARGET_IDENTIFICATION_SURVEY.md`) and the drug-blind cross-disease scorecard
(`20260727_CROSS_DISEASE_TARGET_SCORECARD.md`), instantiated across mechanism channels —
not just Dr. Mohan's ALCAM. All external facts trace to the cited sources.*

---

## 0 · The organizing principle (why the ladder exists)

A target is not "true" or "false" — it accrues **evidence** that moves it up a ladder of
confidence. The single best-quantified predictor of clinical success is **human genetic
support**: mechanisms with direct genetic support are approved at **~2–2.6× the base
rate**, and the effect **grows with confidence in the causal gene** (Nelson 2015, *Nat
Genet*, [10.1038/ng.3314](https://doi.org/10.1038/ng.3314); Minikel 2024, *Nature*,
[10.1038/s41586-024-07316-0](https://doi.org/10.1038/s41586-024-07316-0)). So the whole
life cycle is a strategy to do two things ever more confidently: **name the causal gene**
and **pin the direction of effect** (gain-of-function disease → inhibit; loss-of-function
protective → inhibit; loss-of-function disease → activate/replace).

**"Acknowledged" is the top of the ladder, not a single event.** A target becomes
acknowledged when an intervention against it produces a **human efficacy** result —
ideally an approved drug whose mechanism *is* that target.

---

## 1 · The ladder — six stages (a "Target Readiness Level")

| Stage | Name | What it means | Evidence that *promotes* it | Gate to next stage |
|---|---|---|---|---|
| **T0** | **Association** | A gene/protein correlates with disease | Differential expression, a GWAS locus, a biomarker measurement | Is it *causal*, or a passenger/consequence? |
| **T1** | **Causal nomination + direction** | The causal gene is named and the direction of effect is pinned | GWAS→gene (fine-mapping/L2G), **coloc PP.H4** (shared causal variant with a molecular QTL), **cis-MR** (lifelong natural RCT → direction+magnitude), rare-variant/LoF "human knockouts", **OMIM** monogenic proof | Does perturbing it actually move disease biology? |
| **T2** | **Functional / mechanistic validation** | Deliberate perturbation changes the phenotype; the entity is druggable | CRISPR KO/KD/activation screens, animal models, structure/pocket + modality fit (small molecule / antibody / degrader) | Can a real molecule engage it *and* be safe on-target? |
| **T3** | **Translational / preclinical proof** | A tool molecule/antibody hits it and shows efficacy in disease models; on-target safety scoped | In-vivo efficacy, **PheWAS / cis-MR safety** (on-target side-effect prediction), tox | Does target engagement + a signal appear in humans? |
| **T4** | **Clinical proof-of-mechanism** | A drug against it shows engagement + an efficacy signal in patients (Ph1/2) | Biomarker-confirmed engagement, Ph2 endpoint movement | Does it hold in a controlled Ph3? |
| **T5** | **Acknowledged / validated target** | An **approved** drug works through that mechanism | Ph3 + regulatory approval; standard-of-care | — (now a *credentialing anchor* for new work) |

**Key asymmetries the ladder captures:**
- **T0→T1 is the hardest and highest-value jump** — most candidates die here (correlation ≠ causation; ~90% of GWAS hits are non-coding, so the associated *locus* is not the *gene*).
- **A T5 target de-risks its whole channel** — it becomes the null/positive control every new nomination in that mechanism is scored against (see §2).
- **The ladder is evidence, not time** — a target can sit at T0 for a decade (biomarker with no causal proof) or leap T1→T5 fast when genetics + a matched modality align (e.g. PCSK9).

---

## 2 · The channel view — real targets placed on the ladder, by mechanism

Our drug-blind ranker (Open Targets genetics + literature + pathway + animal evidence,
**excluding** any known-drug data) reconstructed the real autoimmune target map: **15
canonical targets landed in the correct disease's top-10, the rest at #11–12** — a clean
rediscovery of standard-of-care mechanisms from biology alone. Reading those results as a
**mechanism-channel map**, with each channel's exemplar and where it sits on the ladder:

| Mechanism channel | Exemplar target | Stage | What credentialed it (the promoting evidence) |
|---|---|---|---|
| **Complement** | **C5** | **T5** | Approved MG biologics eculizumab/ravulizumab; ranker #1 in MG drug-blind |
| **Antibody recycling (FcRn)** | **FCGRT / FcRn** | **T5** | Efgartigimod/rozanolixizumab (MG); ranker #2 in MG |
| **IL-12/23 → TYK2 spine** | **IL12B, IL23R, TYK2** | **T5** | ustekinumab, risankizumab, **deucravacitinib**; **IL23R LoF R381Q** (protective) is the canonical MR proof (Di Meglio 2011, [10.1371/journal.pone.0017160](https://doi.org/10.1371/journal.pone.0017160)) |
| **IL-17** | **IL17A / IL17F** | **T5** | secukinumab/ixekizumab; bimekizumab (dual A/F) |
| **IL-6** | **IL6R** | **T5** | tocilizumab; **cis-MR Asp358Ala mimics the drug** (IL6R MR Consortium 2012, [10.1016/S0140-6736(12)60110-X](https://doi.org/10.1016/S0140-6736(12)60110-X)) |
| **TNF** | **TNF** | **T5** | adalimumab/infliximab |
| **B-cell depletion** | **MS4A1 / CD20** | **T5** | rituximab/ocrelizumab |
| **BAFF/APRIL** | **TNFSF13B / BAFF** | **T5** | belimumab (SLE); telitacicept (dual BAFF/APRIL) |
| **Co-stimulation** | **CTLA4; CD40** | **T5 / T4** | abatacept (CTLA4, approved); iscalimab (CD40, clinical) |
| **Type-I interferon** | **IFNAR1; TLR/nucleic-acid sensing (TLR9, IRF5)** | **T5 / T1–T2** | anifrolumab (IFNAR1, approved SLE); SLE genetics anchors the TLR/IRF5 axis (nomination stage) |
| **Lymphocyte trafficking** | **S1PR1; ITGA4** | **T5** | fingolimod/ozanimod (S1P); natalizumab/vedolizumab (α4-integrin) |
| **Adhesion / ALCAM–CD6** | **ALCAM (CD166)** | **T0→T1** | **Dr. Mohan's target** — see §3 |

*Canonical cross-disease anchor proofs the ladder rests on:* **PCSK9** (LoF → ~88% CHD
reduction → statins/anti-PCSK9; Cohen 2006, [10.1056/NEJMoa054013](https://doi.org/10.1056/NEJMoa054013)),
**ANGPTL3** (familial hypolipidemia → evinacumab), **SLC30A8** (LoF *protects* from T2D →
direction = inhibit). These are the textbook T1→T5 traversals where genetics named the
gene *and* the direction before the drug existed.

---

## 3 · Where ALCAM (Dr. Mohan's target) sits — and its channel

- **Channel:** cell **adhesion / co-stimulation** — ALCAM (CD166) binds **CD6**; the
  therapeutic arc is the anti-CD6 antibody **itolizumab** (an external asset).
- **Stage today: T0 → T1.** The 2020 aptamer screen (Stanley/Mohan, *Nat Commun* 11:2197,
  [10.1038/s41467-020-15986-3](https://doi.org/10.1038/s41467-020-15986-3)) established
  ALCAM as a **urinary biomarker** of active lupus nephritis, validated across three
  ethnicities (AUC 0.84–0.93) — that is a strong **T0** association. The **LRA Target
  Identification grant** + the "pathogenic urine biomarker" framing of the home-monitoring
  work are the push toward **T1** (from *correlates with* to *causal driver of*).
- **What is still owed to promote it:** the T0→T1 gate — genetics/causal evidence
  (is ALCAM a driver or a passenger of renal inflammation?), then T2 functional proof.
  The CD6 side of the axis is further along clinically (itolizumab), which lends the
  channel credibility but does not by itself credential *ALCAM* as the drug target.

---

## 4 · Where BioMate fits on this ladder (honest scope)

BioMate does **not** claim de-novo target discovery. Its contribution is to **automate and
make reproducible the T0→T1→T2 credentialing** — the hardest, highest-value part:

- **Multi-channel target-confidence** — score a candidate on several complementary
  evidence lines (genetics-anchored causal, proteomic/autoantibody, pathway, animal),
  **each against its own matched null**, returning an interpretable per-target breakdown
  rather than a black-box score. This is exactly the "driver vs passenger" T0→T1 question.
- **Drug-blind face validity is already demonstrated** — the scorecard rediscovered 15/…
  canonical targets in the correct disease without seeing any drug data, which is the
  evidence that the confidence layer tracks real biology.
- **Responder / mechanism stratification** — once a channel is acknowledged (T5), the open
  clinical question becomes *which patient fits which mechanism* (e.g. across the approved
  SLE/LN channels: FcRn, BAFF/APRIL, type-I IFN, B-cell depletion). That "which therapy for
  which patient" layer is downstream of the target ladder and is BioMate's second wedge.

> Honest boundary: the confidence + stratification layers are demonstrated on public data
> and in the drug-blind scorecard; turning a specific T0 biomarker (e.g. ALCAM) into a
> credentialed T1/T2 target is the subject of a pilot on real cohort data, not a settled
> result.

---

## 5 · One-screen summary

```
T0 Association ─▶ T1 Causal+direction ─▶ T2 Functional/druggable ─▶ T3 Preclinical ─▶ T4 Clinical PoM ─▶ T5 Approved (acknowledged)
   biomarker,        fine-map/L2G,           CRISPR, animal,          in-vivo eff. +      Ph1/2 engage    Ph3 + approval
   GWAS locus,       coloc PP.H4, cis-MR,     structure/modality       on-target safety    + signal        = channel anchor
   DE gene           rare-variant/OMIM         fit                     (PheWAS)
        │                   │
        └── hardest jump ───┘  (correlation ≠ causation; ~90% GWAS hits non-coding)

ALCAM ≈ T0→T1 (adhesion/CD6 channel)     C5, FcRn, IL-23/TYK2, IL-6R, CD20, BAFF, IFNAR1, S1P, CTLA-4 ≈ T5
```

---

## 6 · Sources
- Nelson 2015, *Nat Genet* 47:856 — [10.1038/ng.3314](https://doi.org/10.1038/ng.3314)
- Minikel 2024, *Nature* 629:624 — [10.1038/s41586-024-07316-0](https://doi.org/10.1038/s41586-024-07316-0)
- IL6R MR Consortium 2012, *Lancet* — [10.1016/S0140-6736(12)60110-X](https://doi.org/10.1016/S0140-6736(12)60110-X)
- Di Meglio 2011 (IL23R R381Q) — [10.1371/journal.pone.0017160](https://doi.org/10.1371/journal.pone.0017160)
- Cohen 2006 (PCSK9) — [10.1056/NEJMoa054013](https://doi.org/10.1056/NEJMoa054013)
- Stanley/Mohan 2020 (ALCAM), *Nat Commun* 11:2197 — [10.1038/s41467-020-15986-3](https://doi.org/10.1038/s41467-020-15986-3)
- Internal: `docs/20260817_TARGET_IDENTIFICATION_SURVEY.md`, `docs/20260727_CROSS_DISEASE_TARGET_SCORECARD.md`, `docs/20260907_mohan_meeting/20260911_MOHAN_ALCAM_TARGET_PUBLICATION_AND_CURRENT_WORK.md`
