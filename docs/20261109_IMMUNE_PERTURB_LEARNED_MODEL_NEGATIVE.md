# Learned perturbation model: parametric learning does NOT beat the neighbor-mean

Recorded: 2026-11-09. Continues the immune-LLM model work on unseen-perturbation prediction. The
knowledge-weighted neighbor-mean sets the bar (know_r +0.078 Rest, +0.035–0.039 Stim; beats all nulls).
Question: can a *learned* model from a KO's knowledge-graph features beat it (the GEARS direction)?

## Experiment

Full DE_stats, per context (~6.8–7.2k KOs). KO feature = a 256-d random projection of its GO/KEGG/
Reactome gene-set membership ("which pathways is this KO in" — fixed, non-leaky). Ridge map
`features → residual effect`, leave-KO-out (5-fold), best-λ. Compared to the shared-set-weighted
neighbor-mean and random. Metric: top-50 residual-DE Pearson. Pure numpy (ridge closed-form, numpy
Pearson — no scipy, Spark torch broken). `perturb_predictor/learned_model/`.

| context | neighbor_mean | learned_ridge | random | learned − neighbor (t) |
|---|---:|---:|---:|---:|
| Rest | **+0.078** | +0.013 | −0.021 | −0.065 (t=−23.0) |
| Stim8hr | **+0.039** | +0.024 | −0.021 | −0.014 (t=−4.7) |
| Stim48hr | **+0.035** | +0.019 | −0.017 | −0.016 (t=−5.4) |

## Finding

**A learned linear map from KO pathway-membership features loses to the neighbor-mean at every context,
significantly** (t=−5 to −23). It barely clears random (+0.01–0.02). This is now the **third** learned
approach to lose to the simple neighbor-mean:
1. kernel-ridge (learned weighting over the set-sharing kernel) — worse (Rest t=−15.9, earlier gate)
2. feature-ridge (this run) — worse (t=−23/−4.7/−5.4)

**Why the neighbor-mean wins:** it is a strong non-parametric (k-NN-like) predictor — it transfers the
*actual measured effects* of pathway-sharing KOs. A parametric linear model must compress the signal
through a global map from a pathway embedding to a 10,282-d effect, which is a lossier learning problem
at this sample size. Averaging the right neighbors beats learning a global linear map.

## Consequence for the model program

- **For unseen-perturbation prediction, the deployable "best model" is the neighbor-mean.** Ship it;
  parametric linear learning does not improve it.
- **The GNN/GEARS bar is now high and evidence-tempered.** The only untested lever is a genuinely
  *nonlinear* model with graph message passing (real GEARS: per-gene node features + nonlinear
  propagation). Given three linear approaches have failed to beat the neighbor-mean, a nonlinear GNN is
  a higher-risk bet — it must be shown to beat the neighbor-mean (+0.078), not random, before any GPU
  spend is justified. That is the honest go/no-go, not "knowledge should help."

Caveats: top-50 DE metric is oracle-gene-selected (fair across methods, inflates absolute r); the
random-projection feature is a simple knowledge embedding (a learned node2vec/graph embedding might do
better, untested); single aggregated readout. Data `perturb_full/GWCD4i.DE_stats.h5ad`, local, public.
