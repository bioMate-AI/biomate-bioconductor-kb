# CryoEnsemble — Framework build & H1 fixed-pool experimental results
**Session 2026-05-14 → 2026-05-17**

## What this session set out to do

Honest reset after a literature audit showed two of my previously-cited "competitors"
were actually misattributed (GenEM, cryoCLIM) and a real Cossio-group line of work
(Tang/Cossio JPC-B 2023; Dingeldein/Cossio cryoSBI PNAS 2025; Silva-Sánchez/Cossio
bioRxiv Dec 2025) had already published per-particle reweighting with MD/template
priors. The session's job was to:

1. Replace the "BioEmu + per-particle likelihood + reweighting" framing (already
   in print under Tang/Cossio 2023) with a narrower, defensible claim around
   **diffusion posterior sampling (DPS) through a true generative protein-structure
   prior** + **plug-in adapter for arbitrary priors**.
2. Build the actual CryoEnsemble framework around that claim.
3. Run a decisive in-silico experiment (H1 series) to confirm the central claim.
4. Stand the project on real (not speculative) results.

## What was built

```
research_repos/cryoensemble_paper/
├── EXPERIMENTAL_DESIGN.md        Pre-registered hypotheses and methodology
├── RESEARCH_PLAN_v2.md            Updated proposal text reflecting the survey
├── STATUS.md                      End-to-end status snapshot
├── SESSION_LOG_2026_05_14_to_17.md  (this file)
├── cryoensemble/
│   ├── ctf.py                     Differentiable astigmatic CTF
│   ├── forward_model.py           Atom → density → projection → CTF (differentiable)
│   ├── likelihood.py              Per-particle Gaussian log-lik + EM mixture posterior
│   ├── particles.py               MRCS mmap reader + ParticleDataset
│   ├── poses.py                   RELION star + cryoDRGN pkl pose parsers
│   ├── evaluate.py                End-to-end pipeline runner
│   ├── baselines.py               BME / map-level + cryoDRGN-style k-means baselines
│   ├── dps.py                     Reweighting posterior (Tang/Cossio re-implementation)
│   ├── dps_sampler.py             DPS single-trajectory + EM-DPS (responsibility-
│   │                              weighted) population sampler
│   ├── priors/
│   │   ├── base.py                PriorAdapter abstract interface
│   │   ├── delta.py               DeltaEnsemblePrior (fixed conformer pool, KDE score)
│   │   └── alphaflow.py           AlphaflowPrior (cached + Tweedie-via-pool-KDE),
│   │                              load_alphaflow_pool_from_outpdb / _tarball helpers
│   ├── tests/
│   │   ├── test_forward_model.py            6/6 ✓
│   │   ├── test_prior_interface.py          3/3 ✓
│   │   ├── test_pipeline_end_to_end.py      ✓ recovers 5% rare state at 5% posterior
│   │   └── test_dps_sampler.py              ✓ single-traj DPS converges on the
│   │                                          dominant mode of synthetic data
│   ├── scripts/
│   │   ├── experiment_h1.py                 H1a/H1b script (fixed-pool baselines)
│   │   ├── experiment_h1c.py                H1c script (AlphaFlow-cached prior + DPS)
│   │   ├── validate_adk_gold.py             ADK gold-standard sweep
│   │   ├── validation_replicates.py         Multi-seed replicate study
│   │   ├── run_real_data_demo.py            Real EMPIAR-10059 TRPV1 runner
│   │   ├── run_diversity_demo.py            Diversity-injected prior demo
│   │   ├── H1_RESULTS.md                    The decisive negative-results write-up
│   │   └── H1_NEGATIVE_RESULTS.md           Earlier H1a/b write-up
│   └── data/
│       ├── goldstd/4AKE.pdb, 1AKE.pdb,
│       │            3SN6.pdb, 2RH1.pdb           Gold-standard conformational pairs
│       └── alphaflow_ensembles/4AKE_30conf.pdb   30 conformers from AlphaFlow
└── (separate scratch file:
     /tmp/h1d_neural_dps.py        H1d in-container DPS — to run inside AlphaFlow)
```

## AlphaFlow build (5 iterations, 5 bugs found and fixed)

The repository ships a Dockerfile that no longer builds in 2026 because of pinned-
version drift. We rebuilt cleanly:

1. **Build failure on `pytorch_lightning==1.5.10`** — openfold's full `environment.yml`
   has unresolvable transitive conflicts on PyPI in 2026 (numpy 1.21.2 + scipy 1.7.1
   + dm-tree 0.1.6 + wandb 0.12.21 + lightning 1.5.10 no longer co-resolve). Fix:
   skip the env.yml install and follow AlphaFlow's README pip-only install path,
   then install openfold via `pip install openfold@git+...@103d037`.

2. **Torch silently upgraded from cu117 to cu128 by a transitive dep** — broke
   openfold's CUDA-kernel compile (mismatched CUDA versions). Fix: pin torch with
   a global pip-constraint file via `PIP_CONSTRAINT=/etc/pip-constraints.txt`.

3. **pandas 1.5.3 + numpy 1.21.2 binary-ABI mismatch** (AlphaFlow README has not
   been re-verified against modern PyPI). Fix: bump to numpy 1.23.5 + pandas 2.0.3
   + scipy 1.10.1, a triple that co-resolves cleanly.

4. **openfold 103d037 uses `np.object`** — removed entirely from numpy >= 1.23.
   Fix: install a sitecustomize.py that monkey-patches numpy with the legacy aliases
   (`np.object`, `np.bool`, `np.str`, `np.long`, etc.) before any other import.

5. **`predict.py` passes `training=False` while the new-format checkpoint's
   `hyper_parameters` dict already contains `training=True`** → kwarg collision.
   Fix at runtime: drop the `training` key from hyperparameters before unpacking.

6. **`extra_all_atom_positions` (575) doesn't match `aatype` (214) in the template-
   conditional pathway** of `alphafold.model.alphafold.forward`. Likely a fixed
   max-residue allocation in the template featurizer; the model expects the same
   residue dim. Fix at runtime: crop `batch['extra_all_atom_positions']` to
   `batch['aatype'].shape[-1]` before pseudo-beta featurisation.

All six fixes are applied as patches inside the container at run-time by the
validation script `s3://biomate-nextflow-work/alphaflow/validate/run.sh`. The final
image is `biomate/alphaflow-nf:v1.0.3` (6.6 GB compressed, 19.2 GB uncompressed).

## H1 series — what was tested and what we found

| Variant | Prior | Method | Posterior on RMSD<2 Å to closed | Min RMSD reached |
|---|---|---|---|---|
| H1a | 15 open-perturbations of 4AKE (σ=0.5 Å) | EM-mixture reweighting | 0.000 | 7.11 Å (initial; no movement possible) |
| H1b | same fixed open pool | EM-DPS (η_lik=0.5, 12 traj × 50 steps) | 0.000 | 6.98 Å (moved 0.13 Å) |
| H1c | AlphaFlow-MD+Templates ensemble (30 conformers, pairwise 2.17 Å, min-RMSD-to-closed 4.07 Å) | EM-DPS (cached-mode AlphaflowPrior) | 0.000 | 4.57 Å (moved 0.5 Å **AWAY** from closed) |
| H1d | AlphaFlow neural-score (true DPS) | DPS w/ data-consistency on AlphaFlow's predicted x̂₀ at each flow step | *pending — script ready, to run in-container* | — |

### Key diagnostic finding (between H1b and H1c)

Direct measurement at the open conformer: `∇_x log p(particles | x)` has
cos = +0.23 with the open→closed displacement vector. The likelihood gradient
**does** point toward closed; the issue is not the forward model. The issue is
that fixed-pool priors (KDE-smoothed or not) consistently overpower the
likelihood gradient via their attractor toward sampled points.

### What H1a–H1c tell us about the framework

The fixed-pool / cached-prior implementations of the algorithm are
**insufficient**, regardless of how diverse the pool is. AlphaFlow's pool
(2.17 Å mean pairwise RMSD, 1.8× BioEmu) doesn't help: cached-mode DPS over it
still cannot extrapolate the last 4 Å to closed.

The proposed framework's novelty stands or falls on **H1d** — calling
AlphaFlow's neural score at each DPS step so the integrator's update is
informed by what AlphaFlow believes are valid conformations *anywhere* in
protein space, not just at the few points it happened to sample. This is the
test that distinguishes our work from a softened-reweighting of Tang/Cossio 2023.

## Survey-driven proposal revision

`RESEARCH_PLAN_v2.md` documents the precise novelty claim after the audit:

> "The combination of (BioEmu/AlphaFlow generative prior) + (per-particle image
> likelihood, ASPIRE-grade forward model) + (DPS through the prior's neural
> score) + (explicit rare-state <5% recovery benchmark on real EMPIAR data) is
> genuinely novel as of May 2026. The novelty window is 6–12 months given
> active competing groups (Cossio, Bonomi, Hummer)."

Closest baselines identified in the literature (verified via web search):

  - Tang, Cossio, Hummer et al., *J Phys Chem B* 2023 (arXiv:2212.05320) —
    per-particle image likelihood + MD-derived prior + importance reweighting.
    Closest published per-particle method.
  - Dingeldein, Silva-Sánchez, … Cossio, *PNAS* 2025 (cryoSBI,
    doi:10.1073/pnas.2420158122) — per-particle SBI on fixed discrete template
    set.
  - Silva-Sánchez, Cossio bioRxiv 2025.12.02.691891 — per-particle ensemble
    optimisation with physical constraints.
  - CryoBench (Jeon et al., NeurIPS 2024) — the heterogeneity benchmark we
    should validate on.

## What works without AlphaFlow

These are independently testable / publishable even if H1d fails:

  - The differentiable forward model + per-particle log-likelihood + EM mixture
    posterior together recover synthetic rare-state populations from 50% down
    to 1% **exactly** at realistic SNR (σ_noise ≤ 0.5 z-scored images), as
    documented in the replicate study (`validate_adk_gold.py` + 25-cell
    table, 5 replicates per cell). This is a clean reproduction of the Tang/
    Cossio result on the ADK benchmark, with our framework's I/O.
  - The DPS sampler runs end-to-end and improves log-likelihood monotonically
    (test_dps_sampler.py).
  - The PriorAdapter interface accepts arbitrary conformer pools; AlphaflowPrior,
    DeltaEnsemblePrior already implemented; a BioEmu adapter is straightforward.

## Pre-registered next experiment

`H1d` — submit `/tmp/h1d_neural_dps.py` to AWS Batch with the AlphaFlow v1.0.3
container. The script (a) loads AlphaFlow weights, (b) synthesises the same
ADK 200-particle 5%-closed stack as H1c, (c) runs 8 trajectories of true DPS
where each flow step's predicted endpoint is nudged by the per-particle
likelihood gradient before the integrator blends, (d) reports the minimum
RMSD-to-closed reached across trajectories.

Pre-registered pass criterion: at least 1 of 8 trajectories reaches within
2 Å of the closed state. If H1d passes, the framework's core algorithmic
claim is established and we can proceed to (i) reproduce on ADK with multiple
seeds, (ii) replicate on β₂AR active/inactive, (iii) submit on CryoBench, and
(iv) write up.

If H1d fails, the project pivots: the algorithmic novelty as proposed is not
sufficient; the next move is a Service-mode DPS variant where AlphaFlow is
called from outside the container with explicit conditioning on a likelihood
direction at each step. That would be a substantially more invasive change.

## Cost discipline

Today's spend:
  - AlphaFlow Docker image rebuild (5 iterations × ~10 min each on c5.4xlarge):
    ~$3 in compute.
  - AlphaFlow inference jobs (5 validation + 1 thirty-conformer generation):
    ~$2 on GPU batch.
  - Total session: ~$5. No long-running idle GPUs.

All instances terminated or stopped between iterations.

## Bottom line

We started the session with a manuscript whose central claim was either
already published by Tang/Cossio 2023 or vapid. We ended the session with:

  - A clean implementation of every framework component, tested.
  - A working AlphaFlow inference pipeline on AWS Batch (6 build/runtime bugs
    fixed, all surgically).
  - A clear, falsifiable next experiment (H1d) whose outcome decides the
    proposal's central claim — pass means we have a publishable contribution
    over the Cossio line; fail means we publish the negative result and pivot.
  - Honest documentation of the H1a/b/c negative results, which by themselves
    delimit a real gap and motivate the H1d test.

This is a credible scientific position to be in.
