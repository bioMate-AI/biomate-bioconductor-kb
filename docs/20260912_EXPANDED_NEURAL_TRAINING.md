# Expanded immune neural training — 12 September 2026

## What was actually trained

Two residual neural predictors were trained on the combined CZI panels: **768 guide profiles aggregated to 384 target/donor/condition contrasts, 32 targets, four donors, three conditions**. Models predict 512 gene effects selected independently within each fitting fold. One model uses target/condition inputs; the other also uses 132 pretreatment control-state genes. Both have a 64-unit ReLU hidden layer, with 35,584 and 44,032 parameters respectively. These are immune perturbation predictors, not language-model pretraining or fine-tuning.

The raw gene universe is 18,129 genes. All 32 perturbed target genes are excluded from the output-selection universe. Labels are full-library normalized log 1 p effects relative to the independent reference-control pool. The separate feature-control pool supplies baseline state. All counts and control aggregation use the prior checked source artifacts.

No Shifrut cells or CD4 follow-up outcome values enter these neural training runs. Increasing targets from 16 to 32 expands perturbation coverage but leaves independent training donor count at four.

## Training and selection

Four outer held-out-donor folds, three inner donor folds per outer fold, two model variants and two fixed seeds. AdamW, learning rate 0.001 and weight decay 0.01; no architecture/seed search. The network predicts a residual over the guide-shrunk target/condition mean. Training residual priors leave out the training row's donor; validation/test priors use only fitting donors. Fold-specific output genes and feature scaling use fitting data only.

Run 1 allowed 50/200 epochs. All final fits selected 50 epochs and failed the shrinkage baseline. Run 2 preserved run 1, changed only the stopping grid to 0/1/5/10/25/50/200, and allowed the unchanged shrinkage prior at epoch 0. It selected 1 epoch for three outer donor folds and 0 for the fourth. This second run followed observation of run 1 and is development work, not untouched confirmation.

Across both runs,128 fit jobs were evaluated:124 ran optimizer updates and four final zero-epoch jobs retained the unchanged prior. Saved 32 final checkpoint files. Inner training histories are retained, but inner models were not independently retrained during the audit. The original run recorded diagnostic outer MSEs at intermediate epochs; these did not control stopping. Run 2 records the initial prior and preselected final neural score only.

## Results on identical per-fold output panels

| Arm | Equal-donor MSE |
|---|---:|
| No change | 0.02579368 |
| Guide shrinkage | **0.02566928** |
| Fixed-alpha 10 target/condition ridge | 0.02999314 |
| Run 1 target/condition MLP, seeds 0/1 | 0.02990236 / 0.02985061 |
| Run 1 state MLP, seeds 0/1 | 0.03083445 / 0.03025504 |
| Run 2 target/condition MLP, seeds 0/1 | 0.02567945 / 0.02567637 |
| Run 2 state MLP, seeds 0/1 | 0.02569599 / 0.02572041 |

Neither neural variant beats shrinkage overall. A zero-epoch selected checkpoint is a baseline result, not evidence that neural learning helped. Absolute MSE is not comparable with the earlier 132-gene benchmark because output panels differ.

The results show that short training largely avoids the severe overfit in run 1, but there is not yet evidence for added neural predictive value. No seed or model is promoted, and no production inference is enabled.

## Implementation and verification

Independent replay reconstructed all 32 final checkpoints, all 72 outer MSE comparisons, raw labels, output panels, feature scaling and attenuation priors. Maximum prediction discrepancy was 1.11e-16. Zero-epoch model heads were exactly zero and reproduced shrinkage predictions. Source inspection found no held-out fitting leakage. Epoch choices were checked against recorded inner histories; this is not independent retraining of every inner optimizer run.

The installed reusable trainer accepts explicit data-root, output and protocol paths, refuses overwriting a completed run, preserves per-fold model/scaler/readout metadata, and additionally records inner fold indices and selected genes for subsequent runs. Training snapshots used for the completed runs remain unchanged. The installed trainer and related evaluators passed 21 focused tests; tests include exact zero-residual initialization and invariance of readout selection to corrupted held-out values.

Artifacts:

- `docs/20260912_s3_continuation/expanded_neural_training/`: original schedule, results and 16 checkpoints.
- `docs/20260912_s3_continuation/expanded_neural_training_v2/`: early-stop revision, results and 16 checkpoints.
- `research/immune_llm_baseline/train_expanded_neural.py` in the immune training worktree: reusable trainer.

## Related gate checks and next work

Before training, the common 116-readout specificity comparison verified a modest advantage of shrunk matched target means over shrunk condition means and exhaustive mismatched identities. All 2,880 alternative identity comparisons were checked; no favorable random mismatch was selected. This supports retaining target identity in the simple baseline, not adding neural complexity by itself.

The newly identified CD4 arrayed follow-up contains eight IL10/IL21 files representing seven biological donors; DonorC/C2 are the same biological donor in separate batches. Internal donor IDs do not overlap the four screen donors. Only metadata and file headers were inspected: outcome values remain unexamined. Correct future grouping must keep C/C2 together and controls matched within donor/batch/condition. These are new-donor follow-ups within the same study, not a separate independent study. The assay/cell context is closer than the CD8 Shifrut study. [Primary CZI documentation](https://virtualcellmodels.cziscience.com/dataset/genome-scale-tcell-perturb-seq) and [Shifrut GEO record](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE119450) describe the study contexts; exact donor grouping is documented in `followup_validation/cohort_audit.md` with pinned analysis-source provenance.

Next: freeze a matched-assay validation protocol and predictions before reading those outcomes, then evaluate the validated shrinkage baseline and any predeclared neural comparator without fitting on follow-up donors. Do not scale language-model or foundation-model training on the strength of the current four-donor neural result.

Header-only target matching found zero overlap between the nine IL10/IL21 follow-up targets and the current32-target neural training panel. The current models therefore cannot directly serve this validation task. Source-side coverage must be expanded first under a frozen protocol; treating missing target identities as zero effects would be invalid.
