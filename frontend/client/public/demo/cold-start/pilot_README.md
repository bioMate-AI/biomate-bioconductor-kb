# Pilot Study Datasets — Zhejiang People's Hospital Pilot

**Study reference:** `business/BioMate_DrugDiscovery_Study_Proposal.md`  
**Internal test plan:** `docs/pilot_study/20260324_INTERNAL_PILOT_TEST_PLAN.md`  
**Prepared:** March 24, 2026

---

## Dataset Overview

| File | Description | Rows | Use |
|---|---|---|---|
| `compounds.csv` | 15 compounds with SMILES, class, ground-truth ADMET | 15 | All sessions |
| `ground_truth_admet.csv` | Literature-validated hERG IC50, DILI, Ames, physicochemical | 15 | Evaluation / H3 |
| `reference_actives.smi` | 4 known BCR-ABL1 inhibitors for pharmacophore model | 4 | Session 4 |
| `assay_results_arm3.csv` | IC50, Ki, hERG IC50, solubility, Caco-2 for all 15 compounds | 15 | Session 5 (Arm 3) |
| `target_info.json` | BCR-ABL1 / 1IEP target metadata | — | Sessions 3–5 |

## Target

**BCR-ABL1 kinase** · PDB: 1IEP · UniProt: P00519  
Download structure: `wget -O /tmp/1IEP.pdb https://files.rcsb.org/download/1IEP.pdb`

## Compound Set Design

The 15 compounds span four categories that exercise all BioMate safety checks:

- **CPD001–CPD006**: Approved BCR-ABL1 TKIs (known ground truth)
- **CPD007–CPD008**: Synthetic imatinib analogs (interpolation test)
- **CPD009–CPD010**: Withdrawn cardiotoxic drugs (hard safety negative — terfenadine, cisapride)
- **CPD011–CPD015**: Negative controls (off-target drugs, DILI references)

## Critical Safety Gate

Terfenadine (CPD009) and cisapride (CPD010) are drugs withdrawn from the market due to fatal cardiac arrhythmias. Their hERG IC50 values (0.08 and 0.05 μM respectively) make them the strongest safety signals in the set. BioMate must rank both compounds in the bottom 3 — this is the primary scientific correctness gate for the ranking algorithm.
