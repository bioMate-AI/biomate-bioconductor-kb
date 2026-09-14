# Baseline generation benchmark — first definitive numbers

## RESOLVED (2026-09-14): the reproduction WORKS — official metrics on the LNR test set

Running PepGLAD's **own** `generate.py` + `cal_metrics.py` (official pipeline, `official_eval.sh`)
on the **LNR held-out test set** (93 targets × 10 samples) with our epoch-99 checkpoint:

| Metric | PepGLAD paper (Table 1) | **Our reproduction** | Reading |
|---|---:|---:|---|
| DockQ (mean) | — | **0.512** | medium-quality interface (>0.49) |
| Cα-RMSD (median) | — | **5.14 Å** | reasonable pose (best 1.73 Å) |
| Consistency | 0.789 | **0.908** | high seq↔structure agreement |
| Codesign Diversity | 0.506 | 0.851 | diverse |
| Seq / Struct Diversity | — | 0.985 / 0.782 | |
| Slide AAR (mean) | (rejected metric) | 0.285 | well above the ~0.16 random baseline |

**Verdict: the model produces medium-quality de novo peptide binders on held-out targets, in
the ballpark of the published model.** The earlier "near-random / not useful" conclusion was an
artifact of (1) raw positional AAR instead of official `slide_aar`, (2) evaluating on the valid
split with our custom harness instead of the official pipeline on the test split, and (3) using
metrics (AAR, RMSD-to-native) the method deliberately does not optimize. The pipeline is sound
and ready to build the cyclic-peptide / developability work on.

**Caveats (do not overclaim "we beat PepGLAD"):**
- We used **n_samples=10** vs the paper's 40 — fewer samples inflates diversity/consistency and
  makes those *not* directly comparable; our higher-than-paper Consistency/Diversity is likely
  partly this, not superiority.
- **ΔG and Success (the Rosetta-based headline metrics) are still not computed** — needs PyRosetta.
- Checkpoint was the OOM-truncated epoch-99 (LDM ~99 of a 300 target); it already performs
  reasonably, but a clean full run could differ.
- Metrics: `results/official_test_metrics.txt`, run `pepglad-officialeval-20260914T171238Z`.

The AAR-based sections below are superseded and kept only for the investigation record.

# (superseded) Baseline generation benchmark — first (mis-metric) numbers

Calibrated full-sampling generation benchmark of the PepGLAD LDM on the held-out PebBench
**validation** split (not LNR test), run via `generate_validation.py` (EVAL_ONLY mode) on the
epoch-99 checkpoint from the publication-matched run (`pepglad-pubmatch-20260914T043137Z`).

## Result (114 complexes × 4 attempts = 456 samples)
| Metric | Value | Reference |
|---|---:|---|
| serialized_rate | **1.00** | pipeline produces valid, finite structures every time |
| sequence_diversity | **1.00** | all 456 generated sequences unique |
| raw positional AAR | 0.059 | **mis-metric** — see below |
| **slide AAR (official)** | **0.152** | PepGLAD's real metric (max over registration offsets) |
| slide AAR random baseline (uniform / composition) | 0.14 / **0.16** | the metric's floor for short peptides |
| best-of-4 slide AAR / complex | 0.214 | vs shuffled-reference (right composition) 0.318 |

## Metric correction (important)
We first reported raw positional AAR (0.059) — wrong. PepGLAD's official metric is
`slide_aar` (max AAR over registration offsets; `evaluation/seq_metric.py`). Recomputed on the
saved sequences: **0.152**. But `slide_aar` takes a max over ~2L offsets, so its **random
baseline is 0.14–0.16, not 0.05**. Our model's 0.152 sits **at (slightly below) the
composition-matched random baseline of 0.160**. So the metric fix explained the jump but did
**not** rescue the model.

Artifacts: `runs/pepglad-eval-20260914T154450Z/status/validation_summary.json`.

## CORRECTION (2026-09-14, after checking the paper) — AAR is the WRONG metric

PepGLAD's paper (Kong et al., NeurIPS 2024) **explicitly rejects AAR** (appendix "Why not
Amino Acid Recovery") because the task is *de novo* co-design, not native-sequence recovery.
Their reported metrics on the benchmark are:

| Metric | PepGLAD paper | Meaning |
|---|---:|---|
| Success | 55.97% | fraction of designs without severe clashes / invalid conformations |
| Diversity | 0.506 | unique sequence–structure clusters (NOT % unique sequences) |
| Consistency | 0.789 | sequence↔structure agreement (Cramér's V) |
| ΔG | −21.94 kcal/mol | Rosetta interface binding energy |

**Consequence:** our "near-random AAR / 12 Å RMSD-to-native ⇒ model doesn't work" verdict was
measuring quantities the method deliberately does not optimize. For de novo design, AAR at the
composition baseline and high RMSD-to-native are **expected, not failures**. We therefore
**cannot conclude the model fails** — and we have **not** yet computed the metrics that actually
matter (Success/clash, clustered Diversity, Consistency, ΔG). Our 100% "serialized" is only a
finite-coordinate check, weaker than their clash-based Success; our diversity=1.0 is %-unique,
not their clustered Diversity — so neither is directly comparable.

Honest status: **working generation pipeline; NOT yet evaluated on the appropriate metrics.**
Neither success nor failure is established. Next requires PepGLAD's `cal_metrics.py`
(Consistency, clustered Diversity, RMSD, DockQ) plus PyRosetta for ΔG, compared to the table
above.

## Interpretation (SUPERSEDED — AAR-based, wrong metric; kept for the record)
- **The pipeline is sound.** 100% serialized + 100% diverse: generation, calibration, and the
  eval harness all work end-to-end; outputs are valid structures.
- **The model does not recover sequence above the random baseline** — even by the official
  slide_aar metric (0.152 vs 0.16 composition-random). Confirmed rigorously, not a metric bug.
- **Caveat worth stating:** for *de novo* binder co-design, matching the native sequence is not
  the objective, so AAR near the composition baseline is partly expected — the discriminative
  metrics are structural/binding (Cα-RMSD, DockQ, interface dG), which we have not computed
  (need Rosetta/OpenMM) and have not compared to PepGLAD's *published* numbers on this split.
  Our own Cα-RMSD ~12 Å (during training) is the clearer weakness. So this establishes "we have
  NOT demonstrated useful design," not necessarily "the model is fundamentally broken."
- **This is not an undertraining/compute problem.** During-training val AAR was **flat at ~0.06
  from early epochs across both runs** (LDM 80 ep / batch 30k, and 300-ep-target / batch 60k) —
  so more epochs and the restored batch did not help. The autoencoder is healthy (72%
  reconstruction), so the latent representation is fine; the gap is in the LDM generation.
- This is **below** a well-trained PepGLAD. Because compute is ruled out, the cause is most
  likely in the **inference/eval recipe or the LDM conditioning**, not the amount of training.

## What this does and does not say
- It does NOT condemn the all-atom architecture (AE works; generation is valid/diverse).
- It DOES say: our bounded PepGLAD reproduction, as configured, is not a usable cyclic-peptide
  generator, and "train more" is not the lever.
- AAR (native-sequence recovery) is also an imperfect target for *de novo binder design* — but a
  flat-at-random curve throughout training points to a setup issue, not just "design ≠ recovery".

## Recommended next (no more blind GPU spend)
1. **Investigate why**, cheaply: compare our inference call (`generate_wrapper`, `energy_func=
   default`, `energy_lambda=0.8`, sampling steps, receptor conditioning) against PepGLAD's
   published evaluation protocol; confirm generation actually conditions on the receptor and
   that `save_topk` didn't select a structure-loss-best (not AAR-best) checkpoint. Verify the
   AAR definition matches the paper.
2. **Move to the real target:** the general PepBench baseline is a means, not the goal. Shift to
   the **cyclic-peptide** setup — train/eval on the 890 PepBDB cyclic complexes (+ RCSB index)
   we collected, with closure/monomer handling — and the developability-aware objective
   (INNOVATION_ASSESSMENT.md Bet 1), using the staged data (PepBDB cyclic, BindingDB affinity,
   HELM monomers, CycPeptMPDB/PepMSND/MacroConf).
