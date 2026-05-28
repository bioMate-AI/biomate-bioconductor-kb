# Data manifest — ANDV campaign sprint 20260527

| Stamp | Track | Key file | Status |
|-------|-------|----------|--------|
| `20260527T180210Z` | Structural epitopes | `science_sprint/runs/.../track_plan_a_structural_epitopes/` | Complete |
| `20260527T180210Z` | Cross-species | `science_sprint/runs/.../track_plan_a_cross_species/` | Complete |
| `20260527T193013Z` | MHCnuggets | `s3://biomate-nextflow-work/.../mhcnuggets/` | Complete (~506 s) |
| `20260527T193013Z` | NetMHCpan | `s3://biomate-nextflow-work/.../netmhcpan/` | Failed (missing `netmhcpan_path`; only `pipeline_info/`) |
| `20260527T195530Z` | Ensemble Vina | `science_sprint/runs/.../ensemble_results.json` | Complete (3/3 improved) |
| `20260528T033751Z` | GROMACS MD retry | run `9bf5f9a2-…`, outdir `94e4fe18` | Running (LIGAND_PREP submitted) |
| `20260527T195747Z` | GROMACS MD (1st) | `bbfc6a91` | Failed (SYSTEM_SETUP Batch timeout ~26 h) |
| `032000Z` | Chained inhibitor | `runs/andv_nf_pipeline_20260513T032000Z/` | Baseline complete |

Regenerate figure checksums before submit:

```bash
find research/anti-virus/runs/manuscript_figures_v1 -name '*.png' -exec sha256sum {} \; > research/anti-virus/docs/biorxiv_package_v1/figure_sha256.txt
```
