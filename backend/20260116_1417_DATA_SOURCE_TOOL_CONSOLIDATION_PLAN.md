# Data Source Tool Consolidation Plan

**Date**: 2026-01-16
**Status**: Plan Ready for Review

---

## Executive Summary

BioMate has **significant duplication** between Biomni database tools and Galaxy `biomate_ds_*` tools:

| Category | Count |
|----------|-------|
| Duplicate tools (both Biomni and Galaxy) | 31 |
| Biomni-only (unique) | 9 |
| Galaxy-only (unique) | 0 |
| **Total** | **40 Biomni + 31 Galaxy** |

**Recommendation**: Use Galaxy `biomate_ds_*` tools as primary (native Galaxy integration), deprecate duplicate Biomni tools, keep unique Biomni tools.

---

## 1. Analysis Results

### 1.1 Duplicate Tools (31)

These databases have BOTH Biomni and Galaxy tools:

| Database | Biomni Tool | Galaxy Tool |
|----------|-------------|-------------|
| AlphaFold | `biomni/database/query_alphafold` | `biomate_ds_api_alphafold` |
| cBioPortal | `biomni/database/query_cbioportal` | `biomate_ds_api_cbioportal` |
| ClinicalTrials | `biomni/database/query_clinicaltrials` | `biomate_ds_api_clinicaltrials` |
| ClinVar | `biomni/database/query_clinvar` | `biomate_ds_api_clinvar` |
| dbSNP | `biomni/database/query_dbsnp` | `biomate_ds_api_dbsnp` |
| EMDB | `biomni/database/query_emdb` | `biomate_ds_api_emdb` |
| Ensembl | `biomni/database/query_ensembl` | `biomate_ds_api_ensembl` |
| GEO | `biomni/database/query_geo` | `biomate_ds_api_geo` |
| gnomAD | `biomni/database/query_gnomad` | `biomate_ds_api_gnomad` |
| GtoPdb | `biomni/database/query_gtopdb` | `biomate_ds_api_gtopdb` |
| GWAS Catalog | `biomni/database/query_gwas_catalog` | `biomate_ds_api_gwas_catalog` |
| InterPro | `biomni/database/query_interpro` | `biomate_ds_api_interpro` |
| IUCN | `biomni/database/query_iucn` | `biomate_ds_api_iucn` |
| JASPAR | `biomni/database/query_jaspar` | `biomate_ds_api_jaspar` |
| KEGG | `biomni/database/query_kegg` | `biomate_ds_api_kegg` |
| Monarch | `biomni/database/query_monarch` | `biomate_ds_api_monarch` |
| MPD | `biomni/database/query_mpd` | `biomate_ds_api_mpd` |
| OpenFDA | `biomni/database/query_openfda` | `biomate_ds_api_openfda` |
| OpenTargets | `biomni/database/query_opentarget` | `biomate_ds_api_opentarget` |
| Paleobiology | `biomni/database/query_paleobiology` | `biomate_ds_api_paleobiology` |
| PDB | `biomni/database/query_pdb` | `biomate_ds_api_pdb` |
| PDB Identifiers | `biomni/database/query_pdb_identifiers` | `biomate_ds_api_pdb_identifiers` |
| PRIDE | `biomni/database/query_pride` | `biomate_ds_api_pride` |
| Reactome | `biomni/database/query_reactome` | `biomate_ds_api_reactome` |
| RegulomeDB | `biomni/database/query_regulomedb` | `biomate_ds_api_regulomedb` |
| ReMap | `biomni/database/query_remap` | `biomate_ds_api_remap` |
| STRING-DB | `biomni/database/query_stringdb` | `biomate_ds_api_stringdb` |
| Synapse | `biomni/database/query_synapse` | `biomate_ds_api_synapse` |
| UCSC | `biomni/database/query_ucsc` | `biomate_ds_api_ucsc` |
| UniProt | `biomni/database/query_uniprot` | `biomate_ds_api_uniprot` |
| WoRMS | `biomni/database/query_worms` | `biomate_ds_api_worms` |

### 1.2 Biomni-Only Tools (9)

These are **unique** to Biomni and should be **kept**:

| Database | Tool ID | Purpose |
|----------|---------|---------|
| BLAST | `biomni/database/blast_sequence` | Sequence similarity search |
| CCRE Genes | `biomni/database/get_genes_near_ccre` | Gene near cCRE lookup |
| ChEMBL | `biomni/database/query_chembl` | Bioactive molecules |
| DailyMed | `biomni/database/query_dailymed` | Drug label information |
| ENCODE | `biomni/database/query_encode` | Encyclopedia of DNA Elements |
| PubChem | `biomni/database/query_pubchem` | Chemical information |
| QuickGO | `biomni/database/query_quickgo` | Gene ontology browser |
| UniChem | `biomni/database/query_unichem` | Chemical structure mapping |
| CCRE Screen | `biomni/database/region_to_ccre_screen` | SCREEN cCRE analysis |

---

## 2. Recommendation

### 2.1 Primary Strategy: Use Galaxy `biomate_ds_*` Tools

**Advantages:**
1. Native Galaxy tool integration (no Docker needed for API calls)
2. Proper Galaxy history tracking
3. Standard Galaxy I/O handling
4. Already installed in Galaxy

### 2.2 Deprecate Duplicate Biomni Tools

For the 31 duplicate tools, update the workflow generator to prefer `biomate_ds_*`:

```python
# Tool preference mapping
TOOL_PREFERENCE = {
    'biomni/database/query_uniprot': 'biomate_ds_api_uniprot',
    'biomni/database/query_alphafold': 'biomate_ds_api_alphafold',
    # ... (31 mappings)
}
```

### 2.3 Keep Unique Biomni Tools

The 9 unique Biomni tools should remain available:
- BLAST, ChEMBL, DailyMed, ENCODE, PubChem, QuickGO, UniChem, CCRE tools

---

## 3. Implementation Plan

### Phase 1: Update Tool Search Ranking (Immediate)

Update `unified_tool_search.py` to deprioritize duplicate Biomni tools:

```python
# In UnifiedToolSearch._direct_entity_match()
DEPRECATED_TOOLS = {
    'biomni/database/query_uniprot',
    'biomni/database/query_alphafold',
    # ... (31 tools)
}

# Reduce score for deprecated tools
if tool_id in DEPRECATED_TOOLS:
    match_score -= 100  # Strongly prefer Galaxy version
```

### Phase 2: Update Workflow Generator (Short-term)

In `galaxy_workflow_generator.py`, add tool ID normalization:

```python
def _normalize_tool_id(self, tool_id: str) -> str:
    """Normalize tool ID to prefer Galaxy native tools."""
    TOOL_MAPPING = {
        'biomni/database/query_uniprot': 'biomate_ds_api_uniprot',
        # ...
    }
    return TOOL_MAPPING.get(tool_id, tool_id)
```

### Phase 3: Database Cleanup (Medium-term)

Option A: Mark deprecated tools in database
```sql
ALTER TABLE tools ADD COLUMN deprecated BOOLEAN DEFAULT FALSE;
UPDATE tools SET deprecated = TRUE WHERE tool_id IN (
    'biomni/database/query_uniprot',
    -- ...
);
```

Option B: Remove deprecated tools from database (more aggressive)

### Phase 4: Documentation (Ongoing)

Update user documentation to recommend Galaxy `biomate_ds_*` tools.

---

## 4. Migration Checklist

- [ ] Add `DEPRECATED_TOOLS` list to tool search
- [ ] Add `TOOL_MAPPING` to workflow generator
- [ ] Update tool catalog display to show preferred tool
- [ ] Test workflow generation uses correct tools
- [ ] Update documentation
- [ ] Mark deprecated tools in database

---

## 5. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing workflows | Medium | Keep Biomni tools functional, just deprioritize |
| Galaxy `biomate_ds_*` tools missing features | Low | Compare parameter sets before deprecation |
| User confusion | Low | Clear documentation and warnings |

---

## Appendix: Tool Comparison Example

### UniProt Query Tool Comparison

**Biomni Tool**: `biomni/database/query_uniprot`
```
Parameters:
- prompt (str, optional): Natural language query
- endpoint (str, optional): Direct API URL
- max_results (int, optional): Max results
```

**Galaxy Tool**: `biomate_ds_api_uniprot`
```
To be verified - check Galaxy tool XML
```

**Recommendation**: Verify Galaxy tool has equivalent parameters before full deprecation.
