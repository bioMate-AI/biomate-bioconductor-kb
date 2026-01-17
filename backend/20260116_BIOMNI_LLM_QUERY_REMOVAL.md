# Biomni LLM and Query Functions Removal

**Date:** 2026-01-16
**Author:** Claude Code Assistant
**Purpose:** Document removal of LLM-dependent and query functions from Biomni

## Summary

Removed all LLM-dependent functions and query functions from Biomni Python modules. These functions are now handled by Galaxy tools (`biomate_ds_api_*`).

## Files Deleted

| File | Reason |
|------|--------|
| `biomni/tool/database_enhanced.py` | Entirely LLM-dependent (EnhancedQueryEngine) |
| `biomni/tool/protocols.py` | External API query (protocols.io) |

## Functions Removed from database.py

| Removed Function | Galaxy Equivalent | Status |
|-----------------|-------------------|--------|
| `query_uniprot` | `biomate_ds_api_uniprot` | ✅ Available |
| `query_pdb` | `biomate_ds_api_pdb` | ✅ Available |
| `query_kegg` | `biomate_ds_api_kegg` | ✅ Available |
| `query_alphafold` | `biomate_ds_api_alphafold` | ✅ Available |
| `query_interpro` | `biomate_ds_api_interpro` | ✅ Available |
| `query_stringdb` | `biomate_ds_api_stringdb` | ✅ Available |
| `query_pdb_identifiers` | `biomate_ds_api_pdb_identifiers` | ✅ Available |
| `query_chembl` | ⚠️ No direct equivalent | Need to add |
| `query_pubchem` | ⚠️ No direct equivalent | Need to add |
| `query_clinvar` | `biomate_ds_api_clinvar` | ✅ Available |
| `query_dbsnp` | `biomate_ds_api_dbsnp` | ✅ Available |
| `query_geo` | `biomate_ds_api_geo` | ✅ Available |
| `query_ensembl` | `biomate_ds_api_ensembl` | ✅ Available |
| `query_gnomad` | `biomate_ds_api_gnomad` | ✅ Available |
| `query_gwas_catalog` | `biomate_ds_api_gwas_catalog` | ✅ Available |
| `query_reactome` | `biomate_ds_api_reactome` | ✅ Available |
| `query_quickgo` | ⚠️ No direct equivalent | Need to add |
| `query_cbioportal` | `biomate_ds_api_cbioportal` | ✅ Available |
| `query_clinicaltrials` | `biomate_ds_api_clinicaltrials` | ✅ Available |
| `query_dailymed` | ⚠️ No direct equivalent | Need to add |
| `query_emdb` | `biomate_ds_api_emdb` | ✅ Available |
| `query_encode` | ⚠️ No direct equivalent | Need to add |
| `query_gtopdb` | `biomate_ds_api_gtopdb` | ✅ Available |
| `query_jaspar` | `biomate_ds_api_jaspar` | ✅ Available |
| `query_monarch` | `biomate_ds_api_monarch` | ✅ Available |
| `query_mpd` | `biomate_ds_api_mpd` | ✅ Available |
| `query_openfda` | `biomate_ds_api_openfda` | ✅ Available |
| `query_opentarget` | `biomate_ds_api_opentarget` | ✅ Available |
| `query_paleobiology` | `biomate_ds_api_paleobiology` | ✅ Available |
| `query_pride` | `biomate_ds_api_pride` | ✅ Available |
| `query_regulomedb` | `biomate_ds_api_regulomedb` | ✅ Available |
| `query_remap` | `biomate_ds_api_remap` | ✅ Available |
| `query_synapse` | `biomate_ds_api_synapse` | ✅ Available |
| `query_ucsc` | `biomate_ds_api_ucsc` | ✅ Available |
| `query_unichem` | ⚠️ No direct equivalent | Need to add |
| `query_worms` | `biomate_ds_api_worms` | ✅ Available |
| `query_iucn` | `biomate_ds_api_iucn` | ✅ Available |
| `get_enhanced_engine` | N/A (LLM helper) | Removed |
| `use_enhanced_query` | N/A (LLM helper) | Removed |
| `_query_llm_for_api` | N/A (LLM helper) | Removed |

### Functions Retained in database.py

| Function | Reason |
|----------|--------|
| `get_hpo_names` | Local data lookup, no LLM |
| `blast_sequence` | NCBI BLAST API, no LLM |
| `region_to_ccre_screen` | SCREEN API, no LLM |
| `get_genes_near_ccre` | SCREEN API, no LLM |

## Functions Removed from literature.py

| Removed Function | Galaxy Equivalent | Status |
|-----------------|-------------------|--------|
| `query_arxiv` | ⚠️ No direct equivalent | Low priority |
| `query_scholar` | ⚠️ No direct equivalent | Low priority |
| `query_pubmed` | ⚠️ No direct equivalent | Need to add |
| `search_google` | ⚠️ No direct equivalent | Low priority |
| `advanced_web_search_claude` | N/A (LLM-dependent) | Removed |

### Functions Retained in literature.py

| Function | Reason |
|----------|--------|
| `fetch_supplementary_info_from_doi` | DOI resolution, no LLM |
| `extract_url_content` | Web scraping, no LLM |
| `extract_pdf_content` | PDF parsing, no LLM |

## Functions Removed from genomics.py

| Removed Function | Reason |
|-----------------|--------|
| `annotate_celltype_scRNA` | LLM-dependent cell type annotation |

## Galaxy Tool Coverage Analysis

### Tools with Galaxy Toolshed Equivalents (No action needed)

| Removed Biomni Function | Galaxy Toolshed Tool |
|------------------------|---------------------|
| `query_chembl` | `bgruening/chembl` - Search ChEMBL database |
| `query_pubchem` | `bgruening/get_pubchem` - PubChem Download |
| `query_pubmed` | `iuc/pubmed_by_queries` - PubMed query |

### Tools Needing Galaxy Implementation (Low Priority)

| Function | Database | Notes |
|----------|----------|-------|
| `query_quickgo` | QuickGO | Gene Ontology - alternative: use GO tools |
| `query_dailymed` | DailyMed | FDA drug labels - alternative: use openFDA |
| `query_encode` | ENCODE | Regulatory elements - can use UCSC/SCREEN |
| `query_unichem` | UniChem | Compound cross-refs - can use ChEMBL |

### All biomate_ds_api_* Tools Verified

```
biomate_ds_api_alphafold      biomate_ds_api_monarch
biomate_ds_api_cbioportal     biomate_ds_api_mpd
biomate_ds_api_clinicaltrials biomate_ds_api_openfda
biomate_ds_api_clinvar        biomate_ds_api_opentarget
biomate_ds_api_dbsnp          biomate_ds_api_paleobiology
biomate_ds_api_emdb           biomate_ds_api_pdb
biomate_ds_api_ensembl        biomate_ds_api_pdb_identifiers
biomate_ds_api_geo            biomate_ds_api_pride
biomate_ds_api_gnomad         biomate_ds_api_reactome
biomate_ds_api_gtopdb         biomate_ds_api_regulomedb
biomate_ds_api_gwas_catalog   biomate_ds_api_remap
biomate_ds_api_interpro       biomate_ds_api_stringdb
biomate_ds_api_iucn           biomate_ds_api_synapse
biomate_ds_api_jaspar         biomate_ds_api_ucsc
biomate_ds_api_kegg           biomate_ds_api_uniprot
                              biomate_ds_api_worms
```

Total: 31 Galaxy data source tools available

## Security Notes

1. All removed functions used LLM API keys (Anthropic, OpenAI) which are now not required in Biomni tool modules
2. Galaxy tools (`biomate_ds_api_*`) make direct API calls without LLM intermediary
3. This reduces attack surface by removing LLM prompt injection vectors
4. External API tokens (protocols.io) are no longer needed

## Migration Path

For users who were using Biomni query functions:
- Use Galaxy `biomate_ds_api_*` tools instead
- These tools are available in the Galaxy tool panel under "Data Source"
- No API key configuration needed for most databases

## Files Changed

```
Biomni/biomni/tool/
├── database.py          # Cleaned: 4 functions remain (was 44)
├── database_enhanced.py # DELETED
├── literature.py        # Cleaned: 3 functions remain (was 8)
├── protocols.py         # DELETED
└── genomics.py          # Cleaned: removed annotate_celltype_scRNA
```
