# M6 cryo-EM density guidance for OM-TPS

The **real M6 code artifact**: a differentiable cryo-EM density log-likelihood that plugs into OM-TPS's
Onsager–Machlup action as one additive scalar term — the injection point verified in
`OM-TPS/two-for-one-diffusion/actions.py`. Destined for the OM-TPS container patch.

## Files
- `density_guidance.py` — standalone (torch-only) module:
  - `simulate_density(coords, grid, sigma)` — rigid-atom Gaussian map simulation, differentiable.
  - `cc_nll(rho, d_exp)` — 1 − real-space cross-correlation (standard cryo-EM fit score).
  - `density_term(path, grid, d_exp, sigma, tau)` — soft-min-over-frames nll: the density constrains WHICH
    frame(s) visit the observed state (a path waypoint), not a per-frame pull to one map (that would be
    endpoint/state fitting → the reduction trap).
  - `guided_action(action, path, grid, d_exp, sigma, lam)` — OM action (real `actions.py`) + λ·density term.
    Handles `HutchinsonAction` (needs `forces=None`, computes force + divergence internally / double-backward)
    vs `TruncatedAction` (needs forces passed).
- `test_density_guidance.py` — engineering validation (torch-only, CPU, $0). Imports the REAL OM-TPS
  `actions.py`.

## Validation status (2026-08-18, `omtps-core` conda env, torch 2.2.2, numpy<2, CPU)
- **TEST 1 — gradient correctness:** finite-diff vs autograd max err **1.2e-10**. PASS.
- **TEST 2 — composition:** works with real `TruncatedAction` and `HutchinsonAction`; density measurably changes
  objective + gradient. PASS. (Caught a real integration bug: Hutchinson must get `forces=None`.)
- **TEST 3 — path response + ablation:** at λ scaled to the OM magnitude, an informative (off-path) anchor pulls
  the path toward the observed state (closest-approach 2.877→1.750) and moves it MORE than an agreeing anchor
  (RMSD 1.31 vs 0.27) — the ablation logic in miniature. PASS.
- **Finding:** λ must be scaled to the OM-action magnitude (here OM ~1e4, nll ~O(1) → λ~1e4 to take effect). This
  is the guidance-weight schedule the real runs must tune.

## Scope (honest)
This validates the density-guidance **code** — correct gradient, correct composition with the real OM action,
expected path response. It is **NOT** scientific proof of M6. That requires the real pretrained base model
(MDGen/Boltz-2) + experimental kinetics (fast-folder/AdK) on GPU/Batch — see
`docs/20260818_CRYODYNAMICS_M6_DESIGN_AND_ABLATION.md`.

## Run
```bash
conda run -n omtps-core python test_density_guidance.py   # requires the OM-TPS clone at ../OM-TPS
```
