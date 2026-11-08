# New plan — structure-grounded, physics-verified closed loop for cyclic-peptide design

**Date:** 2026-10-22 · The ambitious/SOTA plan, replacing the sequence-level simple work (monomer-composition
oracle + HistGBM + sequence-DPO) that under-performed (permeability 0.3 vs SOTA 0.77; cross-target NULL; DPO +0.098).

## Thesis (what the error analysis forces)
Every shortfall is a **sequence-level ceiling**:
- permeability 0.3 ← monomer-composition features (SOTA CycPeptMP uses atom+monomer+peptide **3D multi-level**);
- cross-target NULL ← AA-composition target vector (`target_features_matter: false`) — sequence features don't transfer;
- DPO +0.098 ← weak sequence oracle reward.

**So move representation, generation, scoring, and reward from sequences to the 3D target–peptide COMPLEX.** Cross-target
transfer should happen through **shared pocket geometry / physics**, not target→sequence correlations. The least-circular
"wet-lab" is **physics (FEP)**, which is inherently structural. This unifies all three fixes under one principle.

## Assets already in hand (wire, don't rebuild)
- **PepGLAD** — 3D co-design generator + **Diffusion-DPO trainer (built, CPU-selftested)**.
- **BoltzGen / Boltz-2 cofold** — peptide–protein complex structures (adopted, validated converter).
- **ChemBERTa ligand embeddings** (`results/chemberta_emb_cyclic.npz`) + **ESM target embeddings** (`results/target_esm_emb.npz`) — both present, unused in the simple pipeline.
- **FEP ΔΔG reward hook** (`ddg_fep` in score/physics_dispatch/reward) — wired; CaDA-Mn metal FF validated.
- **Data:** 106-target measured affinity (`c2_staged`), CycPeptMPDB permeability, display pools.

## Phases

**P1 — Structure-based representation + oracle (attacks permeability + the reward bottleneck).**
Ligand = 3D conformer-ensemble (chameleon) + ChemBERTa; target = ESM + cofolded pocket geometry; multi-level fusion
oracle (toward CycPeptMP 0.77). *Deliverable:* permeability oracle approaching SOTA; a structure-based affinity scorer.
*(Immediate, mostly CPU; the running feature-tier error analysis is its first rung.)*

**P2 — Pocket-conditioned 3D generation (attacks cross-target).**
Generate the peptide **inside the cofolded target pocket** (BoltzGen/PepGLAD pocket-conditioned), so the model learns
pocket→binder *geometry*, not target→binder *sequence*. *Deliverable:* a target-**structure**-conditioned generator.

**P3 — Physics-verified closed loop = the simulated wet-lab (the moat).**
Reward ladder: cofold ipTM/plausibility → MM-GBSA feasibility → **FEP ΔΔG (gold, least-circular assay)**. Close the loop
with **Diffusion-DPO** on the 3D generator, reward = FEP ΔΔG (already wired). The physics assay *is* the simulated wet-lab.

**P4 — The decisive experiment (SOTA + publishable).**
**Leave-one-target-out** across ≥3 same-chemistry targets: train the structure-grounded loop on N−1, generate for the
held-out target, score held-out designs by **independent physics (FEP)** and ultimately a small **wet-lab panel**.
- **Success = held-out cross-target enrichment ABOVE the 3–8% SOTA band AND above adopted BoltzGen**, per-target with uncertainty.
- Baselines: BoltzGen unchanged, the within-target selector, random/size-matched.
- Refutation = NULL → the honest data-wall result (still publishable as a rigorous negative).

**P5 — Publication-standard evaluation.** Leakage-safe (cluster + leave-targets-out) splits; MOSES/GuacaMol metrics
(validity/novelty/diversity/**FCD**); PMO oracle-budget AUC; the physics-assay prospective win; honest negatives reported.

## The one innovation claim this is built to prove
> **Structure-pocket-conditioned generation + physics-verified RLVR achieves execution-verified cross-target cyclic
> generalization above the SOTA band — where sequence-feature transfer is NULL and naive generator fine-tuning is
> NEGATIVE.** That is new (not just assembled), beats SOTA if it lands, and is publishable; a clean NULL is the
> honest data-wall paper.

## Honest cost / risk
- GPU-heavy (cofold + FEP + 3D diffusion). **Phase it;** the decisive LOTO needs only a few targets.
- **FEP is the cost gate** (~GPU-days/edge) — run only the control-edge-validated, congeneric subset; use Spark/spot.
- The cross-target wall may be **data-fundamental** even with structure — the honest refutation is itself the result.
- **Wet-lab remains the only non-circular endpoint;** physics is the best simulated proxy, not a substitute.

## First move
P1 is runnable now and mostly CPU: finish the feature-tier error analysis, then build the **structure-based oracle**
(ChemBERTa + ESM + chameleon-3D fusion) and measure it against the permeability SOTA and as the cross-target affinity
scorer. If it clears the sequence-level ceiling, P2–P4 (GPU) are justified; if not, we've learned the wall is deeper
before spending GPU.
