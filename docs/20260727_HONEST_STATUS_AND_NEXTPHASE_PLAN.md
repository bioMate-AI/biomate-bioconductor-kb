# Honest Status Correction + Next-Phase Plan (Target Discovery / Stratification)

**Date:** 2026-07-27
**Why:** the earlier UCB stage table (`20260723_...` and follow-ups) marked stages 🟢 "done" when a workflow merely **emits that stage's output type** — not when the stage is **validated end-to-end on real, messy cohort data.** This corrects that and sets an honest next-phase plan.

---

## Maturity scale (used below)
- 🟢 **Real-data validated** — run and checked on real, noisy data.
- 🟡 **Plumbing/math verified** — correct on idealized / known-answer inputs; NOT yet real-data validated.
- 🟠 **Output-capable via catalog** — a workflow exists but wasn't integrated/validated for this use this session.
- 🔴 **Not built / genuinely hard.**

## Corrected status — what we ACTUALLY have

| UCB stage / capability | Honest maturity | The precise reality |
|---|---|---|
| **Target scorecard (feature ranking / prioritisation)** | 🟡 | Transparent **rule-based weighted aggregation** of Open Targets' **already-computed** evidence. **Not** ML/AI feature selection; **not** a trained ranker. Tested on OT's pre-packaged data — **not** on a raw-cohort→features chain. |
| Raw cohort → multi-omic → integrated features → rank (the real Stage 2-4) | 🔴/🟠 | The per-omics workflows exist in the catalog, but the **full chain was never run end-to-end on a real cohort.** "End-to-end" so far = "public OT evidence → rank." |
| **Isotype patient stratification** | 🟡 | A **narrow rule-threshold classifier on one well-understood axis** (isotype→FcRn response) on already-measured serology. Verified on synthetic-realistic serology. **Not** general multi-omic endotype stratification. |
| Multi-omic **endotype** stratification (the hard kind) | 🔴 | MOFA exists in the catalog; **not built/validated** this session. This is the genuinely hard, unsolved-in-the-field problem (3 vs 5 vs 8 endotypes; harmonization). |
| **Gate-3 interaction test** | 🟡 | Statistics **verified on fixtures with known answers**; **not** run on a real biomarker-stratified trial dataset. |
| **Repurposing (CMap reversal)** | 🟡 | KS connectivity **math verified on a planted-reverser fixture**; not on real LINCS + a real disease signature. |
| Multi-omics profiling / perturbation / safety | 🟠 | Catalog workflows exist; not run as an integrated pipeline this session. |
| **Cohort design / metadata harmonization** | 🔴 | Not built. The field's real bottleneck (see harmonization survey). |
| Human-in-the-loop step-by-step suggestions | 🟢 | Built + tested (output_analyzer). |

**Honest headline:** most of what we built is **🟡 — correct plumbing/math on idealized inputs, not validated on real data.** The differentiating work is the jump from 🟡→🟢 on real cohorts, plus the hard harmonization/reproducibility pieces the survey flagged. What we have are **credible capability demonstrations and real components — not a solved UCB workflow.**

---

## Next-phase plan (prioritized by defensibility × need; survey-informed)

### Phase A — Prove it's real (close the 🟡→🟢 gap)
- **A1.** Run the **full raw-cohort → multi-omic → integrated-features → scorecard** chain on a **real public cohort** (GEO/ImmPort MG or SLE). Turns Stage 3/4 honest.
- **A2.** Run **gate-3 on a real biomarker-stratified trial dataset** (public), not fixtures.

### Phase B — Build the defensible wedge (the survey's verdict)
- **B1.** **Harmonization select-and-evaluate scorer** — the scIB two-objective metrics (iLISI/cLISI, ASW-batch/celltype, kBET) + method selection + **over-correction detection**. *This is the productizable wedge — the evaluation/selection loop, not any single integration method (which we already have).* ← **starting now.**
- **B2.** **QC-triage gate** + provenance capture ("is this good enough to integrate?").
- **B3.** **Real multi-omic endotyping** (MOFA) on a public cohort with **gate-0 reproducibility** (out-of-cohort label transfer, longitudinal stability) → the M1/M2 manuscript backbone.

### Phase C — Per-client moat
- **C1.** **Metadata harmonization**: deterministic ontology mapper (text2term / EFO-CL-UBERON) + **human-in-the-loop** + a **per-client LLM adapter that PROPOSES mappings for confirmation** (Ludwig L1/L2). Never LLM-alone (survey: 17% out-of-dictionary, hallucinated IDs).
- **C2.** Advisory **learned ranker** (flywheel) on accumulating private outcomes — kept advisory.

### Phase D — Publications (public data, fast)
M5 (five gates), M3 (isotype gate-3), M1/M2 (endotyping reproducibility), M4 (antigen resolution).

---

## What I'm starting now
**B1 — the harmonization evaluation scorer** (`integration_benchmark`): given an integrated embedding + batch + cell-type labels, compute the scIB two-objective metrics and return a verdict (well-integrated / over-corrected / under-corrected). This is the survey's identified defensible wedge, it's locally testable (metrics are math on embeddings + labels), and it operationalizes over-correction detection — the thing that turns "we ran Harmony" into "we selected the method that removed batch without erasing biology." **It will be math-verified on constructed fixtures (well-mixed vs separated vs over-mixed embeddings); real-data validation is a Phase-A follow-up, and I will label it honestly.**
