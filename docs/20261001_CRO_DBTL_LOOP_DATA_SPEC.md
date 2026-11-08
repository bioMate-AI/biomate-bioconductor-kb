# Closed Dry→Wet Loop — CRO Step-by-Step + Exactly What Data We Need Back

**Date:** 2026-10-01 · **Context:** ACT cyclic-peptide program (PD-L1 round 1). Defines the Design→Build→
Test→Learn (DBTL) loop with the CRO, who provides what, what runs in parallel, and — the point of this doc —
**the exact structured data we require back so every result (success OR failure, at any step) optimizes the model.**

## The core principle
We are not buying "winners." We are buying **labeled training signal.** A peptide that fails to synthesize,
fails to cyclize, or binds weakly is **as valuable as a hit** — it's a negative/failure label the generator
and the predictors learn from. So the deliverable we ask the CRO for is **the complete per-peptide outcome at
every step, quantitative, including failures and raw traces** — not a shortlist of hits.

**Record our predictions BEFORE the wet lab.** The learning signal is *predicted vs measured*, so the dry
predictions (iptm, MM-GBSA ΔG, permeability, cyclization-feasibility, aggregation) are frozen per peptide
up front; the CRO data is compared against them.

## The loop, step by step

| # | Step | **We provide** | **CRO does** | **What we MUST get back** | **Learning signal** |
|---|---|---|---|---|---|
| 0 | **Design** (dry, us) | — | — | (frozen) our per-peptide predictions | the baseline to compare against |
| 1 | **Synthesis** (CRO) | sequences, head-to-tail cyclization spec, purity/amount/counterion | SPPS + cyclization + purification | per-peptide: **synthesized Y/N, cyclized Y/N, final purity %, exact MS-measured mass, crude + net yield, and FAILURE MODE if failed** (poor cyclization yield / aggregation / deletion sequence) | synthesizability + cyclization-feasibility model: failed = negatives |
| 2 | **Identity/QC** (CRO) | — | HPLC + MS | **HPLC trace + MS spectrum per peptide** (raw, not just "pass") | confirms *what was actually tested* (purity, correct mass) |
| 3 | **Binding** (CRO, SPR/BLI) | (target protein, or they supply) | affinity ranking → kinetics | per-peptide: **binds Y/N, KD, kon, koff, Rmax, and the raw sensorgrams** — including the **non-binders** | binding predictor calibration; non-binders = hard negatives for the generator |
| 4 | **Function** (CRO, optional) | — | PD-1/PD-L1 competition (ELISA/HTRF) | **% blockade / IC50 per peptide** | functional-site vs off-site binding |
| 5 | **Learn** (dry, us) | ingest all of the above | — | — | build DPO/fine-tune pairs → retrain → round 2 |

## What runs in parallel (to speed the round)
- **All 10 syntheses run in parallel** (the CRO batches them) — not sequential. ~same wall-clock as one.
- **Binding is one SPR batch** across all synthesized analytes vs the single target — one run, all peptides.
- So the round is: *10 parallel syntheses → one SPR batch → one learning update.* The only true serial
  dependency is synthesis → binding (can't assay what isn't made). Function assay (step 4) can run right
  after binding on the same material.
- **Dry side runs in parallel to the wet side:** while the CRO synthesizes, we run the multi-seed refold +
  corpus/retrain prep, so the Learn step is ready the moment data lands.

## Failure branches — every one still closes the loop
- **All fail at synthesis/cyclization (step 1).** → signal: the generator makes *unsynthesizable* sequences.
  We need the **per-peptide failure mode** to fix the cyclization-feasibility screen + add a turn-inducer
  prior to the generator. *We learn even with zero usable peptides.*
- **Synthesized, but none bind (step 3).** → signal: makeable but non-binding. The **measured KDs / non-binder
  labels** retrain the binding predictor + give the generator hard negatives. *A no-hit round is a successful
  learning round.*
- **Some bind weakly.** → KD gradient is the richest signal (rank-order to learn affinity, not just yes/no).
- **A hit binds but doesn't block (step 4).** → it's an off-functional-site binder → condition next round on
  the functional hotspot.

## THE ask to the CRO (the one-line version)
> "Return **per-peptide, quantitative results at every step — synthesis outcome + failure mode, final
> purity, measured mass, and SPR KD/kon/koff with raw sensorgrams — for ALL peptides including the ones that
> fail or don't bind**, in a single structured results table + the raw traces. We are using every outcome as
> data, so do not pre-filter to 'successful' peptides."

That sentence is what turns a normal CRO order into a **loop that optimizes the model** — because the negatives
and the quantitative gradients are exactly what a Design→Build→Test→**Learn** cycle trains on.

## What we do with it (step 5, Learn)
1. **Calibrate predictors:** measured KD vs predicted iptm/ΔG; measured purity/cyclization vs predicted
   feasibility; measured aggregation behavior vs predicted. Refit the scoring thresholds on real labels.
2. **Build preference pairs (DPO):** binder > non-binder, tighter-KD > weaker, synthesizable > failed →
   fine-tune the generator on *our* proprietary measured signal (the data no external tool has).
3. **Retrain M2c** on the enlarged corpus + the new measured pairs → round-2 panel.
This is the compounding edge: each round the model gets better *at our targets* on data only we hold.
