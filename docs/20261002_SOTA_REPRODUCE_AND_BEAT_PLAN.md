# Peptide Binder Generator — Reproduce-and-Beat SOTA Plan (DockQ)

**Date:** 2026-10-02
**Goal:** a peptide-binder generative model that **beats the current SOTA peptide co-design DockQ** (RADiAnce ≈ 0.770, UniMoMo ≈ 0.759) on the standard PepBench/LNR benchmark — model-intrinsic, not wet-lab.
**Scope:** reproducibility audit of RADiAnce + UniMoMo (+ next-best), the exact mechanism of their SOTA gain, apples-to-apples benchmark/numbers, ranked deltas to beat them, and the fastest credible route on our infra.

> **Honesty guardrail up front.** The headline numbers 0.7698 (RADiAnce) and 0.7592 (UniMoMo) differ by only **+0.011 DockQ**, over **100 stochastic samples per target on 93 targets**. Before we claim any "beat," we must (a) run on the **identical LNR/PepBench split**, (b) use the **identical sampling budget and aggregation** (mean-over-candidates vs best-of-N — read it from code, do not assume), and (c) report **seed variance**. A <0.02 DockQ improvement without variance bars is not a credible beat. This mirrors the project rule: fix/measure the real capability, never a number for reporting.

---

## 1. Per-model reproducibility table

| | **RADiAnce** | **UniMoMo** | **PepGLAD** (prior SOTA) | **PepFlow** (next-best class) |
|---|---|---|---|---|
| Paper | "Latent Retrieval Augmented Generation of Cross-Domain Protein Binders" (arXiv 2510.10480; OpenReview B7Bc9xzl2o, 2025/26) | "UniMoMo: Unified Generative Modeling of 3D Molecules for De Novo Binder Design" (ICML 2025; arXiv 2503.19300) | "Full-Atom Peptide Design with Geometric Latent Diffusion" (NeurIPS 2024; arXiv 2402.13555) | "Full-Atom Peptide Design based on Multi-modal Flow Matching" (ICML 2024; arXiv 2406.00735) |
| **Code public?** | **YES** — github.com/srhn225/RADiAnce | **YES** — github.com/kxz18/UniMoMo | YES — github.com/THUNLP-MT/PepGLAD | YES — github.com/Maikuraky/PepFlow |
| **Weights public?** | **NO** — README references `--ckpt /path/...` and a contrastive-VAE checkpoint, but **no download link**. Must retrain. | **YES** — checkpoint on the GitHub Releases page → `./checkpoints/model.ckpt`; cleaned inference code in `./api`, demo designs peptide/antibody/small-molecule binders to KRas G12C. | YES — codesign + conformation weights for PepBench. | YES (repo provides trained models). |
| **Training data + size** | Peptides: PepBench **4,157 train / 114 val**, test **93 (LNR)**. Antibodies: SAbDab **9,473 train / 400 val**, test **60 (RAbD)**. Fragments: ProtFrag **70,498** monomer-derived fragments. Interface retrieval DB spans all three domains. | Peptides: **4,157** complexes + **70,498** synthetic (PepBench + ProtFrag). Antibodies: **9,473 / 400** (SAbDab, >40% id filter). Small molecules: **99,900 train / 100 test** (CrossDocked2020). | PepBench: 4,157 train / 114 val / ~93–114 test. Peptide-only. | PepBDB + Q-BioLip derived split; peptide-only. |
| **Compute to train** | **8 × 80 GB GPUs** (A100/H100-class), parallel. Hours not stated. | Not stated in paper; same data scale + latent-diffusion ⇒ expect **multi-GPU 80 GB, days**. | Single/few-GPU, latent diffusion (lighter than the two above). | Multi-GPU flow-matching. |
| **Stand up on our AWS GPU as a new base?** | Code yes; **retrain required** (no weights) → need 8×80 GB (p4d/p5). | **Fastest** — public weights run inference **day 1**; retraining optional. | Yes, light. | Yes. |
| **Peptide co-design DockQ** | **0.7698** | **0.7592** | **0.592** | ~ (reports AAR/RMSD; lower DockQ class — superseded by PepGLAD→UniMoMo line) |

Sources for the table are listed at the bottom.

---

## 2. Mechanism of the SOTA gain — what actually drove 0.59 → 0.77

The jump is **two separable levers**, and they are not equal in size:

### Lever 1 (the big one, 0.59 → 0.76): unified full-atom latent diffusion + cross-domain data — UniMoMo
- **Full-atom latent diffusion** (inherited from PepGLAD): an **iterative full-atom autoencoder** compresses each residue/fragment "block" to a low-dim latent point (8-d hidden + 3-D coordinate), then an **E(3)-equivariant diffusion** runs in that latent space, with a 2-stage / 10-step iterative decoder back to all atoms. This is what made PepGLAD (0.592) full-atom and already beat backbone-only methods (DiffAb 0.586, dyMEAN 0.374, AF2 0.355 on the same conformation benchmark).
- **UniMoMo's contribution on top (0.592 → 0.759):** a **single unified model** over a **graph-of-blocks** representation where a "block" is *either a standard amino acid or a molecular fragment* (principal-subgraph tokenization). Training jointly on **peptides + antibodies (9,473) + small molecules (99,900) + 70,498 fragments** gives **cross-domain knowledge transfer** — the peptide head benefits from the antibody/fragment/small-molecule interface geometry seen during joint training. **This cross-domain corpus + unified full-atom representation is the single biggest lever behind the SOTA.**

### Lever 2 (the thin top, 0.759 → 0.770, +0.011): retrieval augmentation — RADiAnce
- A **contrastive all-atom VAE** encodes *binding sites* and *binder interfaces* into a **shared contrastive latent space**, trained with reconstruction + KL + contrastive loss so a binding-site latent is near the latents of interfaces that actually bind it.
- At generation, the binding site **retrieves** relevant interface templates (peptide / antibody / protein-fragment) from the cross-domain DB by dot-product similarity; the retrieved interface embeddings are injected into the **latent diffusion denoiser via cross-attention + residual MLPs** ("compressed yet informative prompts"). This lets the model **copy proven interface geometry/residue preferences** into the new design.
- Net effect on peptides is **small (+0.011)** — retrieval helps most on data-scarce domains (antibody AbH3 0.9491 → 0.9582). On peptides, where PepBench already has data, the marginal lift is modest.

### Takeaway for us
> The big win is **unified full-atom latent diffusion trained on a large cross-domain corpus** (UniMoMo). Retrieval (RADiAnce) is a thin, cheap top layer. **Neither model uses a co-folding structural prior (AF3/Boltz/BoltzGen) inside the loop, and neither does best-of-N re-ranking against a learned structure scorer.** Those are the open, high-yield levers.

---

## 3. Exact benchmark / numbers (for apples-to-apples)

- **Benchmark:** **PepBench** (from PepGLAD, NeurIPS 2024) for train/val; **LNR benchmark = 93 protein–peptide test complexes**, peptide length 4–25 residues. This is the split both UniMoMo and RADiAnce report on.
- **Task:** **sequence–structure co-design** (generate both peptide sequence and full-atom bound structure given the binding site). Distinct from the **conformation-generation** sub-task (fixed sequence) that the older sota2 leaderboard tracks (PepGLAD 0.592, DiffAb 0.586, HSRN 0.508, FlexPepDock 0.393, dyMEAN 0.374, AF2 0.355).
- **Sampling budget:** **100 candidates per target** (both papers).
- **Metric:** DockQ (0–1) plus AAR, C-RMSD, ΔΔG/ΔG, IMP, ISM.
- **Headline co-design numbers (RADiAnce paper, extended Table 13 for DockQ):**

| Model | Peptide DockQ (LNR, n=100) | AAR | C-RMSD (Å) | Antibody H3 DockQ |
|---|---|---|---|---|
| **RADiAnce** | **0.7698** | 39.42% | 2.29 | 0.9582 |
| **UniMoMo** | **0.7592** | ~39.45% | 2.19 | 0.9491 |
| **PepGLAD** | **0.592** | 38.62% | 2.74 | — |

> **To beat:** generate on the **same 93 LNR targets, n=100, same DockQ aggregation**, and clear **0.770 with variance bars**. Confirm aggregation in `PepGLAD`/`UniMoMo` eval code (whether DockQ is mean-over-100 or best-of-100) *before* reporting — this is the #1 apples-to-apples trap.

---

## 4. Ranked deltas to BEAT 0.77 (actionable, with feasibility on our infra)

Our assets: **BoltzGen co-folder**, a **PepGLAD/M2c latent-diffusion stack**, **~11k mined peptide complexes** (+ can add SAbDab antibody + PDBbind small-molecule), **AWS GPU**.

| # | Delta (lever) | Why it should exceed 0.77 | Feasibility on our infra |
|---|---|---|---|
| **1** | **Co-fold re-ranker / best-of-N (test-time scaling).** Sample N candidates from our generator (or from UniMoMo weights), fold each binding-site+designed-peptide with **BoltzGen/Boltz**, rank by predicted **ipTM / pDockQ / interface-confidence**, return the top. | Neither RADiAnce nor UniMoMo uses a structure-prediction prior to *select* candidates. A strong co-fold scorer over 100–1000 samples raises reported DockQ directly (it is literally selecting higher-DockQ designs). Highest yield-per-effort; **does not require winning the generative race**. | **Immediate / cheap.** We already have BoltzGen. No retraining. Pure inference + ranking. **Do this first.** |
| **2** | **Match RADiAnce's data+retrieval advantage on our own stack.** Add our ~11k peptide complexes + SAbDab (antibody) + PDBbind (small-mol) into a unified cross-domain training corpus; add a **contrastive-VAE retrieval head** feeding the denoiser via cross-attention. | This is exactly the two levers that produced 0.59→0.77. Replicating cross-domain data + retrieval on a stack we own is the principled route to a *generator* that matches them. | **Medium.** Needs 8×80 GB (p4d/p5) training runs; we own the M2c/PepGLAD code to graft retrieval onto. |
| **3** | **Stronger learned ranker = co-fold ipTM + FoldX/Rosetta ΔG + retrieval-similarity ensemble.** Train a lightweight scorer to predict DockQ from these features; use it for best-of-N. | Turns #1 from a single-signal filter into a calibrated selector; squeezes more DockQ out of the same samples. | **Low-medium.** Features are cheap once BoltzGen + PyRosetta are stood up. |
| **4** | **Cyclic-peptide–specialized variant (white space).** RADiAnce/UniMoMo target *linear* peptides; neither reports a cyclic benchmark. A cyclic-specialized model (macrocycle constraints, head-to-tail/disulfide closure) can claim **SOTA on a cyclic benchmark where they have no entry** (e.g. CPSea / cyclic PepBench subsets). | Uncontested metric; aligns with our macrocycle closed-loop program. Beats "0.77" on a *different, defensible* axis rather than fighting a +0.011 linear-peptide margin. | **Medium.** We have macrocycle domain assets; needs a cyclic test set curated. Strategic hedge, not the primary 0.77 attack. |
| **5** | **Test-time scaling (100 → 1000 candidates) + diversity sampling**, paired with the #1/#3 ranker. | More samples + a good selector monotonically improves best/aggregate DockQ until the generator ceiling. | **Easy but compute-linear.** Cheapest confidence boost once the ranker exists. |

**BoltzGen context:** BoltzGen (MIT, bioRxiv 2025) is an all-atom generative *co-folder* that unifies design + structure prediction and hits ~66% nanomolar success on hard novel targets and ~80% on benchmark targets (PD-L1/TNFα) — evidence the **unified design+co-fold** direction is the frontier. We hold this model; using it as a **scorer/selector** (delta #1) is the single most leverage-efficient move.

---

## 5. Honest path — is beating 0.77 realistic, and the fastest route (A vs B)

**Is it realistic?** Yes, but qualify it. The linear-peptide margin over UniMoMo is only **+0.011**; genuinely beating the generative frontier by retraining a bigger generator is a hard, 8×80 GB, multi-week fight for possibly-in-noise gains. The **credible and fast** path to "> 0.77" is **test-time selection with a co-fold prior** (delta #1) — a lever neither SOTA model uses — layered on a strong base. Cyclic specialization (delta #4) is the credible *second* SOTA claim on uncontested ground.

**Route A — reproduce RADiAnce/UniMoMo, then improve:**
- RADiAnce: code public, **no weights** → full 8×80 GB retrain just to reach parity. Slow.
- UniMoMo: code **and weights** public → stand up **day 1**, verify 0.759 on LNR as our ground-truth baseline.

**Route B — build on our PepGLAD/M2c stack + graft their key levers:**
- We already own the latent-diffusion stack and the data pipeline; add cross-domain corpus (11k peptide + SAbDab + PDBbind) and a retrieval head → an **ownable** generator, no dependency on others' unreleased weights.

**Recommendation — hybrid, B-led:**
1. **Day 1–3 (A, minimal):** pull **UniMoMo public weights**, reproduce **0.7592 on the 93 LNR targets, n=100**, and **pin the exact DockQ aggregation** from the eval code. This is our verified baseline and apples-to-apples harness. (Do **not** sink time into retraining RADiAnce — no weights, low marginal payoff.)
2. **Day 3–10 (delta #1, the fast beat):** wrap a **BoltzGen best-of-N re-ranker** around (a) UniMoMo samples and (b) our M2c samples. Measure DockQ on LNR with the pinned aggregation. **This is the fastest credible route across 0.77** because it exploits a lever both SOTA models omit and needs no training.
3. **Day 10+ (B, the ownable SOTA generator):** on our M2c/PepGLAD stack, train the unified cross-domain + retrieval generator (deltas #2/#3) on 8×80 GB, and in parallel curate a **cyclic benchmark** for delta #4 to claim SOTA on uncontested ground.

**Why B over A as the base:** RADiAnce ships no weights (A is a cold 8×80 GB retrain for parity), whereas we already own an equivalent latent-diffusion stack; building on it avoids the retrain tax, keeps the model ours, and lets us add the one lever (co-fold re-ranking) that actually clears 0.77 fastest. **Fastest to a defensible beat = B-based generator + UniMoMo weights as the day-1 baseline + BoltzGen re-ranking as the immediate 0.77-crossing lever.**

---

## Sources
- RADiAnce — arXiv: https://arxiv.org/abs/2510.10480 ; HTML: https://arxiv.org/html/2510.10480 ; OpenReview: https://openreview.net/pdf?id=B7Bc9xzl2o ; code: https://github.com/srhn225/RADiAnce
- UniMoMo — arXiv: https://arxiv.org/abs/2503.19300 ; HTML: https://ar5iv.labs.arxiv.org/html/2503.19300 ; ICML 2025: https://proceedings.mlr.press/v267/kong25b.html ; OpenReview: https://openreview.net/forum?id=KUN7A7Okb6 ; code+weights: https://github.com/kxz18/UniMoMo
- PepGLAD — arXiv: https://arxiv.org/pdf/2402.13555 ; code: https://github.com/THUNLP-MT/PepGLAD ; PepBench dataset: https://doi.org/10.5281/zenodo.13373108 ; NeurIPS 2024: https://neurips.cc/virtual/2024/poster/95784
- PepFlow — arXiv: https://arxiv.org/abs/2406.00735 ; code: https://github.com/Maikuraky/PepFlow
- PepBench conformation leaderboard (older conformation sub-task): https://www.sota2.com/research/sota/binding-conformation-generation-on-pepbench-test
- BoltzGen — PubMed: https://pubmed.ncbi.nlm.nih.gov/41394589/ ; Benchling build notes: https://www.benchling.com/blog/behind-the-model-building-boltzgen-with-hannes-staerk
- Related full-atom 2025 methods (context): Riemannian–Euclidean Bayesian Flow Networks https://arxiv.org/html/2511.14516 ; Memory-Efficient Equivariant Transformer https://arxiv.org/pdf/2606.25006
