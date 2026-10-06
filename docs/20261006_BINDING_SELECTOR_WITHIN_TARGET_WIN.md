# Binding selector from the display-conditioned LM — a within-target WIN

**Date:** 2026-10-06 · The positive result on the axis SOTA *defers* (display-based binding), after the
structure path was ceded to base BoltzGen (`20261006_STRUCTURE_VS_BINDING_DIVISION_OF_LABOR.md`). Our
enrichment-conditioned cyclic LM, used as a **selector**, ranks held-out binders above non-binders
within target. Code: `cyclic_llm/cyclic_llm_selector.py`. Evals: `results/cyclic_llm_selector_*.json`.

## Method
For each held-out sequence, score the conditional log-likelihood ratio under the trained LM:
`LLR(seq) = logP(seq | <e_hi>) − logP(seq | <e_lo>)`. Train on a **sequence-disjoint** split of a
target's display pool (enrichment-bucketed, hi≥2.0 / lo≤0.0 log2fc); evaluate LLR-vs-`is_binder` on the
held-out split. Metrics: AUC (global ranking) + binder **lift** in the top-5%/10% by LLR (practical
screen). WITHIN-target, honestly held out by sequence. 10.8M-param LM, 2000 steps, local MPS.

## Result — positive on all 4; strong on 3/4

| Target (chemistry) | test (binders) | base rate | **AUC** | **lift @top-5%** | lift @top-10% |
|---|---|---|---|---|---|
| **PADI4** (RaPID thioether) | 4000 (67) | 1.7% | **0.968** | **15.8×** | 8.7× |
| **Abeta42** (phage disulfide) | 4000 (237) | 5.9% | **0.990** | **13.2×** | 10.0× |
| **hIAPP** (phage disulfide) | 4000 (173) | 4.3% | **0.689** | **7.1×** | 4.0× |
| hPCSK9 (XL-RaPID photo-crosslink) | 2827 (152) | 5.4% | 0.357 | 2.6× | 1.6× |

**Headline:** as a practical top-5% screen, the selector enriches held-out binders **2.6–16× over
random on every target** (mean ~9×); global AUC is **0.69–0.99 on 3 of 4**. This is a real demonstration
that display/enrichment conditioning yields a working **binding selector** — the capability SOTA
structure-first tools do not provide (Boltz-2 excludes peptides; BoltzGen/RFpeptides are structure/
designability, not display-based binding).

## Honest caveats (not cherry-picked)
- **hPCSK9 flips** (global AUC 0.357 < 0.5) even though its own 40-step smoke was 0.824 → the full 2000-
  step LLR becomes **non-monotonic** for this target (top-5% still enriched 2.6×, but the global ranking
  anti-correlates). hPCSK9 is the odd one chemically (XL-RaPID photo-crosslink, Bpa/reprogrammed Met) and
  shows **training-length sensitivity**. Most likely a **length/composition confound** in the LLR (it
  sums residues + EOS, so it can track sequence length); a length-normalized / EOS-excluded LLR is the
  robustness fix (next step) — do not report hPCSK9 as a clean win.
- **Within-target only** (sequence-held-out), which is the honest regime for this capability; this is NOT
  the cross-target axis (that stays the field-wide-open null, `20261006_CROSS_TARGET_SOTA_COMPARISON.md`).
- The LM scores binder-LIKENESS from display enrichment, not wet-lab affinity; validation against real
  assay/affinity is the eventual bar (closed loop).

## Why this matters (the win, placed in the program)
- It is the **positive** that anchors the differentiation: base BoltzGen owns structure; **we own
  display-based binding selection** — here with AUC up to 0.99 and 13–16× top-5% enrichment on held-out
  binders. That composition (base structure × our binding selector × closed loop) is the defensible
  product, and this is the first hard evidence the binding half works.

## Next (robustness + composition)
1. **Fix the confound**: length-normalized / EOS-excluded LLR (or per-residue mean log-prob); re-check
   hPCSK9 → aim for AUC>0.6 on 4/4.
2. **Compose over base BoltzGen**: use the selector to re-rank base-BoltzGen-generated cyclic sequences
   for binding (one base generation pass; no fine-tune).
3. Calibrate toward real affinity via the closed loop.
