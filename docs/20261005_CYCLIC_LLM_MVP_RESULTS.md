# Cyclic-Peptide LLM MVP — Results (property-conditioned generation works)

**Date:** 2026-10-05 · First trained model of the innovation thesis
(`docs/20261005_INNOVATION_THESIS_CYCLIC_LLM.md`). A small GPT over SMILES, conditioned on bucketed
permeability + binding via control tokens, trained on the union of CycPeptMPDB + binding_affinity_v1
cyclic. **Joint binding+permeability conditional generation over real data — which no surveyed tool does.**

Code: `research/guangzhou_all_atom/cyclic_llm/{train_cyclic_llm.py, launch_cyclic_llm.sh}`.
Run: `cyclic-llm-full-20261005T202551Z` (AWS g5.xlarge, self-terminated). Checkpoint:
`s3://knowledge-datasets-1759951976/cyclic_peptide/runs/cyclic-llm-full-20261005T202551Z/ckpt/cyclic_llm.pt` (43 MB).

## Training
- **Data:** 21,921 unique canonical cyclic SMILES (7,826 with permeability logPapp; 14,147 with binding
  pAffinity; union, each missing property = explicit `unk` control token).
- **Model:** 10.8M-param GPT (char-level SMILES tokenizer, d=384, 6 layers), 3000 steps on one A10G (~6 min).

## Eval (200 samples per condition; scored by independent RF on real labels)
| Metric | Value | Verdict |
|---|---|---|
| RDKit validity | **0.53** | pass (≥0.5) |
| Macrocycle fraction (of valid) | **0.98** | pass — it learned cyclic chemistry |
| Novelty (not in training) | **0.90** | — |
| **Permeability conditioning** (hi vs lo control → RF-scored logPapp) | hi −5.76 vs lo −6.21, **Δ = +0.45** (n=174/175) | **works** |
| **Binding conditioning** (hi vs lo control → RF-scored pAffinity) | hi 7.02 vs lo 6.20, **Δ = +0.81** (n=67/87) | **works** |

**All four verdicts pass.** Conditioning on "high permeability" produces generations an independent RF
scores ~0.45 log-units more permeable than "low"; conditioning on "high binding" produces ~0.81 higher
pAffinity. This is the core novelty — the control tokens genuinely steer both properties jointly.

## Honest caveats
- **Validity 0.53 is modest** — char-level SMILES + 10.8M params + 3000 steps; a SMILES-BPE tokenizer,
  more steps, or a larger model would raise it toward the ~0.9 that MolGPT-class models reach. Sufficient
  to demonstrate conditioning; not yet production generation quality.
- **Conditioning fidelity is scored by an RF trained on the same real labels** — an *independent model*,
  so the directional hi>lo shift is real evidence the control works, but it is an **in-silico proxy, not
  wet-lab** affinity/permeability ground truth.
- **Binding conditioning has smaller n** (67/87 valid) — directionally clear but should be confirmed with
  more samples / higher validity.
- This is the **MVP** (SMILES, joint binding+permeability). It validates the thesis that a chemistry-LM
  can do joint multi-objective conditional cyclic generation on real data — the regime where the surveyed
  3D tools are single-objective and data-starved.

## Next (per the thesis)
- **v2 representation:** HELM/monomer vocabulary (native ncAA/N-methyl/linker control) — richer than SMILES.
- **Invert the data dependency:** add display/selection-NGS as the primary binding signal (the moat).
- **Close the loop:** replace the RF proxy with orthogonal experimental readouts (the DBTL flywheel).
- **Quality:** SMILES-BPE + more steps to push validity up.
