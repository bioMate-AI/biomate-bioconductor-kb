# Baseline generation benchmark — first definitive numbers

Calibrated full-sampling generation benchmark of the PepGLAD LDM on the held-out PebBench
**validation** split (not LNR test), run via `generate_validation.py` (EVAL_ONLY mode) on the
epoch-99 checkpoint from the publication-matched run (`pepglad-pubmatch-20260914T043137Z`).

## Result (114 complexes × 4 attempts = 456 samples)
| Metric | Value | Reference |
|---|---:|---|
| serialized_rate | **1.00** | pipeline produces valid, finite structures every time |
| sequence_diversity | **1.00** | all 456 generated sequences unique |
| **mean AAR** | **0.059** | random ≈ 0.05 (1/20) → **near random** |
| mean best-of-4 AAR / complex | **0.135** | ~2–3× random — modest signal |

Artifacts: `runs/pepglad-eval-20260914T154450Z/status/validation_summary.json`.

## Interpretation (honest)
- **The pipeline is sound.** 100% serialized + 100% diverse: generation, calibration, and the
  eval harness all work end-to-end; outputs are valid structures.
- **The model does not recover sequence above ~random on average.** Mean AAR 0.059 is at the
  random floor; only best-of-4 (0.135) shows weak signal.
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
