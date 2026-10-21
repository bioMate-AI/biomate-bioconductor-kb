# C2 — Retrospective closed-loop learning on real measured affinity

**Date:** 2026-10-21 · Challenge C2 (per `20261021_PROGRAM_CHALLENGE_MAP.md` / the challenge inventory): prove the closed loop **learns** — validated retrospectively on **real** data, not synthetic.

## Question
Does model-guided acquisition that **retrains each round** find high-affinity cyclic peptides
faster than (a) **random** (no learning) and (b) a **fixed** model that never updates? Beating
random (and fixed) on hit-finding is the operational "the loop learns" claim — the program's moat.

## Design (built, ready to run) — `research/guangzhou_all_atom/c2_retro_loop.py`
- **Oracle = measured pAff** from `binding_affinity_v1` (cyclic subset). This is the **non-circular**
  oracle — it is NOT display enrichment, so the abundance-null circularity we caught this session
  does not apply. (Chosen deliberately over display-NGS for exactly that reason.)
- **Within-target active learning** (the realistic design regime: optimize binders for ONE target):
  seed 5 random labeled → model ranks remaining pool → acquire top-batch (greedy) → oracle reveals
  pAff → retrain → repeat. Background prior = subsample of other targets.
- **Three arms:** `LEARN` (retrain on bg+acquired each round) · `FIXED` (train once on bg+seed, never
  update) · `RANDOM` (no model). LEARN>RANDOM = the loop beats no-learning; LEARN>FIXED = the
  *updating* itself (not just a static model) adds value.
- **Metrics:** hit-recall (fraction of a target's top-20% pAff found) and best-pAff-found vs query
  budget, aggregated over targets × seeds with CIs; Wilcoxon on the per-target final margins.
- **Reuse, not rebuild:** uses the existing `benchmark_binding_models` loader + the cached ECFP+physchem
  features (`results/binding_feature_cache.npz`) + HistGBM — the same stack as the binding-model work.

## Status: BUILT + READY — NOT YET RUN (compute-blocked this session)
The simulation did **not** complete in this session. Under heavy concurrent CPU load in the
environment, even the data load + sklearn import did not finish within 30 min (a load-only probe did
not finish in 180 s, producing no output). No simulation output was ever flushed, so **there is no
result to report — and none is fabricated.** The script is committed and ready; it needs a
less-contended compute slot (or a smaller config: fewer targets/seeds/rounds, smaller background) to
produce the LEARN-vs-FIXED-vs-RANDOM curves.

## Honest caveat to carry into interpretation (when it runs)
Within-target greedy acquisition tends to acquire analogs of known hits (hit expansion) — which is
genuinely useful in design, but means a LEARN>RANDOM margin is partly analog-driven. Report the
curve honestly and, if time permits, stratify by Tanimoto cluster (the `fewshot_sweep` clustering)
to separate hit-expansion from genuine SAR generalization.
