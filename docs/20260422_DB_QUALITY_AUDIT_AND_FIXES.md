# Workflow DB Quality Audit & Fixes — 2026-04-22

## Summary

Full audit of `backend/database/galaxy_ai_tools.db` → workflows table (2,473 records).
Applied 7 fix groups; database now at **100% quality** on all tracked metrics.

## Pre-fix State

| Metric | Before | After |
|--------|--------|-------|
| Total workflows | 2,473 | 2,455 |
| Missing annotations | 6 | 0 |
| Missing tags | 1 | 0 |
| Duplicate names | 18 groups | 0 |
| Mislabeled domain ("general") | 72 fixable | 0 fixable |

## Fixes Applied

### 1. Domain Reclassification (72 workflows)

**Problem**: 536 workflows labeled `domain='general'`. 72 were clearly wrong — nf-core genomics subworkflows, proteomics packages, and transcriptomics modules.

**Root cause**: nf-core subworkflows were bulk-imported with domain="general" because they're utility subworkflows rather than complete pipelines. The domain field should reflect the *biological domain*, not the pipeline role.

**Fix**: Keyword-matched on workflow name + tags to reclassify:
- **66 → genomics**: nf-core BAM/FASTQ/genome processing subworkflows (bam_*, fastq_*, bcl_demultiplex, bam_stats_samtools, etc.) + nf-core primary pipelines (sarek, rnaseq, ampliseq, abotyper, airrflow, etc.)
- **3 → proteomics**: CyTOFpower, cytofQC, tidytof (mass cytometry packages)
- **3 → transcriptomics**: alabaster_spatial and spatialvi-related (spatial transcriptomics)

**Remaining "general"**: 464 Bioconductor R packages that are genuinely general-purpose utility packages with no single domain affiliation.

### 2. Missing Annotations (6 workflows)

Added short descriptive annotations to:
- `12811` DeepEMhancer Post-Processing (cryo_em)
- `12812` Liposome Pore Forming SPA (cryo_em)
- `12813` RELION Multi-Body Refinement (cryo_em)
- `12814` Assay Ingestion And Ranking (drug_discovery)
- `12815` Cro Submission Export (drug_discovery)
- `12828` P0 PKPD Semaglutide Validation (drug_discovery)

### 3. Missing Tags (1 workflow)

- `12828` P0 PKPK Semaglutide: added `["drug_discovery","biomni","nextflow","pkpd","pharmacokinetics","validation"]`

### 4. Duplicate Removal (18 pairs → 18 deleted)

Two patterns of duplicates found:

**Pattern A — Superseded path** (5 pairs, drug_discovery workflows):  
Old IDs `10761,10768,10773,10778,10782` used path `nextflow_nfcore/subworkflows/pharmacology/…`. 
New IDs `12822–12826` use the canonical `nextflow_nfcore/subworkflows/drug_discovery/…` path.
Both files existed. **Kept**: new drug_discovery-path versions. **Deleted**: old pharmacology-path versions.

**Pattern B — Dead-path duplicates** (13 pairs, various domains):  
Old IDs `10573,10575,10610,10639,10726,10736,10741,10748,10749,10807,10816,10819,10825` use valid `subworkflows/` paths.
New IDs `12648–12668` use flat paths (e.g., `nextflow_nfcore/bioengineering/…/main.nf`) that don't exist on disk.
**Kept**: old valid-path versions. **Deleted**: new dead-path versions.

## Remaining Known Issues (Not Fixed)

### Broken paths (377 workflows)
15.2% of workflows reference files that don't exist:
- **230 nfcore primary pipelines**: Reference `nfcore/[pipeline]/main.nf` — these are Galaxy wrapper metadata records, not executable files. They exist for search/discovery.
- **93 nfcore_subwf entries**: Similar metadata-only records.
- **32 nextflow + 22 others**: Mix of stale references and metadata-only entries.

**Decision**: Do not delete. These records are needed for workflow search/discovery (the IR pipeline ranks them). Mark as `is_metadata_only=true` in a future schema migration if needed.

### 464 "general" Bioconductor packages
These R/Bioconductor packages genuinely span multiple domains (normalization, QC, statistics) and "general" is the correct classification. No fix needed.

### 4 drug_discovery workflows with step_count > 0 but empty workflow_json
- `12799` GROMACS Protein-Ligand MD + MM-GBSA
- `12800` REINVENT4 Generative Lead Design  
- `12830` OpenFE RBFE
- `12831` CYP450 DDI Panel

These have `step_count` set but `workflow_json=NULL`. The step_count was set from the Nextflow file, but `workflow_json` (Galaxy .ga format) was never populated. Not a critical bug — the viewer uses `workflow_ga` from the API response, not the stored `workflow_json`.

## Post-fix Domain Distribution

| Domain | Count |
|--------|-------|
| transcriptomics | 865 |
| general (Bioconductor R) | 464 |
| genomics | 369 (+66) |
| epigenomics | 133 |
| proteomics | 113 (+3) |
| variant_calling | 102 |
| drug_discovery | 61 |
| imaging | 45 |
| metagenomics | 42 |
| molecular_biology | 26 |
| single_cell | 22 |
| bioimaging | 22 |
| metabolomics | 21 |
| microbiology | 16 |
| pharmacology | 15 |
| (18 other domains) | 59 |
| **Total** | **2,455** |

## Script

All changes were applied via inline Python script using `sqlite3` directly.
Key fix logic preserved in `backend/scripts/patch_workflow_descriptions.py` (extend with domain patch if needed).
