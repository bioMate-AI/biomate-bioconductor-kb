# Peptide LLM — what it measures well, the gaps, BioMate's assist, and the loop

**Date:** 2026-09-22 · **Inputs:** AI-drug commentary (可颂), Guangzhou ¥70M tender
(generation+optimization; 3 dims = SA · affinity · safety; 4 layers = Knowledge/Reasoning/
Generation/Optimisation), peptide model official eval.
**Purpose:** map the peptide LLM's measured coverage to the tender, name the honest gaps, show which
BioMate abilities fill them, and define how to do better in the generate→verify→learn loop.

## 1. Measured & covered WELL (Layer 3 + affinity-geometry)
Official eval (2026-09-21, LNR test set) — PepGLAD-class:
- **DockQ 0.516** (pose quality) · **Consistency 0.923** (seq↔struct) · RMSD-Cα 4.92Å
- Diversity: seq 0.984 / struct 0.789 / codesign 0.858 (no mode collapse)
- MacroGuide persistent-homology ring-closure guidance → valid macrocycles
- AAR 0.286 (explicitly NOT a headline metric — PepGLAD App. H.1)

→ Strong on **Generation (Layer 3)** and the **geometric half of target affinity**: diverse, all-atom,
correctly-posed peptide/macrocycle binders. One of the three tender dimensions, done well.

## 2. Honest gaps (the model alone is silent)
1. **Affinity = pose, not ΔG.** DockQ ≠ binding free energy. No quantitative tightness.
2. **Synthetic accessibility (dim #1): unscored.** Ring-closure validity is adjacent, not SA.
3. **Safety (dim #3): unscored.** No immunogenicity / protease stability / hemolysis / off-target.
4. **No multi-objective optimization.** It generates; it does not balance affinity×SA×safety×permeability.
5. **No validation loop.** "High score ≠ drug" unaddressed inside the model.

Gaps 1–5 ARE Layers 1/2/4 + Verification — exactly BioMate's role. Narrative: **generate with the
model; verify + optimize with BioMate.**

## 3. BioMate abilities that fill each gap
| Gap | BioMate (built/verified) |
|---|---|
| Quantitative affinity | docking_autodock_vina → **OpenFE FEP/RBFE ΔΔG** (real; replaced a fabrication) |
| Synthetic accessibility | SA/synthesizability term in MPO reward |
| Safety | **ADMET** (hERG/CYP/hepatotox, dev-verified) + immunogenicity (MHC-II), protease stability, hemolysis |
| Permeability (make-or-break for cyclics) | 3D-PSA / perm model (`perm_dpsa3d`) |
| Multi-objective (Layer 4) | **MPO / GP-Pareto EHVI** — selects next batch |
| Knowledge/Reasoning (Layers 1–2) | target selection, routing, multi-agent orchestration |
| Don't waste compute | **QC auto-loop gate** rejects failures before expensive steps |

## 4. Do better IN THE LOOP (the moat — not the generator's DockQ)
1. **Cascade verify cheap→expensive:** SA + physchem + PH validity → docking → FEP ΔΔG (top-k) →
   ADMET/immunogenicity. Early QC-gate rejection = the cycle-time saving the commentary describes.
2. **Multi-objective DURING generation:** add affinity/permeability/SA **guidance** into diffusion
   sampling (as MacroGuide already guides ring-closure) → propose developable, not just posed, candidates.
3. **Active learning (DMTL):** feed FEP/assay ΔG back to **fine-tune the generator** (REINVENT4-style
   transfer + staged RL, adapted to peptides); EHVI picks the maximally-informative next batch.
4. **Close with wet-lab:** macrocycle closed-loop flywheel (order→assay→ingest→retrain), held out as
   validation not training. This is the differentiator; the generator is a commodity.

## 5. Do better on the MODEL
- **Full-batch retrain — RESULT (negative, 2026-09-22):** epoch74 eval (`official-eval-20260922T165855Z`)
  scored **DockQ 0.477 / Consistency 0.846 / RMSD-Cα 5.41Å / AAR 0.293** — BELOW the 0.516 reference on
  every headline metric. The full-batch hypothesis (UBOUND 60000, interrupted at epoch 74/80) did NOT
  improve the model; it regressed. Bigger batch didn't help; blind training tweaks have low expected value.
  → Pivot per the strategy: stop chasing marginal DockQ; prioritize the SOTA head-to-head + the loop.
- Add real ΔG "Success" metric (Rosetta/FoldX) — report affinity, not just pose.
- SOTA benchmark on the same test set (RFdiffusion/PepFlow-class).
- Objective-conditioned guidance heads (affinity + permeability + SA).

## Change log
- 2026-09-22 — created; maps peptide-LLM coverage to the tender's 3 dims/4 layers, names gaps,
  BioMate assist, and loop improvements. Feeds the deck's 生成—验证—学习 narrative.
