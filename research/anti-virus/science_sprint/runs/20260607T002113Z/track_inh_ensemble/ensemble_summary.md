# Ensemble Vina docking — inhibitor track

Generated: 20260607T002113Z

## Setup

- Baseline rigid docking: `/home/yzhang/biomate/research/anti-virus/runs/publication_20260528T223525Z/post_hts_qc/generative_top5_baseline.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **5**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T002113Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb` | succeeded |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3L.pdb` | succeeded |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3M.pdb` | succeeded |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T002113Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3X.pdb` | succeeded |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T002113Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3Y.pdb` | succeeded |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb` | succeeded |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **2 / 5**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `NC(=O)NNC(=O)c1ncc(C(F)(F)F)nc1N` | -7.004 | -6.969 | +0.035 | no | 9P3I |
| `NC(=O)NS(=O)(=O)Nc1ncc(C(F)(F)F)nc1N` | -6.772 | -6.480 | +0.292 | no | 9P3Y |
| `Cc1cnc(NS(=O)(=O)NC(N)=O)c(N)n1` | -6.388 | -6.407 | -0.019 | yes | 9P3I |
| `NC(=O)NS(=O)(=O)Nc1ncc(Cl)nc1N` | -6.220 | -6.197 | +0.023 | no | 9P3I |
| `NC(=O)NC(=O)Nc1ncc(Cl)nc1N` | -6.156 | -6.206 | -0.050 | yes | 9P3Y |

## Strongest ensemble prediction

- SMILES: `NC(=O)NNC(=O)c1ncc(C(F)(F)F)nc1N`
- Ensemble best: **-6.969 kcal/mol** (9P3I)
- Rigid baseline: -7.004 kcal/mol
