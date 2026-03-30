# AlphaFold DB Search Workflow — Implementation

**Date**: 2026-03-20
**Branch**: connection_formal
**Status**: COMPLETE — workflow parses cleanly, mock run 3/3 processes pass

## What was built

### S3 bucket
- `biomate-structure-db` created in us-west-2 with versioning enabled
- Structure: `s3://biomate-structure-db/alphafold/human/{foldseek_db/,mmseqs2_db/,fasta/}`

### Nextflow workflow
- **File**: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/alphafold_db_search/main.nf`
- **Config**: `...alphafold_db_search/nextflow.config`
- **DB build script**: `...alphafold_db_search/scripts/build_alphafold_db.sh`

#### 3 processes:
1. `FOLDSEEK_STRUCTURAL_SEARCH` — `steineggerlab/foldseek:latest`
   - Input: query PDB/CIF + S3 DB URI + search params
   - Output: foldseek_hits.tsv, foldseek_report.html, versions.yml
   - Mock: 5 synthetic hits (TP53, EGFR, CALM1, SOD1, HBB)

2. `MMSEQS2_SEQUENCE_SEARCH` — `soedinglab/mmseqs2:latest`
   - Input: query FASTA/PDB + S3 DB URI + search params
   - Output: mmseqs2_hits.tsv, mmseqs2_report.html, versions.yml
   - Mock: 3 synthetic hits (TP53, EGFR, MAPT)

3. `MERGE_SEARCH_RESULTS` — `python:3.11-slim`
   - Input: foldseek_hits + mmseqs2_hits
   - Output: combined_hits.tsv, search_summary.json, combined_report.html
   - JSON summary: `{foldseek_hits, mmseqs2_hits, total_hits, top_structural[], top_sequence[]}`

### DB registration
- Registered as id=12647 in `galaxy_ai_tools.db` with FTS indexing
- Domain: `drug_discovery`, tags: alphafold, foldseek, mmseqs2, structural-search, sequence-search, etc.

## Key fixes during development
- **Em dash bug**: UTF-8 em dashes (`—`) in Groovy/Nextflow comments crash the parser. Replace with `--`.
- **Triple-quote bug**: Python `"""..."""` strings inside `<< 'PYEOF'` heredocs terminate Nextflow's `"""..."""` script block early. Fix: use `'''...'''` in Python.

## Mock run output
```
executor > local (3)
FOLDSEEK_STRUCTURAL_SEARCH (query) | 1 of 1 ✔
MMSEQS2_SEQUENCE_SEARCH (query)    | 1 of 1 ✔
MERGE_SEARCH_RESULTS (query)       | 1 of 1 ✔
```

Output: `{combined_hits.tsv, combined_report.html, search_summary.json, foldseek/, mmseqs2/}`

## Pending: DB population
The S3 indexes are empty — build with:
```bash
# On r6i.8xlarge (256 GB RAM, 300 GB storage)
bash backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/alphafold_db_search/scripts/build_alphafold_db.sh
```
This downloads ~48k human proteome mmCIF from GCS, builds Foldseek + MMseqs2 indexes, uploads to S3.
Estimated: ~3-4 hours, ~120 GB working space.

## AlphaFold3 credentials placeholder
- `ALPHAFOLD3_DOCKER_USER=` (empty — pending account approval)
- `ALPHAFOLD3_DOCKER_TOKEN=` (empty — pending account approval)
- Apply at: https://alphafold.ebi.ac.uk/
- `NVIDIA_NIM_API_KEY=` (empty — optional, Boltz-2 falls back to local weights)
