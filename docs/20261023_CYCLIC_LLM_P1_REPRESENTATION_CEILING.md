# Cyclic-LLM P1 — the ceiling is representational (3D), not feature-learning

Date: 2026-10-23 · Phase P1 of `20261022_STRUCTURE_GROUNDED_PHYSICS_LOOP_PLAN.md`. The decisive P1 question:
does swapping hand-crafted features for a **learned molecular representation** clear the sequence/2D ceiling
toward SOTA, on either axis (permeability, cross-target affinity)? Answer: **no — cleanly.**

## Permeability (CycPeptMPDB, n=8,466, leakage-safe Bemis-Murcko scaffold split)
ChemBERTa-77M embeddings computed directly for the CycPeptMPDB peptides (the prior ChemBERTa npz was the
design pool — canonical overlap with CycPeptMPDB ~0.3%, so it was never actually tested here). Script:
`cyclic_llm/perm_oracle_chemberta.py`; result: `results/perm_oracle_chemberta.json`.

| Representation | scaffold R² | Pearson | Spearman |
|---|---|---|---|
| RDKit 2D descriptors (baseline) | **0.234** | 0.487 | 0.579 |
| ChemBERTa (learned, NEW) | 0.119 | 0.352 | 0.454 |
| ChemBERTa + 2D (fusion) | 0.173 | 0.454 | 0.506 |
| *prior ECFP + chameleon-3D (random-ish)* | *0.301* | — | — |
| **SOTA CycPeptMP** | **0.77** | — | — |

A learned **2D-SMILES** model (ChemBERTa) is **worse** than RDKit 2D descriptors and nowhere near SOTA.
Truncation is not the cause (token length median 120, p90 197, max 240; 0% > 512). The model is a general
small-molecule LM; cyclic-peptide permeability is a 3D-conformational property it cannot represent.

## Cross-target affinity (prior, `results/xtarget_fm.json`)
Learned reps already tested there: ligand ChemBERTa → per-target Spearman 0.255; + ESM target → 0.262
(target adds +0.007); cross-target **enrichment conditioning NULL** (`target_features_matter: false`).

## Conclusion (decision-relevant)
Both axes confirm the plan's thesis: the ceiling is at the **representation LEVEL** (2D/sequence), not at
feature-learning. More representation swaps (ChemBERTa, dPSA3D, chameleon-3D descriptors, ESM-target
concatenation) are **exhausted** — none clears ~0.30 permeability or moves cross-target off NULL. The SOTA /
cross-target gap requires **3D structure** (pocket geometry, conformer ensembles, physics), i.e. P2–P3
(pocket-conditioned 3D generation + physics-verified scoring). This negative **saves GPU**: it rules out the
cheap levers and justifies the structural/physics direction rather than more sequence/2D tuning.

## Next (P2/P3, GPU)
- Structure-based affinity scorer: cofold target–peptide complexes (BoltzGen/Boltz-2) → pocket-geometry +
  interface features; cross-target LOTO test (does pocket *geometry* transfer where sequence features are NULL?).
- Physics-verified scoring (the simulated wet-lab): the metal-aware αvβ6 MM-GBSA geometry gate already passes
  (controls recover MIDAS coordination); extend the ladder cofold→MM-GBSA→FEP ΔΔG as the reward.
- Permeability is a side-benchmark (the αvβ6 radioligand needs no permeability); the core claim is cross-target
  affinity generalization, which is where P2–P4 are aimed.
