# Workflow Generation Architecture Review

**Date:** 2026-01-19 15:45
**Status:** Review Complete - Improvements Identified

---

## Current Architecture Overview

```
User Intent
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  1. DOMAIN DETECTION (detect_domain)                               │
│     - Transcriptomics, Genomics, Proteomics, Epigenomics,         │
│       Metagenomics, Metabolomics, Data Query                       │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  2. TOOL RETRIEVAL (UnifiedToolSearch)                             │
│     5-stage pipeline:                                              │
│     ├─ LLM Query Analysis (entities, category, expanded terms)     │
│     ├─ Direct Entity Matching (SQL LIKE)                           │
│     ├─ Vector Similarity Search                                    │
│     ├─ FTS5 Full-Text Search                                       │
│     └─ Reciprocal Rank Fusion (RRF)                                │
│     Returns: 30 relevant tools with scores                         │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  3. WORKFLOW STRUCTURE GENERATION (LLM)                            │
│     - Uses ONLY retrieved tools                                    │
│     - Domain-specific phases (e.g., QC → Alignment → Quantification)│
│     - Outputs: workflow_name, steps, reasoning                     │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  4. DATASET SELECTION (WorkflowDatasetSelector)                    │
│     - Assigns reference datasets to workflow steps                 │
│     - Uses Galaxy library datasets                                 │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  5. GALAXY .ga JSON BUILD (_build_galaxy_workflow_json)            │
│     - Normalizes tool IDs (biomni/ → biomni_)                      │
│     - Generates parameters for data source tools (LLM)             │
│     - Builds step annotations with help text                       │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌────────────────────────────────────────────────────────────────────┐
│  6. CITATIONS & METHODS (ToolKnowledgeProvider, MethodsGenerator)  │
│     - Collects tool citations (DOI/PMID)                           │
│     - Generates methods section text                               │
└────────────────────────────────────────────────────────────────────┘
    │
    ▼
Final Output: Galaxy .ga workflow JSON + metadata
```

---

## Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `galaxy_workflow_generator.py` | Main workflow generation orchestrator | ~1000 |
| `unified_tool_search.py` | 5-stage tool retrieval pipeline | ~500 |
| `llm_parameter_generator.py` | LLM-based parameter inference | ~360 |
| `domain_workflow_patterns.py` | Domain-specific workflow phases | ~500+ |
| `workflow_dataset_selector.py` | Dataset assignment to steps | ~100 |
| `tool_knowledge_provider.py` | Tool citations and best practices | ~200 |
| `methods_generator.py` | Methods section text generation | ~150 |
| `query_analyzer.py` | LLM query analysis for search | ~200 |

---

## What's Working Well

1. **Domain Detection**: Automatic detection of 7 analysis domains
2. **Multi-stage Tool Search**: Robust retrieval combining LLM + vectors + FTS5
3. **Tool Validation**: LLM can ONLY use tools from retrieved list
4. **Biomni Integration**: Tool ID normalization (`biomni/` → `biomni_`)
5. **Progress Tracking**: Callback system for UI progress updates
6. **Citations**: Automatic collection of tool citations

---

## Identified Issues & Improvements

### Issue 1: Data Source Tool Detection is Incomplete

**Location:** `_is_data_source_tool()` at line 937

**Current:**
```python
def _is_data_source_tool(self, tool_id: str) -> bool:
    if tool_id.startswith('biomate_dm_'):
        return True
    if tool_id.startswith('biomate_datasource_api_'):
        return True
    # ... hardcoded list
```

**Problem:**
- Missing `biomate_ds_api_*` tools (the actual Galaxy data source tools)
- Hardcoded list doesn't cover all data source patterns

**Fix:**
```python
def _is_data_source_tool(self, tool_id: str) -> bool:
    # BioMate data source API tools (31 tools)
    if tool_id.startswith('biomate_ds_api_'):
        return True
    # ... rest
```

### Issue 2: Parameter Generation for Galaxy Data Source Tools

**Location:** `_build_galaxy_workflow_json()` at line 750

**Current Behavior:**
- Only generates parameters for tools matching `_is_data_source_tool()`
- But `biomate_ds_api_*` tools are not detected

**Impact:** Galaxy data source tools don't get intelligent parameter generation

### Issue 3: Tool ID Mapping Inconsistency

**Location:** `_normalize_tool_id()` at line 919

**Current:**
```python
def _normalize_tool_id(self, tool_id: str) -> str:
    if tool_id.startswith('biomni/'):
        return tool_id.replace('/', '_')
    return tool_id
```

**Issue:** Only handles Biomni tools, not other tool ID formats

### Issue 4: No Workflow Template Matching

**Current:** Every workflow is generated from scratch by LLM

**Improvement:** Add template matching for common workflows:
- RNA-seq differential expression
- Variant calling
- Single-cell analysis
- etc.

This would be faster and more reliable for standard analyses.

### Issue 5: No Input/Output Connection Validation

**Current:** Steps are generated but connections between steps aren't validated

**Impact:** Workflows may have incompatible tool chains

**Note:** `_check_data_type_compatibility()` exists in `workflow_optimizer.py` but isn't used in the generator

---

## Recommended Improvements

### Priority 1: Fix Data Source Tool Detection

```python
# Add biomate_ds_api_* to detection
if tool_id.startswith('biomate_ds_api_'):
    return True
```

### Priority 2: Integrate Workflow Templates

Add template matching before LLM generation:
```python
def generate_workflow(self, user_intent, ...):
    # Try template match first
    template_match = self._match_workflow_template(user_intent)
    if template_match and template_match.confidence > 0.8:
        return self._instantiate_template(template_match, user_intent)

    # Fall back to LLM generation
    return self._generate_with_llm(user_intent, ...)
```

### Priority 3: Add Step Connection Validation

Use existing `_check_data_type_compatibility()` from workflow_optimizer.py:
```python
# After generating workflow structure
from .workflow_optimizer import WorkflowOptimizer
optimizer = WorkflowOptimizer()
errors = optimizer._check_data_type_compatibility(workflow_steps)
if errors:
    log.warning(f"Type compatibility issues: {errors}")
```

### Priority 4: Improve Tool Catalog for LLM

Current `_build_tool_catalog()` could include:
- Input/output formats
- Typical parameter examples
- Tool category/domain

---

## Testing Recommendations

1. **Test data source tool detection** with `biomate_ds_api_*` tools
2. **Test workflow generation** for each domain type
3. **Validate generated .ga JSON** can be imported into Galaxy
4. **Test end-to-end execution** (already passing per Jan 17 test)

---

## Improvements Implemented (2026-01-19)

### 1. Fixed Data Source Tool Detection ✅
**File:** `galaxy_workflow_generator.py:953-956`

Added `biomate_ds_api_*` detection:
```python
# BioMate data source API tools (primary - 31 tools for database queries)
if tool_id.startswith('biomate_ds_api_'):
    return True
```

### 2. Workflow Template Matching ✅
**Status:** Already implemented in `EnhancedWorkflowGenerator`
- High confidence (≥0.8): Direct template
- Medium confidence (0.5-0.8): Adapted template
- Low confidence (<0.5): LLM generation

### 3. Step Connection Validation ✅
**File:** `galaxy_workflow_generator.py:987-1096`

Added `validate_workflow_compatibility()` method:
- Checks output/input format compatibility between consecutive steps
- Handles format aliases (fa↔fasta, fq↔fastq, etc.)
- Handles compressed variants (.gz, .bz2)
- Returns warnings for format mismatches

Integrated into `generate_workflow()`:
- Validates after workflow structure generation
- Reports progress to UI
- Includes `compatibility_validated` and `compatibility_warnings` in output

## Next Steps

1. [ ] Test workflow generation with biomate_ds_api_* tools
2. [ ] Test compatibility validation with known incompatible tool chains
3. [ ] Monitor validation warnings in production
