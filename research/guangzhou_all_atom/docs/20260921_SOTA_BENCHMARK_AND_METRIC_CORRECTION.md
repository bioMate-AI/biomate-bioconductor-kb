# SOTA benchmark + a metric correction (2026-09-21)

**Correction of the record.** During this session I twice judged the peptide model by the WRONG metric and drew a
false conclusion. This doc fixes the record with the real SOTA comparison and the right criteria.

## The metric lesson (load-bearing)

PepGLAD's own paper (Appendix H.1 "Why not Amino Acid Recovery") argues **AAR is unsuitable for target-specific
peptide design** — a *perfect* binder-generator scores AAR ≈ a random generator (correlation with binder fraction
only ~0.22). `slide_aar` is a back-channel diagnostic PepGLAD deliberately does **not** headline.

**The real headline metrics** (PepGLAD Table 1/3): **Success (fraction ΔG<0)**, **Diversity**, **Consistency**,
**DockQ**, **RMSD**. Judge the model by these, NOT AAR (and NOT closure-distance).

### Two errors I made (so they aren't repeated)
1. Dropped MacroGuide because it lost to the cyclic term on **closure-distance** (a sub-metric), then over-narrated
   it as "model done."
2. Called the model "broken/chance-level" because **AAR ≈ 0.059** on the custom harness — but AAR is the wrong metric
   AND that 0.059 came from our **custom `generate_validation.py`**, which misgenerates vs the official pipeline
   (`official_eval.sh` exists precisely to remove that doubt). The official `generate.py` gives AAR ≈ 0.339.

## The real numbers — official PepGLAD `cal_metrics.py` (cyclic eval, 68 complexes, n=10)

Run `pepglad-cyclicofficial-20260915T173626Z` (cyclic-fine-tuned model on the cyclic test set):

| Metric | **Our model** | Published PepGLAD | Read |
|---|---|---|---|
| **DockQ** ↑ | **0.506** | 0.592 (PepBench) / 0.403 (PepBDB) | ~PepGLAD-class, a bit below |
| Slide AAR | 0.339 | 0.367 (own) / 0.206 (PepHAR re-run) | **in published range ✓** |
| RMSD Cα median ↓ | **3.69 Å** | 4.09 Å (PepBench conf task) | comparable/better ✓ |
| Seq Diversity ↑ | 0.937 | 0.506 | higher ✓ |
| Struct / Codesign Diversity ↑ | 0.578 / 0.679 | 0.506 / — | comparable ✓ |
| Consistency ↑ | 0.641 | 0.789 | below — undertraining headroom |

**Verdict:** the model is a **valid, working PepGLAD reproduction** (~PepGLAD-class), **not broken**. It is **not
beating SOTA** — it ~matches its base; newer methods (PepFlow AAR 0.51, PepHAR) and structure-SOTA (Vilya 89% ring
RMSD, different benchmark) are ahead. Caveat: this eval is the **cyclic** test set, not the identical PepBench split
PepGLAD's Table reports — see next step.

## Comparison targets (published, PepBench/PepBDB co-design, Table 1)
Reference 95.7% Success; **PepGLAD Success 55.97% / Diversity 0.506 / Consistency 0.789 / DockQ 0.592** (PepBench).
DiffAb 49.87% / 0.427 / 0.670; dyMEAN 14.60%; HSRN 10.46%. (Success needs PyRosetta ΔG — not yet computed for ours.)

## Next steps (keep optimizing — we do NOT beat SOTA yet)
1. **Apples-to-apples (#1, in progress):** run `official_eval.sh` — PepGLAD's own `generate.py` + `cal_metrics.py`
   on the **LNR test set** with our BASE checkpoint → DockQ/RMSD/Diversity/Consistency directly comparable to
   paper Table 1/3 (minus Success, needs PyRosetta). This replaces the degenerate custom-harness AAR 0.059.
2. **Close the undertraining gap** to fully match PepGLAD (DockQ 0.51→0.59, Consistency 0.64→0.79) — train to
   convergence (spot-resume; runs so far were 4h-capped, loss ~1.5-2.5 not converged).
3. **Add Success (ΔG<0):** wire a PyRosetta/FoldX ΔG so we report the headline Success metric, not just structural.
4. **Then beat SOTA:** benchmark vs PepFlow/PepHAR and do method/architecture work; judge on Success/DockQ/Consistency.

## Change log
- 2026-09-21 — created to correct the AAR-based false alarm; real official metrics recorded (DockQ 0.506, ~PepGLAD
  class); #1 apples-to-apples LNR eval launched.
