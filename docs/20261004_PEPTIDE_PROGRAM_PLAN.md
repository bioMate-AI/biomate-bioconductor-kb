# Cyclic-Peptide Program — Plan (the genuine deltas only, two parallel tracks)

**Date:** 2026-10-04. Honest premise: the core is already built. This plan is ONLY what is *not yet done* — not a re-proposal of finished work. Grounded in `20261004_PEPTIDE_PROGRAM_SYNTHESIS.md` + the two surveys.

## Already DONE (do not redo)
- Multi-objective **selection** (composite ranking: `perm_redesign_v1.py`, `multi_property_selection.py`, 7-component composite) → produced the PD-L1 panel.
- **Two-target hit generation:** PD-L1 (BoltzGen → 10-peptide panel) + αvβ6 (BoltzGen → 12-peptide panel), screened + MM-GBSA/iPTM-ranked.
- **GenScript order email** (synthesis + per-peptide SPR) — send-ready.
- **DPO close-back** built + verified on *synthetic* KD; **surveys + synthesis** done.
- **Data complete:** permeability (CycPeptMPDB), conformers (CREMP), structures (PepBDB/PepBench), **binding (binding_affinity_v1: 136,730 rows, 36,102 cyclic, 434 PD-L1, 227 αvβ6)**.

## The genuine deltas (what's actually new) — run both tracks in PARALLEL

### Track A — Model: real-data binding predictor → principled multi-objective selector
*Delta: we have only ever ranked on PROXIES (MM-GBSA/iPTM). We now have 136k MEASURED affinities and have never trained on them.*
- **A1.** Train a **sequence/SMILES → measured-affinity** model on `binding_affinity_v1` (136k; 36k cyclic; hold out PD-L1/αvβ6 for honest eval). Baselines: RF/XGBoost on descriptors, Chemprop/DMPNN, a peptide-LM head. Report test error + calibration; this *replaces the MM-GBSA proxy* as the binding objective.
- **A2.** Wrap the objectives in a **principled multi-objective optimizer** — **qNEHVI** (Botorch) over {A1 binding, CycPeptMPDB permeability model, synthesizability, selectivity} — replacing the hand-tuned 0.5/0.5 composite. Report **dominated hypervolume vs the current composite** on the existing pools.
- **A3.** Re-score the existing PD-L1/αvβ6 pools with A1+A2; compare the re-ranked top-N to the composite panels (does real-data MO change the picks?).
- *Deliverable:* a real-data multi-objective selector + the honest comparison vs the composite we already use.

### Track B — Generation: RFpeptides (proven hit-rate) alongside BoltzGen
*Delta: our panels used BoltzGen; RFpeptides has the proven higher wet-lab hit rate on novel targets (12/39 binders, 9.4 nM).*
- **B1.** Stand up **RFpeptides / CycleDesigner** (RFdiffusion-cyclic backbone → ProteinMPNN → **cyclic self-consistency filter** HighFold3/CyclicBoltz1) on PD-L1 (5o45) + αvβ6 (9xmm).
- **B2.** Gate candidates with our existing filters (CREMP strain, CycPeptMPDB permeability) + score with Track-A's real-data binding model.
- **B3.** Compare RFpeptides panels vs the BoltzGen panels (designability scRMSD, predicted binding) — a head-to-head of generation methods on our targets.
- *Deliverable:* a second, stronger hit set per target + a method comparison; candidates for a future CRO round.

### The loop (closes when real data returns)
Both tracks feed the DPO close-back. It has run only on synthetic KD; the **real loop turns when the GenScript round-1 KD returns** → `wetlab_kd_to_pairs.py` → DPO → re-score. That's the genuinely-not-done validation; it's gated on the CRO, which is why round-1 matters.

## Honest framing (no over-claim)
- Track A is a real upgrade (real measured binding vs proxy; principled MO vs hand composite) but uses **established methods** — it's rigor + data, not a new method.
- Track B is a **method swap** to the proven-best generator, not a new category.
- The defensible contribution remains the **integrated system + proprietary data + prospectively-validated loop** (synthesis doc), not a "we beat SOTA model" claim.
- Honest gaps carried: binding model generalization to novel targets is unproven (hold-out test will show it); the loop's efficacy claim needs the real CRO data.

## Success criteria (measurable, honest)
- A: binding-model held-out error + calibration; MO hypervolume gain vs composite.
- B: RFpeptides vs BoltzGen designability + predicted-binding head-to-head on PD-L1/αvβ6.
- Loop: once CRO KD lands — does a DPO round improve the next panel's realized hit metric.
