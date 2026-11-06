# Implementation audit and downstream-only reevaluation — 12 September 2026

**The checked computations are reproducible. The downstream prediction gate still fails, and guide-level effect agreement is weak in this selected 132-gene panel.** This is not a conclusion about the full transcriptome or all perturbation models.

## Implementation errors fixed

- Metric masks must be boolean. Integer arrays previously triggered NumPy advanced indexing instead of observation masking.
- Unknown ridge variants now raise an error instead of silently behaving as a state model.
- Metric values convert to float64 before subtraction/squaring, preventing intermediate float32 overflow. The earlier stored arrays were already float64; this change does not alter their metrics.
- Control metadata is now bound to the exact source URI, ETag and size. Extraction checks current sparse offsets, gene names and selected row metadata before reading counts and verifies source identity after reading. The target extractor also checks identity before/after reads. A stale metadata cache fails explicitly.
- A downstream-only refit excludes each target's own readout from per-output training, baseline estimation, inner-donor alpha selection, and reported metrics. The earlier evaluation excluded it only in a secondary reported metric; its original design was documented but did not answer this stricter question.
- Early downstream tests caught scikit-learn's single-output prediction shape; explicit reshaping fixed the grouped per-output assignment. Direct-target predictions are saved as NaN with explicit false scoring masks.

The revised metadata planner ran against S3 into a separate cache directory. All 11 old cached arrays match the current bound cache, and the current source ETag/size match recorded count extraction. This is current metadata/object-identity verification, not a retroactive whole-object SHA256 claim. Original counts and caches remain preserved.

## Label reliability

The guide comparison covers 192 target/donor/condition pairs using two guides per target. Effects exclude the directly perturbed readout. Independent control pools are swapped between guides to separate shared-reference noise from apparent agreement.

| Comparison | Mean Pearson |
|---|---:|
| Normalized perturbed expression profiles | 0.9733 |
| Guide effects with shared control reference | 0.1516–0.1563 |
| Guide effects with disjoint control references | 0.0586–0.0607 |

Disjoint-reference Spearman is 0.0350–0.0416. High expression-profile correlation is therefore not evidence of reliable perturbation effects. Reusing a noisy reference increases apparent effect agreement. These comparisons share donors and conditions; they are descriptive checks, not independent-donor confidence intervals or a biological noise ceiling. Frozen readout selection and source efficacy filtering restrict interpretation.

## Downstream-only refit

Same reused 16-target/four-donor development data and four outer donor folds. All three inner donor validations select alpha from 1/10/100. No directly perturbed readout contributes to fitting or selection. This is a new development protocol, not independent confirmation on an untouched test set.

| Method | Equal-donor downstream MSE | Downstream Spearman |
|---|---:|---:|
| No change | 0.015534 | undefined |
| Condition mean | 0.016095 | 0.059239 |
| Target/condition mean | 0.018534 | 0.061843 |
| Target/condition ridge | 0.015821 | 0.069905 |
| Baseline-state ridge | 0.016501 | 0.060215 |
| Shuffled-state ridge | 0.016974 | 0.057995 |

No-change still has lower MSE than every learned arm; adding baseline state still makes the matched model worse. The refit does not rescue downstream prediction.

## Verification

- **86 integrated module/evaluator tests plus 2 source-binding tests passed.**
- Adversarial tests changing every directly perturbed outcome by 1e9 left downstream predictions, baselines, hyperparameter selections and reports unchanged.
- The hardened original evaluator reproduced all 34 prior saved arrays exactly.
- Independent weighted normal-equation reconstruction verified all **120 ridge fits**, every baseline and alpha grid, all masks and metric summaries. Maximum prediction difference: **2.11e-15**.
- Guide reliability checks independently reconstructed 1,920 correlations, checked 960 scalar MSE values and 192 reference-cancellation identities.

Evidence is under `/Users/kky/biomate-review/docs/20260912_s3_continuation/`: `implementation_detail_audit.md`, `implementation_checked_extract/`, `guide_reliability/`, and `downstream_only_evaluation/`. Updated source and tests are installed in the immune training worktree. Raw artifacts and source snapshots are copied to `/Users/kky/biomate-audit-fix/out/20260912_implementation_downstream_audit/`.

## Next work

Before larger training, improve the assay/readout signal test: evaluate more guides and control support, and broaden readout coverage using a frozen external panel or training-only selection. The current 132-gene panel may miss responsive genes. Keep guide/run composition and successful-perturbation filtering explicit. Only then expand target validation and test state interactions. Do not interpret a larger model or more repeated fits as a substitute for reliable labels and new donor evidence.
