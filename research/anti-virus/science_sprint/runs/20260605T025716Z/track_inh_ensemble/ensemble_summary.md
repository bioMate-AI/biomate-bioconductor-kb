# Ensemble Vina docking — inhibitor track

Generated: 20260605T025716Z

## Setup

- Baseline rigid docking: `research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **5**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260605T025716Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb` | succeeded |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3L.pdb` | succeeded |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3M.pdb` | succeeded |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260605T025716Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3X.pdb` | succeeded |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260605T025716Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3Y.pdb` | succeeded |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb` | succeeded |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **4 / 5**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `N=C(N)NC(=O)NC(=O)NC(=N)N` | -6.527 | -6.530 | -0.003 | yes | 9P3I |
| `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` | -6.275 | -6.412 | -0.137 | yes | 9P3Y |
| `N=C(N)NC(=O)c1nccnc1N` | -6.267 | -6.267 | +0.000 | no | 9P3I |
| `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N1` | -6.099 | -6.197 | -0.098 | yes | 9P3Y |
| `N=C(N)NC(=O)NC(=N)N` | -6.065 | -6.066 | -0.001 | yes | 9P3I |

## Strongest ensemble prediction

- SMILES: `N=C(N)NC(=O)NC(=O)NC(=N)N`
- Ensemble best: **-6.530 kcal/mol** (9P3I)
- Rigid baseline: -6.527 kcal/mol
