# Innovation assessment and proposed differentiators

Honest answer to three questions: are we on the latest architecture with real innovation,
do we have enough data for it, and what else must be collected. This is a direction
proposal, not a claim of implemented novelty.

**Scope:** the program focuses on **cyclic peptides**, delivered as the first plugin on a
**shared all-atom backbone** whose other drug modalities (small molecule, then
ternary/PROTAC) are added later as additional plugins — one backbone, many modality plugins.

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

## 3. Cyclic-peptide design is NOT solved — the open problems

Correcting an earlier overstatement (do not repeat it to the partner): the frontier is not
"peptides are done, only ternary/PROTAC is open." Cyclic-peptide therapeutic design has many
open problems, and the count of clinically-validated de novo *generative* peptide drugs is
≈ 0. What is actually unsolved, and what we should attack:

- **Hit rate:** even best-in-class methods (RFdiffusion / BoltzGen-class) have **low
  experimental hit rates** on novel targets. Most designs fail in the lab. Amino-acid
  recovery ~0.2–0.5 is a benchmark number, not a working binder.
- **Affinity:** reliably designing nM-potency binders de novo — unsolved.
- **Developability (why most peptide drugs are injectable):** membrane permeability / oral
  bioavailability, proteolytic stability, half-life, aggregation, solubility, immunogenicity.
  This is the wall the CycPeptMPDB / PepMSND / MacroConf data speaks to.
- **Non-natural chemistry:** generative modeling of cyclic / stapled / N-methylated /
  D-amino-acid peptides is immature.
- **Metric gap:** AAR / RMSD do not predict function; in-silico ≠ in-vivo. GLP-1-class
  successes came from decades of med-chem, not generative models.

## 4. Proposed differentiators (ranked, cyclic-peptide first)

### Architecture thesis — one all-atom backbone, each modality a plugin
The platform thesis (stated earlier, and the right one) is a **single all-atom generative
backbone with per-modality plugins/adapters**, not a separate model per modality. Each plugin
supplies its own chemistry representation, topology constraints, training data and evaluation;
the backbone supplies shared all-atom geometry. This is the UniMoMo / BoltzGen direction, and
it is the actual architectural differentiator — a shared representation that lets modalities
transfer and lets the private-data moat span the whole portfolio.

- **First plugin = cyclic peptide.** Cyclic peptides are the focus and the hardest first case:
  the plugin must enforce **macrocyclization / head-to-tail and disulfide closure**,
  **stereochemistry**, and **non-natural monomers** — exactly the "explicit closure/crosslink
  edges" and monomer support called out in PLAN.md §1. A molecule being cyclic is not proof of
  the correct closure; the plugin validates requested vs. observed topology.
- **Honesty on feasibility:** a unified all-atom backbone trained *from scratch* is infeasible
  on ~4k complexes + one A10G. The buildable path is to **adopt/extend an open backbone**
  (UniMoMo or BoltzGen) and build the cyclic-peptide plugin first; other plugins follow.
  PepGLAD is the current qualification baseline, not necessarily the final backbone.

### Bet 1 (headline capability, rides on the backbone) — Developability-aware, experiment-native generation
Collapse "generate → filter → Bayesian-optimize" into a **single learned objective**, and make
**developability** first-class — not a post-hoc filter. For the cyclic-peptide plugin: co-design
sequence + structure + closure *and* the developability profile (**membrane permeability**,
proteolytic stability, half-life), optimizing expected multi-property gain **plus** expected
information gain under the property model's **uncertainty**. The model proposes the peptide *and*
implicitly the most informative next experiment.

- Why it differentiates: directly attacks the cyclic-peptide walls above (hit rate +
  permeability/developability), and turns the 生成–验证–学习 loop from a pipeline into one system
  so the private-data moat **compounds** — each assay round sharpens both generator and
  acquisition policy. This is the capability that makes the "plugin per modality" backbone
  valuable rather than just a representation trick.
- Feasibility: builds on the qualified baseline + the permeability/stability data we already
  have; fits current compute. **Start here.**

### Bet 1b (supporting) — Induced-fit / ensemble co-design
Generate the peptide *and* sample the pocket's conformational response instead of designing
against one static structure — for flexible / cryptic pockets. Folds into Bet 1 as a structural
conditioning improvement.

### Later plugins on the same backbone (sequenced, not off-lane)
Small-molecule and then **ternary glue / PROTAC** generation are **additional plugins on the
same backbone**, not a different program. They are deferred for **data-readiness** reasons
(ternary structures are scarce), not because they are out of scope — the plugin architecture is
exactly what lets us add them later without a new model. Sequence: cyclic peptide → small
molecule → ternary/degrader (PLAN.md §6).

### Plugin feasibility by modality — two axes
A plugin varies on two independent axes, and conflating them is what makes "glues are just
another plugin" oversell a hard problem:

- **Axis 1 — chemistry / representation:** which atoms / bonds / topology the plugin emits.
  Easy to unify; the all-atom backbone already provides the substrate.
- **Axis 2 — biological conditioning / objective:** what the molecule is generated *against*.
  This is the hard axis, and it is where glues/degraders diverge.

| Modality | Axis 1 (chemistry) | Axis 2 (conditioning) | Verdict |
|---|---|---|---|
| **Cyclic peptide** (first plugin) | closure / disulfide, stereochemistry, non-natural monomers | single pocket | Focus; hardest Axis-1 case |
| **Small molecule** | valence, drug-likeness, synthesizability, large chemical space | single pocket (same regime as cyclic peptide) | Cleanest add; single-pocket like the peptide plugin |
| **Molecular glue** | *the glue is itself a small molecule → reuses the small-molecule plugin* | **ternary complex + cooperativity** (E3–glue–target); NOT single pocket | Molecule generator is a plugin; the ternary/cooperativity objective is a **backbone extension + data problem** |
| **PROTAC** | bivalent: two ligands + linker | **ternary complex + linker geometry + cooperativity** | Same as glue, plus linker design |

Key point: for glues and PROTACs the *molecule generator* is a cheap plugin (Axis 1), but the
capability that actually matters — designing for a **productive protein–protein interface and
cooperativity** — is a new conditioning regime (Axis 2) that requires extending the backbone to
model **ternary geometry** and acquiring scarce **ternary-complex data**. Small molecule varies
only on Axis 1; glue/PROTAC vary on both. That is why they are sequenced last, not because they
are a different program.

## 5. Data sufficiency — honestly, not for the innovative version

| Purpose | Have | Enough? |
|---|---|---|
| Train/validate PepGLAD **baseline** | PepBench ~4,157 complexes | Yes |
| Property conditioning (permeability/stability) | CycPeptMPDB ~7k PAMPA, PepMSND 605, MacroConf 68 | Marginal |
| Bet 1 (developability-aware, experiment-native) | above + no live assay | No — needs an experimental feedback channel |
| Later ternary / PROTAC plugin | — | No — ternary structures scarce (deferred, not off-lane) |
| Unified all-atom backbone **from scratch** | — | No — needs PDB-scale (100k+) + multi-GPU; extend an open backbone instead |

The decisive gap is **not** more structures. It is that the **"学习/learn" arm has no real
signal**: the DMTA replay could only *simulate* learning on historical labels. Without a
wet-lab feedback source or a high-fidelity FEP oracle, the moat cannot compound — only be
demonstrated in silico.

## 6. Additional resources to collect (peptide-focused)

- **Structural breadth:** PepBDB + PDB-wide protein–peptide extraction to grow beyond
  PepBench's ~4,157 complexes.
- **Developability labels (the priority):** more matched permeability / stability / half-life
  data beyond CycPeptMPDB + PepMSND; these feed Bet 1's developability objective directly.
- **Affinity / property conditioning:** BindingDB / ChEMBL peptide+target subsets.
- **Non-natural chemistry:** a monomer + coupling-rule library so cyclic / stapled /
  N-methylated / D-amino-acid peptides are representable and synthesizable by construction.
- **The gating resource:** an **experimental feedback source** — partner assay, CRO
  contract, or at minimum a validated FEP surrogate used as an oracle.
- **Compute:** one A10G suffices for baselines/fine-tuning; foundation-scale needs
  A100/H100 multi-GPU.
- *(Deferred, only if a degrader branch is funded: PROTAC-DB 2.0 / ternary complexes.)*

## 7. Recommendation

1. Let the current baseline finish → first honest held-out numbers.
2. Draft a concrete design doc for **Bet 1** (developability-aware, experiment-native peptide
   generator on top of the qualified baseline) — highest leverage and most buildable with
   what we have.
3. Treat the shared backbone + plugins as the architecture from day one: build the
   cyclic-peptide plugin first; add small-molecule and ternary/PROTAC plugins later as data
   allows — same backbone, no new program.

No leadership claim is warranted until blinded held-out performance (and, for the moat,
prospective experimental results) exist. See [[SURVEY]], [[PLAN]], and
`WET_LAB_DATA_AND_REPLAY.md`.
