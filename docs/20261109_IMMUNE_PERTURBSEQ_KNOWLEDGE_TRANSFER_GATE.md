# Perturb-seq knowledge-transfer gate: the first positive transfer signal, and where to build the model

Recorded: 2026-11-09. Follows the stimulation investigation (`20261108_0905_...WHY_KNOWLEDGE...`),
which concluded knowledge-for-transfer is undemonstrable on stimulation because the task has no
unseen-entity gap. This moves to the regime that *does* have one: held-out-perturbation prediction.

## Setup

Data: `czi_tcell_deltas.npz` (CZI genome-scale CD4⁺ T Perturb-seq, Marson/Pritchard 2026) — **300 KO
genes × 18,533 readout genes**, `delta` = LFC(KO)−LFC(control). Cached locally on Spark (`fs_long/work`),
no S3 (the atlas S3 key is expired). Leave-ONE-KO-out (300 folds; prediction = neighbor-averaging, no
training). For a held-out KO g:
- **know**: shared-count-weighted mean effect of training KOs sharing ≥1 GO/KEGG/Reactome gene-set with g
- **rand**: mean of |N(g)| random training KOs (size-matched → isolates knowledge CONTENT)
- **null**: mean of all training KOs (the generic-response baseline)

269/300 KOs have ≥1 knowledge neighbor. 10,701 gene-sets loaded. Metric: Pearson on each KO's true
top-50 DE genes (the mean-saturation-robust metric; full-transcriptome corr can't rank models — memory
`project_immune_fm_execution_path`). CPU-only.

## Result 1 — raw effect is mean-saturated (as warned)

Pearson on top-50 DE genes: **know +0.115 ≈ null +0.125 ≈ rand +0.099** (zero = 0). Knowledge does NOT
beat the mean-null (paired Δr=−0.016, t=−1.0). A **generic perturbation response** (stress/activation
programs) dominates most KOs' top-DE genes, so the global mean predicts them as well as anything. This
reproduces the documented "causal effect-prediction ρ was mean-saturated" finding at the bridge level.

## Result 2 — on the KO-SPECIFIC residual, knowledge carries real signal

Remove the generic response (center: `delta − delta.mean(0)`) and score on each KO's top-50
*residual*-DE genes (`perturb_leaveKOout_20261108/residual_results.json`):

| method | Pearson on top-50 KO-specific DE genes (n=269) |
|---|---:|
| know (pathway neighbors) | −0.028 ± 0.317 |
| rand (random neighbors) | −0.102 ± 0.298 |
| **paired know − rand** | **+0.0735, t=+2.8, 57% of KOs** |

**Knowledge-selected neighbors predict a held-out KO's *specific* effect significantly better than
size-matched random neighbors (t=2.8 across 269 KOs).** This is the **first positive transfer signal in
the entire investigation**: unlike stimulation (no unseen-entity gap at all), the perturbation task has
a real gap AND external knowledge bridges part of it. The GEARS premise — pathway relations carry
perturbation-effect similarity — is REAL on this data.

**But the absolute predictive power is ~0** (know r ≈ −0.03, not positive). A crude pathway-neighbor
mean does not convert the signal into a usable predictor. This is precisely why GEARS uses a *learned*
GNN rather than a neighbor-average: the raw graph signal is weak and must be amplified and combined with
the perturbation representation by a model.

## Decision — build the learned knowledge model HERE, not on stimulation

The cheap gates located the right investment:
- **Stimulation**: no unseen-entity gap; knowledge can at best match raw → do NOT build a learned
  knowledge model there (it would show nothing).
- **Perturbation (here)**: real gap; external knowledge carries significant KO-specific signal
  (know > rand, t=2.8) that a crude mean leaves near-zero → a learned graph model (GEARS-style GNN, or
  the expiMap-style masked decoder on the perturbation representation) is justified, because there is
  genuine signal to amplify.

This is the honest, non-circular case for the GPU program: not "knowledge should help" in the abstract,
but a measured, significant, content-controlled signal (vs. random neighbors) that a learned model can
plausibly convert into prediction — on a task that actually has the gap.

## Result 3 — learned-headroom gate: MARGINAL on the subset → GPU GNN not yet justified

Does a LEARNED weighting over the knowledge graph beat the uniform neighbor-mean? Exact leave-one-out
kernel ridge (hat-matrix form) with a Jaccard gene-set-sharing kernel, same top-50 residual metric
(`perturb_leaveKOout_20261108/learned_headroom.json`):

| method | top-50 residual Pearson |
|---|---:|
| rand (random neighbors) | −0.102 |
| know (uniform neighbor-mean) | −0.028 |
| **kernel-ridge (learned weights, best λ=0.1)** | **−0.007** |

Learned weighting improves on uniform averaging (Δr=+0.021) but **not significantly** (paired t=+1.2,
frac>0=0.53) and absolute r stays ≈0. So on the **300-KO subset with a single set-sharing kernel**, a
learned model has only marginal headroom. The signal is real (know > rand, t=2.8) but weak, and learning
the weighting barely converts it.

## Data blocker — the decisive richer test cannot run yet

The marginal headroom is confounded by **data thinness**: 300 KOs + one Jaccard kernel is far thinner
than GEARS (full perturbation set + rich GO/PPI graph + GNN propagation). The decisive test needs the
**full 33,983-contrast `GWCD4i.DE_stats.h5ad` (16.8 GB)** + richer knowledge features (node2vec on the
full GO/PPI graph) — but that file is **NOT cached on Spark** (only the 300-KO `czi_tcell_deltas.npz`
exists) and the atlas S3 key is **expired** (`InvalidAccessKeyId`). So the richer gate is blocked on
data acquisition.

## DECISION — defer the GPU GNN; resolve the data blocker first; explicit go-criterion

Do **not** build the GPU GEARS-style model yet. Current evidence: a real but weak knowledge-transfer
signal (t=2.8 vs random) that a simple learned model does not yet convert to positive prediction on the
thin subset. **GPU go-criterion:** on the FULL contrasts + a richer knowledge graph, the learned map must
(a) beat the uniform neighbor-mean significantly AND (b) reach positive absolute top-DE residual Pearson
on held-out KOs. Until both hold, a GNN would likely reproduce the subset's near-zero result.

**Immediate blocker to clear (non-GPU):** restore Spark's AWS creds (or locate a cached copy) to pull
`GWCD4i.DE_stats.h5ad` + build node2vec GO/PPI features, then re-run Results 2–3 at full scale. This is a
data/credential task, not a modeling one.

## Result 4 — FULL SCALE (33,983 contrasts, ~7k KOs/context): signal is STRONG and POSITIVE

Ran the full DE_stats (downloaded from the public atlas — the bucket is open, `--no-sign-request`;
the expired key was the only blocker). Read directly with h5py (the loader calls scipy.stats.pearsonr
which crashes on this python's broken torch). QC-kept 21,157/33,983 contrasts; ~6,800–7,200 unique KOs
per context. Per-context residual, top-50 metric (`perturb_fullscale_20261108/results.json`):

| context | n KOs | know_r | rand_r | know−rand t | kernel-ridge r | kridge − neighbor-mean (t) |
|---|---:|---:|---:|---:|---:|---:|
| Rest | 6,840 | **+0.078** | −0.021 | **+28.5** | +0.035 | −0.044 (−15.9) |
| Stim8hr | 7,142 | +0.039 | −0.016 | +14.8 | +0.032 | −0.006 (−1.8) |
| Stim48hr | 7,175 | +0.035 | −0.014 | +13.7 | +0.028 | −0.005 (−1.7) |

**The 300-KO subset was simply too thin.** At full scale the knowledge-neighbor predictor is strongly
positive (know_r +0.078 at Rest) and crushes the random-neighbor control (t up to +28.5). A knowledge-
weighted neighbor average genuinely predicts a held-out KO's specific effect — a real, cheap win on the
unseen-perturbation task.

**But learned weighting (kernel ridge) does NOT beat the simple neighbor-mean** — it is worse at every
context (Rest t=−15.9). The simple shared-set-weighted average already captures the signal; linear
learned weighting over the same kernel adds nothing.

## Decision (updated) — ship the knowledge-neighbor predictor; GPU GNN must clear a HIGH bar

- **Perturbation effect prediction is a genuine knowledge win**: the knowledge-weighted neighbor-mean
  positively predicts unseen-KO effects at scale (t≥+13.7 vs random). This is deployable now, cheap,
  no GPU.
- **GPU go-criterion tightened**: a learned GNN/expiMap must beat not the random/mean baseline but the
  **knowledge-neighbor-mean** (know_r +0.078 Rest). Our kernel-ridge test shows linear learned weighting
  is WORSE than the neighbor-mean, so the bar is real — only a model that adds the perturbation's own
  features + nonlinear graph propagation (true GEARS) could clear it, and that must be demonstrated
  against the neighbor-mean, not random, before any GPU spend.

## Next (gated, this time with evidence behind it)

1. Strengthen the measurement first (cheap): use the full 33,983-contrast DE_stats (not the 300-KO
   subset), add the per-context axis (Rest/Stim8/Stim48 — the natural IRM environments), and test
   whether a **learned** linear/MLP map from a KO's graph-embedding → residual effect beats the random
   -neighbor and mean baselines on held-out KOs (still cheap, establishes the learned-model headroom).
2. Only if (1) shows headroom: build the GEARS-style GNN / expiMap decoder and evaluate leave-KO-out
   and leave-context-out with degree-aware nulls and the top-DE metric. Compare to the documented
   measured virtual-KO screen (AUROC 0.85) which is the current real positive.

Caveats: 300-KO subset, leave-one-out neighbor-mean is the weakest possible learner, single aggregated
readout (per-donor environments in `GWCD4i.DE_stats.by_donors.h5mu` not used yet), top-DE selection by
true effect is standard but is an oracle gene-selection (same genes for all methods → fair comparison).

Artifacts: `docs/20261108_knowledge_features_baseline/perturb_leaveKOout/` (both scripts, raw + residual
results). Data: Spark `fs_long/work/czi_tcell_deltas.npz`; loader `code_20261004/load_czi_perturbseq.py`.
