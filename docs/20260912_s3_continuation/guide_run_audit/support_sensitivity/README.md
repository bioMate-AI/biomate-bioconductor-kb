# Predefined guide cell-support sensitivity

Both guide profiles must meet each cell threshold in a target/donor/condition group. All thresholds were specified before this sensitivity run; none is selected as a preferred analysis. Controls and readout definitions remain unchanged. All directly perturbed readouts are excluded.

| Minimum cells per guide | Pairs | Targets | Donors | Conditions | Targets covering all 12 groups |
|---|---:|---:|---:|---:|---:|
| Unfiltered | 192 | 16 | 4 | 3 | 16 |
| 10 | 182 | 16 | 4 | 3 | 10 |
| 25 | 128 | 16 | 4 | 3 | 1 |
| 50 | 71 | 15 | 4 | 3 | 0 |
| 100 | 24 | 9 | 4 | 3 | 0 |

## all_genes (18,129 genes before target exclusion)

| Minimum cells | Pearson forward | Pearson swapped | Spearman forward | Spearman swapped |
|---|---:|---:|---:|---:|
| Unfiltered | 0.003079 | 0.009523 | 0.014965 | 0.020037 |
| 10 | 0.001803 | 0.008346 | 0.013393 | 0.018628 |
| 25 | -0.001214 | 0.006812 | 0.007160 | 0.014269 |
| 50 | -0.017529 | -0.006147 | -0.005902 | 0.003683 |
| 100 | -0.078723 | -0.046219 | -0.040522 | -0.017078 |

## control_expressed (10,729 genes before target exclusion)

| Minimum cells | Pearson forward | Pearson swapped | Spearman forward | Spearman swapped |
|---|---:|---:|---:|---:|
| Unfiltered | 0.002777 | 0.009171 | -0.000434 | 0.005893 |
| 10 | 0.001557 | 0.008047 | -0.001621 | 0.004912 |
| 25 | -0.001434 | 0.006609 | -0.005171 | 0.003512 |
| 50 | -0.017646 | -0.006239 | -0.016026 | -0.004512 |
| 100 | -0.078510 | -0.046146 | -0.056511 | -0.028302 |

Increasing the minimum cell requirement does not reveal strong positive guide agreement in this subset. It sharply changes target and donor composition; differences between rows cannot be attributed causally to cell support. At 100 cells only 24 pairs across 9 targets remain; none of the targets covers all 12 donor/condition groups.

The control-expressed panel uses CPM ≥1 in at least 6 of 12 pooled-control donor/condition groups, using all donors descriptively. These are dependent observations from the same outcome-selected 16-target development subset, with disjoint guide reference pools rather than independent biological cohorts. No confidence intervals or significance claims are made.

All target/donor/condition coverage counts and pair eligibility are saved in results.json. Independent verification rebuilt normalization and 1,536 correlations from raw target/control arrays using SciPy correlation functions; checked 4,776 filtered metric entries, all coverage counts, and 40 summary means. Verification uses the exact division-then-multiplication normalization order because floating-point order can perturb tied Spearman ranks.
