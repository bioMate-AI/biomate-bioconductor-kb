# Dataset Format Compatibility Assessment
**Date**: October 9, 2025
**Project**: BioMate - Local Dataset Format Analysis
**Purpose**: Determine if existing local datasets are Galaxy-ready or need format conversion

---

## Executive Summary

**Analysis of 84 local datasets (76 biomni_data_lake + 8 metaboanalyst pathway files)**:
- ✅ **51 files (61%)** are Galaxy-ready (CSV, TSV, TXT formats)
- ⚠️ **41 Parquet files (49%)** need conversion to CSV/TSV
- ⚠️ **7 PKL files (8%)** need conversion to CSV/TSV
- ✅ **10 SQLite files (100%)** are Galaxy-compatible for specific tools
- ✅ **1 OBO file** is compatible (ontology format)
- ✅ **1 JSON file** is compatible

**Key Finding**: Most datasets require minimal preprocessing. Parquet files need one-time conversion to CSV/TSV for universal Galaxy compatibility.

---

## Galaxy Datatype System Overview

### Standard Galaxy Datatypes

Galaxy has a comprehensive datatype registry. Common formats for tabular data:

| Galaxy Datatype | File Extensions | Description | Compatibility |
|----------------|----------------|-------------|---------------|
| **tabular** | .tsv, .txt | Tab-separated values | ✅ Universal |
| **csv** | .csv | Comma-separated values | ✅ Universal |
| **txt** | .txt | Plain text | ✅ Universal |
| **sqlite** | .sqlite, .db | SQLite database | ⚠️ Tool-specific |
| **json** | .json | JSON format | ⚠️ Limited support |
| **obo** | .obo | Ontology format | ✅ Ontology tools |
| **parquet** | .parquet | Apache Parquet | ❌ Not native |
| **pkl** | .pkl, .pickle | Python pickle | ❌ Not native |

### How Galaxy Tools Accept Datasets

Galaxy tools declare input requirements in two ways:

#### 1. **Data Input Parameters** (for workflow inputs)
```xml
<param name="input_file" type="data" format="tabular,csv,tsv" label="Input dataset"/>
```
- Accepts datasets from Galaxy history
- Format auto-detection or user-specified
- Works with uploaded files

#### 2. **Reference Data Parameters** (for large databases)
```xml
<param name="reference_db" type="text" label="Reference database path"/>
<!-- OR -->
<param name="reference_db" type="data" format="tabular" label="Reference database"/>
```
- Can point to server file paths (for large files)
- Or accept as data input (for user uploads)

---

## Local Dataset Format Analysis

### 1. biomni_data_lake (76 files)

#### Format Distribution
```
41 parquet files (54%)
21 csv files (28%)
7 pkl files (9%)
3 txt files (4%)
2 tsv files (3%)
1 obo file (1%)
1 json file (1%)
```

#### Detailed Assessment by Format

##### ✅ Galaxy-Ready Formats (27 files, 36%)

**CSV Files (21 files)**:
- DepMap_CRISPRGeneDependency.csv (403 MB)
- DisGeNET_geneNDiseaseAssociations.csv (96 MB)
- DGIdb_interactions.csv (16 MB)
- DrugBank_approved_target.csv (19 MB)
- HGNC_complete_set.csv (14 MB)
- LINCS_L1000_compounds.csv (2.0 MB)
- LINCS_L1000_genes.csv (24 KB)
- NCBI_Gene_Info_Homo_sapiens.csv (56 MB)
- Open_Targets_disease_target_associations.csv (1.2 GB)
- OpenTargets_gene_ontology.csv (56 MB)
- PubChem_BioAssay_summary.csv (42 MB)
- SIDER_drug_side_effects.csv (10 MB)
- STRING_protein_links_detailed.csv (1.7 GB)
- STRING_protein_aliases.csv (154 MB)
- STRING_protein_functional_enrichment.csv (2.1 MB)
- TTD_P1-01-TTD_target_download.csv (370 KB)
- TTD_P1-02-TTD_drug_download.csv (1.3 MB)
- TTD_P1-03-TTD_crossmatching.csv (228 KB)
- TTD_P1-06-Drug_synonyms.csv (1.1 MB)
- UniProt_Human_Proteome.csv (231 MB)
- drugbank_all.csv (51 MB)

**Status**: ✅ **Ready to use** - Native Galaxy tabular format

**TSV Files (2 files)**:
- BindingDB_All_202409.tsv (5.8 GB)
- GO_biological_process.tsv (78 MB)

**Status**: ✅ **Ready to use** - Native Galaxy tabular format

**TXT Files (3 files)**:
- KEGG_pathway_disease.txt (1.0 MB)
- KEGG_pathway_drug.txt (157 KB)
- KEGG_pathway_list.txt (73 KB)

**Status**: ✅ **Ready to use** - Can be treated as tabular if tab/comma delimited

**OBO Files (1 file)**:
- gene_ontology_edit.obo (47 MB)

**Status**: ✅ **Ready to use** - Standard ontology format, supported by GO enrichment tools

**JSON Files (1 file)**:
- Reactome_PathwayHierarchy.json (1.5 MB)

**Status**: ✅ **Ready to use** - JSON is supported, though tabular might be more universally compatible

##### ⚠️ Requires Conversion (48 files, 63%)

**Parquet Files (41 files)**:
- ChEMBL_activities.parquet (5.0 GB)
- ChEMBL_assays.parquet (167 MB)
- ChEMBL_compound_properties.parquet (569 MB)
- ChEMBL_compounds.parquet (1.2 GB)
- ChEMBL_drug_mechanisms.parquet (26 MB)
- ChEMBL_molecule_hierarchy.parquet (108 MB)
- ChEMBL_target_components.parquet (1.8 MB)
- ChEMBL_target_dictionary.parquet (10 MB)
- COSMIC_gene_census.parquet (195 KB)
- Ensembl_gene_annotations.parquet (186 MB)
- ExAC_variants.parquet (8.3 GB)
- GTEx_tissue_gene_expression.parquet (1.8 GB)
- KEGG_compound.parquet (38 MB)
- KEGG_drug.parquet (36 MB)
- KEGG_enzyme.parquet (5.4 MB)
- KEGG_genes_eco.parquet (15 MB)
- KEGG_genes_hsa.parquet (43 MB)
- KEGG_pathway.parquet (3.1 MB)
- KEGG_reaction.parquet (21 MB)
- PubChem_Compound_inchi.parquet (2.6 GB)
- PubChem_Compound_props.parquet (8.4 GB)
- Reactome_ChEBI2Pathway_All_Levels.parquet (2.7 MB)
- Reactome_Ensembl2Pathway_All_Levels.parquet (6.7 MB)
- Reactome_NCBI2Pathway_All_Levels.parquet (6.1 MB)
- Reactome_UniProt2Pathway_All_Levels.parquet (7.3 MB)
- clinvar_variant_summary.parquet (626 MB)
- gnomad_genomes_variants.parquet (12 GB)
- pubchem_compound_mesh.parquet (211 MB)
- pubchem_compound_parent.parquet (363 MB)
- pubchem_compound_same.parquet (1.6 GB)
- pubchem_protein.parquet (2.3 GB)
- (+ 11 more parquet files)

**Issue**: Parquet is a columnar binary format not natively supported by Galaxy datatypes.

**Status**: ⚠️ **Needs conversion to CSV/TSV**

**Recommendation**:
```python
# One-time conversion script
import pandas as pd
import glob

parquet_files = glob.glob('/path/to/biomni_data_lake/*.parquet')
for parquet_file in parquet_files:
    df = pd.read_parquet(parquet_file)
    csv_file = parquet_file.replace('.parquet', '.csv')
    df.to_csv(csv_file, index=False)
    print(f"✓ Converted {parquet_file} → {csv_file}")
```

**PKL Files (7 files)**:
- HPO_disease_phenotype_associations.pkl (22 MB)
- KEGG_pathway_compounds.pkl (13 MB)
- KEGG_pathway_genes.pkl (26 MB)
- PubChem_Compound_cid.pkl (2.5 GB)
- Reactome_PathwaysRelation.pkl (232 KB)
- UniProt_ID_Mapping.pkl (1.3 GB)
- hmdb_metabolites.pkl (87 MB)

**Issue**: Python pickle format is not a Galaxy datatype.

**Status**: ⚠️ **Needs conversion to CSV/TSV**

**Recommendation**:
```python
import pickle
import pandas as pd

pkl_files = glob.glob('/path/to/biomni_data_lake/*.pkl')
for pkl_file in pkl_files:
    with open(pkl_file, 'rb') as f:
        data = pickle.load(f)

    # Convert to DataFrame (assuming dict or list structure)
    if isinstance(data, dict):
        df = pd.DataFrame.from_dict(data, orient='index')
    elif isinstance(data, list):
        df = pd.DataFrame(data)
    else:
        df = pd.DataFrame(data)

    csv_file = pkl_file.replace('.pkl', '.csv')
    df.to_csv(csv_file, index=True)
    print(f"✓ Converted {pkl_file} → {csv_file}")
```

### 2. MetaboAnalyst SQLite Databases (10 files)

**Files**:
- FragsAnnotateDB_v02042024.sqlite (1.4 GB)
- FragsAnnotateDBNL_v02042024.sqlite (1.2 GB)
- MS2ID_Bio_v09102023.sqlite (710 MB)
- MS2ID_BioNL_v09102023.sqlite (468 MB)
- MS2ID_Exposomics_v09102023.sqlite (1.4 GB)
- MS2ID_ExposomicsNL_v09102023.sqlite (1.0 GB)
- MS2ID_Lipids_v09102023.sqlite (1.5 GB)
- MS2ID_LipidsNL_v09102023.sqlite (1.1 GB)
- MS2ID_Pathway_v09102023.sqlite (130 MB)
- MS2ID_PathwayNL_v09102023.sqlite (90 MB)

**Status**: ✅ **Galaxy-compatible for specific tools**

**Compatible Tools** (from assessment):
- **ipaPy2 MS2 annotation** - Accepts MS2 database parameter
- **CFM-ID** - Accepts local database in CSV (can query SQLite and export)
- Custom metabolomics tools that use SQLite

**Usage Pattern**:
```xml
<!-- Galaxy tool can accept SQLite directly -->
<param name="ms2_database" type="data" format="sqlite" label="MS2 Spectral Database"/>
```

**Alternative**: Export key tables to CSV for broader compatibility:
```python
import sqlite3
import pandas as pd

sqlite_files = glob.glob('/path/to/metaboanalyst/*.sqlite')
for db_file in sqlite_files:
    conn = sqlite3.connect(db_file)

    # Get table names
    tables = pd.read_sql_query("SELECT name FROM sqlite_master WHERE type='table'", conn)

    for table_name in tables['name']:
        df = pd.read_sql_query(f"SELECT * FROM {table_name}", conn)
        csv_file = db_file.replace('.sqlite', f'_{table_name}.csv')
        df.to_csv(csv_file, index=False)
        print(f"✓ Exported {db_file}:{table_name} → {csv_file}")

    conn.close()
```

### 3. MetaboAnalyst Pathway TXT Files (8 files)

**Files**:
- smpdb_pathways.txt
- KEGG_pathway_info.txt
- Reactome_pathway_info.txt
- (+ 5 more pathway .txt files)

**Status**: ✅ **Galaxy-ready** - Standard text format

---

## Format Compatibility Matrix

| Format | # Files | Size Range | Galaxy Native? | Action Required | Compatible Tools |
|--------|---------|------------|----------------|-----------------|------------------|
| **CSV** | 21 | 24 KB - 2.1 GB | ✅ Yes | None | Universal (1,332+ tools) |
| **TSV** | 2 | 78 MB - 5.8 GB | ✅ Yes | None | Universal (1,332+ tools) |
| **TXT** | 11 | 73 KB - 47 MB | ✅ Yes | None | Universal |
| **SQLite** | 10 | 90 MB - 1.5 GB | ⚠️ Tool-specific | None (or CSV export) | ipaPy2, CFM-ID, custom tools |
| **JSON** | 1 | 1.5 MB | ⚠️ Limited | Optional CSV conversion | JSON-aware tools |
| **OBO** | 1 | 47 MB | ✅ Yes | None | GO enrichment tools |
| **Parquet** | 41 | 195 KB - 12 GB | ❌ No | **Convert to CSV** | None (must convert) |
| **PKL** | 7 | 232 KB - 2.5 GB | ❌ No | **Convert to CSV** | None (must convert) |

---

## Recommendations

### Priority 1: Convert Parquet Files (HIGH PRIORITY)

**Why**: 41 files (54% of biomni_data_lake) are in Parquet format, which is not a Galaxy datatype.

**Action**: One-time batch conversion to CSV
```bash
# Create conversion script
python3 /Users/jingqiwang/biomate/backend/scripts/convert_parquet_to_csv.py

# Script converts all .parquet → .csv in biomni_data_lake
# Estimated time: 30-60 minutes (depending on file sizes)
```

**Impact**: Unlocks 41 datasets for use with 1,332+ Galaxy tools

### Priority 2: Convert PKL Files (MEDIUM PRIORITY)

**Why**: 7 files in Python pickle format are not Galaxy-compatible.

**Action**: Convert to CSV based on data structure
```bash
python3 /Users/jingqiwang/biomate/backend/scripts/convert_pkl_to_csv.py
```

**Note**: Requires inspection of each PKL file structure (dict, list, DataFrame, etc.)

**Impact**: Unlocks 7 datasets for Galaxy workflows

### Priority 3: SQLite Database Strategy (LOW PRIORITY - OPTIONAL)

**Current Status**: SQLite files work with specific metabolomics tools (ipaPy2, CFM-ID)

**Options**:
1. **Keep as SQLite** - Use directly with compatible tools
   - ✅ Efficient storage
   - ✅ Queryable databases
   - ⚠️ Limited to tools that accept SQLite

2. **Export to CSV** - Export key tables for broader compatibility
   - ✅ Universal tool compatibility
   - ⚠️ Larger file sizes
   - ⚠️ Loss of relational structure

**Recommendation**: **Keep SQLite as-is** for metabolomics workflows. Export to CSV only if needed for tools that don't support SQLite.

### Priority 4: Update Dataset Index (IMMEDIATE)

**Action**: Update `dataset_index_comprehensive.json` with format compatibility flags

**Add to each dataset entry**:
```json
{
  "biomni_data_lake_ChEMBL_activities_parquet": {
    "name": "ChEMBL_activities.parquet",
    "format": "parquet",
    "galaxy_compatible": false,
    "requires_conversion": true,
    "target_format": "csv",
    "converted_file": "ChEMBL_activities.csv",
    "compatible_tools": []
  },
  "biomni_data_lake_BindingDB_All_202409_tsv": {
    "name": "BindingDB_All_202409.tsv",
    "format": "tsv",
    "galaxy_compatible": true,
    "requires_conversion": false,
    "compatible_tools": [
      "similarity_search_tool_id",
      "compound_screening_tool_id"
    ]
  }
}
```

---

## Implementation Plan

### Phase 1: Parquet Conversion (Week 1)

**Tasks**:
1. Create `scripts/convert_parquet_to_csv.py`
2. Run conversion on all 41 parquet files
3. Update dataset index with new CSV file paths
4. Test CSV file integrity (random sampling)

**Estimated time**: 1 day

**Deliverables**:
- 41 new CSV files in biomni_data_lake
- Updated dataset index
- Conversion log (success/failure for each file)

### Phase 2: PKL Conversion (Week 1)

**Tasks**:
1. Inspect PKL file structures (5-10 min per file)
2. Create `scripts/convert_pkl_to_csv.py` with custom logic per file
3. Run conversion on all 7 PKL files
4. Update dataset index

**Estimated time**: 4 hours

**Deliverables**:
- 7 new CSV files
- Updated dataset index
- Conversion documentation

### Phase 3: Dataset Index Update (Week 1)

**Tasks**:
1. Add `galaxy_compatible`, `requires_conversion`, `compatible_tools` fields
2. Map each dataset to compatible Galaxy tools (from 1,332 database-accepting tools)
3. Generate compatibility report

**Estimated time**: 2 hours

**Deliverables**:
- Enhanced dataset index with tool mappings
- Dataset-to-tool compatibility matrix (JSON)

### Phase 4: SQLite Strategy Decision (Week 2)

**Tasks**:
1. Test ipaPy2/CFM-ID with existing SQLite databases
2. If needed, create selective CSV exports (e.g., compound_spectrum table)
3. Document SQLite usage in Galaxy workflows

**Estimated time**: 3 hours (if export needed)

**Deliverables**:
- SQLite usage documentation
- Optional: CSV exports of key tables

---

## Technical Specifications

### Conversion Script: Parquet to CSV

**File**: `/Users/jingqiwang/biomate/backend/scripts/convert_parquet_to_csv.py`

```python
#!/usr/bin/env python3
"""
Convert all Parquet files in biomni_data_lake to CSV format for Galaxy compatibility
"""
import pandas as pd
import glob
import os
import sys
from pathlib import Path

SOURCE_DIR = "/Users/jingqiwang/Biomni/knowledge_data/biomni_data_lake"
LOG_FILE = "/Users/jingqiwang/biomate/backend/logs/parquet_conversion.log"

def convert_parquet_to_csv(parquet_file: str) -> bool:
    """Convert single parquet file to CSV"""
    try:
        print(f"Converting {os.path.basename(parquet_file)}...", end=" ")

        # Read parquet
        df = pd.read_parquet(parquet_file)

        # Generate CSV filename
        csv_file = parquet_file.replace('.parquet', '.csv')

        # Write CSV
        df.to_csv(csv_file, index=False)

        file_size = os.path.getsize(csv_file) / (1024**3)  # GB
        print(f"✓ ({file_size:.2f} GB)")

        return True
    except Exception as e:
        print(f"✗ ERROR: {e}")
        return False

def main():
    # Find all parquet files
    parquet_files = glob.glob(f"{SOURCE_DIR}/*.parquet")
    print(f"Found {len(parquet_files)} Parquet files\n")

    success_count = 0
    failure_count = 0

    # Convert each file
    for parquet_file in sorted(parquet_files):
        if convert_parquet_to_csv(parquet_file):
            success_count += 1
        else:
            failure_count += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Conversion complete:")
    print(f"  ✓ Success: {success_count}")
    print(f"  ✗ Failure: {failure_count}")
    print(f"{'='*60}")

    return 0 if failure_count == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
```

### Conversion Script: PKL to CSV

**File**: `/Users/jingqiwang/biomate/backend/scripts/convert_pkl_to_csv.py`

```python
#!/usr/bin/env python3
"""
Convert all PKL files in biomni_data_lake to CSV format for Galaxy compatibility
Handles different data structures (dict, list, DataFrame)
"""
import pickle
import pandas as pd
import glob
import os
import sys

SOURCE_DIR = "/Users/jingqiwang/Biomni/knowledge_data/biomni_data_lake"

def convert_pkl_to_csv(pkl_file: str) -> bool:
    """Convert single PKL file to CSV based on data structure"""
    try:
        print(f"Converting {os.path.basename(pkl_file)}...", end=" ")

        # Load pickle
        with open(pkl_file, 'rb') as f:
            data = pickle.load(f)

        # Convert to DataFrame based on type
        if isinstance(data, pd.DataFrame):
            df = data
        elif isinstance(data, dict):
            # Try to infer structure
            if len(data) > 0:
                first_value = next(iter(data.values()))
                if isinstance(first_value, (dict, list)):
                    df = pd.DataFrame.from_dict(data, orient='index')
                else:
                    df = pd.DataFrame(list(data.items()), columns=['key', 'value'])
            else:
                df = pd.DataFrame()
        elif isinstance(data, list):
            df = pd.DataFrame(data)
        else:
            # Try generic conversion
            df = pd.DataFrame(data)

        # Generate CSV filename
        csv_file = pkl_file.replace('.pkl', '.csv')

        # Write CSV
        df.to_csv(csv_file, index=True)

        print(f"✓ ({len(df)} rows)")

        return True
    except Exception as e:
        print(f"✗ ERROR: {e}")
        return False

def main():
    # Find all PKL files
    pkl_files = glob.glob(f"{SOURCE_DIR}/*.pkl")
    print(f"Found {len(pkl_files)} PKL files\n")

    success_count = 0
    failure_count = 0

    # Convert each file
    for pkl_file in sorted(pkl_files):
        if convert_pkl_to_csv(pkl_file):
            success_count += 1
        else:
            failure_count += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Conversion complete:")
    print(f"  ✓ Success: {success_count}")
    print(f"  ✗ Failure: {failure_count}")
    print(f"{'='*60}")

    return 0 if failure_count == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
```

---

## Summary

### Current State

**Galaxy-Ready Datasets (35 files, 42%)**:
- 21 CSV files
- 2 TSV files
- 11 TXT files (pathways + gene ontology)
- 1 OBO file

**Tool-Specific Compatible (10 files, 12%)**:
- 10 SQLite databases (metabolomics tools)

**Requires Conversion (48 files, 57%)**:
- 41 Parquet files → CSV
- 7 PKL files → CSV

### After Conversion

**Galaxy-Ready Datasets (83 files, 99%)**:
- All Parquet → CSV (41 new CSV files)
- All PKL → CSV (7 new CSV files)
- Existing CSV/TSV/TXT (34 files)
- OBO (1 file)

**Tool-Specific Compatible (10 files)**:
- 10 SQLite databases (keep as-is for metabolomics)

### Next Steps

1. **User Decision**: Approve conversion strategy?
2. **Phase 1 Execution**: Run Parquet → CSV conversion (1 day)
3. **Phase 2 Execution**: Run PKL → CSV conversion (4 hours)
4. **Phase 3 Execution**: Update dataset index with compatibility flags (2 hours)

---

**Document Version**: 1.0
**Author**: Claude (AI Assistant)
**Status**: Assessment Complete - Awaiting Approval for Conversion
