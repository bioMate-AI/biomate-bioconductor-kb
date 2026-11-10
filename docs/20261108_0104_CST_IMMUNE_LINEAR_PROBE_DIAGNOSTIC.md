> Interpretation update (2026-11-08): a missing CP10k transform and omitted derived knowledge channel were identified. Numbers below remain historical pipeline results; see [20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md](20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md) before interpreting representation quality.

# Immune transfer: converged linear probes

Recorded: 2026-11-08T01:04:01.175242-06:00

## Finding

Raw RNA outperformed frozen pretrained embeddings at every matched regularization setting tested for stimulation prediction. Thus the prior weak frozen-neural-head result cannot be explained solely by its short optimization schedule. This is evidence against deployment of this checkpoint as a frozen feature extractor for this endpoint under the tested input/missing-modality protocol. It does not establish that pretraining erased all stimulation information, that nonlinear readouts cannot recover it, or that other immune tasks will fail.

## Protocol

Same GSE261278 D534 data, 15,000 cells, 10% labels, three held-out-cell-type folds and seeds 0/1/2. Exact saved labelled/test indices reused from the normalization experiment. Encoder inputs normalized on all outer-training feature rows; held-out rows excluded. RNA only; auxiliary knowledge/protein/ATAC/genetics/TCR inputs absent, as in the preceding transfer experiments. Classifier feature standardization fitted on labelled rows only for every arm. This second standardization effectively restandardizes raw RNA on labelled rows; it operates on representation coordinates for embedding arms. Interpret this as a standard linear-readout benchmark, not a pure replay of neural-head optimization.

Features: raw RNA (2,000 dimensions), frozen pretrained z, and frozen randomly initialized z (same checkpoint-reconstructed architecture). The random encoder is an architecture/initialization control, not a trained scratch model or PCA-matched control. Checkpoint reconstruction initializes some architecture-specific components from zero placeholders; do not call this an independently designed generic random-projection baseline.

Logistic regression: balanced class weights, L-BFGS, tolerance 1e-6, maximum 2,000 iterations. Fixed C grid 0.01, 0.1, 1, 10. Reference C=1 registered in protocol.json. No selection using outer-fold scores; the entire grid is reported. Seeds change labelled subset selection (and random encoder initialization); the pretrained encoder weights are fixed. Seed variation must not be described as three independent pretrained models.

## Results

| Features | C | AUROC | AUPRC |
|---|---:|---:|---:|
| raw | 0.01 | 0.9466 ± 0.0020 | 0.8508 ± 0.0158 |
| raw | 0.1 | 0.9454 ± 0.0021 | 0.8450 ± 0.0199 |
| raw | 1.0 | 0.9444 ± 0.0028 | 0.8405 ± 0.0228 |
| raw | 10.0 | 0.9437 ± 0.0034 | 0.8369 ± 0.0245 |
| pretrained_z | 0.01 | 0.8154 ± 0.1368 | 0.6386 ± 0.1611 |
| pretrained_z | 0.1 | 0.7593 ± 0.1703 | 0.5564 ± 0.1641 |
| pretrained_z | 1.0 | 0.7357 ± 0.1776 | 0.5131 ± 0.1655 |
| pretrained_z | 10.0 | 0.7295 ± 0.1771 | 0.4924 ± 0.1641 |
| random_z | 0.01 | 0.8653 ± 0.0219 | 0.6436 ± 0.0536 |
| random_z | 0.1 | 0.8418 ± 0.0249 | 0.5696 ± 0.0708 |
| random_z | 1.0 | 0.8350 ± 0.0262 | 0.5333 ± 0.0781 |
| random_z | 10.0 | 0.8328 ± 0.0269 | 0.5152 ± 0.0811 |

Mean ± sample standard deviation across three label-sampling seeds, not confidence intervals. Pretrained embeddings are highly sensitive to the sampled labels and regularization. No significance claim is made. Comparing the best C values after viewing this table would be test-set selection, not validated tuning.

## Validation and limitations

All 108 fits terminated below the iteration cap without ConvergenceWarning. This is the solver's stopping criterion, not proof of a globally optimal scientific protocol. All 36 out-of-fold prediction arrays contain 15,000 finite probabilities; labels and groups match the prior experiment. Container exit 0, OOMKilled=false.

Runtime 6.9 seconds; maximum process RSS 1.91 GiB; CUDA peak allocated 65.7 MiB.


This remains exploratory cell-type holdout within a dataset; donor metadata is absent, pretraining overlap is unresolved, and these outer folds have already been examined. No exact pretraining-input normalization comparison has been completed. The representation may be poorly matched to RNA-only inference or to this task; this experiment does not distinguish those mechanisms. Classifier convergence does not resolve distribution shift, feature quality or regularization choice.

## Updated plan

1. Audit the exact pretraining preprocessing and missing-modality inference contract before attributing this deficit to the learned objective. Verify gene transforms, scaling and modality masks against the training pipeline.
2. Use group-disjoint inner validation to select encoder/head learning rates and readout regularization; give scratch comparable selection effort. Keep outer folds exploratory and report all choices.
3. Separate feature usefulness from initialization usefulness: frozen linear extraction is weak here, while fine-tuning can still adapt the representation. Do not claim one from evidence for the other.
4. Replicate the frozen/raw comparison and tuned adaptation on an audited independent functional endpoint before restarting large-scale pretraining or revising manuscript claims.

Artifacts and executable script: `20261108_linear_probe_diagnostic/`. Checkpoint unchanged. No large-scale pretraining was launched.
