# Downstream guide agreement audit

Evaluated 192 target/donor/condition pairs (16 targets, four donors, three conditions; two guides per target). All metrics exclude the perturbed gene where it occurs in the frozen 132-gene panel. Raw counts are normalized using each profile's full-library UMIs, then natural log1p. Each pair is weighted equally.

| Comparison | Mean Pearson | Mean Spearman | Mean squared difference |
|---|---:|---:|---:|
| Direct normalized perturbed profiles | 0.9733 | 0.9694 | 0.04553 |
| Effects, shared feature control reference | 0.1516 | 0.0989 | 0.04553 |
| Effects, shared reference control reference | 0.1563 | 0.1199 | 0.04553 |
| Effects, disjoint controls, forward assignment | 0.0586 | 0.0350 | 0.05065 |
| Effects, disjoint controls, swapped assignment | 0.0607 | 0.0416 | 0.04972 |

The strong profile agreement is dominated by common gene abundance. It does not establish perturbation-effect reproducibility. Effect agreement drops materially when the guides use different control references. Shared-reference subtraction cancels exactly from guide-to-guide differences, so its MSE necessarily equals the direct-profile MSE; that equality is not evidence of independent effect validation.

The two non-targeting control pools use globally disjoint guide identities. They share donor and condition, so they are not independent biological cohorts. Their mean squared difference is 0.00465; the average squared effect magnitude across guides and reference choices is 0.02746. These are descriptive quantities, not an estimated irreducible noise floor. Unequal guide efficiencies, off-target effects, cell numbers, correlated assay errors, normalization, and response-based eligibility can all contribute to disagreement.

The pilot contains previously outcome-selected targets and metadata-complete guides. Results do not generalize to the full target universe. Both reference orientations are reported to avoid arbitrary assignment bias. No confidence intervals or significance tests treat the 192 dependent rows as independent samples. This comparison does not establish an upper bound for a model trained on aggregated guides.

Implementation checks recompute every saved control aggregate from raw guide counts, enforce exact gene order and globally disjoint control guide identities, require one observation per target/guide/donor/condition, independently check 960 MSE calculations with scalar loops, and verify all 192 shared-reference cancellation identities. Input and evaluator SHA256 hashes are recorded in `results.json`, with per-target, per-donor and individual-pair metrics.

Run: `/opt/homebrew/bin/python3 docs/20260912_s3_continuation/guide_reliability/evaluate.py`.
