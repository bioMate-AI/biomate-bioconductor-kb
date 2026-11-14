# MG PBMC demo — provenance

## Files

| File | Role |
|------|------|
| `counts_matrix.csv` | Gene × sample integer counts (10 MG_AChR_pos + 10 HC) |
| `sample_metadata.csv` | Sample sheet (`sample`, `condition`, `replicate`) |
| `contrasts.csv` | Contrast `MG_AChR_pos_vs_HC` on `condition` |

- **What:** Pseudobulk-aggregated AChR-positive myasthenia gravis PBMC
  tutorial inputs derived from GEO accession **GSE227835** (Li et al.).
- **Source:** Same bytes as `frontend/client/public/demo/mg_demo/` (cold-start
  attach set). Vendored here so `nf-core/differentialabundance` can fall back
  to on-disk demo paths without a live S3 `Channel.fromPath` download when no
  user inputs are supplied.
- **Not** a substitute for the larger S3 copy at
  `s3://biomate-nextflow-work/demo/mg_demo/` used by explicit URI prefills;
  both are real tutorial inputs, not fabricated results.
