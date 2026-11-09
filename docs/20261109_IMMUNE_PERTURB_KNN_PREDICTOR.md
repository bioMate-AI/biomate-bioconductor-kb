# Knowledge-neighbor perturbation predictor: packaged + benchmarked (shippable immune-task win)

Recorded: 2026-11-09. Workstream #1 of the "best on immune tasks" push. Packages the full-scale finding
(`20261109_IMMUNE_PERTURBSEQ_KNOWLEDGE_TRANSFER_GATE.md`, Result 4) into a deployable capability and
benchmarks it rigorously.

## What it is

`knn_perturb_predictor.py` — `KnnPerturbPredictor(weighting, topk)` with `fit(ko_names, effects,
gene_sets)` / `predict(query_ko_names)` / `predict_loo()`. Given training KOs' per-context residual
effect vectors + curated gene-sets (GO/KEGG/Reactome), it predicts an unseen KO's effect as the
set-sharing-weighted average of its pathway neighbours' measured effects. Pure numpy, CPU, no scipy
(this Spark python's torch is broken and poisons scipy's array-api; the h5ad is read with h5py directly).
Module verified: `predict_loo()` matches the inline reference to 0.0; `predict(['IL2RA'])` → [1,10282],
exact-name self-matches excluded (LOO-safe).

## Benchmark — leave-KO-out on the FULL DE_stats (21,157 QC-kept contrasts, ~6.2–6.6k KOs/context)

Metric: Pearson + direction accuracy on each held-out KO's true top-50 residual-DE genes. Baselines:
size-matched random-neighbor, mean-null. (`benchmark_results.json`.)

| context | **plain_count** | jaccard | topk10 | topk25 | degeneric | rand_neighbor | mean_null |
|---|---:|---:|---:|---:|---:|---:|---:|
| Rest | **+0.0781** | +0.0554 | +0.0267 | +0.0331 | +0.0401 | −0.0213 | −0.0315 |
| Stim8hr | **+0.0385** | +0.0396 | +0.0275 | +0.0321 | +0.0095 | −0.0206 | −0.0049 |
| Stim48hr | **+0.0352** | +0.0353 | +0.0229 | +0.0273 | +0.0109 | −0.0168 | +0.0157 |

Direction accuracy (top-50): plain_count 0.525 / 0.510 / 0.502 vs random ~0.49 — modest but above chance.

## Does any variant beat the plain neighbor-mean? NO — ship plain_count.

Paired t vs plain_count (positive = beats it):

| variant | Rest | Stim8hr | Stim48hr |
|---|---:|---:|---:|
| jaccard | −15.7 | +0.6 | +0.1 |
| topk10 | −17.9 | −3.8 | −4.2 |
| topk25 | −17.5 | −2.4 | −3.0 |
| degeneric (top-1 PC removed) | −33.5 | −32.6 | −26.4 |

- **jaccard** ties plain on the Stim contexts (ns) but is clearly worse at Rest → plain_count is the robust choice.
- **top-k** (restricting to nearest neighbours) consistently HURTS → averaging over *all* pathway neighbours is better.
- **de-generic** (removing the dominant generic axis before averaging) HURTS most → that axis carries shared structure the neighbour average exploits.

## Verdict

`plain_count` (shared-set-count-weighted mean over all pathway neighbours) is the shippable predictor:
it positively predicts unseen-KO transcriptional effects (Rest +0.078, Stim ~+0.035–0.039), beats
random-neighbour and mean-null at every context, and no cheaper or fancier variant beats it. It is a
genuine, GPU-free win on unseen-perturbation prediction — a hard immune task — and sets the bar a
learned GNN must clear (beat plain_count, not random) before any GPU spend is justified.

Honest limits: single aggregated readout (per-donor environments unused); top-50 selected by true effect
(standard, same genes for all methods → fair); direction accuracy is modest; this predicts the
KO-specific *residual* (generic response removed per context), not the raw effect (which is
mean-saturated). Evaluated leave-one-KO-out, not leave-pathway-out (neighbours can share a pathway with
the held-out KO — this is the intended mechanism, matching GEARS, not leakage).

## Artifacts

`docs/20261108_knowledge_features_baseline/perturb_predictor/`: `knn_perturb_predictor.py` (module),
`bench_knn_perturb.py` (benchmark), `benchmark_results.json`. Spark: `~/immune_fm_spark/ws_pertpred/`;
data `~/immune_fm_spark/perturb_full/GWCD4i.DE_stats.h5ad`.
