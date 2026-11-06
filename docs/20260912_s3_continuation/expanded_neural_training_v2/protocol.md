# Expanded neural predictor training protocol

Train on the combined 32-target CZI development panels: 768 guide profiles, 384 target/donor/condition contrasts, four donors and three conditions. Raw full-library normalized log1p contrasts use the existing independent reference-control pool. The feature pool provides pretreatment state. No follow-up validation outcomes or external-study cells enter training.

Four outer held-out-donor folds, three inner held-out-donor folds. Each fitting fold selects 512 output genes using training-control CPM>=1 and variance across training target means; exclude all 32 perturbed genes. Fixed original132 baseline-state genes form optional inputs, standardized using fitting rows only. This remains reused-data development, not untouched validation or unseen-target prediction.

Train two residual MLPs: target/condition features, or those features plus pretreatment state. One64-unit ReLU hidden layer; zero-initialized output head; AdamW learning rate0.001, weight decay0.01; full-batch MSE; seeds0 and1. Inner donor MSE selects0,1,5,10,25,50 or200 epochs independently for each variant/seed, without selecting a winning seed. The prior is the guide-shrunk training target/condition mean. Training residuals use leave-one-training-donor-out priors; validation priors use only fitting donors. Refit on three outer-training donors using the selected epoch count.

Compare on the same512 output genes per outer fold: no-change, condition mean, target/condition mean, guide-shrunk mean, and a target/condition Ridge(alpha10), plus both MLP seeds/variants. Ridge alpha10 is fixed, not tuned on test outcomes. Save actual trained state dictionaries, input schema/scaler, selections, predictions, epoch-selection histories and source hashes; independently replay checkpoints.

No model promotion from this development comparison. Preserve negative results and all seeds. Biological replication remains four donors; 384 rows are not384 independent biological samples.

Development revision: all v1 folds chose the earliest available50 epochs and failed the shrinkage baseline. Before v2 execution, extend stopping checkpoints to0/1/5/10/25/50/200, explicitly allowing no neural correction at0. Preserve v1 unchanged; no learning-rate/architecture/seed selection. Outer neural outputs are scored at the preselected final epoch in v2; the unchanged epoch0 prior is also scored as a baseline, never used to change the inner-selected stopping point. A zero-epoch final checkpoint is the unchanged shrinkage baseline, not evidence that neural learning helped.
