# Cyclic-LLM v3.1 — multi-target cross-target generalization: NULL (deeper than n=1)

**Date:** 2026-10-06 · Tests whether making the target-feature prefix **vary** during training
(n≥2 training targets) unlocks the cross-target generalization that v3 could not (v3 used n=1 →
constant prefix → zero gradient → NULL by construction). Code: `cyclic_llm/train_cyclic_llm_v3_1.py`.
Evals: `results/cyclic_llm_v3_1_{hPCSK9,PADI4,FIKK13}_eval.json`.

## Design
Leave-one-target-out over the **3 mRNA-display RaPID targets** in `display_ngs_multitarget` — the
only same-display-**platform** trio we have (no new harvest): PADI4, hPCSK9, FIKK13. Each fold trains
on 2 targets with a **per-record target prefix** (each row carries its own target's 24-d feature
vector, so the prefix genuinely varies → a real gradient to learn "target → binder"), holds out the
3rd, and asks: does conditioning on the **held-out** target's features produce more held-out-binder-like
peptides than conditioning on the **mean of the training** targets? Scored by a held-out-target
enrichment regressor (RF on the held-out rows) + identity to the held-out target's own binders.
Same architecture as v3 (10.8M char-GPT, 3000 steps, local MPS).

## Result — NULL in all 3 folds

| Held-out | Train (chem) | enr-cond (hi−lo) | target-transfer (heldout−trainmean) | identΔ | validity | Verdict |
|---|---|---|---|---|---|---|
| **hPCSK9** | PADI4+FIKK13 (both thioether) | −0.119 | +0.026 | −0.002 | 0.985 | **NULL** |
| **PADI4** | hPCSK9+FIKK13 (mixed) | −0.014 | +0.013 | +0.008 | 0.995 | **NULL** |
| **FIKK13** | PADI4+hPCSK9 (mixed) | +0.034 | +0.022 | −0.004 | 0.998 | **NULL** |

Signal thresholds (from the eval): transfer needs pred-enr delta **> 0.10** AND an identity delta
**> 0.02**; target-features-matter needs |pred-enr delta| **> 0.2**. Every fold is an order of
magnitude below. Validity is excellent (0.98–1.0), so the model trains fine — it simply does not use
the (varying) target features to generalize to a new target. Even the **enrichment** conditioning
(hi vs lo) is ≈0 / negative **on the held-out regressor** — the "hi" generations are not enriched-like
*for a target the model never saw binders for* (within-target, v2 showed enrichment conditioning does
work, Δ+0.317 — the difference here is strictly the held-out target).

## Interpretation (the honest, publishable finding)
- **v3 (n=1):** NULL — explained away as a degenerate constant prefix.
- **v3.1 (n=2, varying prefix):** **still NULL.** So cross-target transfer is **not** unlocked merely
  by giving the prefix a gradient. At this scale (10M params, 2 training targets, display-enrichment
  labels, composition-based target features) the model learns **target-specific memorization**, not a
  generalizable target→binder function. The data wall is **deeper than target count.**
- This **bounds the claim hard**: do not assert "our LLM generalizes across targets." The defensible
  contribution stays the *within-target* results (MVP joint conditioning; v2 display-enrichment
  Δ+0.317) + the closed-loop system, not cross-target zero-shot.

## Caveats
- **Cyclization confound** (co-varies with target: PADI4/FIKK13 thioether, hPCSK9 photo-crosslink).
  It does not threaten a NULL (a confound could only manufacture a false *positive*); it would matter
  only if a fold had shown transfer. The cleanest fold (hPCSK9 held out, trained on 2 thioether
  targets) is also NULL.
- **n=2 is still small.** A true test of "transfer needs scale" wants **10s–100s of targets** and/or
  **structure-aware target features** (pocket embedding, not AA-composition). That is the next data +
  representation step, not a within-reach tweak.

## Next
- Headline stays our-own-LLM **within-target** (validated) + closed loop; cross-target is an open,
  honestly-bounded frontier requiring many targets + richer target features.
- If cross-target is pursued: harvest ≥10 same-chemistry display targets and swap the 24-d composition
  descriptor for a learned target-pocket embedding; re-run this exact LOTO harness.
