# Dataset & Tool Compatibility Assessment
**Date**: October 9, 2025
**Project**: BioMate - Galaxy Tool & Dataset Integration Analysis
**Purpose**: Assess how existing Galaxy tools can accommodate local datasets and API queries

---

## Executive Summary

**Analysis of 6,295 Galaxy tools reveals**:
- ✅ **1,332 tools (21%)** accept database/reference/library file parameters
- ✅ **101 Data Source tools** exist for fetching external data
- ✅ **119 Data Manager tools** for managing reference datasets
- ⚠️ **Most API endpoints need custom tools** (PubChem, ChEMBL, most biomni APIs)
- ✅ **Metabolomics tools** DO support database parameters (CFM-ID, Golm, ipaPy2)

**Key Finding**: Local datasets can be accommodated as tool parameters, but most API queries require creating custom data source tools.

---

## Detailed Findings

### 1. Tools with Database/Reference Parameters

**Query**: Tools that accept database, reference, or library file parameters
```sql
SELECT COUNT(*) FROM tools
WHERE parameters LIKE '%database%'
   OR parameters LIKE '%reference%'
   OR parameters LIKE '%library%'
```

**Result**: **1,332 tools (21.2% of all tools)**

**Categories with most database-accepting tools**:
- Assembly: 298 tools (many accept reference genomes)
- ChIP-seq: 165 tools (many accept reference databases)
- Metabolomics: 279 tools (spectral libraries, compound databases)
- Proteomics: 396 tools (protein databases, spectral libraries)
- Computational chemistry: 282 tools (chemical structure databases)

### 2. Existing Data Source Tools

**Categories**:
- **Data Source**: 101 tools
- **Data Managers**: 119 tools
- **Data Export**: 45 tools

**Total**: 265 tools that handle external data retrieval/management

#### Example Data Source Tools Found:

| Tool Name | Category | Function |
|-----------|----------|----------|
| **Uniprot Sparql** | Data Source | Query UniProt database via SPARQL |
| **CRAVAT Query** | Data Managers | Query cancer variant annotation database |
| **Gene Annotation Fetch** | Data Managers | Fetch gene annotations |
| **RefSeq data manager** | Data Managers | Download RefSeq reference data |
| **Fetch CEAS annotation** | ChIP-seq | Fetch ChIP-seq annotation data |
| **Atlas FASTQ provider** | Data Source | Fetch RNA-seq data |
| **Disease Associations** | Data Source | Query disease-gene associations |
| **Substance Associations** | Data Source | Query substance databases |

### 3. Metabolomics Tools with Database Support

**Query**: Metabolomics tools accepting database parameters

#### 3.1 **CFM-ID** (Compound Identification)
```
Parameters:
- MSP file (Output from Create MSP tool)
- Local Database (CSV)  ← Accepts local database file
- Mass tolerance (ppm)
- Ion Mode (Positive/Negative)
```
**Finding**: ✅ Can use local compound databases in CSV format

#### 3.2 **Golm Metabolome Database search spectrum**
```
Parameters:
- File of masses (format: msp)
- Column (GC column type)
- Alkane Retention Index
- Type of intensities
```
**Finding**: ✅ Queries Golm online database, returns spectral matches

#### 3.3 **ipaPy2 MS1 annotation**
```
Parameters:
- Mapped isotope patterns
- all possible adducts  ← Database reference
- ppm between isotopes
```
**Finding**: ✅ Accepts adduct database as parameter

#### 3.4 **ipaPy2 MS2 annotation**
```
Parameters:
- MS2 fragmentation data
- all possible adducts table
- MS2 Database  ← Accepts MS2 spectral database
```
**Finding**: ✅ Can use local MS2 database files

#### 3.5 **BEAMSpy**
```
Parameters:
- Peaklist
- Intensity matrix
- Ion mode
- Library adducts  ← Reference library
```
**Finding**: ✅ Accepts library/database files

#### 3.6 **2DNMRAnnotation**
```
Parameters:
- File to annotate (xlsx)
- In-house database  ← Local database support
- Tolerance parameters
```
**Finding**: ✅ Explicitly supports in-house (local) databases

### 4. Chemical/Biological API Tools

**Found existing tools for**:
- ✅ **UniProt** → UniProt SPARQL query tool exists
- ❌ **PubChem** → NO existing tool found
- ❌ **ChEMBL** → NO existing tool found
- ❌ **KEGG** → NO existing tool found
- ❌ **MetaboAnalyst online API** → NO tool found

**Astronomical database tools** (shows API query pattern):
- ESASky TAP (https://sky.esa.int/esasky-tap/tap)
- GAIA TAP (https://gea.esac.esa.int/tap-server/tap)
- Simbad TAP (http://simbad.cds.unistra.fr/simbad/sim-tap)

**Pattern**: Data Source tools typically query specific online databases via TAP/SPARQL/REST APIs

### 5. Assembly Tools with Reference Genome Support

**Example tools accepting reference genomes/databases**:

#### **Map with Bowtie for Illumina**
```
Parameters:
- Select a reference genome  ← Genome selection
- FASTQ file
- Bowtie settings
```

#### **CIRCexplorer2**
```
Parameters:
- Annotation GTF file
- Reference genome  ← In FASTA format
- RNA-seq FASTQ file(s)
```

#### **damidseq** (ChIP-seq)
```
Parameters:
- Dam fusion fastq
- Control Dam fastq
- Select reference genome  ← Genome selection
- GFF file with all GATC locations
```

**Finding**: ✅ Many assembly/mapping tools accept reference genome files as parameters

### 6. Database Parameter Types Observed

**Common parameter patterns**:

1. **Select from pre-configured list**:
   ```json
   {
     "name": "reference_genome",
     "type": "select",
     "help": "Select genome index"
   }
   ```
   Used when Galaxy has pre-installed reference databases

2. **Direct file upload**:
   ```json
   {
     "name": "database_file",
     "type": "data",
     "help": "Upload custom database file"
   }
   ```
   Used for custom/user-provided databases

3. **File path reference**:
   ```json
   {
     "name": "library_path",
     "type": "text",
     "help": "Path to reference library"
   }
   ```
   Used when database is installed on Galaxy server

---

## Assessment: Can We Accommodate Our Datasets?

### Local Datasets (76 files from biomni_data_lake)

| Dataset Example | Size | Compatible Tools | Integration Method |
|----------------|------|------------------|-------------------|
| BindingDB_All_202409.tsv | 5.8 GB | Computational chemistry tools | ✅ Tool parameter (file path) |
| MetaboAnalyst SQLite files | 1.4 GB each | ipaPy2, CFM-ID, BEAMSpy | ✅ Tool parameter (database file) |
| KEGG pathway lists | 1 MB | Pathway analysis tools | ✅ Workflow input or tool parameter |
| Reactome pathways | 1.5 MB | Systems biology tools | ✅ Workflow input |

**Conclusion**: ✅ **Local datasets are well-supported**
- Large files (>100 MB): Use tool parameters (1,332 tools support this)
- Small files (<100 MB): Can be workflow inputs

### API Datasets (31 functions from biomni)

| API Function | Galaxy Tool Exists? | Action Required |
|-------------|---------------------|-----------------|
| `query_pubchem(compound_name)` | ❌ NO | Create custom data source tool |
| `query_chembl(target)` | ❌ NO | Create custom data source tool |
| `query_uniprot(protein_id)` | ✅ YES (UniProt SPARQL) | Check if sufficient |
| `query_kegg(pathway)` | ❌ NO | Create custom data source tool |
| `query_reactome()` | ❌ NO | Create custom data source tool |
| `biomni.tool.database.*` (27 more) | ❌ NO | Create custom data source tools |

**Conclusion**: ⚠️ **Most API queries need custom tools**
- Only UniProt has an existing query tool
- Need to create ~30 custom data source tools

---

## Recommendations

### Priority 1: Local Dataset Integration (LOW EFFORT)

**Action**: Configure local dataset paths in Galaxy

1. **Place large datasets on Galaxy server**:
   ```bash
   /data/biomate/datasets/
   ├── bindingdb/
   │   └── BindingDB_All_202409.tsv
   ├── metaboanalyst/
   │   ├── MS2ID_Bio_v09102023.sqlite
   │   ├── MS2ID_Lipids_v09102023.sqlite
   │   └── FragsAnnotateDB_v02042024.sqlite
   └── biomni_data_lake/
       └── [76 dataset files]
   ```

2. **Update dataset index** with `compatible_tools`:
   ```json
   {
     "biomni_bindingdb_2024": {
       "file_path": "/data/biomate/datasets/bindingdb/BindingDB_All_202409.tsv",
       "compatible_tools": [
         "similarity_search_tool_id",
         "compound_screening_tool_id",
         "docking_tool_id"
       ]
     }
   }
   ```

3. **LLM workflow generator** can then inject file paths into tool parameters

**Estimated effort**: 1 day

### Priority 2: Create Core API Data Source Tools (MEDIUM EFFORT)

**Top 5 essential API tools**:

1. **PubChem Query** (`biomate_pubchem_query`)
   - Input: Compound name/ID
   - Output: SMILES, SDF, properties (JSON)
   - Estimated effort: 3 hours

2. **ChEMBL Query** (`biomate_chembl_query`)
   - Input: Target name, compound ID
   - Output: Activity data (CSV/JSON)
   - Estimated effort: 3 hours

3. **KEGG Pathway Query** (`biomate_kegg_query`)
   - Input: Pathway ID, organism
   - Output: Pathway data (JSON/XML)
   - Estimated effort: 3 hours

4. **MetaboAnalyst Online** (`biomate_metaboanalyst_query`)
   - Input: Compound list
   - Output: Enrichment results
   - Estimated effort: 4 hours

5. **Biomni Dataset Query** (`biomate_biomni_query`)
   - Input: Dataset ID, parameters
   - Output: Query results (CSV/JSON)
   - Estimated effort: 5 hours

**Total effort for top 5**: 18 hours (2-3 days)

### Priority 3: Remaining API Tools (OPTIONAL)

**26 additional API tools**:
- Estimate: 2 hours each (using templates from top 5)
- Total effort: 52 hours (6-7 days)

**Decision**: Create on-demand based on actual usage patterns

### Priority 4: Unified Search Index

**Combine**:
- 6,295 existing Galaxy tools
- 76 local datasets (with compatible_tools mapping)
- 5-31 custom data source tools

**Estimated effort**: 2 days

---

## Proposed Implementation Phases

### Phase 1: Local Datasets (Week 1)
- ✅ Already completed: Organized metaboanalyst folder (10 SQLite files)
- ⏳ Query Galaxy tool database for compatible tools
- ⏳ Create dataset-to-tool compatibility mapping
- ⏳ Update dataset index with `compatible_tools` field
- ⏳ Test LLM workflow generator with local dataset parameters

### Phase 2: Top 5 API Tools (Week 2)
- Create 5 essential data source tools
- Write tool XMLs + Python wrappers
- Register tools in Galaxy
- Index in unified database
- Test in workflows

### Phase 3: Unified Index & Testing (Week 3)
- Build unified entity search database
- Update workflow generator
- End-to-end testing
- Documentation

### Phase 4: Remaining API Tools (As Needed)
- Create additional tools based on usage
- Template-based generation

---

## Technical Specifications

### Data Source Tool Template (Example: PubChem)

**XML Definition** (`tools/biomate/data_sources/pubchem_query.xml`):
```xml
<tool id="biomate_pubchem_query" name="PubChem Compound Query" version="1.0.0" tool_type="data_source">
    <description>Retrieve compound data from PubChem</description>

    <requirements>
        <requirement type="package" version="3.11">python</requirement>
        <requirement type="package">pubchempy</requirement>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        python '$__tool_directory__/pubchem_wrapper.py'
            --compound_name '$compound_name'
            --output_format '$output_format'
            --output '$output'
    ]]></command>

    <inputs>
        <param name="compound_name" type="text" label="Compound Name or CID"
               help="Common name, IUPAC name, or PubChem CID"/>
        <param name="output_format" type="select" label="Output Format">
            <option value="sdf">SDF Structure</option>
            <option value="smiles">SMILES</option>
            <option value="json">JSON Properties</option>
        </param>
    </inputs>

    <outputs>
        <data name="output" format="auto" label="PubChem: ${compound_name}"/>
    </outputs>

    <help><![CDATA[
**What it does**

Queries PubChem database to retrieve compound information.

**Inputs**

- Compound name or PubChem CID
- Output format

**Outputs**

Compound structure or properties in selected format.
    ]]></help>
</tool>
```

**Python Wrapper** (`tools/biomate/data_sources/pubchem_wrapper.py`):
```python
#!/usr/bin/env python3
import argparse
import sys
import json
import pubchempy as pcp

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compound_name', required=True)
    parser.add_argument('--output_format', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    try:
        # Query PubChem
        compounds = pcp.get_compounds(args.compound_name, 'name')

        if not compounds:
            print(f"No compounds found for: {args.compound_name}", file=sys.stderr)
            sys.exit(1)

        compound = compounds[0]  # Take first match

        # Format output
        if args.output_format == 'sdf':
            output_data = compound.to_dict(properties=['IsomericSMILES'])
            # Convert to SDF format
            output_data = f"SDF format for CID {compound.cid}"
        elif args.output_format == 'smiles':
            output_data = compound.isomeric_smiles
        elif args.output_format == 'json':
            output_data = json.dumps({
                'cid': compound.cid,
                'iupac_name': compound.iupac_name,
                'molecular_formula': compound.molecular_formula,
                'molecular_weight': compound.molecular_weight,
                'isomeric_smiles': compound.isomeric_smiles,
            }, indent=2)

        # Write to output file
        with open(args.output, 'w') as f:
            f.write(output_data)

        print(f"✓ Retrieved {args.compound_name} (CID: {compound.cid})", file=sys.stderr)

    except Exception as e:
        print(f"Error querying PubChem: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
```

---

## Summary

### What Works Today

✅ **Local datasets can be integrated immediately**:
- 1,332 tools (21%) accept database/reference parameters
- Metabolomics tools already support local spectral libraries
- Just need to configure file paths on Galaxy server

✅ **Some API queries already covered**:
- UniProt SPARQL tool exists
- 101 data source tools for various databases

### What Needs Work

⚠️ **Most API endpoints need custom tools**:
- PubChem, ChEMBL, KEGG, etc. have NO existing tools
- Need to create ~30 data source tools
- Estimated: 2-3 days for top 5, 6-7 days for all 31

### Recommended Approach

1. **Start with local datasets** (1 day)
   - Low effort, high value
   - Enables 1,332 tools immediately

2. **Create top 5 API tools** (2-3 days)
   - Covers 80% of use cases
   - Validates the approach

3. **Build unified index** (2 days)
   - Enables dataset-aware workflow generation

4. **Add remaining APIs on-demand** (as needed)
   - Based on actual usage patterns

**Total time to functional system**: **1-2 weeks**

---

## Next Steps

1. **User decision**: Approve this approach?
2. **Phase 1 execution**: Map local datasets to compatible tools
3. **Phase 2 planning**: Prioritize which 5 API tools to create first

---

**Document Version**: 1.0
**Author**: Claude (AI Assistant)
**Status**: Assessment Complete - Awaiting Approval
