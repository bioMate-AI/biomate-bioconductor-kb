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

## Progress (2026-09-15)
- **Step 1 — stability predictor ✅** ECFP4 + bootstrap-bagged HistGBM on the PepMSND leak-free
  folds: OOF AUROC **0.842**, ECE 0.053, epistemic std 0.127. `results/stability_predictor_metrics.json`.
- **Step 2 — developability-scored generation ✅** Scored all 272 cyclic designs (from the eval
  `none` run) → predicted stability + uncertainty, ranked (`score_generation.py`,
  `results/generation_developability.json`). Designs mean P(stable) 0.462 vs reference 0.438 —
  **reference-level** (generation isn't yet guided toward stability); top-10 at 0.83–0.91,
  uncertainty 0.06–0.15. The generate→verify→rank loop is demonstrated end-to-end, in silico.
  - **Observation to watch:** many top-ranked designs are **cysteine-rich** — the generator (fine-
    tuned partly on disulfide-cyclized peptides) produces CYS-heavy sequences, and the stability
    model may score CYS-rich peptides high by association. Flag before trusting; a real synthesis/
    assay would test it.

- **Step 3 — property-directed selection ✅** (`property_guided_selection.py`,
  `results/property_guided_selection.json`) Best-of-k by predicted stability on the 272 designs
  (4/target): k=1→0.461, k=2→0.553, k=3→0.605, k=4→**0.635** vs random pick 0.462 — a **+0.17
  lift**, monotonic with budget. The generate→verify→**select** (acquisition) loop works end-to-end.
  Proxy caveat: selecting by the same predictor we report; the lift shows a selectable spread, not
  proven real stability (needs wet lab). Larger-N budget needs a GPU generation run.

### Bet-1 remaining levers (scoped)
1. **Differentiable latent stability surrogate** → true sampler-guidance (bias sampling, not just
   select). The current predictor (fingerprint HistGBM) isn't differentiable through the latent.
2. **Scale generation budget** (more attempts/target) → extend the best-of-N curve higher (GPU).
3. **Fold in permeability** — match its CycPeptMPDB featurization; strengthen past scaffold-R² 0.1–0.3.
4. **Close macrocyclization** (Phase-1 atom-space closure) so designs are scored as true cyclics.

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
