# Innovation assessment and proposed differentiators

Honest answer to three questions: are we on the latest architecture with real innovation,
do we have enough data for it, and what else must be collected. This is a direction
proposal, not a claim of implemented novelty.

## 1. What is actually built today is a baseline, not an innovation

The model currently training on GPU is **PepGLAD** (THUNLP-MT, pinned commit
`bad015ca`), a *published* 2024 latent-diffusion all-atom peptide co-design model. We are
training it longer and running a held-out generation benchmark. This is **baseline
qualification** (PLAN.md §2), not a novel architecture.

What this project has produced so far: a chemical-identity evaluation harness
(`evaluate.py`), leak-free data splits (`rebuild_stability_folds.py`), an offline DMTA
replay (`replay_permeability.py`), and a qualified baseline. No novel model has been
proposed or trained yet. State this plainly to the partner.

## 2. The written platform ability is table-stakes, not a moat

> 以口袋条件化全原子模型设计小分子、环肽等候选分子，结合构象集合、物理约束和多目标贝叶斯优化，
> 实现活性、安全性、成药性与可合成性的协同寻优；再通过实验反馈持续训练企业专属模型。

Pocket-conditioned all-atom generation + conformational ensembles + physical constraints +
multi-objective Bayesian optimization + experimental feedback → private model is the
**necessary** stack, and essentially every well-funded competitor claims it. No single
component is defensible in 2026. Differentiation must come from **how the pieces are
fused**, and from attacking problems commodity generators cannot.

## 3. Proposed differentiators (ranked)

### Bet 1 — Experiment-native generation (highest leverage, most buildable)
Collapse "generate → filter → Bayesian-optimize" into a **single learned objective**. Train
the generator so its native goal is to maximize expected multi-property gain **plus**
expected information gain, conditioned on the current property model's **uncertainty**. The
model proposes the molecule *and* implicitly the most informative next experiment.

- Why it differentiates: turns the 生成–验证–学习 loop from a pipeline into one system and
  makes the private-data moat actually **compound** — each assay round sharpens both the
  generator and the acquisition policy.
- Feasibility: builds on top of an open all-atom baseline (no from-scratch foundation
  model); fits current compute. Start here, on top of the qualified PepGLAD baseline.

### Bet 2 — Ternary-complex generation for molecular glues / PROTACs (the real open problem)
Generate the **ternary** geometry (E3 – glue/PROTAC – target), where induced proximity, not
a single pocket, defines success. Static pocket-conditioned generators cannot do this; very
few public models attempt it. A narrow solution is a genuine scientific moat and matches the
glue/环肽 ambition — but it is the most data-starved direction.

### Bet 3 — Induced-fit / ensemble co-design for flexible & cryptic pockets
Generate the ligand *and* sample the pocket's conformational response instead of docking into
one static structure. This targets flexible/"undruggable" pockets where commodity generators
fail.

## 4. Data sufficiency — honestly, not for the innovative version

| Purpose | Have | Enough? |
|---|---|---|
| Train/validate PepGLAD **baseline** | PepBench ~4,157 complexes | Yes |
| Property conditioning (permeability/stability) | CycPeptMPDB ~7k PAMPA, PepMSND 605, MacroConf 68 | Marginal |
| Bet 1 (experiment-native) | — | No — needs an experimental feedback channel |
| Bet 2 (ternary / PROTAC) | — | No — ternary structures are scarce |
| Frontier unified all-atom backbone from scratch | — | No — needs PDB-scale (100k+) + multi-GPU |

The decisive gap is **not** more structures. It is that the **"学习/learn" arm has no real
signal**: the DMTA replay could only *simulate* learning on historical labels. Without a
wet-lab feedback source or a high-fidelity FEP oracle, the moat cannot compound — only be
demonstrated in silico.

## 5. Additional resources to collect

- **Structural breadth:** PepBDB + PDB-wide protein–peptide extraction; PDBbind / BioLiP2 /
  Q-BioLiP for a small-molecule branch.
- **Ternary (gates Bet 2):** PROTAC-DB 2.0, published glue / E3 ternary complexes.
- **Affinity / property conditioning:** BindingDB / ChEMBL peptide+target subsets.
- **Synthesizability-by-construction:** non-natural monomer + coupling-rule library
  (peptides); purchasable building-block + reaction-template set (small molecules) — so
  outputs are synthesizable by design, not filtered after generation.
- **The gating resource:** an **experimental feedback source** — partner assay, CRO
  contract, or at minimum a validated FEP surrogate used as an oracle.
- **Compute:** one A10G suffices for baselines/fine-tuning; foundation-scale needs
  A100/H100 multi-GPU.

## 6. Recommendation

1. Let the current baseline finish → first honest held-out numbers.
2. Draft a concrete design doc for **Bet 1** (experiment-native generator on top of the
   qualified baseline) — highest leverage and most buildable with what we have.
3. In parallel, pressure-test **Bet 2** feasibility against what public ternary data actually
   exists before committing to it.

No leadership claim is warranted until blinded held-out performance (and, for the moat,
prospective experimental results) exist. See [[SURVEY]], [[PLAN]], and
`WET_LAB_DATA_AND_REPLAY.md`.
