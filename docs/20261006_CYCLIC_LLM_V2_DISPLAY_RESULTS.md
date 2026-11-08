# Cyclic-LLM v2 — Enrichment-Conditioned Generation from Display-NGS (results)

**Date:** 2026-10-06 · The innovation-thesis core test: can display-selection ENRICHMENT (not a
docking/structure proxy) be the PRIMARY signal for conditional cyclic-peptide generation? Trained on
the harvested PADI4 RaPID mRNA-display dataset (370,806 unique peptides × 5 rounds), conditioned on the
terminal-round enrichment bucket (log2fc_R6_vs_R2). Small GPT over the variable AA sequence (the
macrocyclization scaffold — ClAc initiator + Cys thioether — is constant across the library).

## Result: YES, learnable — but ONLY when the buckets isolate the rare binder tail
| Condition | hi bucket | Δ pred-enrichment (hi−lo) | Δ identity-to-top-binder | verdict |
|---|---|---|---|---|
| Smoke (binder-enriched head subset) | q90=2.81 | +0.27 | +0.052 | works |
| Full, **quantile** buckets | q90=**0.0** | **+0.066** | +0.014 | **fails** |
| Full, **binder-threshold** (hi>2, 4× oversample) | 2,445 strong binders | **+0.317** | +0.045 | **works** |

Full binder-threshold eval (400 samples/condition): validity **0.988**, novelty **0.995**, unique 1.0,
exact-top-binder-copy 0.0 (not memorizing); enriched-kmer recovery hi 0.034 vs lo 0.009 (Δ+0.025).
All four verdicts TRUE.

## Honest interpretation
- **Display-enrichment IS a learnable primary binding signal for conditional generation** — conditioning
  on "high enrichment" produces measurably more binder-like sequences than "low," by an independent
  held-out enrichment regressor and by similarity to the validated binder family.
- **The quantile failure was a bucketing artifact, not a true negative.** The full distribution's median
  log2fc is −0.28 and q90 is 0.0 (selection kills most peptides), so quantile "hi" lumped marginal
  survivors with the rare strong binders and diluted the signal (+0.066). Thresholding to the real binder
  tail (log2fc>2, ~2.4k of 371k) + oversampling recovered strong conditioning (+0.317, ~4.8× stronger).
  **Lesson: with display data, bucket by the enriched tail, not quantiles.**

## Caveats (not hidden)
- **In-silico only:** conditioning is scored by a held-out AA-composition RF regressor, not wet-lab.
- **Single target (PADI4):** this proves the display signal is LEARNABLE, NOT multi-target generalization.
- Binder-family *identity* recovery is modest (+0.045); the strong, robust signal is predicted-enrichment
  (+0.317). The model learns "more enriched-like," not "copy the top binder" (0 copies).
- AA-sequence MVP: the fixed macrocyclization scaffold is metadata, not generated (v3 = HELM/monomer for
  arbitrary ncAA/cyclization + multi-target display pools + close the loop with real assay readouts).

## Artifacts
- Code: `research/guangzhou_all_atom/cyclic_llm/train_cyclic_llm_v2.py` + `launch_cyclic_llm_v2.sh`
- Checkpoint: `s3://knowledge-datasets-1759951976/cyclic_peptide/runs/cyclic-llm-v2-full-20261006T000253Z/ckpt/cyclic_llm_v2.pt`
- Data: `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/display_ngs_padi4_rapid/`
