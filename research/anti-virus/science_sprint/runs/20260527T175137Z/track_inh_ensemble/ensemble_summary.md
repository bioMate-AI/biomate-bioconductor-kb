# Ensemble Vina docking — inhibitor track

Generated: 20260527T175137Z

## Setup

- Baseline rigid docking: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/04_docking_vina/docking_autodock_vina_results.json`
- Pocket box: `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_pockets.json`
- Receptor conformers: **6**
- Compounds docked: **3**

### Conformers

| Label | Source | S3 receptor | Dock status |
| --- | --- | --- | --- |
| top_pocket | `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/top_pocket.pdb` | failed |
| 9P3I | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T175137Z/track_inh_ensemble/receptors/9P3I.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/9P3I.pdb` | failed |
| 9P3Y | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T175137Z/track_inh_ensemble/receptors/9P3Y.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/9P3Y.pdb` | failed |
| 9P3X | `/home/yzhang/biomate/research/anti-virus/science_sprint/runs/20260527T175137Z/track_inh_ensemble/receptors/9P3X.pdb` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/9P3X.pdb` | failed |
| 9P3L | `/home/yzhang/biomate/research/anti-virus/structures/9P3L.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/9P3L.pdb` | failed |
| 9P3M | `/home/yzhang/biomate/research/anti-virus/structures/9P3M.cif` | `s3://biomate-nextflow-work/inputs/andv_campaign/science_sprint/20260527T175137Z/9P3M.pdb` | failed |

## Aggregate vs rigid baseline

- Compounds with improved ensemble best score: **0 / 3**

| SMILES | Baseline (kcal/mol) | Ensemble best | Δ | Improved | Best conformer |
| --- | ---: | ---: | ---: | --- | --- |
| `CC(=O)Oc1ccccc1C(=O)O` | -4.917 | — | — | no | — |
| `Oc1ccccc1` | -3.646 | — | — | no | — |
| `CC(=O)Nc1ccc(O)cc1` | -4.644 | — | — | no | — |
