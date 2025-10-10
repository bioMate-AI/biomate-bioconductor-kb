# Dataset Integration Status & Reference Guide
**Date**: 2025-10-10
**Purpose**: Clarify current dataset integration status and point to latest documents

---

## 📄 LATEST/CURRENT Documents

### 1. **reference_data_complete.json** (606 KB) - CANONICAL DATA SOURCE
**Last Updated**: Oct 9, 19:50

**Contains**:
- `tools`: 40 Galaxy data source tools (PubChem, ChEMBL, KEGG, HMDB, UniProt, Reactome)
- `datasets`: 115 local datasets with full metadata
- `metaboanalyst_databases`: 10 SQLite spectral databases with schemas

**Structure per dataset**:
```json
{
  "name": "BindingDB_All_202409.tsv",
  "access_method": "local_file",
  "path": "/path/to/file",
  "size": "5.8GB",
  "format": "tsv",
  "description": "...",
  "category": "drug_discovery",
  "use_cases": ["drug target prediction", "..."],
  "index_columns": ["ligand", "target", "..."],
  "schema": {...},
  "query_examples": [...]
}
```

**Missing Field**: `compatible_tools` - Which Galaxy tools can use this dataset

---

### 2. **GALAXY_DATA_TOOLS_AND_DATASETS_REFERENCE_2025-10-09.md** (33 KB)
**Last Updated**: Oct 9, 19:52

**Human-readable reference document with**:
- Detailed descriptions of 40 Galaxy data source tools
- Tool parameters and usage examples
- API query patterns for external databases
- Summary statistics

**Use this for**: Understanding what Galaxy data tools exist and how to use them

---

### 3. **DATASET_FORMAT_COMPATIBILITY_ASSESSMENT_2025-10-09.md** (18 KB)
**Last Updated**: Oct 9, 18:10

**Analysis of file format compatibility**:
- ✅ 35 files (42%) Galaxy-ready (CSV, TSV, TXT, OBO)
- ✅ 10 SQLite databases (12%) compatible with specific tools
- ⚠️ 41 Parquet files (49%) need conversion to CSV
- ⚠️ 7 PKL files (8%) need conversion to CSV

**Includes**: Conversion scripts for Parquet → CSV and PKL → CSV

**Use this for**: Understanding which datasets need format conversion

---

### 4. **DETAILED_DATASET_DESCRIPTIONS_2025-10-09.md** (20 KB)
**Last Updated**: Oct 9, 22:30

**Comprehensive descriptions for**:
- 10 MetaboAnalyst SQLite databases (detailed use cases, data sources)
- 6 major local datasets (BindingDB, DepMap, DDInter, EveBio, CRISPR_sgRNA)

**Use this for**: Understanding what each dataset contains and when to use it

---

### 5. **data_tools_detailed.json** (184 KB)
**Last Updated**: Oct 9, 19:36

**Detailed metadata for 40 Galaxy data source tools**:
```json
{
  "tool_id": "toolshed.g2.bx.psu.edu/repos/.../PubChem_Download",
  "name": "PubChem Download",
  "category": "Computational chemistry",
  "parameters": [...],
  "help_text": {...}
}
```

**Use this for**: Programmatic access to data tool specifications

---

## 🗑️ OUTDATED Documents (Marked with OLD_ prefix)

These documents contain **outdated architectural proposals** that have been superseded:

### OLD_DATASET_WORKFLOW_INTEGRATION_PROPOSAL_2025-10-09.md
- ❌ Proposed 3-tier integration (small files, large files, API queries)
- ✅ **Current approach**: 2 categories only (Data Management Tools, Data Source Tools)
- Status: **Superseded by simpler architecture**

### OLD_DATASET_TOOL_COMPATIBILITY_ASSESSMENT_2025-10-09.md
- ❌ Generic assessment that 1,332 tools accept database parameters
- ⚠️ Did NOT provide specific dataset-to-tool mapping
- Status: **Analysis incomplete, needs actual mapping work**

### OLD_DATASET_AND_WORKFLOW_ARCHITECTURE_CLARIFICATION.md
- Historical discussion of architecture gaps
- Status: **Reference only, decisions have been made**

---

## 📊 Current State Summary

### What We Have ✅

1. **115 local datasets** cataloged with metadata
2. **40 Galaxy data source tools** documented
3. **10 MetaboAnalyst databases** with detailed schemas
4. **Format compatibility analysis** complete
5. **Conversion scripts** ready for Parquet/PKL files

### What's Missing ❌

1. **`compatible_tools` mapping** - Which tools work with which datasets
2. **Parquet/PKL conversion execution** - 48 files need format conversion
3. **Dataset upload to Galaxy** - Files not yet in Galaxy instance
4. **Unified search index** - Tools + datasets in single searchable database

---

## 🎯 Integration Architecture (CURRENT)

### Dataset Categories

**1. Local Datasets → Data Management Tools**
- Upload/manage reference databases in Galaxy
- Examples: BindingDB, DepMap, MetaboAnalyst SQLite files
- Access via: File upload or server path reference

**2. API Queries → Data Source Tools**
- Query external APIs during workflow execution
- Examples: 40 existing Galaxy tools (PubChem, ChEMBL, KEGG, etc.)
- Access via: Tool execution in workflow step

### How Datasets Integrate into Workflows

```
User Request
    ↓
AI Workflow Generator
    ↓
    ├─→ Local Dataset: Reference as tool parameter
    │   Example: tool_state = {"database": "/path/to/BindingDB.tsv"}
    │
    └─→ API Dataset: Insert data source tool step
        Example: Step 0 = PubChem_Download tool
```

---

## 📋 Next Steps

### Immediate Tasks

1. **Create dataset-to-tool compatibility mapping**
   - Analyze which of 1,332+ tools can use which datasets
   - Add `compatible_tools` field to reference_data_complete.json

2. **Execute format conversions**
   - Convert 41 Parquet files → CSV
   - Convert 7 PKL files → CSV
   - Update reference_data_complete.json with new file paths

3. **Build unified search index**
   - Combine tools + datasets in single SQLite FTS5 database
   - Enable AI workflow generator to discover both

### Future Work

4. **Upload datasets to Galaxy library**
   - Make datasets accessible via Galaxy UI
   - Configure data libraries for reference data

5. **Test dataset-aware workflow generation**
   - Verify AI can select appropriate datasets
   - Test workflows with local dataset parameters

---

## 🔍 How to Use This Guide

**If you want to...**

- **See all available datasets** → Read `reference_data_complete.json`
- **Understand dataset contents** → Read `DETAILED_DATASET_DESCRIPTIONS_2025-10-09.md`
- **Check format compatibility** → Read `DATASET_FORMAT_COMPATIBILITY_ASSESSMENT_2025-10-09.md`
- **Find data source tools** → Read `GALAXY_DATA_TOOLS_AND_DATASETS_REFERENCE_2025-10-09.md`
- **Get tool specifications** → Read `data_tools_detailed.json`
- **Understand architecture** → Read this document

**Ignore files with `OLD_` prefix** - they contain outdated proposals

---

## 📚 Document Hierarchy

```
CURRENT DOCUMENTS:
├── reference_data_complete.json           ← CANONICAL data source
├── data_tools_detailed.json               ← Tool specifications
├── GALAXY_DATA_TOOLS_AND_DATASETS_REFERENCE_2025-10-09.md
├── DATASET_FORMAT_COMPATIBILITY_ASSESSMENT_2025-10-09.md
└── DETAILED_DATASET_DESCRIPTIONS_2025-10-09.md

OUTDATED DOCUMENTS (for reference only):
├── OLD_DATASET_WORKFLOW_INTEGRATION_PROPOSAL_2025-10-09.md
├── OLD_DATASET_TOOL_COMPATIBILITY_ASSESSMENT_2025-10-09.md
└── OLD_DATASET_AND_WORKFLOW_ARCHITECTURE_CLARIFICATION.md
```

---

**Last Updated**: 2025-10-10
**Maintained By**: Claude (AI Assistant)
**Status**: Active - reflects current architecture