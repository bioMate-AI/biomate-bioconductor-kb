# Ensemble Vina docking — inhibitor track

Generated: 20260527T195530Z

## Setup

- Baseline rigid docking: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/04_docking_vina/docking_autodock_vina_results.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **3**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/top_pocket.pdb` | succeeded |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T195530Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3I.pdb` | succeeded |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T195530Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3Y.pdb` | succeeded |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T195530Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3X.pdb` | succeeded |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3L.pdb` | succeeded |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3M.pdb` | succeeded |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **3 / 3**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `CC(=O)Oc1ccccc1C(=O)O` | -4.917 | -6.217 | -1.300 | yes | 9P3Y |
| `Oc1ccccc1` | -3.646 | -4.708 | -1.062 | yes | 9P3Y |
| `CC(=O)Nc1ccc(O)cc1` | -4.644 | -5.907 | -1.263 | yes | 9P3Y |

## Strongest ensemble prediction

- SMILES: `CC(=O)Oc1ccccc1C(=O)O`
- Ensemble best: **-6.217 kcal/mol** (9P3Y)
- Rigid baseline: -4.917 kcal/mol
