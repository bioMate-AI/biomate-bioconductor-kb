# Cyclic-Peptide Program — Synthesis of the Two Surveys → Honest Strategy

**Date:** 2026-10-04 · Integrates `20261004_MULTIOBJECTIVE_GENERATIVE_SURVEY.md` (7f4ed2300, 60 refs) + `20261004_DATA_SCARCITY_GENERALIZATION_SURVEY.md` (55d9f58fc, 56 refs). Grounded in those sources; honest gaps lead; no asserted "innovation."

## The two surveys converge on one conclusion
1. **Novel-target generalization is NOT winnable by better generative modeling on our data.** The only approaches with *wet-lab* success on novel targets without target-specific binding data are **physics/structure priors** (RFpeptides, Nat Chem Biol 2025: 12/39 binders, 9.4 nM, <20 designs/target; AlphaProteo incl. PD-L1 but as a mini-protein) or **generating the data experimentally** (mRNA/phage display + NGS). Foundation-model transfer — including UniMoMo — **does not generalize out-of-distribution** (BOOM, arXiv 2505.01912); its cross-domain win is in-silico only. → This explains why our UniMoMo fine-tune plateaued, and why chasing a data-starved generator to "beat SOTA" on novel targets is the wrong bet.
2. **Multi-objective cyclic-peptide generation is immature / unaddressed** (per the MO survey: no published, validated 4–5-objective cyclic-peptide Pareto generator). And we already hold the data for the *cheap* objectives (permeability CycPeptMPDB 7,334–8,466; conformers CREMP 36,198; developability). → A well-designed multi-objective cyclic generator is a real, buildable component — honestly an **engineering design on known MO methods** (preference-conditioned inner loop + qNEHVI outer loop), applied to a cyclic setting the field hasn't covered, **not a new method**.

## The honest contribution (what is / isn't ours)
- **NOT a claim:** "our generative model beats SOTA." Generalization comes from physics priors we'd *use* (RFpeptides/CycleDesigner), not out-model.
- **The genuine contribution = the integrated closed-loop SYSTEM:** physics-prior hit generation → multi-objective selection on data we own → proprietary binding data (CRO/display) → sample-efficient novel-target cyclic design, **prospectively validated**. The moat is the *loop + proprietary data*, not any single model (both surveys independently conclude this).
- **The novel component (honestly framed):** a multi-objective cyclic-peptide generator/selector across {binding, permeability, synth, selectivity, stability} — a setting the literature hasn't validated — built on established MO machinery. Present it as "among the first to do multi-objective cyclic design," not "no competitor."

## Concrete integrated design
1. **Generation (novel target, zero binding data):** physics/structure priors — **RFpeptides / CycleDesigner** backbones + **HighFold3 / CyclicBoltz1 / AfCycDesign** cyclic self-consistency filters. Gate with our **CREMP strain** + **CycPeptMPDB permeability**. Gets real PD-L1/αvβ6 cyclic hits with no new binding data.
2. **Multi-objective selection/generation:** **preference-conditioned inner loop** (Rewards-in-Context / MODPO) scoring the *cheap* objectives we have data for (permeability, stability, selectivity) in-loop; **qNEHVI Bayesian outer loop** spending scarce binding evaluations on a surrogate to recover the (non-convex) Pareto front. Cyclization + synthesizability as **hard decode constraints**, not soft rewards (MO survey finding). Scalarization avoided (provably misses non-convex fronts).
3. **Data engine (kills the binding wall + builds the moat):** mRNA/phage display + NGS per target (later, proprietary) + the GenScript CRO loop (round-1 sent). Feeds the binding axis + the DPO close-back.
4. **Closed loop:** sample-efficient active learning couples 1–3 (simple fine-tuning surrogates — meta-learning is partly oversold, arXiv 2404.02314).

## Honest gaps (lead with these)
- No published method provably generalizes to a novel cyclic target from data alone — our generalization is *imported* from physics priors, not invented.
- Binding data is still being collected — until assay labels close the loop, binding-objective optimization is proxy + uncertainty, not validated.
- Multi-objective cyclic generation is unproven in the literature (mostly 2025–26 preprints) — our contribution is early-mover, not a demonstrated SOTA.
- CycPeptMPDB count: 7,334 (published) vs 8,466 (live DB) — use 7,334 externally.

## What this means for a publication (honest)
The defensible paper is the **integrated, prospectively-validated closed loop + the multi-objective cyclic generator**, with the physics-prior generation acknowledged as adopted, not claimed. It is a *systems + application* contribution with real wet-lab validation — not a "we beat the cyclic SOTA model" claim, which the evidence does not support.
