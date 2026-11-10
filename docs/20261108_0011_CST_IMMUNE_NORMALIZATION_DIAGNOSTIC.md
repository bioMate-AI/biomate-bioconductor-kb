> Interpretation update (2026-11-08): a missing CP10k transform and omitted derived knowledge channel were identified. Numbers below remain historical pipeline results; see [20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md](20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md) before interpreting representation quality.

# Immune transfer: normalization diagnostic

Recorded: 2026-11-08T00:11:23.284734-06:00

## Finding

Fitting normalization on all outer-training features modestly improved both pretrained and scratch models. It did not reverse the pretrained model's low-label deficit. With matched optimizer updates, pretrained mean AUPRC increased from 0.7934 to 0.8059; scratch increased from 0.8183 to 0.8273. The scratch-minus-pretrained gap decreased slightly, from 0.0248 to 0.0214. This diagnostic provides no evidence that labelled-subset normalization is the main explanation for the remaining gap. It does not test compatibility with the exact original pretraining transform.

## Protocol

RNA only; GSE261278 D534, 15,000 cells; 10% labelled cells per training fold; three cell-type-disjoint folds; seeds 0/1/2; pretrained and scratch arms. Same labels, indices, seed handling, architecture, learning rate (3e-4), batch size (256), and update endpoints as the prior diagnostic. The only intended intervention is the set of feature rows used to estimate each gene's mean and standard deviation.

New normalization uses every outer-training cell's features, but no extra labels; it excludes all outer-held-out cells. This grants additional unlabelled training-data access and must be reported as such. Both models receive the same access. Endpoints remain 48 updates versus 468–480 updates, with no best-endpoint selection. No hyperparameter tuning or inner-validation selection was performed in this diagnostic.

| Normalization | Arm | Schedule | AUROC | AUPRC |
|---|---|---|---:|---:|
| labelled-only | pretrained | fixed_epochs | 0.9124 ± 0.0517 | 0.7486 ± 0.1310 |
| labelled-only | pretrained | matched_full_label_updates | 0.9305 ± 0.0241 | 0.7934 ± 0.0692 |
| labelled-only | scratch | fixed_epochs | 0.9448 ± 0.0081 | 0.8302 ± 0.0123 |
| labelled-only | scratch | matched_full_label_updates | 0.9392 ± 0.0100 | 0.8183 ± 0.0198 |
| all-training-features | pretrained | fixed_epochs | 0.9177 ± 0.0481 | 0.7634 ± 0.1266 |
| all-training-features | pretrained | matched_full_label_updates | 0.9318 ± 0.0261 | 0.8059 ± 0.0622 |
| all-training-features | scratch | fixed_epochs | 0.9486 ± 0.0098 | 0.8423 ± 0.0171 |
| all-training-features | scratch | matched_full_label_updates | 0.9421 ± 0.0086 | 0.8273 ± 0.0140 |

Values are means ± sample standard deviations over three seeds, not confidence intervals or significance tests. The outer splits have already been inspected: these are exploratory results. They are not donor-held-out or independent-cohort validation, and pretraining overlap remains unresolved.

## Validation and resources

All prior labelled and test indices match exactly. Normalization-fit indices are disjoint from held-out cells and contain the designated labelled cells. Labels and group arrays match the prior run. All 12 output prediction arrays contain 15,000 finite probabilities. Saved artifacts include per-fold normalization means/scales, exact indices, metrics and the executable diagnostic script.

Runtime 99.8 seconds; maximum process RSS 2.23 GiB; CUDA allocated peak 135.2 MiB, reserved peak 166.0 MiB. Container exit 0, OOMKilled=false, 12 GiB cap, two CPUs, one GPU job. These bounds apply to this task, not full-corpus training.

## Updated decision and next work

The update-count intervention had a larger effect than the normalization intervention in these runs. Neither removed the deficit. Retain both protocol choices explicitly; do not quietly replace historical results with the more favorable protocol.

Next prioritize converged frozen-embedding and raw-feature regularized logistic probes using matched training labels and outer folds. Check convergence rather than using a short neural-head fit as the representation-quality test. Follow with inner-group-validation selection of encoder/head learning rates and gradual unfreezing if justified. Give scratch and pretrained models comparable selection budgets. Keep preprocessing fit inside the appropriate inner training split during tuning.

Only after those controls should we attribute failure to the pretraining objective or change large-scale training. Freeze the selected protocol before independent functional replication. Continue auditing data provenance and pretraining overlap in parallel with these methodological checks; this document does not claim that work is complete.

Artifacts: `20261108_normalization_diagnostic/`. Baseline: `20261107_spark_immune_status/update_count_diagnostic/`. Research model checkpoint remains unchanged.
