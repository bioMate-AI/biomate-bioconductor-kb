# Findings Report — potency predictor

**Run ID:** 727de1b4-5bed-4409-92ca-d7ba10a7f46e

## Summary

potency predictor finished. Key scores: test MAE=0.7920; validation MAE=0.9433; gate pass. Read the Key Results table below (sourced from metrics.json); full artifacts remain in Outputs.

## Key Results

| Metric | Value | Source |
| --- | --- | --- |
| Gate · MAE | 0.9433 | metrics.json |
| Test MAE | 0.7920 | metrics.json |
| Validation MAE | 0.9433 | metrics.json |
| Data split | bemis_murcko_scaffold · train=1211 · val=151 · test=151 | manifest.json |

- **Gate · MAE**: Passed gate (threshold n/a, lower_is_better)
- **Test MAE**: Hold-out test performance (test_mae)
- **Validation MAE**: Validation performance (val_mae)
- **Data split**: Scaffold-aware / holdout separation used for training
