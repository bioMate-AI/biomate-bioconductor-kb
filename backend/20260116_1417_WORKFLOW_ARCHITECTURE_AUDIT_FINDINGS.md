# BioMate Workflow Architecture Audit - Detailed Findings

**Date**: 2026-01-16 14:17
**Scope**: Deep code review based on user feedback

---

## Summary of Issues Found

| Issue | Severity | Status |
|-------|----------|--------|
| `workflow_search_rag.py` - duplicate/confusing code | Medium | Should remove |
| Input/output validation - STUB not implemented | High | Needs implementation |
| Biomni tools duplicate Galaxy `biomate_ds_*` tools | High | Needs consolidation |
| 951 indexed workflows exist but underutilized | Medium | Use properly |

---

## 1. Workflow Template Resources - CLARIFICATION

### 1.1 The CORRECT Resources

**A. 951 Indexed Workflows in Database**
- Location: Stored in `galaxy_ai_tools.db` → `workflows` table
- Also as JSON: `lib/galaxy/ai/data/workflows/workflow_*.json` (951 files)
- Access via: `unified_workflow_search.py` - Uses FTS5 for search

**B. `workflow_templates.py` - 3 Curated Templates**
- Contains 3 manually curated templates with REAL Galaxy tool IDs
- Example tools: `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0`
- Templates: RNA-seq, Variant Calling, Genome Assembly
- **This is CORRECT and should be KEPT**

**C. `rag_workflow_loader.py` - RAG Engine**
- Loads 951 workflow JSONs for similarity search
- Class: `RAGWorkflowRecommender`, `SimpleRAGEngine`
- **This is CORRECT**

### 1.2 The CONFUSING Resource (Should Remove)

**`workflow_search_rag.py` - DUPLICATE/CONFLICTING**

This file contains 3 DIFFERENT hardcoded templates that CONFLICT with `workflow_templates.py`:

```python
# workflow_search_rag.py lines 48-121
templates = {
    "rna_seq_differential_expression": {...},  # Uses simplified tool IDs: "FastQC", "HISAT2"
    "variant_calling": {...},                   # Different from workflow_templates.py
    "lc_ms_metabolomics": {...}                 # Not in workflow_templates.py
}
```

**Problems:**
1. Uses simplified tool IDs (`FastQC`) instead of real Galaxy IDs
2. Duplicates functionality of `workflow_templates.py`
3. Has different template content (LC-MS vs Genome Assembly)
4. Causes confusion about which template source to use

**Recommendation**: Remove `workflow_search_rag.py` or merge its logic into `unified_workflow_search.py`

---

## 2. Input/Output Validation - STUB NOT IMPLEMENTED

### 2.1 Location

File: `lib/galaxy/ai/workflow_optimizer.py`
Method: `_check_data_type_compatibility()` (lines 488-506)

### 2.2 Current Code (STUB)

```python
def _check_data_type_compatibility(self, steps: List[WorkflowStep]) -> List[str]:
    """Check data type compatibility between connected steps."""

    errors = []

    # This would need access to tool registry to check actual input/output types
    # For now, perform basic checks

    step_map = {step.step_id: step for step in steps}

    for step in steps:
        for input_name, connection in step.input_connections.items():
            source_step_id = connection.get('id')
            if source_step_id and source_step_id in step_map:
                # In a real implementation, would check tool registry
                # for actual input/output type compatibility
                pass  # <-- STUB - DOES NOTHING!

    return errors
```

### 2.3 Database Has the Data

The `tools` table has `inputs` and `outputs` columns:

```sql
SELECT inputs, outputs FROM tools WHERE inputs IS NOT NULL LIMIT 1;
-- Result: inputs = ["fa", "fasta"], outputs = ["fa", "fasta"]
```

### 2.4 What Needs Implementation

```python
def _check_data_type_compatibility(self, steps: List[WorkflowStep]) -> List[str]:
    """Check data type compatibility between connected steps."""
    errors = []
    step_map = {step.step_id: step for step in steps}

    for step in steps:
        for input_name, connection in step.input_connections.items():
            source_step_id = connection.get('id')
            if source_step_id and source_step_id in step_map:
                source_step = step_map[source_step_id]

                # Get source tool's output types from database
                source_outputs = self._get_tool_outputs(source_step.tool_id)

                # Get current tool's input types from database
                target_inputs = self._get_tool_inputs(step.tool_id)

                # Check compatibility
                if not self._types_compatible(source_outputs, target_inputs):
                    errors.append(
                        f"Type mismatch: {source_step.tool_id} outputs {source_outputs} "
                        f"but {step.tool_id} expects {target_inputs}"
                    )

    return errors
```

---

## 3. Biomni Tools vs Galaxy Data Source Tools - DUPLICATION

### 3.1 Biomni Database Tools (40 tools)

Location: `biomni/database/*`

```
biomni/database/query_alphafold
biomni/database/query_cbioportal
biomni/database/query_clinicaltrials
biomni/database/query_clinvar
biomni/database/query_dbsnp
biomni/database/query_emdb
biomni/database/query_ensembl
biomni/database/query_geo
biomni/database/query_gnomad
... (40 total)
```

### 3.2 Galaxy `biomate_ds_*` Tools (Already Exist!)

These are ALREADY in Galaxy as data source tools:

```
biomate_ds_api_alphafold    → ALPHAFOLD [Data Source]
biomate_ds_api_cbioportal   → CBIOPORTAL [Data Source]
biomate_ds_api_clinicaltrials → CLINICALTRIALS [Data Source]
biomate_ds_api_clinvar      → CLINVAR [Data Source]
biomate_ds_api_dbsnp        → DBSNP [Data Source]
biomate_ds_api_emdb         → EMDB [Data Source]
biomate_ds_api_ensembl      → ENSEMBL [Data Source]
biomate_ds_api_geo          → GEO [Data Source]
biomate_ds_api_gnomad       → GNOMAD [Data Source]
```

### 3.3 Duplication Analysis

| Database | Biomni Tool | Galaxy Tool | Duplicate? |
|----------|-------------|-------------|------------|
| AlphaFold | `biomni/database/query_alphafold` | `biomate_ds_api_alphafold` | YES |
| cBioPortal | `biomni/database/query_cbioportal` | `biomate_ds_api_cbioportal` | YES |
| ClinicalTrials | `biomni/database/query_clinicaltrials` | `biomate_ds_api_clinicaltrials` | YES |
| ClinVar | `biomni/database/query_clinvar` | `biomate_ds_api_clinvar` | YES |
| dbSNP | `biomni/database/query_dbsnp` | `biomate_ds_api_dbsnp` | YES |
| EMDB | `biomni/database/query_emdb` | `biomate_ds_api_emdb` | YES |
| Ensembl | `biomni/database/query_ensembl` | `biomate_ds_api_ensembl` | YES |
| GEO | `biomni/database/query_geo` | `biomate_ds_api_geo` | YES |
| gnomAD | `biomni/database/query_gnomad` | `biomate_ds_api_gnomad` | YES |
| UniProt | `biomni/database/query_uniprot` | ? | Check |
| PDB | `biomni/database/query_pdb` | ? | Check |

### 3.4 Recommendation

**Option A: Use Galaxy `biomate_ds_*` Tools**
- Already integrated with Galaxy
- No Docker needed (runs as Galaxy tools)
- Consistent with Galaxy ecosystem

**Option B: Keep Biomni but Remove Duplicates**
- Remove Biomni tools that duplicate `biomate_ds_*`
- Keep unique Biomni tools (IUCN, Paleobiology, WoRMS, etc.)

**Option C: Consolidate into Unified Data Query Layer**
- Create single interface for all database queries
- Backend decides which tool to use
- Hide complexity from workflow generator

---

## 4. Files to Review/Clean Up

### 4.1 Should REMOVE or MERGE

| File | Reason |
|------|--------|
| `workflow_search_rag.py` | Duplicates `workflow_templates.py` with conflicting content |

### 4.2 Should IMPLEMENT

| File | Method | Status |
|------|--------|--------|
| `workflow_optimizer.py` | `_check_data_type_compatibility()` | STUB - needs implementation |

### 4.3 Should KEEP

| File | Purpose |
|------|---------|
| `workflow_templates.py` | 3 curated templates with real Galaxy tool IDs |
| `unified_workflow_search.py` | Database-backed workflow search with FTS |
| `rag_workflow_loader.py` | 951 workflow JSON loader for RAG |

---

## 5. Architecture Clarity

### 5.1 Correct Workflow Search Flow

```
User Query: "RNA-seq differential expression"
     │
     ▼
┌─────────────────────────────────┐
│  unified_workflow_search.py     │  ← PRIMARY: Database FTS
│  - Searches workflows table     │
│  - 951+ indexed workflows       │
│  - Returns WorkflowMatch        │
└─────────────────────────────────┘
     │
     │ if no match or need more detail
     ▼
┌─────────────────────────────────┐
│  workflow_templates.py          │  ← FALLBACK: Curated templates
│  - 3 verified templates         │
│  - Full Galaxy tool IDs         │
│  - Tested workflows             │
└─────────────────────────────────┘
```

### 5.2 What to Remove

```
┌─────────────────────────────────┐
│  workflow_search_rag.py         │  ← REMOVE: Conflicting duplicates
│  - 3 different templates        │
│  - Simplified tool IDs          │
│  - Causes confusion             │
└─────────────────────────────────┘
```

---

## 6. Next Steps

1. **Remove `workflow_search_rag.py`** and update any imports
2. **Implement `_check_data_type_compatibility()`** using database inputs/outputs
3. **Consolidate Biomni/Galaxy data source tools** - choose one or create unified interface
4. **Audit all code importing `workflow_search_rag`** and redirect to `unified_workflow_search`

---

## 7. Import Dependencies for `workflow_search_rag.py`

Files that import `WorkflowSearchRAG`:

```
lib/galaxy/ai/ai_assistant.py:24:  from .workflow_search_rag import WorkflowSearchRAG
lib/galaxy/ai/ai_assistant.py:69:  self.workflow_search = WorkflowSearchRAG(galaxy_app)
```

**Migration path:**
```python
# BEFORE (ai_assistant.py)
from .workflow_search_rag import WorkflowSearchRAG
self.workflow_search = WorkflowSearchRAG(galaxy_app)

# AFTER - Use unified_workflow_search
from .unified_workflow_search import UnifiedWorkflowSearch
self.workflow_search = UnifiedWorkflowSearch()
```

Note: The `UnifiedWorkflowSearch` class has different methods but provides the same functionality with more workflows (951 vs 3).

---

## Appendix: Database Schema for I/O Validation

```sql
-- Tools table has these columns for I/O types:
inputs          -- JSON array: ["fa", "fasta"]
outputs         -- JSON array: ["fa", "fasta"]
galaxy_inputs   -- Galaxy-specific input definitions
galaxy_outputs  -- Galaxy-specific output definitions
```

Implementation can use these columns to validate workflow connections.
