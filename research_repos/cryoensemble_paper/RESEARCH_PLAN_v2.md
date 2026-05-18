# CryoEnsemble v2 — Research Plan (Post-Survey)

**Status:** Re-designed 2026-05-14 after literature audit revealed that per-particle reweighting (Tang/Cossio 2023) and per-particle SBI (Dingeldein/Cossio 2025) are already published. The survey identifies a narrower, genuinely-unaddressed gap.

---

## 1. The unaddressed gap

Every existing method that conditions cryo-EM on a generative prior treats the prior as a **fixed sample set**:

| Method | Prior representation | Inference |
|---|---|---|
| Tang, Cossio, Hummer (JPC-B 2023) | Fixed MD trajectory | Bayesian reweighting (importance sampling) |
| cryoSBI (Dingeldein et al., PNAS 2025) | Fixed discrete templates | Amortized neural posterior estimation |
| Silva-Sánchez, Cossio (bioRxiv Dec 2025) | Candidate set + physical constraints | Coordinate perturbation under constraints |
| cryoPhold (Sep 2025) | AlphaFold ensemble | Map-level BME reweighting |
| CryoBoltz (Jun 2025) | AF3 / Boltz model | Map-level guidance |
| **Proposed CryoEnsemble** | **Pretrained generative model** | **Diffusion posterior sampling (DPS) through the prior** |

The crucial difference: in DPS the prior is **not** a fixed point cloud but a generative score field. Samples from the posterior can lie **off the convex hull of the prior's training distribution**, because the data-consistency gradient pulls them toward what the particles support while the prior's score keeps them on the manifold of valid protein conformations.

This is well-established in image restoration (Chung et al. NeurIPS 2022, Song et al. ICLR 2022) but **has not been applied to cryo-EM conformational heterogeneity with a protein-structure prior**.

---

## 2. The contribution — restated precisely

**DPS-EM: Diffusion Posterior Sampling for cryo-EM conformational heterogeneity, using pretrained protein structure generative models as priors.**

Three component contributions:

### C1 — Algorithm
A DPS sampler whose update is

    x_{t-1} = denoise_θ(x_t)  +  η · ∇_{x_t} log p(particles | x_t, pose, CTF)

where `denoise_θ` is the score/denoiser of a pretrained protein generative model (BioEmu, AlphaFlow, RFdiffusion, or future) and the second term is the per-particle cryo-EM likelihood gradient.

### C2 — Generative-prior interface
A standardized adapter that wraps any pretrained protein structure model exposing either:
- a denoiser ε_θ(x, t) (true diffusion models: RFdiffusion, AlphaFlow's flow-equivalent),
- an unconditional sampler (BioEmu, AF3 multi-seed) → wrap via Tweedie's formula or via replicated forward passes,

into a single `PriorAdapter` API. Future protein models plug in by implementing this interface.

### C3 — Multi-prior mixture
Different priors capture different motion types. We combine them at inference time using particle-evidence-weighted mixture: 

    p(x | particles) ∝ Σ_k π_k(particles) · p_k(x | particles)

where π_k is the marginal evidence of prior k given the particle stack.

---

## 3. Falsifiable hypotheses

| ID | Hypothesis | Decisive metric | Pre-registered threshold | Pre-registered failure |
|---|---|---|---|---|
| **H1** | DPS recovers rare states **off the prior's training distribution**; reweighting cannot. | Rare-state recall when the prior contains *only* the dominant state. | DPS: ≥ 0.5; reweighting: ≤ 0.05. | If DPS = reweighting, the DPS step is doing nothing — failure of C1. |
| **H2** | DPS through a pretrained prior matches or beats Tang/Cossio's per-particle reweighting on its own benchmark. | Per-state recovery on CryoBench MD-derived subsets. | Recall@5% ≥ Tang/Cossio (within 0.05) on at least 3/4 CryoBench systems. | If we underperform Tang/Cossio with the same prior, our DPS isn't worth it. |
| **H3** | Multi-prior mixture > best single prior on systems with diverse motion types. | Recall on a mixed-motion benchmark (membrane GPCR active/inactive + intermediate). | Mixture ≥ max(BioEmu, AlphaFlow, AF3) + 0.1. | If single prior wins, multi-prior is overhead. |
| **H4** | Per-particle likelihood necessary (not just sufficient) for rare-state recovery. | Same prior + same DPS, swap per-particle ↔ map-level. | Per-particle ≥ 0.5; map-level ≤ 0.05 at 5% population. | If map-level matches per-particle, our likelihood choice is redundant. |
| **H5** | The framework generalises to out-of-training proteins. | Held-out membrane transporter not in any prior's training set; recovery curve. | Recall@10% ≥ 0.3 on a novel target. | If recovery collapses on a novel protein, the priors don't generalise. |

H1 and H4 are the **decisive** ones — they separate this work from Tang/Cossio.

---

## 4. Experimental program

### Tier 1 — Synthetic with controlled ground truth (weeks 1–3)

| System | RMSD | Why |
|---|---|---|
| ADK 4AKE/1AKE | 7.13 Å | Classic open/closed, simple |
| β₂AR 3SN6/2RH1 | ~14 Å (TM6) | Published GPCR pair; relevant to drug discovery |
| Calmodulin 1CFD/1CFC | ~3 Å | Small-RMSD case — hard |
| CryoBench MD subsets | mixed | Standard benchmark for the field |

Per-system, sweep rare-state populations {1%, 3%, 5%, 10%, 20%}, three priors {BioEmu, AlphaFlow, MD-snapshots}, two methods {DPS-EM (ours), reweighting (Tang/Cossio reimplemented)}. **5 replicates each.**

### Tier 2 — Real EMPIAR with published per-class ground truth (weeks 4–6)

- **EMPIAR-10076** (Davis 2016, 5 ribosome assembly intermediates) — primary cryoDRGN benchmark; class labels available.
- **EMPIAR-10180** (Plaschka 2017, 4 spliceosome states) — used by cryoSBI for direct comparison.
- **EMPIAR-10028** (β₂AR-Gs, we already have it) — single state but allows us to test rare-state injection from BioEmu's inactive-state predictions.

### Tier 3 — Head-to-head against published methods (weeks 7–8)

Direct comparison, same datasets:
- cryoDRGN-AI (Levy et al., *Nat Methods* 2025) — neural baseline
- RECOVAR (Gilles & Singer, *PNAS* 2025) — covariance-based baseline
- DynaMight (Schwab et al., *Nat Methods* 2024) — deformation baseline
- Tang/Cossio (JPC-B 2023) — per-particle reweighting (re-implemented)
- cryoSBI (Dingeldein et al., *PNAS* 2025) — per-particle SBI

### Tier 4 — Real-research application (weeks 9–10)

Apply the framework to a protein that:
- has limited cryo-EM data (one resolved state),
- is suspected to populate multiple states,
- is biologically important (likely the sister's protein, once Tiers 1–3 establish reliability).

This is the deliverable that demonstrates research value, not benchmark performance.

---

## 5. Honest assessment of what's hard

1. **Score-function exposure of BioEmu.** BioEmu publishes a sampler, not a score. Two options:
   - Wrap via Tweedie: `score ≈ (E[x_0|x_t] − x_t) / σ_t²` using BioEmu as a denoising oracle. Requires many forward passes.
   - Use AlphaFlow (Jing et al., arXiv:2402.04845) — already a flow model with a tractable velocity field that maps to a score.
   - Fall back: use a learned score head trained on BioEmu samples (~1 week of GPU).

2. **Pose / CTF calibration.** Established cryo-EM software (RELION/cryoSPARC) handles this; we need ASPIRE for forward-model compatibility. ~1 week of integration.

3. **Computational cost.** DPS = 50–200 sampler steps × O(seconds per step per conformer). For a 10k-particle stack with 20 conformers, 100 steps, ~1 sec/step on L4 → 56 hours. Solvable with batch-parallelism on multiple GPUs and amortization (one DPS run per dataset, not per particle).

4. **Pre-registration discipline.** We commit to the H1–H5 thresholds before running. If H1 fails, we publish the negative finding instead of cherry-picking metrics.

---

## 6. Deliverables (Google AI4Science Year 1)

| Month | Deliverable | Evidence |
|---|---|---|
| 1–2 | `dpsem` Python package: forward model (ASPIRE-backed), per-particle likelihood, EM mixture posterior, DPS sampler | passing unit tests + ADK synthetic recovery curve |
| 3 | `PriorAdapter` interface + 3 reference implementations (BioEmu, AlphaFlow, AF3-multi-seed) | drop-in swap works on the same pipeline |
| 4–5 | Tier 1 + Tier 2 results | preprint Methods sections + recovery tables |
| 6 | Head-to-head against 5 published baselines (Tier 3) | leaderboard table; if H1 fails, document and pivot |
| 7 | First preprint submission | bioRxiv |
| 8–9 | Tier 4 real-research case study (sister's protein, IF the framework works on benchmarks) | hypothesis-generation result for an experimentalist |
| 10 | Open release: code, weights, reproducibility scripts | GitHub + Zenodo DOI |

Year 1 milestone for the grant: rare-state recall ≥ 0.5 at 5% population on CryoBench, **with H1 confirmed**. If H1 fails, we publish that as a negative result demonstrating reweighting's sufficiency and switch the project's focus.

---

## 7. What to build right now (week 1 of the plan)

1. **`PriorAdapter` interface** — the central object. (~1 day)
2. **`bioemu_adapter.py`** — wraps BioEmu's sampler, exposes Tweedie-score for DPS. (~2 days)
3. **`mdsnap_adapter.py`** — wraps a fixed MD ensemble as a "delta" prior, for Tang/Cossio reimplementation. (~½ day)
4. **`tang_cossio_baseline.py`** — re-implement importance-reweighting baseline. (~1 day)
5. **`dps_sampler.py`** — DPS update loop alternating prior score and likelihood gradient. (~2 days)
6. **`adk_h1_h4_experiment.py`** — first decisive experiment, H1 and H4 on ADK synthetic. (~½ day)

7 days of focused implementation, then we run H1+H4 and gate on the result.
