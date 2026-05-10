# Blog Notes: Physics-Based FEP vs AI for Free Energy Prediction

Source: `Physics_vs_AI_free_engery_prediction.jpg`, `Physics_vs_AI_free_engery_prediction3.jpg`

## Source

ByteDance Research + Anew Therapeutics collaborative study comparing AI scoring functions against physics-based FEP in prospective drug discovery settings.

## Core Finding

AI models (graph neural networks, transformer-based) consistently **outperform FEP on retrospective benchmarks** but **underperform FEP on prospective de novo projects**. The benchmark → reality gap is real and large.

## Why the Discrepancy

- **Retrospective benchmarks** test on congeneric series with similar scaffolds to training data → AI exploits latent similarity
- **Prospective de novo** projects introduce novel scaffolds with no close analogs → AI extrapolates out of distribution
- Physics-based FEP makes no structural similarity assumptions; it computes thermodynamic perturbation integrals directly

## Practical Recommendations (from the paper)

1. Use AI for **hit-to-lead** speed (screening large chemical spaces cheaply)
2. Use FEP for **lead optimization** confirmatory calculations (especially for novel chemotypes)
3. "AI is an accelerator, not a replacement" — FEP provides prospective reliability that AI cannot yet match

## Implications for BioMate

BioMate's docking pipeline uses Vina/Glide binding score. Neither is FEP. For clients doing serious lead optimization:
- A FEP-ready workflow (OpenFE, Perses, or Schrodinger FEP+) would be a meaningful differentiator
- At minimum, uncertainty quantification on AI scoring outputs would surface when FEP referral is warranted
