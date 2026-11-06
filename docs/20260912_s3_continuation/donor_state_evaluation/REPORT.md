# Baseline-state donor-transfer pilot — 12 September 2026

Adding control baseline state did not improve the matched target/condition ridge predictor in this pilot. The biological baseline-state benefit gate remains unmet.

The evaluation used 384 targeting pseudobulk profiles (16 targets, two guides each, four donors and three conditions), aggregated into 192 target/donor/condition labels. A separate 348-profile non-targeting sample supplies guide-disjoint feature and reference control pools. Counts and full-transcriptome library denominators were validated; all control aggregates were recomputed exactly, and control/target source rows and guide identities were disjoint.

Labels are differences of library-normalized log1p pseudobulk expression, not the publication’s DE log fold changes. Perturbed profiles enter labels only. Feature-state inputs use the feature control pool; reference controls define the label reference. Targets passed the source eligibility/efficacy filters; this is a selected development panel.

Four outer leave-one-donor-out folds each used all three possible inner donor validations to choose ridge alpha from 1, 10 and 100. Scaling and fits used training donors only. There were 120 small ridge fits including inner selection; they are not 120 independent experiments. All test target/condition combinations were observed in outer training.

| Method | MSE, all genes | Spearman, all genes | MSE, excluding perturbed gene | Spearman, excluding perturbed gene |
|---|---:|---:|---:|---:|
| no_change | 0.022864 | undefined | 0.015534 | undefined |
| condition_mean | 0.023134 | 0.057817 | 0.016528 | 0.048146 |
| target_condition_mean | 0.018980 | 0.080567 | 0.018534 | 0.061843 |
| target_condition | 0.017503 | 0.082250 | 0.016170 | 0.064076 |
| baseline_state | 0.018195 | 0.072590 | 0.016854 | 0.054302 |
| shuffled_state | 0.018681 | 0.071019 | 0.017324 | 0.052681 |

Values average donors equally. Zero-change predictions have undefined Spearman; no zero correlation was substituted. The target-excluded metrics are secondary: alpha selection used all-readout MSE, including the directly perturbed gene.

| Held-out donor | Target/condition ridge MSE | State ridge MSE | Shuffled-state MSE | State alpha |
|---|---:|---:|---:|---:|
| CE0006864 | 0.014394 | 0.015152 | 0.016100 | 100 |
| CE0008162 | 0.013915 | 0.014645 | 0.014141 | 100 |
| CE0008678 | 0.019568 | 0.020540 | 0.021619 | 100 |
| CE0010866 | 0.022135 | 0.022442 | 0.022862 | 10 |

State ridge MSE is worse on the equal-donor average than the matched target/condition ridge. Removing the directly perturbed gene leaves the no-change MSE lower than every learned arm. A small advantage over one fixed grouped state shuffle does not establish a state benefit when the simpler matched model performs better.

Verification: 11 synthetic contract/split/scaling tests passed. Independent verification reconstructed all 192 labels and feature states from saved raw selected counts, recomputed 48 metric comparisons with a separate rank-correlation implementation, and checked all four outer and 12 inner donor splits. Fitted ridge objects were not saved; predictions, hyperparameter tables and exact split indices were saved.

During input validation, the original target archive was rejected for five object-dtype metadata arrays before fitting. The extraction writer and metadata were repaired to native strings; numeric archive members were unchanged and the repair manifest retains old/new hashes. Results reference the repaired input hash.

Limits: four donors provide only 12 distinct donor-condition control states; thousands of profiles or genes do not increase biological donor replication. The donor-shuffle arm uses one fixed derangement per training donor set, not a permutation confidence interval. Donor/run and guide abundance can influence summed pseudobulks. The 16-target panel and source efficacy eligibility restrict generalization. No unseen-target, clinical, causal or full machinery validation is claimed.

Next: preserve this negative baseline-state result, diagnose control-versus-control noise and guide/run effects before larger neural training, and evaluate additional prespecified targets with stronger donor coverage.
