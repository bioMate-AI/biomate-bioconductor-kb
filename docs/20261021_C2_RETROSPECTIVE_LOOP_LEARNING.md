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

## Status: OFFLOADED to a clean spot CPU box — ready to run, not yet run
**Diagnosis:** the blocker was purely **local CPU contention**, not the code — the data load is 4.9 s,
but a *single* HistGBM fit took **231 s** here (vs ~1 s on an idle machine), and the AL loop does
hundreds of fits. So it's offloaded to a dedicated, uncontended spot CPU box.

- **Launcher:** `research/guangzhou_all_atom/c2_launch.sh` — mirrors `build_fep_inputs.sh`: multi-type/AZ
  **spot** sweep (c6i/c6a/c5/m6i 2xlarge across us-west-2 AZs), `instance-initiated-shutdown=terminate`,
  90-min hard cap, self-terminating user-data; installs a **clean** python via micromamba
  (`python=3.11 numpy scipy scikit-learn` — NOT the broken anaconda py3.9), pulls the staged inputs,
  runs the FULL config (all targets×seeds×rounds — the box has the slot), writes results + a
  `C2_START`/`C2_DONE` canary log to the S3 `out/` prefix, then shuts down. Fresh results only (clears
  the stale sentinel at start); fail-loud (always uploads stdout+log, records `rc`).
- **Self-contained inputs (staged to S3):** `c2_retro_loop.py` + `c2_staged.npz`
  (fp+desc+pAff+target+flags; 2.1 MB) at `s3://biomate-nextflow-work/cyclic_peptide/c2_loop/`. No CSV,
  rdkit, or pandas needed on the box. (Rebuild the npz locally with the one-liner in the commit if lost.)
- **S3 out/ prefix:** `s3://biomate-nextflow-work/cyclic_peptide/c2_loop/out/`
- **Run (parent, from this worktree):** `bash research/guangzhou_all_atom/c2_launch.sh`
- **Poll:** `aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/c2_loop/out/c2_stdout.txt - --region us-west-2`
  (C2_START → per-target → `FINAL[raw]`/`FINAL[novel]` → C2_DONE); full curves in `out/c2_result.json`; `out/DONE` (`rc=0`) = finished.

The honesty cut is built into the sim: it reports **both** raw hit-recall **and** `novel_cluster_hits`
(hits in Tanimoto clusters NOT present in the seed set) for LEARN/FIXED/RANDOM — the LEARN-vs-RANDOM
margin must survive the **novel-cluster** cut to count as genuine SAR generalization rather than
analog hit-expansion. No result is fabricated; the box produces the real curves.

## Honest caveat to carry into interpretation (when it runs)
Within-target greedy acquisition tends to acquire analogs of known hits (hit expansion) — which is
genuinely useful in design, but means a LEARN>RANDOM margin is partly analog-driven. Report the
curve honestly and, if time permits, stratify by Tanimoto cluster (the `fewshot_sweep` clustering)
to separate hit-expansion from genuine SAR generalization.
