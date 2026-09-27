# Cyclic-Peptide Corpus Expansion + Training Strategy — Proposal for Committee Review

**Date:** 2026-09-27 · **Status:** PROPOSAL — under adversarial review. The training-strategy section is an **open question**, not a settled plan.

---

## Part A — Corpus expansion (data)

**What we already have (S3 `cyclic_peptide/datasets/`, partial):** `cremp_partial`, `pepbdb`, `pepbench`, `bindingdb_peptide`, `peptideclm2_pepmsnd`, `approved_cyclic_peptide_drugs`, `macroconf`, `helm_monomers`, plus `nme_v1` (1,225 N-Me, just built).

**Ranked expansion moves (speed × leverage):**
1. **Aggregate + standardize existing cyclic DBs** → one schema (seq/HELM + SMILES + structure + nme_mask/mods). CycPeptMPDB (8,466), PepBDB/PepBench (peptide–protein *complexes with structure*), BindingDB-peptide, approved cyclic drugs, PDB/Q-BioLip cyclic subset (mine by SS-bond / head-to-tail). Mostly de-dup + normalize.
2. **Complete CREMP** — *the* macrocyclic-peptide conformer set (~36k macrocycles, 31M+ DFT/xTB conformers). We have `cremp_partial`. **Biggest single structure-rich win, no new experiments.**
3. **Structure-generate SMILES-only entries** — ETKDG (cheap, done for nme_v1) → upgrade with **HighFold3 / HighFold-MeD** (native cyclic + N-Me/D-AA) or Boltz/Chai-1/AF3 for bound-relevant geometry. Unlocks CycPeptMPDB's 8,466 as structure data.
4. **Augmentation** — multi-conformer (CREMP-style), SMILES enumeration + cyclic-ring-permutation, matched-pair (mmpdb).

**Honest caveats:** ETKDG/generated conformers are *solution* guesses, not receptor-bound poses (fine for representation/AE learning, weaker for target-conditioned bound geometry); **de-dup + family-disjoint splits** or metrics inflate; keep measured-vs-generated provenance.

**Corpus scale estimate (post-assembly):** CREMP ~36k macrocycles (+conformers) + CycPeptMPDB 8.5k + PepBDB/PepBench complexes + drugs ≈ **~45k+ unique cyclic peptides**, most with (generated) structure. **This is NOT tiny** — directly relevant to the training-strategy question below.

---

## Part B — Training strategy (THE OPEN QUESTION — the doubt to adjudicate)

**My earlier proposal was:** *foundation-pretrain the chemistry-native representation on small molecules + linear peptides → transfer/fine-tune on cyclic.* **This is a hypothesis, and it is contested.** The core question:

> With ~45k structured cyclic peptides (CREMP-heavy), is the best path (A) broad foundation pretraining then fine-tune, (B) mid-training (continued pretraining) on cyclic, (C) SFT directly on cyclic, or (D) a curriculum? **Does small-molecule / linear-peptide pretraining actually transfer to cyclic — or is the domain gap too large to help (or even negative)?**

### The options
- **A — Broad foundation pretrain → fine-tune cyclic.** *For:* leverage large data; a chemistry-native rep shares atoms/bonds/local geometry across chemistries; precedent (NCFlow pretrains on small-mol + protein-ligand; PepINVENT is a small-mol-lineage chem-LM). *Against:* **domain gap** — small molecules are MW<500 drug-like organics; cyclic peptides are MW 500–2000 macrocyclic amino-acid polymers with cyclization-driven conformation/permeability that small molecules never exhibit. Linear peptides share residues but **cyclization is the whole point** (it changes conformation, rigidity, permeability). Transfer may be weak, or **negative** (wasted capacity on irrelevant chemistry).
- **B — Mid-training on cyclic.** Continue-pretrain a general model on cyclic-specific data (CREMP + CycPeptMPDB) *before* task SFT — bridges the gap; keeps low-level transfer while re-centering the distribution on macrocycles.
- **C — SFT directly on cyclic (from scratch or light init).** *For:* with ~45k structured cyclic peptides + CREMP's 31M conformers, we may have **enough** to train directly — and the domain-specific signal (macrocyclic geometry, cyclization) is exactly what we need; broad pretraining could dilute it. Aligns with "peptides are data-efficient; small data → train a peptide one."
- **D — Curriculum.** e.g. linear peptides → cyclic (closest transfer path, shares residues), or small-mol → peptide → cyclic. Stages the gap.

### What actually transfers (the crux of the debate)
- **Low-level (atoms, bonds, local geometry, valence):** transfers broadly → argues *for* some broad pretraining.
- **High-level (macrocyclic ring conformation, cyclization-driven permeability, backbone constraints):** cyclic-specific, **must be learned on cyclic data** → argues *for* mid-training/SFT on cyclic.
- **Representation-dependent:** an atom-level chemistry-native rep makes small-molecule pretraining more transferable (shared atoms); a residue-level rep makes linear-peptide transfer more natural but small-molecule transfer weak.

### The honest position
This **cannot be settled by assertion** — it needs an **ablation**: {SFT-cyclic-only} vs {mid-train-cyclic} vs {broad-pretrain→fine-tune} vs {curriculum}, measured on a **family-disjoint cyclic eval** (the 7-metric panel), with a **leakage-filtered split** and a **from-scratch baseline** + a **linear-only-transfer baseline** to detect negative transfer. My "broad pretrain" proposal should be treated as *one arm of that ablation*, not the plan.

---

## Open questions for the committee
1. Broad-pretrain-then-transfer vs mid-training vs SFT-on-cyclic vs curriculum — **which, and why**, given ~45k structured cyclic peptides?
2. Does small-molecule pretraining transfer to macrocyclic peptides, or is the gap too large / negative? Does linear-peptide pretraining transfer to cyclic?
3. Is our cyclic data (CREMP-heavy) **already enough** for direct training, making broad pretraining unnecessary or harmful?
4. What is the **decisive, cheap experiment** to settle this before committing GPU?
5. Does the answer depend on the **representation** (atom-level vs residue-level) and on whether the target is the **AE** (geometry) vs the **generator** (co-design)?
