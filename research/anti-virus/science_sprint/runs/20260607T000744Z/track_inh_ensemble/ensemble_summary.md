# Ensemble Vina docking — inhibitor track

Generated: 20260607T000744Z

## Setup

- Baseline rigid docking: `/home/yzhang/biomate/research/anti-virus/runs/publication_20260528T223525Z/post_hts_qc/publication_top20_baseline.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **20**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T000744Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb` | succeeded |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3L.pdb` | succeeded |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3M.pdb` | succeeded |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T000744Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3X.pdb` | succeeded |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260607T000744Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T195530Z/9P3Y.pdb` | succeeded |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb` | succeeded |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **10 / 20**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `CN1N[C@H](c2ccc(O)cc2)[C@@H]2C(=O)NC(=O)[C@H]21` | -6.952 | -6.759 | +0.193 | no | 9P3I |
| `NC(=O)NC(=O)c1nc2ccccc2[nH]c1=O` | -6.878 | -7.483 | -0.605 | yes | 9P3Y |
| `O=C1N[C@@]2(O)C(=O)c3ccccc3[C@]2(O)N1` | -6.855 | -6.851 | +0.004 | no | 9P3I |
| `C[C@@H]1CN(C)c2nc3c(c(=O)[nH]c(=O)n3C)n2C1` | -6.762 | -6.109 | +0.653 | no | 9P3Y |
| `Cc1cc2c(cn1)CN(C(=O)[C@@H]1CNC(=O)N1)C2` | -6.754 | -6.750 | +0.004 | no | 9P3I |
| `O=C(NCCO)c1c(O)[nH]c2ccccc2c1=O` | -6.735 | -6.787 | -0.052 | yes | 9P3Y |
| `Cc1cc(N2CC3(CNC(=O)N3C)C2)nc(=N)[nH]1` | -6.720 | -6.792 | -0.072 | yes | 9P3I |
| `O=C1c2ccccc2C[C@H]1n1ccc(O)nc1=O` | -6.691 | -6.826 | -0.135 | yes | 9P3Y |
| `Nc1nc(=O)c2c([nH]1)CN(Cc1ccccc1)C2` | -6.675 | -6.473 | +0.202 | no | 9P3Y |
| `CC1=NNc2nc3c(c(=O)[nH]c(=O)n3C)n2[C@@H]1C` | -6.642 | -6.500 | +0.142 | no | 9P3Y |
| `N=c1ccc(C(=O)N2C[C@H](O)[C@@H](F)C2)c[nH]1` | -6.636 | -6.794 | -0.158 | yes | 9P3Y |
| `O=C1N[C@@H](c2ccccc2)C(=O)N2C[C@H](O)C[C@@H]12` | -6.615 | -7.562 | -0.947 | yes | 9P3Y |
| `O[C@H]1C=CC2=C([C@H](O)c3ccccc32)[C@H]1O` | -6.600 | -7.375 | -0.775 | yes | 9P3Y |
| `CN1C(=O)N(C)[C@@]2(O)c3ccccc3C(=O)[C@@]12O` | -6.548 | -5.792 | +0.756 | no | 9P3I |
| `Cc1c(C(=N)NO)c(O)nc(=O)n1C` | -6.508 | -6.489 | +0.019 | no | 9P3I |
| `O=C1c2ccccc2C[C@@H]1n1ccc(O)nc1=O` | -6.508 | -6.579 | -0.071 | yes | 9P3Y |
| `Nc1nc2cc3[nH]c(N)nc3cc2c(=O)[nH]1` | -6.505 | -6.494 | +0.011 | no | 9P3I |
| `NNCC(=O)Nc1nc2ccccc2s1` | -6.498 | -6.510 | -0.012 | yes | 9P3I |
| `Cc1cc(C(=O)N[C@H]2CC(=O)NC2=O)c(C)[nH]1` | -6.482 | -6.475 | +0.007 | no | 9P3I |
| `Cc1cnc(N2C[C@H]3CNC(=O)C[C@H]3C2)[nH]c1=N` | -6.470 | -6.610 | -0.140 | yes | 9P3Y |

## Strongest ensemble prediction

- SMILES: `O=C1N[C@@H](c2ccccc2)C(=O)N2C[C@H](O)C[C@@H]12`
- Ensemble best: **-7.562 kcal/mol** (9P3Y)
- Rigid baseline: -6.615 kcal/mol
