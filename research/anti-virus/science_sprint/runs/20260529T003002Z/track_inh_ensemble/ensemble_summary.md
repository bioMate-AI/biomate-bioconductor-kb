# Ensemble Vina docking — inhibitor track

Generated: 20260529T003002Z

## Setup

- Baseline rigid docking: `research/anti-virus/runs/publication_20260528T223525Z/zinc150_screen/vina/docking_autodock_vina_results.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **15**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/top_pocket.pdb` | failed |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T003002Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/9P3I.pdb` | failed |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T003002Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/9P3Y.pdb` | failed |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260529T003002Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/9P3X.pdb` | failed |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/9P3L.pdb` | failed |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260529T003002Z/9P3M.pdb` | failed |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **0 / 15**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `N=C(N)NC(=O)c1nccnc1N` | -6.267 | — | — | no | — |
| `CNC1=NC(N)=C2NCCN=C2N1` | -5.881 | — | — | no | — |
| `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` | -5.678 | — | — | no | — |
| `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O` | -5.603 | — | — | no | — |
| `C[C@]12NCCN3CCN(CCN1)[C@@H]32` | -5.599 | — | — | no | — |
| `N=C(N)C1=C[C@@H](O)[C@@H](O)[C@@H](CO)O1` | -5.560 | — | — | no | — |
| `NC[C@H]1O[C@@H](O)[C@@H](O)[C@@H](O)[C@@H]1O` | -5.554 | — | — | no | — |
| `CO[C@@]12C[C@H](CN)O[C@H]1NC(=O)N2` | -5.531 | — | — | no | — |
| `NC(=O)CC(O)(CC(N)=O)C(N)=O` | -5.489 | — | — | no | — |
| `O=C1NC(=O)c2[nH]c(=O)c(O)nc21` | -5.425 | — | — | no | — |
| `C[C@]12NCCN[C@@]1(C)NCCN2` | -5.422 | — | — | no | — |
| `O=C1CN2C(=O)CCN[C@H]2CN1` | -5.400 | — | — | no | — |
| `O=C(O)[C@@H](O)[C@H]1O[C@H](O)[C@H](O)[C@H]1O` | -5.389 | — | — | no | — |
| `O=C(O)[C@H](O)C[C@H](O)[C@H](O)CO` | -5.297 | — | — | no | — |
| `OC[C@@H]1O[C@H](O)[C@@H](F)[C@@H](O)[C@@H]1O` | -5.273 | — | — | no | — |
