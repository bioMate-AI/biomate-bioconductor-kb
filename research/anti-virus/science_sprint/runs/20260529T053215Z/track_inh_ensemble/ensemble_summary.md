# Ensemble Vina docking — inhibitor track

Generated: 20260529T053215Z

## Setup

- Baseline rigid docking: `research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **5**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb` | failed |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T053215Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb` | failed |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T053215Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3Y.pdb` | failed |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T053215Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3X.pdb` | failed |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3L.pdb` | failed |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3M.pdb` | failed |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **1 / 5**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `N=C(N)NC(=O)c1nccnc1N` | -6.267 | -6.267 | +0.000 | no | 9P3I |
| `CNC1=NC(N)=C2NCCN=C2N1` | -5.881 | -5.881 | +0.000 | no | 9P3I |
| `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` | -5.678 | -5.738 | -0.060 | yes | 9P3Y |
| `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O` | -5.603 | -5.603 | +0.000 | no | 9P3I |
| `C[C@]12NCCN3CCN(CCN1)[C@@H]32` | -5.599 | -5.599 | +0.000 | no | 9P3I |

## Strongest ensemble prediction

- SMILES: `N=C(N)NC(=O)c1nccnc1N`
- Ensemble best: **-6.267 kcal/mol** (9P3I)
- Rigid baseline: -6.267 kcal/mol
