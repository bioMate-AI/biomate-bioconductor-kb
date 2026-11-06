# Cross-target / novel-target generalization — v3.1 NULL **in SOTA context**

**Date:** 2026-10-06 · A NULL is only meaningful against the baseline. This places our cyclic-peptide
cross-target results (v3/v3.1 + the measured OOD evals) next to the SOTA numbers from the two deep
surveys (`docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md`), so "v3.1 = NULL" is read as a **field-level
frontier**, not a standalone model failure. It also says exactly what IS and ISN'T a fair comparison.

## The claim being tested
"Can a model, trained on some targets, design/rank binders for a **held-out target it never saw binders
for** (cross-target / novel-target zero-shot)?" This is the single hardest axis in the field, and the
survey's thesis was that **SOTA defers or fails it** — so our job is to measure where we land *relative
to SOTA*, not in a vacuum.

## SOTA — novel-target / cross-target, as surveyed (documented, cited)
| Method | What it reports | Novel-target result | Honest caveat |
|---|---|---|---|
| **BoltzGen / BoltzProt-1** | de-novo binder design | **~3.3% confirmed hit** (3/10 novel targets); some runs 3.3%→8.0% | authors explicitly **"do not make the zero-shot claim"**; "succeed by reusing interaction motifs" |
| **RFdiffusion** | de-novo binder design | **~7%** independent-replication hit | **needs human-specified hotspots** (not zero-shot) |
| **RFpeptides** (Nat Chem Biol 2025) | de-novo **cyclic** binders | lit bar ~12/39 targets yielded a binder (best ~9.4 nM) | **canonical-AA only**; ncAA deferred to future work |
| **Boltz-2** | binding ΔG | — | **excludes peptides** from the affinity model; FEP OOD **negative** ("right answers for wrong reasons") |
| **UniMoMo** | generator accuracy (DockQ ~0.759) | — | **linear-only, in-distribution** — not a cross-target number at all |

Net SOTA reading: the best *honest* novel-target numbers are **low single-digit confirmed-hit %**, and
they are per-design hit rates after heavy filtering — not evidence a model "knows" a new target. Every
tool **defers calibrated binding, dynamics, ncAA, and OOD generalization** (survey §limitations).

## Ours — measured, cyclic (same hardest axis)
| Our artifact | Metric | Cross-target / OOD result | In-distribution (for contrast) |
|---|---|---|---|
| Binding predictor (XGB, 136k affinities) | Spearman on a **held-out target** | **0.18** (collapse) | 0.736 in-dist |
| Cold-start designability surrogate | AUC, **leave-one-target-out** | **0.44–0.55** (≈ random) | ~0.62 within-target |
| Permeability predictor | R², OOD | **0.19** | 0.45 in-gate |
| cyclic-FT generator | DockQ (in-dist) | — | 0.506 (vs UniMoMo 0.759); plateaued |
| **v3 cyclic-LLM** (n=1 train target) | cross-target transfer | **NULL** | — |
| **v3.1 cyclic-LLM** (n=2 train targets, 3 LOTO folds) | cross-target transfer | **NULL** (all 3 folds; deltas ≪ threshold, validity 0.98–1.0) | within-target: v2 display Δ+0.317 |
| **BoltzGen cyclic FT (ours)** | novel-target LOTO (structure-reuse path) | **PENDING** (`i-0f77b1679c4fbca52`) — the one *same-metric head-to-head* on our data | — |

## Reading (the point the NULL alone misses)
1. **Cross-target generalization is unsolved for everyone.** SOTA's honest ceiling is ~3–8% confirmed
   hit *with* motif-reuse / hotspots; our models land on the **same frontier** — OOD collapse (0.74→0.18),
   cold-start ≈ random, v3/v3.1 NULL. Our NULL is **consistent with the field**, not a unique defect.
2. **So v3.1's NULL confirms the surveyed thesis**, it doesn't contradict our program: "zero-shot novel-
   target is largely illusion" was the survey's finding about SOTA; we reproduced it on our own data with
   a clean, leakage-controlled LOTO. That is a *result*, not a disappointment — it bounds the claim and
   kills any premature "our LLM generalizes across targets."
3. **Where the field (and we) DO have signal is WITHIN-target + closed-loop** — exactly the regime SOTA
   *defers*: joint multi-objective conditional generation on real display data (MVP; v2 Δ+0.317), MO
   selection (qNEHVI +115% HV), within-target designability triage (~43% co-folds saved). That is the
   defensible contribution; cross-target zero-shot is explicitly **out of scope / open frontier for all**.

## Fair-comparison caveats (do not overstate)
- **Units differ.** SOTA's "~3.3% confirmed hit" is wet-lab/structure-confirmed per design; ours are
  in-silico rank/transfer metrics (Spearman, AUC, regressor-scored deltas). These are **directionally**
  comparable (both say cross-target fails/plateaus) but **not** numerically equal — do not write "3.3% vs
  NULL" as if one number.
- **The one clean head-to-head** is the **BoltzGen cyclic FT LOTO** (in flight): same leave-one-target-out
  protocol, same data, structure-reuse SOTA path vs our chemistry-LLM path — that yields a like-for-like
  novel-target datapoint. Expected (per survey) to also plateau; we will report the actual number.
- **Scale caveat** (from v3.1): our NULL is at n=2 training targets / 10M params / composition target
  features. A real attempt at cross-target needs 10s–100s of targets + structure-aware target embeddings;
  SOTA's single-digit hits use far larger structure pretraining. We are not claiming we beat SOTA at
  cross-target — we are showing **nobody has it**, and positioning on the regime that is winnable.

## Bottom line
v3.1 NULL, read against SOTA, means: **cross-target zero-shot cyclic-peptide design is an open
field-wide frontier (SOTA ~3–8% hit with motif-reuse/hotspots; ours NULL/near-random OOD).** The honest,
defensible program is within-target multi-objective + closed-loop (where we show real gains and SOTA
defers), with cross-target as a labeled frontier requiring scale + richer target representations — not a
claim to make today. The BoltzGen-FT LOTO will add the one same-metric SOTA-path comparison on our data.
