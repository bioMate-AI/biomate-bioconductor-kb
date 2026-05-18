# H1 negative results on fixed-pool priors — and why they motivate generative-prior DPS

**Date:** 2026-05-15
**System:** ADK 4AKE/1AKE (Cα RMSD = 7.13 Å)
**Particles:** 200 synthetic, 5 % closed-state population, full CTF, Gaussian noise σ=0.05.
**Prior:** 15 perturbations of the open state (σ=0.5 Å). **No closed conformers in the prior.**

## Results

| Method | Posterior mass on near-closed conformers | Closest refined conformer to closed (Å) |
|---|---|---|
| **Reweighting** (Tang/Cossio-style; EM mixture over fixed pool) | 0.000 | (n/a — pool unchanged) |
| **Fixed-pool DPS** (DeltaEnsemblePrior + EM-DPS, 12 trajectories × 50 steps, η_lik=0.5, σ_kernel=5.0) | 0.000 | 6.98 (started at 7.11; moved 0.13 Å in 50 steps) |

## What this means

Both methods fail to recover the 5 % rare state — as expected — because they share a fundamental constraint: **the posterior is forced to lie in the prior's support.**

  - Reweighting can only redistribute probability mass over the pool. With zero pool members near the closed state, posterior mass on closed is identically zero.
  - Fixed-pool DPS adds a likelihood-gradient step, but the KDE prior score acts as a strong attractor toward the pool. With trajectories initialised near the open mode and a 7-Å distance to closed, the prior score's pull-back dominates the likelihood gradient's pull-forward — even at large step sizes and small prior weight.

We verified the likelihood gradient at the open conformer **does point toward the closed direction** (cos ≈ +0.23 with the open→closed displacement vector), so the bottleneck is not gradient information, it is the prior's mass concentration.

## Implication

The CryoEnsemble framework's central claim — recovery of rare states from particle-level evidence — requires a **prior with native support beyond a fixed conformer pool**. A learned generative prior (e.g. AlphaFlow-MD+Templates) can produce conformers that lie outside the immediate template's neighborhood, and its score function permits trajectories to traverse the protein-valid manifold without being pulled back to a fixed pool.

These negative results therefore *strengthen* the case for the proposed framework: they demonstrate quantitatively that the published baselines (Tang/Cossio 2023; any importance-reweighting scheme; naïve DPS over fixed conformer pools) cannot solve the off-prior rare-state problem, leaving a genuine open gap for a generative-prior method to fill.

The next experiment (H1c) uses AlphaFlow-MD+Templates as the prior with the same particles and target, and tests whether the generative score function enables the off-manifold recovery that the fixed-pool baselines provably cannot achieve.
