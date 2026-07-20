# Cyclic-Peptide (环肽) Modality Track — Plan Addendum

**Date:** 2026-07-19 · **Extends:** `20260719_AUTOIMMUNE_MODEL_TRAINING_STRATEGY_AND_DGX_EXECUTION.md`
**Decision:** target cyclic peptides (macrocycles) as a specific drug modality, as a first-class parallel track.

## Why this sharpens (not diverts) the strategy
- **Marketed autoimmune precedent:** voclosporin (cyclic undecapeptide, MW 1214) is FDA-approved for **lupus nephritis** — a cyclic-peptide drug in *our* disease area. IL-17A / IL-23 / TNF / integrin **PPIs** (autoimmune drivers) are classic macrocycle targets — undruggable by small molecules, reachable (and potentially oral) by macrocycles.
- **The moat is the ADMET gap we already found:** our ADMET engine (ADMET-AI) is trained on *small molecules* and **fails on macrocycles** (chameleonic behavior, N-methylation, TPSA>250, MW 500–2000). That's both the requirement (can't reuse small-molecule ADMET) and the differentiation (competitors' ADMET stacks share the blind spot). Macrocycle permeability/ADMET is genuinely under-served.
- **Scaffolding exists:** `cyclic_peptide_design` workflow (matched UC1 conf 236 in the 20260714 benchmark); prior IL-17A / SARS-CoV-2 macrocycle use cases benchmarked vs voclosporin/EK1.

## Integration with the autoimmune single-cell track (the closed loop)
The sc corpus is **not** replaced — its role becomes the **target-selection front-end**:
```
autoimmune single-cell virtual cell  ->  which PPI, which cell state (target)
        -> cyclic-peptide design (CyclicMPNN / AlphaFold3 / Boltz)
        -> macrocycle-specific ADMET / permeability gate   <-- the moat
        -> dock / benchmark vs voclosporin  -> candidate
```
No competitor couples autoimmune single-cell target-ID with macrocycle design + macrocycle-specific ADMET. That end-to-end is the defensible claim.

## Dataset (auto-collected, EC2→S3 — same harness)
- **CycPeptMPDB** — field-standard cyclic-peptide membrane-permeability DB (`CycPeptMPDB_Peptide_All.csv`, PAMPA/Caco-2). The permeability values *are* the labels — no clinical-label mining needed (cleaner than the SLEDAI problem).
- **ChEMBL macrocycle subset** (bioactivity) — later add via ChEMBL API.
- **PDB/PDBe cyclic-peptide–protein complexes** — for the structure/binding side.
- Stored under `s3://knowledge-datasets-1759951976/cyclic_peptide/`.

## Model track (priority order)
1. **Macrocycle permeability / ADMET model** — the moat piece. Descriptor + GNN on CycPeptMPDB. Small/cheap; runs in the **biomni-admet ECR image** (rdkit) on EC2 (or the Spark). **Elevated ahead of the SLE FM** — cleaner data, clearer gap, direct design value.
2. **Design → fold → dock pipeline** — CyclicMPNN / AlphaFold3 / Boltz for macrocycle structure (HELM/SMILES rep), dock to the autoimmune PPI, benchmark vs voclosporin. **GPU burst (cloud H100)** for structure prediction.

## Baseline gate (same discipline)
Before any learned macrocycle model: does a simple **RDKit-descriptor model** (MW, TPSA, logP, HBD, N-Me, ring size, Yudin rules) already predict CycPeptMPDB permeability well? High R² ⇒ value is in design/structure, not a new permeability model; low R² ⇒ headroom for a learned model. *(Running now — instance B.)*

## Execution (EC2/S3; local not workable)
- **rdkit/cheminformatics:** `biomate/biomni-admet` ECR image (rdkit present) — no fragile pip installs.
- **Permeability/ADMET model:** CPU / small GPU — DGX-Spark- or EC2-feasible.
- **Structure/design:** GPU burst (AlphaFold3/Boltz) — cloud H100, not the Spark.

## Status (2026-07-19, all on EC2→S3, self-terminating)
- **Cyclic-peptide dataset + descriptor baseline gate:** running (instance B, biomni-admet image) → `cyclic_peptide/baseline/`.
- **SLE baseline gate:** rerun after pseudobulk fix (instance A) → `autoimmune_sc_corpus/labels/baseline/`.
- **SLEDAI labels:** extracted — Perez `obs` has per-donor `disease_state` (261-donor table in S3).
- **Autoimmune sc corpus:** 1.29M cells / 6,335 donors / 5 groups in S3 (target-selection front-end).
