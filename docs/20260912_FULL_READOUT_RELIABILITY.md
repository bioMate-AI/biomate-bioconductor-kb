# Full-readout guide reliability — 12 September 2026

## Result

Expanding the frozen pilot from 132 to all 18,129 source genes did not recover reproducible downstream guide effects. This weakens the narrow-readout-panel explanation for the previous failed model gate; it does not establish a cause or condemn the whole source dataset.

| Readout panel | Genes before target exclusion | Mean disjoint-reference Pearson, two orientations | Mean disjoint-reference Spearman, two orientations |
|---|---:|---:|---:|
| Original frozen panel | 132 | 0.05856 / 0.06074 | 0.03504 / 0.04155 |
| All source genes | 18,129 | 0.00308 / 0.00952 | 0.01496 / 0.02004 |
| Control-expressed sensitivity panel | 10,729 | 0.00278 / 0.00917 | -0.00043 / 0.00589 |

These are means across 192 dependent target/donor/condition guide pairs. The two orientations swap the disjoint reference pools; they are not separate replications. Directly perturbed gene symbols are excluded from every panel.

All-gene disjoint-reference Pearson by condition: Rest -0.0125/-0.0081; Stim8hr 0.0052/0.0148; Stim48hr 0.0165/0.0219. No condition shows strong mean downstream agreement. Shared-reference all-gene Pearson remains higher, 0.07465/0.08841, consistent with shared reference noise inflating apparent agreement. Overall expression-profile Pearson remains 0.97389 and must not be interpreted as reliable perturbation effects.

## Data and integrity

Read all gene counts for the same 384 targeting and 348 control profiles, retaining the original 16 targets, two guides each, four donors and three conditions. No new outcomes were used to select rows. Sparse logical payload estimate: 124,938,032 bytes; compressed local arrays: 15,894,847 bytes. This is not a full 44.6 GB download or measured network-traffic accounting.

Checks passed for frozen row metadata, unique sparse indices, nonnegative finite integer counts, exact full-library sums, exact original 132-gene counts, and source ETag/size before/after reads. ETag/size is object-identity verification, not a whole-object SHA. Local artifacts have SHA256 hashes. The original 132-gene metric summaries reproduce within numerical tolerance.

The control-expressed panel requires pooled-control CPM >=1 in at least six of twelve donor/condition groups. It uses all donors and is only a descriptive sensitivity analysis, not a panel suitable for held-out training evaluation. It can favor condition-specific genes. All-gene correlations are sensitive to low counts and ties; the expressed-panel result addresses part of that concern. MSE magnitudes across panels are not comparable measures of improved performance.

## Guide support

The lower-supported guide per pair has median 35 cells, range 5–339. The within-pair cell-count ratio has median 2.32 and maximum 58.43. In the original132 panel, this imbalance has descriptive Spearman -0.219 with disjoint-reference guide agreement; minimum cells alone has Spearman -0.045. These dependent and confounded associations do not identify the source of noise or justify filtering labels after seeing agreement.

## Decision and next experiment

Do not promote the model or increase model size on the strength of this experiment. No new predictor was trained here; the prior downstream model gate remains failed.

Next, audit guide/run composition and perturbation efficacy before expanding training:

1. Inventory all guides for the frozen targets using basic cell/count QC, separately recording efficacy-based exclusions. Determine whether more than two guides exist and whether run-level aggregates obscure replicate structure.
2. Check direct-target knockdown and consistency across guides as a diagnostic, keeping that readout excluded from downstream evaluation. Avoid selecting successful guides on held-out outcomes.
3. Predefine a higher-support sensitivity protocol and a training-only gene-selection rule. Report coverage lost and retain the unfiltered comparison; do not optimize thresholds on the final score.
4. Require independent donor or dataset replication before claiming generalization. More genes and repeated fits within these four donors do not increase independent biological sample size.

Raw arrays, scripts, source manifest, guide-support diagnostics and detailed results are in `docs/20260912_s3_continuation/full_readout_reliability/` in the review worktree. Independent numerical verification is recorded separately in that directory.

## Independent verification and direct-target diagnostic

Independent implementation reconstructed 8,640 row-level metrics and 315 donor/condition summaries plus overall means; maximum absolute difference 5.75e-14. The verifier preserves exact normalization operation order because floating-point tie breaking can slightly change rank correlations. It uses independent centered-dot-product Pearson, rank Pearson and MSE calculations.

A subsequent diagnostic found lower directly targeted normalized expression than both references in 364 of 380 profiles with both references measurable (384 profiles total). Median target-to-control ratios were 0.1490 and 0.1470 for the two reference pools. Four zero-control ratios remain undefined, without a pseudocount. An initial assertion that every reference was positive failed; explicit missing-ratio handling corrected that invalid assumption before producing results. These relative-abundance measurements are consistent with intended target reduction in many selected profiles, not causal efficacy estimates, significance tests or proof of reliable downstream responses. No profiles were filtered using this diagnostic. Step2 above has this initial diagnostic completed; run/guide composition and independent replication remain outstanding.
