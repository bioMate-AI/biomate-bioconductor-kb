# Synthetic multi-omics hospital demonstration

Recovered original synthetic inputs used in the 2026-11-05 validation documented in docs/20261105_SYSUCC_SIM_MULTIOMICS_VALIDATION.md. These contain no hospital patient data.

RNA: 1500 genes × 150 synthetic samples; protein: 400 × 144; methylation: 600 × 145. Rows are features, columns samples. Join on the 139 shared sample IDs. mo_feature_matrix.csv is the historical 139-sample supervised matrix with layer-prefixed features, sample_id and subtype. Drop sample_id from predictors and use subtype only as the label; keep ground_truth.csv out of unsupervised fitting. true_drivers.csv is evaluation truth, never a selected-feature input.

These inputs reproduce the prior fixture identity; no completed run, model, result or clinical performance is imported into a user's project. Launch explicitly and examine actual outputs. provenance.json preserves input SHA256 hashes and the historical storage prefix for auditing. Historical near-perfect synthetic results do not establish real-cohort accuracy.
