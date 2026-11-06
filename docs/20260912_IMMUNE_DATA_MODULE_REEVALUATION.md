# Immune data/module correction and reevaluation — 12 September 2026

**Result: missingness, baseline comparison, and archive interoperability are corrected. The re-evaluated perturbation head still does not show meaningful predictive value beyond its matched controls. No production promotion.**

## Corrections applied

1. **Missing effects:** the CZI loader no longer imputes untestable effects as zero. Default callers reject missingness with a specific error; observation-aware callers explicitly request `missing_policy="mask"`, receive `Y_observed`, and retain NaN in `Y_delta`. Infinity is rejected. The HDF5 handle closes on success and failure. The ERM/IRM and baseline entrypoints are migrated. The unmigrated target-selection/p1b entrypoints now fail explicitly on missing data rather than generating silently biased output; full migration of those workflows remains outstanding.
2. **Training/scoring:** only observed effects contribute loss or gradients. Entirely unobserved training rows and condition groups are skipped. Readouts eligible for scoring are determined from training observations. Baseline means exclude missing entries, with a training-only pooled fallback where a condition lacks a readout. True zero effects remain observations.
3. **ERM/IRM comparison:** both arms now use equal weighting across observed culture-condition groups. Previously ERM used pooled MSE while IRM used an average of condition risks, confounding the penalty comparison. IRM now differs by its penalty. This is not held-out-condition validation: culture conditions occur in both folds.
4. **Baseline gate:** removed the hardcoded 0.069/0.060 comparison and silent historical-floor fallback. Every baseline is recomputed on the same current labels, seed, target split and readout eligibility. `--floor-json` now rejects obsolete external-floor usage. A numeric advantage alone is not a scientific gate.
5. **Data archives:** repaired all 15 first-pilot external prediction archives into a versioned directory. IDs are native Unicode. Every field loads with `allow_pickle=False`; every non-ID NPY member is byte-for-byte unchanged. Originals remain untouched. A narrowly restricted reader was used only for the known local legacy string-array metadata; it is not a general unrestricted pickle loader.

## Real-data reevaluation

Used the existing **331 contrasts, 117 targets, 132 readouts** extracted from CZI DE statistics. This is a reused development subset, not a newly acquired or donor-independent test set. It contains zero missing entries; missing-value correctness is therefore exercised by separate regression and HDF5/CLI fixtures, not claimed as a performance improvement on this subset.

Nine configurations: ERM, IRM, and within-condition shuffled-training-label ERM, each at seeds 0–2. Fixed 100 epochs, 32-dimensional gene embeddings, 64-dimensional hidden layer, target-held-out test fraction 0.3. No test-based epoch selection. All conditions of a target stay together. These splits differ from the earlier frozen-projection H1 pilot, so its .0319/.0533 scores are not a direct before/after comparison.

| Predictor | Pooled row Spearman, independently recomputed |
|---|---:|
| Training-condition mean | 0.05666479 |
| ERM | 0.05663811 |
| IRM | 0.05663785 |
| Shuffled-training-label ERM | 0.05648227 |

Differences are negligible. IRM adds no demonstrated benefit; shuffled labels are competitive. The head appears to reproduce much of the condition-mean signal. This is evidence against promoting this target/condition-only design on the present data, not evidence that perturbation modeling generally cannot work.

These are row-pooled development metrics, with targets overlapping across seeds; they do not provide independent cohort confidence intervals. Both label observations and split membership were checked against the source prepared arrays. All nine checkpoints reproduced their saved predictions after reload. The nine configurations were rerun once after final guard changes; numeric outputs matched. Only the final nine are retained as the canonical new experiment, not counted as eighteen independent experiments.

## Validation and artifacts

The regression suite contains **61 passing tests**, including an actual HDF5 missing-effect fixture and a subprocess test of the corrected legacy ERM/IRM CLI. Synthetic fixtures verify behavior only; the table above uses real deposited effects.

- Corrected source: `/Users/kky/biomate-audit-fix/research/immune_llm_baseline/`
- Canonical new fit artifacts, checkpoints, protocol and training source snapshots: `/Users/kky/biomate-audit-fix/out/20260912_perturbation_reevaluation/`
- Repaired external prediction archives: `/Users/kky/biomate-audit-fix/out/20260912_prediction_metadata_repair/`
- Report-side evidence and independent verification script: `20260912_immune_reevaluation/`

The archive migration log records its original temporary creation paths; the versioned durable directory above contains identical files. No original predictions or historical metrics were overwritten. The earlier 57-run audit remains historical evidence. No new ATAC donor-transfer or H4 scientific validation is claimed by this reevaluation.

## Remaining scientific work

The next substantive H1 step requires baseline cell-state information, rather than more tuning of target and condition inputs against this reused test subset. Preserve the negative gate. Separately, obtain common-interval ATAC fragment counts for donor transfer; do not zero-fill incompatible peak sets. H4 still requires a raw-label/censoring audit and a clear distinction between prospective prediction and prediction given measured post-perturbation proteomics.

These are outstanding modeling/data requirements. The corrected code and successful execution checks do not fulfill them automatically.
