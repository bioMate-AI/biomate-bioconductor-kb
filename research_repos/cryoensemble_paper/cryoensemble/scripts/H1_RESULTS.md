# H1 series — what each variant told us (chronological)

**System.** ADK 4AKE→1AKE open/closed, RMSD 7.13 Å.  Synthetic 200 particles at 5 % closed
population, full CTF, Gaussian noise σ=0.05.

| ID | Prior | Method | Posterior on RMSD<2Å to closed | Min RMSD reached | Verdict |
|---|---|---|---|---|---|
| H1a | 15 open-perturbations (σ=0.5 Å, all ~0.86 Å from open) | EM-mixture reweighting | **0.000** | 7.11 Å (unchanged) | expected — pool has no closed conformers |
| H1b | same pool | EM-DPS, η_lik=0.5, σ_kernel=5.0, 12 traj × 50 steps | **0.000** | 6.98 Å (moved 0.13 Å) | KDE prior over-rules likelihood gradient |
| H1c | **AlphaFlow-MD+Templates** ensemble (30 conformers from 4AKE template — RMSD-to-open 1.4–4.7 Å, pairwise 2.17 Å) | EM-DPS, same hyperparameters | **0.000** | 4.57 Å (was 4.07 Å — **moved 0.5 Å AWAY** from closed) | a real generative prior generated diverse conformers but KDE-smoothed DPS still attracts trajectories to the prior's central mass |

## Diagnosis

1. **Reweighting** (H1a, RW arm of H1c) is fundamentally constrained to the convex hull of
   the prior pool. Without a prior member near closed, posterior weight on closed is
   identically zero. Pre-registered as expected.

2. **Cached-mode DPS** (H1b, DPS arm of H1c) wraps a fixed conformer pool as a kernel-
   density estimate and combines its smooth score with the likelihood gradient. The KDE
   smoother *pulls back toward the pool* with magnitude proportional to its kernel width
   — the broader the kernel, the weaker the pull, but also the less informative. In
   practice the prior's KDE mass always dominates, and trajectories never escape the
   pool's convex region. Net: cached-mode DPS approximates a *softened* reweighting,
   not an off-manifold extrapolation.

3. **AlphaFlow's pool itself spans real conformational diversity** (mean pairwise 2.17 Å,
   max 4.7 Å) but does not reach the closed state (min 4.07 Å). The closed state is
   ~4 Å past the prior's coverage. A 5%-population particle signal at this distance,
   filtered through KDE-smoothed responsibilities, is not enough to drive any
   trajectory the remaining 4 Å.

## What this tells us about the framework

The fixed-pool / cached-prior versions of the algorithm are **definitively insufficient**.
The proposed framework's novelty stands or falls on **true neural-score DPS** —
calling AlphaFlow's `model.inference()` at each DPS step so that the score field is
the *learned generative prior's* score, not the KDE smoothing over a few of its
samples. Only this version can in principle extrapolate beyond the sample pool, because
AlphaFlow's score at any point in protein-conformation space tells the integrator
where the model believes valid conformations exist — not just where the few samples
we drew happen to lie.

## Plan

H1d (true neural-score DPS): call AlphaFlow inside the DPS loop. Two implementations:

  - **In-container DPS**: run the entire CryoEnsemble loop inside the AlphaFlow Docker
    image (we have it built, v1.0.3). At each DPS step, call
    `AlphaFlowWrapper.inference(batch, schedule=[t, s])` to advance the protein one
    flow step, then add the per-particle likelihood gradient scaled by η_lik. This is
    the most direct test.
  - **Service-mode DPS**: keep CryoEnsemble locally; expose AlphaFlow as a gRPC/HTTP
    service that takes `(x_t, t)` and returns `E[x_0|x_t]`. Each DPS step is a remote
    call. Latency-tolerant; can run from local GB10.

In-container is simpler and faster to set up. Will be H1d's first attempt.

## What this does NOT change

- The PriorAdapter / DPS sampler framework code is unchanged — it's the prior wiring
  that's swapping from cached-KDE to neural-score.
- The H1a/b/c negative results are publishable as motivation, since they precisely
  delineate which baselines do and do not solve rare-state recovery.
- The proposal's central deliverable (per-particle conditioning, multi-prior
  framework, rare-state recovery) is intact — just shifted from "any prior plus DPS"
  to "neural-score prior plus DPS".
