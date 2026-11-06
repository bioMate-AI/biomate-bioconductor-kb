# What transfers from small-molecule generative design → our macrocyclic-peptide engine (2024–2026)

Four parallel cited surveys (all-atom generation, optimization/closed-loop, synthesizability/building-blocks,
ADMET/permeability). The organizing insight: the small-molecule field is far more mature, and most of the
machinery we need is proven there. Our openings are the peptide-specific instantiations — especially
**conformation-aware permeability** and **synthesizability-by-construction over a non-natural monomer alphabet**,
neither of which is solved in the peptide literature yet.

## Transferable pillars (deduped across surveys)

### 1. Generation representation
- **Masked discrete diffusion over a fragment/monomer alphabet with fixed positions held immutable**
  (GenMol on SAFE; substrate MDLM/SEDD). A HELM string *is* a monomer-block sequence → direct port; gives
  **hard in-alphabet + hard "keep these residues fixed" guarantees** and native linker/motif/decoration modes.
  Highest-leverage, most reproducible starting point for monomer-constrained peptide generation.
- **Embed-diffuse-then-snap-to-catalog** (SynFormer's BB-selection diffusion): embed HELM monomers, flow in
  embedding space for smooth optimization, project to nearest in-library monomer → synthesizable by construction
  with a differentiable latent. Solves the large non-natural-monomer vocabulary.
- **Joint continuous+categorical flow matching + equivariant/scale-OT** (FLOWR, SemlaFlow): ~20-step sampling,
  higher validity, size-dependent prior (apt for variable peptide length). Adopt if/when we move off BoltzGen diffusion.
- **FlowMol3 cheap add-ons** (backbone-agnostic): self-conditioning, "fake/placeholder atoms" for variable
  length, train-time geometry distortion.
- **Unified/neural-field backbone**: FuncBind (Genentech, 2025) already generates small molecules **and
  macrocyclic peptides with non-canonical residues** in one target-conditioned model, and ships a **macrocyclic-
  peptide benchmark/dataset (MCP)**. Early/modest numbers but the most on-point precedent.

### 2. Cyclization
- **Composable, train-free geometric guidance** (CP-Composer — demonstrated *on PepGLAD*; GeoCycler): impose
  head-to-tail/disulfide/staple closure at sampling time, zero-shot, no retraining. Plus **cyclic position
  encodings** (RFpeptides, AfCycDesign — both crystal-validated cyclic *binders*).

### 3. Optimization / closed loop  (we are at best-of-N; this is the upgrade)
- **Active-learning outer loop around a physics oracle** (SGPO/GAL pattern): generate → verify with all-atom
  ΔG → retrain surrogate → repeat, **5–7 rounds, batches of 100–250**. Empirically the sample-efficient regime;
  fixes surrogate OOD drift.
- **qLogNEHVI (Ax/BoTorch)** as the noise-aware Pareto batch selector (constrained variants for hard ADMET
  cutoffs); **MOGFN/GFlowNets** when per-round diversity matters.
- **REINVENT4 MPO recipe** (per-objective transforms → weighted geometric-mean soft-AND → diversity filter) as
  the reward-engineering template.
- **Ship a tuned genetic algorithm first, keep a GA inner loop** — on PMO, Genetic GFN (16.2) leads and a plain
  tuned Mol GA (15.7) beats almost every deep model. Highest-ROI sample-efficiency move.
- **FAR-DPO** (Diffusion/Flow-DPO on PepGLAD/PepFlow, cyclic-peptide-specific, +10.9-pt success from
  feasibility-gated preference pairs) as the "learn" step — **preprint, no code yet, unverified**.

### 4. Non-circular physics oracle  (our verification discipline, now de-risked)
- **FEP is quantitatively validated on cyclic peptides** — FEP+ across KRAS/PCSK9/MCL-1/JAK2/Cyclin, >230
  peptidic analogues, **ΔΔG RMSE 1.06 kcal/mol**. The plan is not speculative.
- **Active-learning FEP makes it affordable**: 3–6% sampling recovers 50–75% of top binders, ~20× cost cut
  (one case $160K→$9.6K). This is the single most defensible "non-circular oracle" upgrade.
- **ML potentials**: MACE-OFF23 + a macrocycle-specific MLIP (delta-learned to DFT, trainable on CREMP) →
  ML/MM alchemical FEP ΔΔG RMSE ~0.45.
- **Boltz-2 affinity**: fast (~1000×) but **circular/OOD-fragile** (no better than docking on novel chemotypes;
  *no* macrocycle numbers). Use only as a guarded, calibrated pre-filter — never the sole reward.
- **Reward-hacking is real and worse for peptides** (oversized greasy unmakeable macrocycles game MW). Mandatory:
  applicability-domain guard (DyRAMO) + diversity filter + the non-circular verifier above.

### 5. Permeability  (our claimed differentiator — course-corrected)
- **Our R² 0.23 is the floor.** A plain **DMPNN/Chemprop-RDKit or XGBoost-on-descriptors** reaches ~0.5–0.55
  (scaffold) to ~0.77 (random/augmented) on the same CycPeptMPDB data. **Fix the baseline and report honest
  splits first.** (Honest yardstick: BenchmarkCycPeptMP, DMPNN R²=0.555.)
- **Proven middle path**: MD-ensemble conformational descriptors (IMHB count, SA-3D-PSA, Rgyr, and their
  **polar↔apolar span** = in-silico EPSA) fused with strong 2D features → improves **OOD generalization**
  (LODO R≈0.61). Reference impl: MDML_PeptPerm; augmentation model CycPeptMP (R²≈0.77).
- **Get realistic ensembles from CREMP** (CycPeptMPDB's own 3D is energy-minimized/unrealistic — why naive 3D fails).
- **Yellow flag**: ensemble *variance* features carried <2% of signal in one broad study — validate that the span
  actually helps on our data before betting on the "chameleon = variance" story.
- **Permeability-conditioned generation** via PepTune (masked discrete diffusion + Monte-Carlo tree guidance) —
  plug our permeability oracle in as the MCTG scorer.

### 6. Synthesizability-by-construction  (a genuine opening)
- **Do NOT reward with SA_Score/SCScore/RAScore** — size-confounded, stereo-blind, gameable, and they *penalize*
  exactly our desired N-methyl/D/macrocycle features. Make synthesizability **structural** (in-alphabet + valid
  coupling/cyclization by construction); add a learned **SPPS-difficulty** model (aggregation, aspartimide,
  difficult couplings) if a score is needed.
- **GFlowNet assembly over a closed alphabet** (RGFN/SynFlowNet): actions = {append monomer, N-methylate, set
  D-stereo, cyclize/staple} → diverse *make-able* libraries; "~100× cheaper synthesis" maps to preferring robust
  couplings/common monomers.
- **Joint all-atom-3D + assembly-graph** (SynCoGen pattern): masked discrete diffusion over monomers/topology +
  flow-matching over coordinates — nothing published does this for peptides yet (highest novelty).
- **Existing monomer-alphabet peptide generators to build on**: **PepINVENT** (CHUCKLES; NNAA/D/N-Me RL),
  **HELM-GPT** (HELM-native, RL). Peptide SPPS-feasibility integration is greenfield — our contribution opportunity.

## Honest proven-vs-hype ledger
- **Proven / mature**: joint flow matching + few-step OT; masked-discrete-diffusion fragment constraints (GenMol);
  synthesis-tree/GFlowNet by-construction (SyntheMol wet-lab-validated, SynFlowNet/RGFN); FEP on cyclic peptides;
  AL-FEP economics; boosted-trees permeability baselines; RFpeptides/AfCycDesign (crystal-validated).
- **Promising but early**: unified/neural-field backbones (FuncBind, ADiT); macrocycle-specific MLIPs;
  MD-ensemble permeability (OOD gain real, in-domain R² gain modest).
- **Preprint / unverified (treat as leads)**: FAR-DPO, GeoCycler/PepALD, several 2026-dated arXiv IDs; Boltz-2 as
  a reward (demonstrated circular). CrossDocked Vina "success" leaderboards are gameable; the CIDD 37.9% headline
  is an LLM-refinement hybrid, not an architecture advance.

## Adopt-list mapped to our roadmap (priority)
1. **Fix the permeability baseline** (DMPNN/XGBoost, honest splits) — cheap, immediate, corrects our R²=0.23 story.
2. **MD-ensemble permeability oracle** on CREMP ensembles (reuse MDML_PeptPerm) → the differentiator, honestly scoped.
3. **Active-learning loop around the physics oracle** (qLogNEHVI selector + REINVENT4 MPO reward + diversity/AD guards),
   replacing best-of-N; ship a GA baseline alongside.
4. **FEP as the non-circular verifier** at the funnel top (AL-FEP to afford it) — the defensible upgrade.
5. **Monomer-constrained generation** via masked discrete diffusion over HELM alphabet (GenMol pattern) /
   build on HELM-GPT + PepINVENT; SPPS-difficulty as structural constraint, not SA_Score.
6. **Cyclization guidance** (CP-Composer-style) + permeability-conditioned generation (PepTune) as the steering layer.

## Data / code fetch list (→ staged in S3 cyclic_peptide/)
- **CREMP** — 36,198 macrocyclic peptides, ~31.3M xTB geometries (Zenodo 7931445; code Genentech/cremp). *cross-
  corroborated by 3 surveys; realistic ensembles for permeability + ML-potential training.* **TOP fetch.**
- **FuncBind MCP** macrocyclic-peptide dataset (HF Willete3/mcpp_dataset) + code prescient-design/funcbind.
- **Permeability**: BenchmarkCycPeptMP (Gobliu), CycPeptMP (akiyamalab), MDML_PeptPerm (akiyamalab). CycPeptMPDB already staged.
- **Peptide generators (reference)**: HELM-GPT (charlesxu90), PepINVENT (in REINVENT4), RINGER (Genentech), PepTune.
- **Small-molecule patterns to port**: GenMol (+MDLM), SynFormer, RGFN, SynFlowNet, SynCoGen, SAFE, Saturn, FLOWR, SemlaFlow.
