# BioMate Workflow Generation Architecture Review

**Date**: 2026-01-14 13:36
**Author**: Claude Code Analysis
**Scope**: Backend workflow generation code review

---

## Executive Summary

After a thorough review of the BioMate backend workflow generation code, I identified several fundamental architectural issues that affect the reliability and efficiency of workflow generation. The core problem is a **redundant LLM call pattern** where BioMate's LLM interprets user intent, but then passes natural language to tools that invoke *another* LLM internally.

---

## 1. The Core Problem: Redundant LLM Calls

### 1.1 Biomni Tool Dual-Mode Interface

The Biomni database tools have a dual-mode parameter design:

```
biomni/database/query_uniprot:
  - prompt (str, optional): Natural language query - requires internal LLM
  - endpoint (str, optional): Direct API URL - NO LLM needed
  - max_results (int, optional): Maximum results to return
```

### 1.2 Current (Problematic) Flow

```
User: "Find BRCA1 human protein"
         │
         ▼
┌─────────────────────────────┐
│   BioMate LLM               │  ◄── LLM Call #1
│   Interprets user intent    │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Parameter Generator       │
│   Generates:                │
│   prompt="Find information  │
│   about BRCA1 human protein"│
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Biomni UniProt Tool       │
│   ┌───────────────────────┐ │
│   │ Internal LLM          │ │  ◄── LLM Call #2 (REDUNDANT!)
│   │ Interprets prompt     │ │
│   └───────────────────────┘ │
│   Makes API call to UniProt │
└─────────────────────────────┘
```

### 1.3 Ideal Flow (What Should Happen)

```
User: "Find BRCA1 human protein"
         │
         ▼
┌─────────────────────────────┐
│   BioMate LLM               │  ◄── Single LLM Call
│   Interprets: gene=BRCA1    │
│              organism=9606  │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   API Query Builder         │  ◄── MISSING COMPONENT
│   Constructs:               │
│   endpoint="https://rest.   │
│   uniprot.org/uniprotkb/    │
│   search?query=gene:BRCA1   │
│   +AND+organism_id:9606"    │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Biomni UniProt Tool       │
│   Direct API call           │  ◄── No internal LLM!
│   (uses endpoint parameter) │
└─────────────────────────────┘
```

---

## 2. Biomni Tool Parameter Inconsistency

### 2.1 Parameter Design Audit

| Tool | `prompt` | `endpoint`/Direct | Design Quality |
|------|----------|-------------------|----------------|
| `biomni/database/query_uniprot` | optional | optional | Good |
| `biomni/database/query_alphafold` | N/A | uses `uniprot_id` | Good |
| `biomni/database/query_interpro` | **required** | optional | Problematic |
| `biomni/database/query_pdb` | **required** | optional (query) | Problematic |
| `biomni/database/query_kegg` | **required** | optional | Problematic |
| `biomni/database/query_stringdb` | **required** | optional | Problematic |
| `biomni/database/query_jaspar` | **required** | optional | Problematic |

### 2.2 Problem Analysis

Tools with **required** `prompt` parameter force LLM interpretation even when BioMate has already parsed the user intent. This defeats the purpose of having BioMate interpret intent at the workflow level.

### 2.3 Recommendation

All Biomni tools should follow the UniProt pattern:
- `prompt`: optional, for truly ambiguous queries
- Direct parameters (endpoint, identifiers, etc.): preferred for structured queries

---

## 3. Workflow Generation Architecture

### 3.1 Key Components

```
lib/galaxy/ai/
├── galaxy_workflow_generator.py   # Main workflow generator
├── enhanced_workflow_generator.py # Template-based + RAG hybrid
├── workflow_search_rag.py         # Template search system
├── unified_tool_search.py         # Multi-stage tool retrieval
├── llm_parameter_generator.py     # LLM-based parameter inference
├── workflow_dataset_selector.py   # Dataset assignment (stub)
└── types.py                       # Data types (Tool, Workflow, etc.)
```

### 3.2 GalaxyWorkflowGenerator Flow

**File**: `lib/galaxy/ai/galaxy_workflow_generator.py`

```python
def generate_workflow(user_intent, max_tools_search=30):
    # Step 1: Tool Search (multi-stage retrieval)
    available_tools = self._retrieve_tools_from_index(user_intent)

    # Step 2: LLM generates workflow structure
    workflow_structure = self._generate_workflow_structure(user_intent, available_tools)

    # Step 3: Dataset selection (currently stub)
    dataset_assignments = self.dataset_selector.select_datasets_for_workflow(...)

    # Step 4: Build Galaxy .ga JSON with LLM parameter generation
    galaxy_workflow = self._build_galaxy_workflow_json(workflow_structure, ...)

    return galaxy_workflow
```

### 3.3 Issues Identified

#### Issue 1: LLM Designs Entire Workflow Without Domain Knowledge

The LLM generates workflow structure based on tool descriptions alone. It doesn't have:
- Knowledge of what each tool actually outputs
- Understanding of input/output type compatibility
- Domain-specific best practices for bioinformatics workflows

**Example of generated workflow prompt:**
```python
system_prompt = """You are an expert bioinformatics workflow architect...

## WORKFLOW DESIGN PRINCIPLES:
### PHASE 1: DATA VALIDATION
### PHASE 2: CORE ANALYSIS
### PHASE 3: POST-PROCESSING
### PHASE 4: OUTPUT PREPARATION
"""
```

These generic phases don't match how biologists actually work.

#### Issue 2: No Input/Output Type Validation

The workflow generator doesn't verify that Tool A's output type is compatible with Tool B's input type. This can lead to broken workflows.

#### Issue 3: Tool Catalog Missing Parameter Semantics

The tool catalog shown to LLM includes parameters but doesn't explain *when* to use each parameter:

```python
def _build_tool_catalog(self, tools):
    # Shows: name, type, help text
    # Missing: when to use endpoint vs prompt
    # Missing: API URL format examples
```

---

## 4. Template System Analysis

### 4.1 Workflow Search RAG

**File**: `lib/galaxy/ai/workflow_search_rag.py`

Good design pattern:
```python
# Search templates FIRST, generate only as fallback
if template_matches[0]["relevance_score"] >= 15:
    strategy = "template_based"    # Use template directly
elif template_matches[0]["relevance_score"] >= 8:
    strategy = "hybrid"            # Adapt template
else:
    strategy = "rag_assisted"      # Generate from scratch
```

### 4.2 Current Templates

Only 3 templates exist:

1. **RNA-seq Differential Expression**
   - Tools: FastQC → HISAT2 → FeatureCounts → DESeq2

2. **Variant Calling Pipeline**
   - Tools: FastQC → BWA → Picard → GATK HaplotypeCaller → GATK VariantFiltration

3. **LC-MS Metabolomics**
   - Tools: MSConvert → XCMS → MetaboAnalystR (x3)

### 4.3 Template Issues

1. **Simplified tool IDs**: Templates use `FastQC`, `HISAT2` instead of actual Galaxy tool IDs like `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0`

2. **No tool version pinning**: Templates don't specify tool versions

3. **No installation validation**: No check that template tools are actually installed in Galaxy

---

## 5. Tool Search Architecture

### 5.1 UnifiedToolSearch Pipeline

**File**: `lib/galaxy/ai/unified_tool_search.py`

```
Query: "UniProt protein query"
         │
         ▼
┌─────────────────────────────┐
│ Stage 0: LLM Query Analysis │
│ - Extract entities          │
│ - Infer category            │
│ - Expand terms              │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Stage 1: Direct Entity Match│
│ SQL LIKE on extracted       │
│ entities                    │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Stage 2: Vector Similarity  │
│ Semantic embeddings search  │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Stage 3: FTS5 Full-Text     │
│ With category filter        │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Stage 4: Result Fusion      │
│ Reciprocal Rank Fusion      │
└─────────────────────────────┘
```

### 5.2 Search Quality

The search system is well-designed with:
- Multi-stage retrieval for robustness
- Biomni tool prioritization (50-point boost)
- RRF fusion for combining results

---

## 6. Missing Components

### 6.1 API Query Builder (CRITICAL)

**Purpose**: Convert parsed intent into proper API queries for each database

```python
# MISSING - Needs implementation
class APIQueryBuilder:
    """Build direct API queries from parsed intent."""

    def build_uniprot_query(self, intent: ParsedIntent) -> str:
        """
        Convert parsed intent to UniProt REST API URL.

        Example:
            intent = ParsedIntent(
                gene="BRCA1",
                organism="human",  # → organism_id:9606
                fields=["function", "sequence"]
            )
            →
            "https://rest.uniprot.org/uniprotkb/search?query=gene:BRCA1+AND+organism_id:9606&fields=cc_function,sequence"
        """
        pass

    def build_pdb_query(self, intent: ParsedIntent) -> dict:
        """Build RCSB PDB structured query JSON."""
        pass

    def build_kegg_query(self, intent: ParsedIntent) -> str:
        """Build KEGG REST API query."""
        pass
```

### 6.2 Tool Usage Pattern Registry

**Purpose**: Define when to use which parameter for each tool

```yaml
# MISSING - Needs implementation
tool_usage_patterns:
  biomni/database/query_uniprot:
    prefer_direct: true
    direct_parameter: endpoint
    use_prompt_when: "query is too complex for structured API"
    endpoint_format: "https://rest.uniprot.org/uniprotkb/{operation}?{params}"
    common_operations:
      - search: "query={search_terms}&format=json"
      - fetch: "accession/{uniprot_id}"

  biomni/database/query_pdb:
    prefer_direct: true
    direct_parameter: query
    query_format: "RCSB Search API JSON"
```

### 6.3 Input/Output Type Graph

**Purpose**: Validate tool chain compatibility

```python
# MISSING - Needs implementation
class ToolCompatibilityGraph:
    """Graph of tool input/output type compatibility."""

    tool_io_types = {
        "fastqc": {
            "inputs": ["fastq", "fastq.gz"],
            "outputs": ["html", "txt"]
        },
        "hisat2": {
            "inputs": ["fastq", "fastq.gz"],
            "outputs": ["bam", "sam"]
        },
        "featurecounts": {
            "inputs": ["bam"],
            "outputs": ["tabular"]
        }
    }

    def validate_workflow_chain(self, steps: List[str]) -> bool:
        """Check if tool chain has compatible I/O types."""
        pass
```

---

## 7. Recommendations

### 7.1 Short-Term Fixes (Implemented)

- [x] Include parameter schema in LLM prompt for workflow generation
- [x] Add guidance about preferring `endpoint` over `prompt`
- [x] Include rich metadata (parameters, help_text, examples) in tool catalog

### 7.2 Medium-Term Improvements (Needed)

1. **Implement API Query Builder Module**
   - Create builders for each major database (UniProt, PDB, KEGG, etc.)
   - Register builders with tool IDs
   - BioMate should use builder output for `endpoint` parameter

2. **Fix Biomni Tool Parameter Design**
   - Make `prompt` optional for all tools
   - Add direct query parameters as preferred alternative
   - Document when to use each parameter mode

3. **Expand Workflow Template Library**
   - Add 50+ proteomics workflow templates
   - Add 30+ genomics workflow templates
   - Add 20+ metabolomics workflow templates
   - Use actual Galaxy tool IDs with version pinning

4. **Add Input/Output Type Validation**
   - Build tool I/O type registry
   - Validate workflow chains before generation
   - Suggest compatible tools when building workflows

### 7.3 Long-Term Architecture

```
                    User Intent
                         │
                         ▼
              ┌──────────────────────┐
              │   Intent Parser      │
              │   (LLM with schema)  │
              └──────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          │                             │
          ▼                             ▼
┌─────────────────────┐     ┌─────────────────────┐
│  Template Matcher   │     │  Workflow Designer  │
│  (if score > 0.8)   │     │  (if no template)   │
└─────────────────────┘     └─────────────────────┘
          │                             │
          │                   ┌─────────┴─────────┐
          │                   │                   │
          │                   ▼                   ▼
          │         ┌─────────────────┐ ┌─────────────────┐
          │         │ Tool Graph      │ │ API Query       │
          │         │ Navigator       │ │ Builder         │
          │         └─────────────────┘ └─────────────────┘
          │                   │                   │
          └───────────────────┴───────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  Workflow Validator │
                    │  (I/O compatibility)│
                    └─────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  Galaxy .ga Export  │
                    └─────────────────────┘
```

---

## 8. Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| `lib/galaxy/ai/galaxy_workflow_generator.py` | 993 | Main workflow generator |
| `lib/galaxy/ai/enhanced_workflow_generator.py` | 552 | Template + RAG hybrid |
| `lib/galaxy/ai/workflow_search_rag.py` | 336 | Template search system |
| `lib/galaxy/ai/unified_tool_search.py` | 540 | Multi-stage tool retrieval |
| `lib/galaxy/ai/llm_parameter_generator.py` | 363 | LLM parameter inference |
| `lib/galaxy/ai/workflow_dataset_selector.py` | 41 | Dataset assignment (stub) |
| `lib/galaxy/ai/types.py` | 269 | Data types |
| `database/galaxy_ai_tools.db` | N/A | Tool metadata database |

---

## 9. Conclusion

The BioMate workflow generation system has a solid foundation with multi-stage tool search and template-based generation. However, the **redundant LLM call pattern** is a fundamental efficiency issue that needs architectural changes to resolve.

The key insight is that BioMate should **fully interpret user intent** and generate **direct API queries** rather than passing natural language to tools for re-interpretation. This requires:

1. An API Query Builder component
2. Consistent tool parameter design (prompt should be optional)
3. Tool usage patterns that specify when to use direct vs NL parameters

These changes would make BioMate more efficient, reliable, and faster by eliminating redundant LLM calls.
