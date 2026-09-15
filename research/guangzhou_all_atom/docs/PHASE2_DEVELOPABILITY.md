# Phase 2 — developability-aware generation (Bet 1) kickoff

Chosen direction after Phase 1 (working cyclic generator: slide-AAR 0.23 vs 0.17 random). Build
the differentiator from [[BET1_DESIGN]]: generation coupled to calibrated developability
predictors. Grounded in an inventory of what already exists (memory principle: don't rebuild).

## Inventory (S3 `cyclic_peptide/`) — what exists, honestly
Permeability predictors from earlier (July) work already trained on CycPeptMPDB (n≈8466):
| model | random-split R² | scaffold-split R² (leak-free) |
|---|---:|---:|
| histGBM descriptors (`fm_probe`) | 0.47 | ~0.25 |
| gnn+desc (`model/`) | 0.40 | — |
| histGBM 2D/3D (`scorer/`) | 0.27 | 0.11–0.13 |
| singletask histGBM (`multitask`) | — | 0.29 |
| D-MPNN chemprop (`dmpnn_peptideclm`) | 0.27 | — |
| **published references** | — | **CPMP 0.67 / CycPeptMP 0.77** |

**Honest gap:** our permeability predictors generalize poorly (scaffold R² 0.1–0.3) vs the
published 0.67–0.77. Good enough for *ranking* (the offline replay showed guided > random on
top-decile recovery), NOT good enough to trust as a precise oracle. Guidance must therefore be
uncertainty-aware and humble, not treated as ground truth.

Also present: offline DMTA replay (`replay_permeability.py`, `permeability_replay.json`) — the
acquisition loop already validated. Missing: a **stability** predictor (PepMSND leak-free folds
were rebuilt in `results/pepmsnd_fold_rebuild.json` / `data/processed/pepmsnd_stability_folds.csv`
for exactly this).

## Phase-2 plan (re-scoped to the honest state)
1. **Stability predictor** (the clear gap) — train + calibrate on the PepMSND leak-free folds
   (binary label). Report AUROC + calibration (ECE) with proper cross-fold CV. CPU, cheap.
2. **Developability-scored generation** — connect the fine-tuned cyclic generator to the
   predictors: generate cyclic candidates → build RDKit mol/SMILES → score permeability +
   stability (with uncertainty) → rank. Reports the developability distribution of generated
   designs + the top candidates. This is the "generate → verify" loop, in silico.
3. **Uncertainty-aware acquisition** — extend the existing replay to multi-property (perm +
   stability) EI + information-gain; validate vs random/greedy at equal label budget.
4. **(stretch) Strengthen permeability** toward the published references — the current cap
   (~0.3 scaffold) limits guidance quality; a stronger predictor (or CycPeptMP-style model) is
   the real lever, but is its own effort.

## Honest guardrails
- Predictors are ranking-grade, not oracle-grade (scaffold R² 0.1–0.3); report uncertainty and
  applicability-domain, never imply calibrated potency.
- No wet lab → "learn" is simulated (offline replay), not a closed prospective loop.
- Generated-peptide → SMILES conversion for the SMILES-based predictors is a real integration
  step (esp. for cyclic/non-standard); validate the conversion before trusting scores.

## First step (starting now)
Stability predictor on the PepMSND leak-free folds — cheap, self-contained, uses the folds we
built, and gives the second developability endpoint with honest calibration. Then wire
developability-scored generation.
