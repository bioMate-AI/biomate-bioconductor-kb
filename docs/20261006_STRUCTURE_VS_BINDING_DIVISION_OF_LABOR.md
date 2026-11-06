# Decision: structure = base BoltzGen (use as-is); differentiate on BINDING (conditioning + closed loop)

**Date:** 2026-10-06 · A locked strategic decision from the BoltzGen LOTO smoke + the cross-target
SOTA comparison. Purpose: stop re-litigating where we compete. Supersedes the "fine-tune BoltzGen to
win novel-target design" framing.

## The evidence that forced it (BoltzGen LOTO smoke, run `bgen-loto-smoke-20261006T183036Z`)
Base BoltzGen vs our cyclic fine-tune, 3 held-out targets, head-to-head (`results/boltzgen_loto_smoke_summary.json`):

| target | base iptm / filter-RMSD | ft iptm / filter-RMSD | winner |
|---|---|---|---|
| 1xq7 | 0.470 / 2.29 Å | 0.390 / 2.53 Å | base |
| 3g5v | 0.795 / 1.47 Å | 0.702 / 5.34 Å | base |
| 4b8y | 0.801 / 1.06 Å | 0.492 / 1.77 Å | base |

**Mean Δiptm = −0.16; base wins on all three, on both metrics.** The pipeline was valid (ft ckpt
loaded as `--design_checkpoints`, all 6 arms `ARM_OK`). Two readings, both pointing the same way:
1. **Base BoltzGen is already excellent at cyclic designability** (iptm ~0.8, ~1.0–1.5 Å on 3g5v/4b8y;
   consistent with the prior 1yf4 0.45 Å). Structure is a **solved** sub-problem for us via the open
   weights.
2. **Our brief fine-tune (~229 complexes, 12 epochs, single model vs the base 2-model design ensemble)
   DEGRADED it** — forgetting / under-data. Chasing a structure-FT win is low-marginal: base is already
   near-ceiling, so the headroom is small and we just spent three dead training runs proving it.

## Decision
- **Structure / designability → use base BoltzGen AS-IS.** Do not fine-tune it; do not run the full
  27-target LOTO to re-confirm ft < base. The cyclic fine-tune line is **retired** (kept on S3 for the
  record: `bgen-ft-full-20261006T073802Z/ckpt/finetuned.ckpt`).
- **Binding → our differentiation.** The axis SOTA *defers* (calibrated, display/enrichment-conditioned
  binding selection) is the only place we have a positive signal: **v2 within-target display-enrichment
  conditioning Δ+0.317**. Press there.
- **Winning architecture = composition, not a monolith:** base BoltzGen (or RFpeptides) generates
  cyclic structures → **our cyclic-LLM + display/enrichment conditioning selects/ranks for binding** →
  closed loop (QC/physics verify + the DBTL flywheel). Each part does what the other can't; we do not
  rebuild structure (base owns it) and we do not claim cross-target zero-shot binding (field-wide open).

## What this retires vs presses
- **Retired:** BoltzGen cyclic fine-tune (ft < base); cross-target zero-shot binding chase (shared null,
  per `docs/20261006_CROSS_TARGET_SOTA_COMPARISON.md`).
- **Pressed:** (1) extend v2 display-enrichment conditioning (more targets, held-out-within-target eval,
  honest per-synthesized metric); (2) wire it as the **selector over base-BoltzGen-generated structures**
  (the composition) + the closed-loop verify; (3) keep the moat framing = data + loop + composition, not
  "our model beats SOTA at structure."

## Honest caveats
- The smoke is 3 targets / 4 designs (noisy in absolute terms) — but ft loses on **all three, both
  metrics, by large margins**, and base's strength is independently corroborated (1yf4 0.45 Å). The
  decision is robust to the sample size.
- "ft (single) vs base (2-model ensemble)" is not a perfectly controlled model-count comparison — but
  the *practical* question ("does fine-tuning give better cyclic designs than out-of-the-box?") is
  answered no, and base being near-ceiling makes a controlled re-test low-value.
