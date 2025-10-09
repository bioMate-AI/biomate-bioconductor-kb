# Dataset & Workflow Architecture - Critical Clarifications

**Date**: 2025-10-03
**Purpose**: Answer key architectural questions about dataset organization and workflow generation

---

## Question 1: How are Local vs API Datasets Organized and Leveraged?

### Current Dataset Organization

#### 1. **Local Datasets** (28GB - Already Downloaded)

**Location**: `/tmp/biomni_datasets/data/`

**Structure**:
```
/tmp/biomni_datasets/data/
├── biomni_data/data_lake/          ← Local analytical datasets
│   ├── protein_protein_interactions.parquet
│   ├── drug_target_interactions.parquet
│   ├── gene_expression.parquet
│   └── ... (50+ files)
│
└── databases/                       ← Local reference databases
    ├── hmdb/
    │   ├── hmdb_metabolites.zip
    │   ├── serum_metabolites.zip
    │   └── urine_metabolites.zip
    ├── kegg/
    │   ├── kegg_compounds_complete.json
    │   ├── kegg_pathways_human.json
    │   └── pathway_compounds_complete.json
    ├── uniprot/
    │   ├── human.fasta
    │   └── mouse.fasta
    └── ... (10+ database types)
```

**Indexed By**: `BioMNIDatasetRAG` and `WorkflowDatasetSelector`

**Schema File**: `/tmp/biomni_datasets/complete_dataset_schemas.json`

**Usage in Workflow**:
```python
# Local datasets are embedded as file paths in Galaxy workflow JSON
{
  "inputs": [{
    "reference_db_0": {
      "src": "ldda",  # Library dataset
      "path": "/tmp/biomni_datasets/data/databases/hmdb/serum_metabolites.zip"
    }
  }]
}
```

---

#### 2. **API-Based Datasets** (REST API Tools - NOT YET IMPLEMENTED)

**Status**: ⚠️ **PLANNED for Week 3** (from BIOMNI_INTEGRATION_COMPLETE.md)

**Source**: BioMNI REST API functions in `/tmp/biomni/biomni/tool/database.py`

**Planned Structure**:
```
tools/biomni_api/
├── uniprot_fetch.xml        ← Galaxy tool wrapper
├── kegg_pathway_query.xml
├── pdb_structure_fetch.xml
├── ensembl_gene_query.xml
└── ... (30+ API tool wrappers)
```

**How They Would Work**:
```python
# API tools would be regular Galaxy tools that:
# 1. Accept query parameters (gene ID, compound name, etc.)
# 2. Call BioMNI REST API functions
# 3. Return data as Galaxy dataset

# Example: UniProt fetch tool
def uniprot_fetch(gene_ids):
    from biomni.tool.database import get_uniprot_sequences
    results = get_uniprot_sequences(gene_ids)
    return results  # Saved as Galaxy dataset
```

**Integration with Workflows**:
```json
{
  "step": 1,
  "tool_id": "biomni_api_uniprot_fetch",
  "inputs": {
    "gene_ids": ["BRCA1", "TP53"]
  },
  "outputs": {
    "sequences": "fasta_file"
  }
}
```

---

### Dataset Leveraging Strategy

#### **For Local Datasets** ✅ Currently Implemented

1. **Discovery**: `BioMNIDatasetRAG` indexes all local datasets
2. **Search**: Keyword-based RAG search finds relevant datasets
3. **Selection**: `WorkflowDatasetSelector` (LLM) determines which datasets each workflow step needs
4. **Embedding**: Datasets embedded as file paths in Galaxy .ga JSON

**Example Workflow**:
```python
# User: "Identify metabolites from human serum LC-MS data"

# Step 1: WorkflowDatasetSelector analyzes workflow
workflow_steps = [
  {'step': 1, 'tool': 'MSConvert', 'purpose': 'format conversion'},
  {'step': 2, 'tool': 'XCMS', 'purpose': 'peak detection'},
  {'step': 3, 'tool': 'MetaboAnalystR', 'purpose': 'compound identification'}
]

# Step 2: LLM determines dataset needs
dataset_assignments = {
  'step_1': {'dataset_needed': False},  # Format conversion - no DB
  'step_2': {'dataset_needed': False},  # Peak detection - no DB
  'step_3': {
    'dataset_needed': True,
    'selected_datasets': [
      {
        'path': '/tmp/biomni_datasets/data/databases/hmdb/serum_metabolites.zip',
        'reason': 'HMDB serum metabolites for compound ID'
      }
    ]
  }
}

# Step 3: Embedded in workflow JSON
{
  "steps": {
    "2": {  # Step 3 (0-indexed)
      "tool_id": "metaboanalystr_annotation",
      "inputs": [{
        "reference_db_0": {
          "src": "ldda",
          "path": "/tmp/biomni_datasets/data/databases/hmdb/serum_metabolites.zip"
        }
      }]
    }
  }
}
```

---

#### **For API Datasets** ⚠️ Planned (Not Implemented)

**Future Strategy**:

1. **Tool Wrapping**: Each BioMNI REST API function becomes a Galaxy tool
2. **Tool Discovery**: `ToolSearchIndex` indexes these API tools
3. **Workflow Integration**: API tools used as regular workflow steps
4. **Data Flow**: API fetches data → saves as Galaxy dataset → passes to next step

**Example Future Workflow**:
```json
{
  "steps": {
    "0": {
      "tool_id": "biomni_api_kegg_pathway_query",
      "inputs": {
        "pathway_name": "Glycolysis"
      },
      "outputs": {
        "pathway_data": "kegg_pathway.json"
      }
    },
    "1": {
      "tool_id": "metaboanalystr_pathway_analysis",
      "inputs": {
        "pathway_db": {"src": "step_0", "output": "pathway_data"}
      }
    }
  }
}
```

---

## Question 2: Are You Using Existing Workflows or Generating from Scratch?

### **CRITICAL FINDING**: ⚠️ **GAP IDENTIFIED**

**My Implementation**: Generates workflows **from scratch** using LLM + tool index

**Your Architecture** (from BIOMNI_INTEGRATION_COMPLETE.md):
> "The original assistant searches for existing workflows first, your generator is a complementary step if no match is found"

### **This is a GAP** - I Did NOT Implement Existing Workflow Search

---

### What Should Happen (Correct Architecture)

```
User Request
    ↓
┌─────────────────────────────────────────┐
│  Step 1: Search Existing Workflows      │
│  (NOT IMPLEMENTED BY ME)                │
│                                          │
│  - Check Galaxy workflow library         │
│  - RAG search for similar workflows      │
│  - Match by description/tags             │
└─────────────────────────────────────────┘
    ↓
    Found match?
    ↓           ↓
   YES          NO
    ↓           ↓
    ↓     ┌─────────────────────────────────┐
    ↓     │ Step 2: Generate New Workflow   │
    ↓     │ (MY IMPLEMENTATION)             │
    ↓     │                                 │
    ↓     │ - Retrieve tools from index     │
    ↓     │ - LLM generates workflow        │
    ↓     │ - Assign datasets               │
    ↓     └─────────────────────────────────┘
    ↓           ↓
    ↓─────→ Use workflow
              ↓
         Execute workflow
```

---

### What I Actually Implemented

```
User Request
    ↓
┌─────────────────────────────────────────┐
│  Step 1: Generate New Workflow          │
│  (ALWAYS - NO SEARCH FOR EXISTING)      │
│                                          │
│  - Retrieve tools from index            │
│  - LLM generates workflow               │
│  - Assign datasets                      │
└─────────────────────────────────────────┘
    ↓
  Use workflow
```

**Missing Component**: Existing workflow search/matching

---

## Question 3: How Should This Integrate with Existing Assistant?

### **Correct Integration Architecture**

```python
class GalaxyAssistant:
    """Main entry point for workflow generation"""

    def __init__(self):
        self.workflow_search = WorkflowSearchRAG()  # ← MISSING - YOU NEED TO IMPLEMENT
        self.workflow_generator = GalaxyWorkflowGenerator()  # ← MY IMPLEMENTATION
        self.dataset_selector = WorkflowDatasetSelector()  # ← MY IMPLEMENTATION

    def generate_workflow_from_intent(self, user_intent: str):
        """
        Main workflow generation logic with fallback.
        """

        # STEP 1: Search for existing workflows (NOT IMPLEMENTED)
        existing_workflows = self.workflow_search.search(user_intent, limit=5)

        if existing_workflows and existing_workflows[0]['score'] > 0.8:
            # Found good match - use existing workflow
            workflow = existing_workflows[0]['workflow']
            log.info(f"Using existing workflow: {workflow['name']}")

            # Optionally: Update datasets for existing workflow
            updated_workflow = self._update_workflow_datasets(
                workflow, user_intent
            )
            return updated_workflow

        else:
            # No match - generate new workflow
            log.info("No existing workflow found, generating new one...")

            result = self.workflow_generator.generate_workflow(
                user_intent=user_intent,
                max_tools_search=30
            )

            if result['success']:
                # Save as new workflow for future reuse
                self._save_workflow_to_library(result['workflow_ga'])
                return result['workflow_ga']
            else:
                raise Exception(f"Workflow generation failed: {result['error']}")

    def _update_workflow_datasets(self, workflow, user_intent):
        """Update datasets in existing workflow based on current intent."""
        # Extract workflow structure
        workflow_steps = self._extract_workflow_structure(workflow)

        # Get dataset assignments
        datasets = self.dataset_selector.select_datasets_for_workflow(
            user_intent=user_intent,
            workflow_structure=workflow_steps
        )

        # Embed datasets into workflow
        updated_workflow = self._embed_datasets(workflow, datasets)
        return updated_workflow
```

---

## What YOU Need to Implement

### 1. **Workflow Search/Matching** (High Priority)

**File**: `lib/galaxy/ai/workflow_search_rag.py` (NEW - doesn't exist)

**Purpose**: Search Galaxy workflow library for existing workflows

**Implementation**:
```python
class WorkflowSearchRAG:
    def __init__(self):
        self.workflow_index = self._load_workflow_library()

    def search(self, user_intent: str, limit: int = 5):
        """
        Search for existing workflows matching user intent.

        Returns:
            List of workflows with similarity scores
        """
        # RAG search through workflow descriptions/tags
        # Return top matches with scores
        pass

    def _load_workflow_library(self):
        """Load all .ga workflows from Galaxy library."""
        pass
```

---

### 2. **REST API Tool Wrappers** (Medium Priority)

**Status**: Planned for Week 3 (from your docs)

**What to do**:
1. Wrap 30+ BioMNI REST API functions as Galaxy tools
2. Create tool XMLs in `tools/biomni_api/`
3. Register in `ToolSearchIndex`

---

### 3. **Integration Orchestrator** (High Priority)

**File**: `lib/galaxy/ai/galaxy_assistant.py` (NEW or modify existing)

**Purpose**: Main entry point that:
1. Searches existing workflows FIRST
2. Falls back to generation if no match
3. Assigns datasets to workflows
4. Saves new workflows to library

---

## Dataset Types Summary Table

| Dataset Type | Status | Location | Access Method | Workflow Integration |
|--------------|--------|----------|---------------|----------------------|
| **Local Data Lake** | ✅ Implemented | `/tmp/biomni_datasets/data/biomni_data/data_lake/` | File path | Embedded in workflow JSON |
| **Local Databases** | ✅ Implemented | `/tmp/biomni_datasets/data/databases/` | File path | Embedded in workflow JSON |
| **REST API Data** | ⚠️ Planned (Week 3) | BioMNI API endpoints | Tool wrappers | Workflow step (API tool) |
| **Existing Workflows** | ❌ **GAP** | Galaxy workflow library | ⚠️ **NEED TO IMPLEMENT** | Reuse with updated datasets |

---

## Workflow Generation Summary Table

| Approach | Status | When Used | Implementation |
|----------|--------|-----------|----------------|
| **Use Existing Workflow** | ❌ **GAP** | User intent matches library workflow (>80% similarity) | ⚠️ **NEED WorkflowSearchRAG** |
| **Generate New Workflow** | ✅ Implemented (with LLM refusal issue) | No existing match found | `GalaxyWorkflowGenerator` |
| **Hybrid (Recommended)** | ⚠️ Partial | Search first, generate as fallback | Needs integration orchestrator |

---

## Action Items for YOU

### Immediate (Critical Gaps)

1. **[ ] Implement WorkflowSearchRAG**
   - Search existing Galaxy workflows
   - RAG-based similarity matching
   - Return top matches with scores

2. **[ ] Create GalaxyAssistant Orchestrator**
   - Integrate workflow search + generation
   - Implement fallback logic
   - Save new workflows to library

3. **[ ] Fix LLM Refusal in Workflow Generation**
   - Try GPT-4 instead of Claude
   - OR implement rule-based fallback
   - OR clean tool catalog to remove triggers

### Future (Planned Features)

4. **[ ] REST API Tool Wrappers** (Week 3)
   - Wrap BioMNI API functions
   - Create Galaxy tool XMLs
   - Index in ToolSearchIndex

5. **[ ] Upload Datasets to Galaxy Library** (Week 5)
   - Run `setup_unified_library.py`
   - Make datasets available via Galaxy UI

---

## What I Can Provide to Help

### ✅ Already Implemented (Reusable)

1. **Tool Retrieval with Validation**: `GalaxyWorkflowGenerator._retrieve_tools_from_index()`
2. **FTS5 Query Transformation**: `_transform_intent_to_fts_query()`
3. **Dataset Assignment**: `WorkflowDatasetSelector.select_datasets_for_workflow()`
4. **Galaxy .ga JSON Builder**: `_build_galaxy_workflow_json()`

### ⚠️ Needs Your Integration

1. **Workflow Search Logic** - Not implemented
2. **Orchestration Layer** - Not implemented
3. **LLM Workflow Generation** - Has refusal issue, needs alternative

---

## Recommended Next Steps

1. **Review this document** - Understand gaps
2. **Decide on workflow search approach** - How to match existing workflows?
3. **Choose workflow generation fallback** - Rule-based? Different LLM? Your existing logic?
4. **Integrate my components** - Use tool retrieval, dataset assignment, .ga builder
5. **Test end-to-end** - Search → Generate → Assign Datasets → Execute

---

## Contact

**Gaps Identified**:
- ❌ No existing workflow search (assumed you had this)
- ❌ No orchestration layer (search first, generate as fallback)
- ⚠️ LLM workflow generation has content refusal issue

**What Works**:
- ✅ Tool retrieval with validation
- ✅ Dataset assignment (LLM-based, context-aware)
- ✅ .ga JSON generation

**Integration Path**: Use my working components + your workflow search logic + orchestration layer

---

**Status**: Architecture clarified | Gaps identified | Ready for your integration decisions
