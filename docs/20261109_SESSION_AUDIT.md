# Session audit — immune knowledge-transfer + per-task scoreboard

Recorded: 2026-11-09. Self-audit of this session's work, with one independent re-measurement.

## Verdict

**Robust (cross-validated, well-controlled):**
- **Scarcity crossover** — knowledge beats raw at low labels (+0.14 @ ~60). Hardened: pre-registered
  fixed C, 30 paired draws, size-matched shuffled null (knowledge beats raw AND the null). The stim
  raw/know numbers (0.882/0.846) were reproduced independently by both my probes and the scoreboard
  harness. Trustworthy.
- **Unseen-perturbation knowledge signal at full scale** (know +0.078 vs random, t≈+28) — reproduced
  by two independent implementations (my numpy gate + the subagent benchmark). Direction + significance
  real.
- Negatives reported honestly (fm_z < raw on stim; no transfer under tissue shift; mean-saturation).

**Corrected overclaims:**
1. **"Model is best on annotation" → fm_z ≈ PCA at proper convergence.** The scoreboard's annotation run
   used a loose solver (`max_iter=200, tol=1e-2`) on a random in-donor split. Independent re-run at
   proper convergence (`saga 2000, tol=1e-3`, same split, 8k cells, all converged below cap):
   **fm_z 0.472 ≈ pca 0.466 (+0.005)** > raw 0.436 > know 0.391 — the fm_z-over-PCA margin collapsed
   from +0.022 to +0.005. A single leave-tissue-out fold (bone_marrow) was suggestive of an fm_z edge
   under shift (0.414 vs pca 0.355), but 3/4 tissue folds did not finish, so **no generalization claim**.
   Net: fm_z ties the PCA baseline on easy annotation; a real edge is unconfirmed. (`run_annot_fix.py`,
   `annot_fix_output.txt`.)
2. **Perturbation predictor "shippable win" → significant but weak.** The Pearson signal is strongly
   significant vs random (t≈+28), but absolute direction accuracy is 0.50–0.525 vs 0.49 chance — a
   reliably-better-than-random but *weak* predictor, not a strong one. It sets the baseline a GNN must
   beat; it is not a standalone strong capability.
3. **"Best on 2 of 3 tasks"** is softer than stated: one of those two (annotation) is a PCA tie once
   convergence is fixed.

**Methodology risks logged:**
- Annotation harness (`run_bench.py`): random (non-group) split + loose convergence. Fixed in the
  re-measurement above; the original harness should adopt `tol≤1e-3` and a group-disjoint option.
- 300-KO perturbation used `scipy.stats.pearsonr`; full-scale used numpy (scipy crashed on Spark's
  broken torch). Different implementations — full-scale confirms direction, but subset vs full are not
  strictly comparable.
- Top-50 DE metric selects genes by the *true* effect (oracle gene selection): fair across methods,
  inflates absolute r, not a deployment metric.
- Paired t-stats are over draws/cells on the same data, not independent biological replicates — they
  overstate population significance.

**Relayed but not independently recomputed by me:** the subagent-computed `fm_z` embeddings (stim 0.835,
annotation). I re-measured the annotation *probe* (above) using the saved `z_fm_stim.npy`, but did not
re-derive the embedding itself.

**Process:** thrashed on the broken-torch failure (tried a torch stub twice before diagnosing the loader
as the scipy source) — a lapse in "read the full error before retrying." Several launches wasted cycles
(pkill self-match; setsid redirect). No GPU was ever spent (the cheap gates worked); nulls/controls were
used throughout; the batch-clean blocker was not faked.

## Corrected bottom line

- Knowledge helps under **label scarcity** — robust.
- Knowledge carries a **real-but-weak** unseen-perturbation signal — robust in direction, weak in
  magnitude.
- The FM encoder **ties PCA** on easy annotation at proper convergence; its generalization edge is
  unconfirmed. It **loses to raw** on abundant-label stim.
- Responder stratification (the clinically valuable task) remains credential-blocked and unmeasured.

So: the model is competitive and has one robust niche (scarcity) and one weak-but-real niche
(perturbation), but a clean "best on immune tasks" is not yet established against the simple baselines —
the honest target remains beating PCA/raw per task under proper, group-disjoint, converged evaluation.
