# Dataset & Workflow Integration Proposal
**Date**: October 9, 2025
**Project**: BioMate - Galaxy Bioinformatics Platform
**Purpose**: Unified architecture for integrating datasets (local files + API queries) into AI-generated workflows
**Status**: Proposal - Awaiting Review

---

## Executive Summary

This proposal outlines an architecture to integrate **115 datasets** (76 local files, 31 API queries, 8 MetaboAnalyst databases) into the Galaxy workflow generation system. The key challenge is that **Galaxy workflows consist exclusively of tool execution steps**—datasets must either be (1) workflow inputs, (2) tool outputs, or (3) retrieved via specialized "data source tools."

**Key Decision**: Datasets and tools require **different handling** in Galaxy:
- **Local dataset files** → Direct references as workflow inputs or tool parameters
- **API-based dataset queries** → Custom Galaxy "data source tools" (one tool per API endpoint)

**Proposed Strategy**: Three-tier integration
1. **Local files**: Index in unified database, reference directly in workflows
2. **API queries**: Create Galaxy data source tool wrappers
3. **LLM orchestrator**: Decides when to use data source tools vs. direct file references

---

## Table of Contents

1. [Background & Problem Statement](#background--problem-statement)
2. [Galaxy Tool Architecture Analysis](#galaxy-tool-architecture-analysis)
3. [Proposed Architecture](#proposed-architecture)
4. [Implementation Plan](#implementation-plan)
5. [Example Workflows](#example-workflows)
6. [Technical Specifications](#technical-specifications)
7. [Next Steps](#next-steps)

---

## Background & Problem Statement

### Current State

**Tools**: 6,295 Galaxy tools indexed in SQLite FTS5 database
**Datasets**: 115 datasets cataloged in JSON, but NOT integrated into workflow system
**Workflow Generator**: Can search tools, but has NO awareness of available datasets

### The Core Problem

**Galaxy workflows require tools at every step**. You cannot have a workflow step that says "query PubChem API" or "load BindingDB file"—these must be represented as Galaxy tools.

From `GALAXY_COMPREHENSIVE_TOOL_INDEX_REBUILD_2025-01-09.md`, we see:
- Tools have strict XML format with defined inputs/outputs
- Tools are indexed with parameters extracted from documentation
- Workflow steps reference tool IDs: `toolshed.g2.bx.psu.edu/repos/{owner}/{repo}/{tool}/{version}`

**Question**: Can we treat API queries as tools? Or as dataset references?

**Answer**: It depends on the dataset access pattern.

---

## Galaxy Tool Architecture Analysis

### How Galaxy Handles Data

Based on the tool index structure, Galaxy has **three mechanisms** for data:

#### 1. **Workflow Inputs** (Dataset Collections)
```json
{
  "step_type": "data_input",
  "label": "Input dataset",
  "outputs": [{"name": "output", "type": "data"}]
}
```
**Use case**: User-uploaded files or pre-existing datasets in Galaxy history
**Limitation**: Must exist BEFORE workflow starts

#### 2. **Data Source Tools** (Special category in Galaxy)
```xml
<!-- Example: PubChem data source tool -->
<tool id="pubchem_query" tool_type="data_source">
  <inputs>
    <param name="compound_name" type="text" label="Compound Name"/>
  </inputs>
  <outputs>
    <data name="output" format="sdf"/>
  </outputs>
  <command>python fetch_pubchem.py --compound "$compound_name" --output "$output"</command>
</tool>
```
**Use case**: Fetch data from external APIs during workflow execution
**Key feature**: NO input datasets required, only parameters

#### 3. **Tool Parameters** (Direct file/database references)
```json
{
  "tool_state": {
    "reference_database": "/path/to/bindingdb.tsv",
    "input_file": {"src": "hda", "id": 123}
  }
}
```
**Use case**: Tools that need reference databases (e.g., BLAST database, spectral libraries)
**Limitation**: Path must be accessible on Galaxy server

### Existing Data Tools in Galaxy

Checking the 6,295 indexed tools for data retrieval patterns:

**Categories with data source tools**:
- **"Get Data"** category (if exists) - tools that fetch from external sources
- **"Convert Formats"** (287 tools) - may include data importers
- **"Text Manipulation"** - some tools read from URLs

**Example tools that might handle external data**:
- NCBI data fetchers
- Ensembl genome downloaders
- Public database importers

**Conclusion**: Galaxy DOES have data source tools, but we need to check if:
1. Existing tools cover our 31 API endpoints (unlikely)
2. We need to create custom data source tools (most likely)

Let me check if there are existing query tools in the database...

### Critical Insight

**From the tool index structure** (`parameters` field in database):
```json
{
  "parameters": [
    {
      "name": "reference_db",
      "label": "Reference Database",
      "type": "select",  // ← This shows databases as parameters
      "help": "Select reference database for search"
    }
  ]
}
```

Some Galaxy tools DO accept database files as **parameters** (not inputs). This means:
- **Large local datasets** (BindingDB, MetaboAnalyst SQLite files) can be tool parameters
- **No separate tool needed** if we place files on Galaxy server
- **LLM just needs to know** which tools accept which databases

---

## Proposed Architecture

### Three-Tier Dataset Integration

#### **Tier 1: Small Local Files (<100 MB)** → Workflow Inputs
- **Examples**: Sample metadata CSV, small reference lists
- **Method**: Upload as workflow input datasets
- **Galaxy representation**: `data_input` step
- **Workflow integration**: Direct file reference

```json
{
  "0": {
    "type": "data_input",
    "label": "Sample Metadata",
    "outputs": [{"name": "output", "type": "tabular"}]
  }
}
```

#### **Tier 2: Large Local Files (>100 MB)** → Tool Parameters
- **Examples**: BindingDB (5.8 GB), MetaboAnalyst SQLite (1.4 GB each)
- **Method**: Place files on Galaxy server, reference in tool parameters
- **Galaxy representation**: Tools that accept database parameters
- **Workflow integration**: Parameter value in `tool_state`

```json
{
  "1": {
    "tool_id": "similarity_search",
    "tool_state": {
      "reference_database": "/data/bindingdb/BindingDB_All_202409.tsv",
      "query_smiles": {"__class__": "ConnectedValue"}  // From previous step
    }
  }
}
```

**Action required**: Check which existing Galaxy tools accept database parameters, or create custom tools.

#### **Tier 3: API Queries** → Custom Data Source Tools
- **Examples**: PubChem query, ChEMBL API, biomni.tool.database.query_*
- **Method**: Create Galaxy data source tools (one per API function)
- **Galaxy representation**: Custom tool XML + Python wrapper
- **Workflow integration**: Tool execution step with parameters

```json
{
  "2": {
    "tool_id": "biomate_pubchem_query",
    "tool_state": {
      "compound_name": "aspirin",
      "output_format": "sdf"
    },
    "outputs": [{"name": "compound_data", "type": "sdf"}]
  }
}
```

**Action required**: Create 31 custom data source tool XMLs + wrappers.

### Unified Search Index Architecture

**Combine tools + datasets in single SQLite database**:

```sql
CREATE TABLE entities (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,  -- 'galaxy_tool', 'local_dataset', 'api_dataset'
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,

    -- For galaxy_tool
    tool_id TEXT,
    parameters TEXT,  -- JSON
    help_text TEXT,   -- JSON

    -- For local_dataset
    file_path TEXT,
    file_format TEXT,
    size_bytes INTEGER,
    access_method TEXT,  -- 'direct_reference', 'tool_parameter'
    compatible_tools TEXT,  -- JSON array of tool IDs that accept this dataset

    -- For api_dataset
    api_name TEXT,
    api_function TEXT,
    query_parameters TEXT,  -- JSON
    data_source_tool_id TEXT,  -- Link to corresponding Galaxy data source tool

    -- Common
    use_cases TEXT,
    outputs TEXT,  -- JSON
    tags TEXT
);

-- FTS5 search across all entities
CREATE VIRTUAL TABLE entities_fts USING fts5(
    name,
    description,
    category,
    use_cases,
    tags
);
```

**Example records**:

```json
// Galaxy tool
{
  "id": "tool_similarity_search",
  "entity_type": "galaxy_tool",
  "name": "Molecular Similarity Search",
  "tool_id": "toolshed.g2.bx.psu.edu/repos/.../similarity_search",
  "parameters": [
    {"name": "query", "type": "data"},
    {"name": "database", "type": "select", "options": ["bindingdb", "chembl"]}
  ]
}

// Local dataset
{
  "id": "dataset_bindingdb_2024",
  "entity_type": "local_dataset",
  "name": "BindingDB All Compounds 2024",
  "file_path": "/data/biomni/bindingdb/BindingDB_All_202409.tsv",
  "file_format": "tsv",
  "size_bytes": 6200000000,
  "access_method": "tool_parameter",
  "compatible_tools": ["tool_similarity_search", "tool_docking"],
  "use_cases": ["drug discovery", "target prediction"]
}

// API dataset
{
  "id": "api_pubchem_query",
  "entity_type": "api_dataset",
  "name": "PubChem Compound Query",
  "api_name": "pubchem",
  "api_function": "get_compound_by_name",
  "query_parameters": [
    {"name": "compound_name", "type": "text", "required": true}
  ],
  "data_source_tool_id": "biomate_pubchem_query",  // Custom tool we'll create
  "outputs": [{"name": "smiles", "type": "text"}, {"name": "structure", "type": "sdf"}]
}
```

### LLM Orchestration Logic

**Enhanced workflow generation prompt**:

```python
def generate_workflow(user_intent):
    # Step 1: Search unified index
    tools = search_entities(user_intent, entity_type='galaxy_tool')
    local_datasets = search_entities(user_intent, entity_type='local_dataset')
    api_datasets = search_entities(user_intent, entity_type='api_dataset')

    # Step 2: LLM plans workflow with ALL available entities
    prompt = f"""
Generate a Galaxy workflow for: {user_intent}

Available tools ({len(tools)}):
{json.dumps(tools, indent=2)}

Available local datasets ({len(local_datasets)}):
{json.dumps(local_datasets, indent=2)}

Available API datasets ({len(api_datasets)}):
{json.dumps(api_datasets, indent=2)}

Rules:
1. ALL workflow steps must be Galaxy tools (tool_id required)
2. For local datasets: Use as tool parameter if compatible_tools includes the tool
3. For API datasets: Use the data_source_tool_id as a workflow step
4. Small files can be workflow inputs (type: data_input)

Return JSON workflow following Galaxy .ga format.
"""

    workflow_plan = llm.generate(prompt)
    return build_galaxy_workflow(workflow_plan)
```

**Decision tree**:

```
User intent: "Find kinase inhibitors similar to imatinib in BindingDB"

LLM analysis:
1. Need imatinib structure → API query (PubChem)
   → Insert step: biomate_pubchem_query tool

2. Need similarity search → Galaxy tool exists
   → Check if tool accepts BindingDB parameter
   → YES: tool_similarity_search has "database" parameter
   → Insert step: tool_similarity_search with database="/data/bindingdb/..."

3. Need to filter kinases → Galaxy tool (text filtering)
   → Insert step: filter_by_target_type

Final workflow:
Step 0: biomate_pubchem_query (compound_name="imatinib")
Step 1: tool_similarity_search (query=step0.output, database="bindingdb")
Step 2: filter_kinases (input=step1.output)
```

---

## Implementation Plan

### Phase 1: Assess Existing Galaxy Tools (2-3 hours)

**Goal**: Identify which of the 6,295 tools can handle our datasets

**Tasks**:
1. Query database for tools with database/reference file parameters
2. Check "Get Data", "Data Source", "Text Manipulation" categories
3. Identify tools that accept large file parameters
4. Map local datasets to compatible tools

**SQL queries**:
```sql
-- Find tools with database parameters
SELECT id, name, parameters
FROM tools
WHERE parameters LIKE '%database%'
   OR parameters LIKE '%reference%'
   OR parameters LIKE '%library%';

-- Find data source tools
SELECT id, name, category
FROM tools
WHERE category LIKE '%data%'
   OR description LIKE '%fetch%'
   OR description LIKE '%download%'
   OR description LIKE '%query%';
```

**Output**: Document mapping:
- Which local datasets can be tool parameters
- Which tools need to be created for API queries
- Which datasets need workflow input steps

### Phase 2: Create Custom Data Source Tools (1-2 days)

**Goal**: Wrap 31 API functions as Galaxy data source tools

**For each API endpoint** (e.g., `biomni.tool.database.query_pubchem`):

1. **Create tool XML** (`tools/biomate/data_sources/pubchem_query.xml`):
```xml
<tool id="biomate_pubchem_query" name="Query PubChem" version="1.0.0" tool_type="data_source">
    <description>Retrieve compound data from PubChem</description>

    <requirements>
        <requirement type="package" version="3.11">python</requirement>
        <requirement type="package" version="1.0">pubchempy</requirement>
    </requirements>

    <command detect_errors="exit_code"><![CDATA[
        python '$__tool_directory__/pubchem_wrapper.py'
            --compound_name '$compound_name'
            --output_format '$output_format'
            --output '$output'
    ]]></command>

    <inputs>
        <param name="compound_name" type="text" label="Compound Name"
               help="Common name or IUPAC name"/>
        <param name="output_format" type="select" label="Output Format">
            <option value="sdf">SDF</option>
            <option value="smiles">SMILES</option>
            <option value="json">JSON</option>
        </param>
    </inputs>

    <outputs>
        <data name="output" format="auto" label="PubChem: ${compound_name}"/>
    </outputs>

    <help><![CDATA[
**What it does**

Queries the PubChem database to retrieve compound information.

**Inputs**

- Compound name (text): Common or IUPAC name
- Output format: SDF structure, SMILES string, or JSON metadata

**Outputs**

Compound data in selected format.

**Example**

Input: "aspirin"
Output: Structure file or properties JSON
    ]]></help>

    <citations>
        <citation type="doi">10.1093/nar/gkaa971</citation>
    </citations>
</tool>
```

2. **Create Python wrapper** (`tools/biomate/data_sources/pubchem_wrapper.py`):
```python
#!/usr/bin/env python3
import argparse
import sys
import json

# Import from biomni codebase (moved to biomate)
from biomate.datasets.api_queries import query_pubchem

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compound_name', required=True)
    parser.add_argument('--output_format', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    try:
        # Call the API function
        result = query_pubchem(compound_name=args.compound_name)

        # Format output
        if args.output_format == 'sdf':
            output_data = result['structure_sdf']
        elif args.output_format == 'smiles':
            output_data = result['smiles']
        elif args.output_format == 'json':
            output_data = json.dumps(result, indent=2)

        # Write to Galaxy output
        with open(args.output, 'w') as f:
            f.write(output_data)

        print(f"✓ Retrieved data for {args.compound_name}", file=sys.stderr)

    except Exception as e:
        print(f"Error querying PubChem: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
```

3. **Register tool** in `config/tool_conf.xml`:
```xml
<toolbox>
  <section id="biomate_data_sources" name="BioMate Data Sources">
    <tool file="biomate/data_sources/pubchem_query.xml"/>
    <tool file="biomate/data_sources/chembl_query.xml"/>
    <!-- ... 29 more tools -->
  </section>
</toolbox>
```

4. **Index tool** in database:
```python
# Run after creating all tools
python scripts/index_custom_tools.py \
    --tool_dir tools/biomate/data_sources \
    --output galaxy_ai_tools.db
```

**Estimated effort**:
- 1-2 hours per API tool (XML + wrapper + testing)
- 31 API tools × 1.5 hours = **47 hours** (6 days)
- **Optimization**: Template-based generation can reduce to 2-3 days

### Phase 3: Move biomni API Code to biomate (1 day)

**Goal**: Make API functions accessible to Galaxy tools

**Structure**:
```
biomate/backend/
├── lib/
│   └── biomate/
│       └── datasets/
│           ├── __init__.py
│           ├── api_queries.py          # From biomni.tool.database
│           ├── local_datasets.py       # Local file accessors
│           └── metaboanalyst.py        # MetaboAnalyst SQLite queries
```

**Migration**:
1. Copy `biomni.tool.database` module to `biomate.datasets.api_queries`
2. Update imports in tool wrappers
3. Add to Galaxy's Python path

### Phase 4: Build Unified Entity Index (1 day)

**Script**: `backend/scripts/build_unified_entity_index.py`

**Process**:
1. Load 6,295 Galaxy tools from existing database
2. Load 115 datasets from `dataset_index_comprehensive.json`
3. Add 31 custom data source tools
4. Create `entities` table
5. Populate FTS5 search index

**Output**: `backend/galaxy_unified_index.db` (~40 MB)

### Phase 5: Update Workflow Generator (2 days)

**Changes to** `lib/galaxy/ai/galaxy_workflow_generator.py`:

1. **Replace tool-only search** with entity search:
```python
# OLD
tools = self.tool_rag.search(user_intent, limit=50)

# NEW
entities = self.entity_search.search(user_intent, limit=100)
tools = [e for e in entities if e['entity_type'] == 'galaxy_tool']
datasets_local = [e for e in entities if e['entity_type'] == 'local_dataset']
datasets_api = [e for e in entities if e['entity_type'] == 'api_dataset']
```

2. **Enhance LLM prompt** with dataset context (see "LLM Orchestration Logic" above)

3. **Add parameter injection** for local datasets:
```python
def inject_dataset_parameters(step, local_datasets):
    """Check if step's tool accepts any local datasets as parameters"""
    tool_id = step['tool_id']
    tool_info = get_tool_info(tool_id)

    for param in tool_info['parameters']:
        if param['type'] == 'select' and 'database' in param['name']:
            # Find matching dataset
            for dataset in local_datasets:
                if tool_id in dataset.get('compatible_tools', []):
                    step['tool_state'][param['name']] = dataset['file_path']
                    break
```

### Phase 6: Testing (1 day)

**Test cases**:

1. **API query workflow**:
   - User intent: "Get structure of compound ABC123"
   - Expected: One-step workflow with `biomate_pubchem_query` tool

2. **Local dataset parameter**:
   - User intent: "Find similar compounds to aspirin in BindingDB"
   - Expected: Step 1: pubchem_query, Step 2: similarity_search with database parameter

3. **Multi-source workflow**:
   - User intent: "Identify metabolites in LC-MS data using MS2ID library"
   - Expected: Step 1: xcms_peak_detection, Step 2: ms2id_annotation with database="/data/metaboanalyst/MS2ID_Complete.sqlite"

**Validation**:
- Verify generated .ga workflow is valid Galaxy format
- Check tool IDs resolve correctly
- Confirm parameters are properly formatted
- Test workflow execution in Galaxy (if available)

---

## Example Workflows

### Example 1: API Query + Tool

**User intent**: "Find kinase inhibitors similar to imatinib"

**Generated workflow**:
```json
{
  "a_galaxy_workflow": "true",
  "name": "Find Kinase Inhibitors Similar to Imatinib",
  "steps": {
    "0": {
      "id": 0,
      "type": "tool",
      "tool_id": "biomate_pubchem_query",
      "name": "Query PubChem: Imatinib",
      "tool_state": {
        "compound_name": "imatinib",
        "output_format": "smiles"
      },
      "outputs": [{"name": "output", "type": "text"}],
      "annotation": "Retrieve imatinib structure from PubChem"
    },
    "1": {
      "id": 1,
      "type": "tool",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/.../molecular_similarity",
      "name": "Similarity Search",
      "tool_state": {
        "query": {"__class__": "ConnectedValue", "output_name": "output", "id": 0},
        "reference_database": "/data/biomni/BindingDB_All_202409.tsv",
        "similarity_threshold": 0.7,
        "fingerprint_type": "morgan"
      },
      "outputs": [{"name": "hits", "type": "tabular"}],
      "annotation": "Search BindingDB for similar compounds"
    },
    "2": {
      "id": 2,
      "type": "tool",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/.../filter_by_column",
      "name": "Filter Kinases",
      "tool_state": {
        "input": {"__class__": "ConnectedValue", "output_name": "hits", "id": 1},
        "column": "target_type",
        "pattern": "kinase"
      },
      "outputs": [{"name": "filtered", "type": "tabular"}],
      "annotation": "Filter results for kinase targets only"
    }
  }
}
```

### Example 2: Local Dataset + Tool Chain

**User intent**: "Identify metabolites in LC-MS data using MS2ID spectral library"

**Generated workflow**:
```json
{
  "steps": {
    "0": {
      "type": "data_input",
      "label": "LC-MS Data (mzML)",
      "outputs": [{"name": "output", "type": "mzml"}]
    },
    "1": {
      "tool_id": "toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_xcmsset/...",
      "name": "XCMS Peak Detection",
      "tool_state": {
        "input": {"__class__": "ConnectedValue", "id": 0},
        "ppm": 25,
        "peakwidth": "20,50"
      }
    },
    "2": {
      "tool_id": "biomate_ms2id_annotation",  // Custom tool we create
      "name": "MS2ID Metabolite Annotation",
      "tool_state": {
        "peak_list": {"__class__": "ConnectedValue", "id": 1},
        "spectral_library": "/data/biomni/metaboanalyst/MS2ID_Complete_v09102023.sqlite",
        "mass_tolerance": 0.01,
        "score_threshold": 0.8
      }
    }
  }
}
```

---

## Technical Specifications

### File Locations

```
biomate/backend/
├── galaxy_unified_index.db              # NEW: Combined tools + datasets
│
├── lib/
│   ├── galaxy/ai/
│   │   ├── galaxy_workflow_generator.py # UPDATED: Dataset-aware
│   │   ├── entity_search.py             # NEW: Unified search
│   │   └── dataset_accessor.py          # NEW: Dataset access abstraction
│   │
│   └── biomate/
│       └── datasets/
│           ├── api_queries.py           # MOVED FROM biomni
│           ├── local_datasets.py        # NEW
│           └── metaboanalyst.py         # NEW
│
├── tools/
│   └── biomate/
│       └── data_sources/
│           ├── pubchem_query.xml        # NEW: 31 API tools
│           ├── pubchem_wrapper.py
│           ├── chembl_query.xml
│           └── ...
│
├── scripts/
│   ├── build_unified_entity_index.py    # NEW
│   ├── index_custom_tools.py            # NEW
│   └── migrate_biomni_apis.py           # NEW
│
└── config/
    └── tool_conf.xml                    # UPDATED: Add biomate tools
```

### Database Schema

**Unified entity table**:
```sql
CREATE TABLE entities (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL CHECK(entity_type IN ('galaxy_tool', 'local_dataset', 'api_dataset')),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    use_cases TEXT,

    -- Galaxy tool fields
    tool_id TEXT,
    version TEXT,
    parameters TEXT,  -- JSON
    help_text TEXT,   -- JSON
    inputs TEXT,      -- JSON
    outputs TEXT,     -- JSON

    -- Local dataset fields
    file_path TEXT,
    file_format TEXT,
    size_bytes INTEGER,
    access_method TEXT,  -- 'workflow_input', 'tool_parameter', 'direct_reference'
    compatible_tools TEXT,  -- JSON array

    -- API dataset fields
    api_name TEXT,
    api_function TEXT,
    query_parameters TEXT,  -- JSON
    data_source_tool_id TEXT,  -- FK to corresponding tool

    -- Metadata
    tags TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_entity_type ON entities(entity_type);
CREATE INDEX idx_category ON entities(category);
CREATE INDEX idx_data_source_tool ON entities(data_source_tool_id);

CREATE VIRTUAL TABLE entities_fts USING fts5(
    name,
    description,
    category,
    use_cases,
    tags,
    content=entities
);
```

### API Function → Galaxy Tool Mapping

| biomni API Function | Galaxy Tool ID | Tool Type |
|---------------------|----------------|-----------|
| `query_pubchem(compound_name)` | `biomate_pubchem_query` | data_source |
| `query_chembl(target_name)` | `biomate_chembl_query` | data_source |
| `query_uniprot(protein_id)` | `biomate_uniprot_query` | data_source |
| ... (28 more) | ... | data_source |

**Total custom tools needed**: 31 data source tools

---

## Next Steps

### Immediate Actions (Next 1-2 days)

1. **Kill the background download process** (it's still running)
2. **Review this proposal** - Approve architecture or suggest changes
3. **Assess existing Galaxy tools** - Run Phase 1 queries to identify tool-dataset compatibility

### Decision Points

**Question 1**: Should we create all 31 API tools, or prioritize a subset?
- **Option A**: Start with 5 most critical APIs (PubChem, ChEMBL, UniProt, KEGG, MetaboAnalyst)
- **Option B**: Create all 31 upfront using templates
- **Recommendation**: Option A - validate approach with 5 tools first

**Question 2**: How should we handle large local datasets?
- **Option A**: Copy all to Galaxy server (requires ~20 GB disk space)
- **Option B**: Mount from Biomni location (requires shared filesystem)
- **Recommendation**: Option B initially, Option A for production

**Question 3**: Should the unified index replace the existing tool index?
- **Option A**: New database, keep existing `galaxy_ai_tools.db`
- **Option B**: Migrate to unified index, deprecate old database
- **Recommendation**: Option A for safety, Option B after validation

### Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Assess tools | 3 hours | None |
| Phase 2: Create 5 API tools (pilot) | 1 day | Phase 1 |
| Phase 3: Migrate biomni APIs | 1 day | None (parallel) |
| Phase 4: Build unified index | 1 day | Phase 3 |
| Phase 5: Update workflow generator | 2 days | Phase 4 |
| Phase 6: Testing | 1 day | Phase 5 |
| **Total (Pilot)** | **5-6 days** | |
| Phase 2b: Create remaining 26 tools | 3 days | Phase 6 validation |
| **Total (Complete)** | **8-9 days** | |

---

## Summary

**Key Architectural Decisions**:
1. ✅ Local datasets → Tool parameters or workflow inputs (no custom tools needed)
2. ✅ API queries → Custom Galaxy data source tools (31 tools required)
3. ✅ Unified search index → Single database for tools + datasets
4. ✅ LLM orchestrator → Decides when to use data source tools vs parameters

**Advantages of This Approach**:
- Leverages existing Galaxy tool framework
- No changes to Galaxy core needed
- Datasets become searchable alongside tools
- Workflows remain standard Galaxy .ga format
- Scalable: Easy to add more datasets/APIs

**Open Questions**:
1. Which of the 6,295 existing tools accept database file parameters?
2. Should we prioritize 5 API tools or implement all 31?
3. Where should large dataset files be stored (Galaxy server vs mounted)?

**Next Step**: Await your feedback, then proceed with Phase 1 assessment.

---

**Document Version**: 1.0
**Author**: Claude (AI Assistant)
**Status**: Proposal - Awaiting Review
