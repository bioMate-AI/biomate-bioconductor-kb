# CryoEnsemble Experimental Design

**Goal:** Demonstrate that CryoEnsemble is genuinely better than existing methods, with rigorous head-to-head comparisons on the same data.

---

## The novelty claim — precisely stated

> *CryoEnsemble recovers rare conformational states (population <5%) from a cryo-EM particle stack that **(a)** map-level reweighting methods cannot recover by mathematical construction, and **(b)** data-only methods (cryoDRGN/-AI) cannot recover due to the particle-count resolution floor — provided that an external generative prior contains the rare state.*

Two pieces, separately testable:

1. **Per-particle vs map-level conditioning** (algorithmic novelty, independent of prior quality)
2. **External prior vs no prior** (the role of an MD/AI-derived prior in unlocking the rare state)

---

## Pre-registered hypotheses

| ID | Hypothesis | Decisive metric | Pre-stated threshold |
|---|---|---|---|
| H1 | At rare-state fraction ≤5%, **per-particle CryoEnsemble recovers > 0.5 posterior mass on the rare state**; **map-level BME recovers ≤ 0.05** | posterior_mass(rare_state) | difference ≥ 0.4 |
| H2 | At rare-state fraction ≤5%, **CryoEnsemble + good prior outperforms cryoDRGN-AI clustering** | rare-state recall (RMSD<2Å) | recall: CE ≥ 0.5; cryoDRGN ≤ 0.1 |
| H3 | When the prior **does not contain** the rare state, CryoEnsemble cannot recover it (failure mode is well-defined, not a hallucination) | posterior on rare-state region | < 0.05 with bad prior, > 0.5 with good prior |
| H4 | At normal SNR (σ_noise ≈ 0.5 z-scored), CryoEnsemble's population estimate is accurate within ±3 absolute pp of ground truth, **including at 2% fraction** | abs_error(population) | ≤ 0.03 |
| H5 | CryoEnsemble's failure mode is graceful (over-estimation by ~5pp) at very low SNR (σ=2.0); it does not silently produce false rare states | rare-state recovery when truth = 0 | < 0.05 |

H4–H5 are already supported by our ADK replicate study. H1, H2, H3 are the **decisive** ones.

---

## Experiments

### Experiment A — per-particle vs map-level (H1) [decisive, runnable now]

**System:** ADK 4AKE/1AKE (7.13 Å open↔closed), 214 Cα, well-validated pair.

**Design (factorial):**
- Method ∈ {CryoEnsemble (ours), BME map-level (cryoENsemble-style), data-only k-means (cryoDRGN-style)}
- Rare-state fraction ∈ {50%, 20%, 10%, 5%, 2%, 1%}
- 5 replicates each → 90 runs total

**Controlled variables:**
- Same prior (20 conformers: 10 open-perturbed + 10 closed-perturbed, σ=0.5 Å)
- Same particle synthesis (400 particles per run, real CTF, random SO(3) poses, noise σ=0.5)
- Same forward model
- Same evaluation script

**Outcome metrics:**
- `posterior_mass_closed`: posterior weight on the closed-state conformers
- `abs_error`: |posterior_mass_closed − rare_fraction_truth|
- `rare_state_recovered`: bool (posterior_mass_closed > 0.01)

**Pre-registered result:** at 5% truth, CryoEnsemble posterior on closed ≥ 0.04 (recall > 0.8); BME posterior on closed ≤ 0.05 (and effectively zero); cryoDRGN clustering produces 20 clusters all in the open mode (since closed particles are below the cluster-formation threshold at <5%).

**Falsification:** if BME or cryoDRGN recovers the closed state at <5% population, H1 fails.

### Experiment B — generalization across systems (H1, H2) [next, after A]

Repeat Experiment A on:
1. ADK 4AKE/1AKE (7.13 Å) — easy, big RMSD
2. β₂AR 3SN6 (active) / 2RH1 (inactive) — published 14 Å TM6 displacement
3. Calmodulin Ca²⁺-bound vs apo (1CFD/1CFC) — small RMSD (~3 Å), hard case
4. Adenylate kinase intermediate (4ZIN) — 3-state instead of 2-state

Same factorial design.

**Pre-registered:** CryoEnsemble wins on 1, 2, 3, ties or wins on 4. If it fails on 3 (small-RMSD case), that's a documented limitation.

### Experiment C — real cryo-EM benchmarks (H1, H2)

Use published benchmarks with known multi-state ground truth:
- **EMPIAR-10076** (Davis 2016): 5 ribosome assembly intermediates with class labels
- **EMPIAR-10180** (Plaschka 2017): 4 spliceosome states
- **CryoBench** (Jeon NeurIPS 2024): 4 synthetic-with-ground-truth systems

**Baselines (using their published numbers):**
- cryoDRGN-AI (Zhong 2025)
- 3DFlex (Punjani 2023)
- cryoENsemble (map-level BME)

**Outcome:** match or exceed published per-class recovery numbers.

### Experiment D — prior ablation (H3)

For each rare fraction in A:
- Arm A: prior contains both states (current setup)
- Arm B: prior contains ONLY the dominant state (no closed conformers)
- Arm C: prior contains the dominant state + wrong rare state (decoy)

**Pre-registered:** Arm B fails to recover (no posterior on closed) — proves we're not hallucinating; Arm C produces high entropy / low ESS — proves the method distinguishes good prior from bad.

---

## What's deliberately NOT in scope

- 3DFlex / DynaMight comparisons on real data — those need cryoSPARC/RELION pipelines I don't have set up; defer to Year 1 of the funded project.
- GenEM head-to-head — pending verification it exists. If it does, **a 5th experiment is required** before claiming novelty over them.
- Sister's protein — held back until Experiment A passes H1.

---

## Infrastructure decisions (informed by audit)

1. **Forward model:** keep ours for Experiments A & D (controlled synthetic; physics is trivial to verify); **switch to ASPIRE for Experiments B & C** when we hit real-data calibration issues (pose convention, CTF normalization).
2. **Baseline implementations:** implement BME and cryoDRGN-style k-means *in our codebase* with the same I/O so the comparison is apples-to-apples. (Map-level BME is ~30 lines; data-only k-means is ~20 lines.)
3. **Prior:** Experiment A uses curated PDB-derived prior. Real BioEmu prior comes in Experiments C+, with whatever diversity it actually produces.

---

## Order of execution

| Day | Run | Deliverable |
|---|---|---|
| 1 | Implement BME baseline + cryoDRGN k-means baseline in our codebase | `baselines.py` |
| 1 | Experiment A: 90 runs (3 methods × 6 fractions × 5 reps) on ADK | Table + per-method recovery curves |
| 2 | Experiment D: prior ablation | Failure-mode demonstration |
| 3–5 | Experiment B: 4 more PDB pairs | Cross-system generalisation table |
| 6+ | Experiment C: real EMPIAR benchmarks (gated on A, B passing) | Real-data wins |

If Experiment A fails H1, we stop and rethink. **No real-data run until the synthetic head-to-head proves the algorithmic advantage.**
