# Comprehensive Gap Analysis & Implementation Plan
**Date:** October 9, 2025
**Project:** BioMate - Integrated LLM Chat + Galaxy Bioinformatics Platform
**Status:** Analysis Complete, Implementation Pending

---

## Executive Summary

Analysis of the integrated biomate system reveals the AI workflow generation layer is complete and sophisticated, but critical dataset RAG components are missing (source files lost, only compiled .pyc remains). The system can generate workflows but cannot assign reference datasets or execute them without Galaxy core installation.

**Critical Blockers:**
1. Missing dataset RAG source files (`biomni_dataset_rag.py`, `workflow_dataset_selector.py`)
2. Missing dataset catalog/index (105+ reference datasets)
3. Missing backend API endpoints for dataset operations
4. Galaxy platform core not installed (no workflow execution capability)

---

## System Architecture Overview

### Current State

```
┌─────────────────────────────────────────────────────────────┐
│                    FRONTEND (GalaxyChat)                    │
│  ✅ Chat Interface + LLM Orchestration                      │
│  ✅ Workflow Visualization                                  │
│  ✅ File Upload + Parameter Configuration                   │
│  ✅ SSE Real-time Updates                                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ HTTP + WebSocket
                       │
┌──────────────────────▼──────────────────────────────────────┐
│              BACKEND (Node.js + Python)                     │
│  ✅ API Proxy Layer (TypeScript)                            │
│  ✅ Tool Search (2,169 tools indexed)                       │
│  ❌ Dataset Search APIs (not implemented)                   │
│  ❌ Workflow Execution APIs (not implemented)               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │
┌──────────────────────▼──────────────────────────────────────┐
│            AI WORKFLOW GENERATION LAYER                     │
│  ✅ WorkflowSearchRAG (template search)                     │
│  ✅ GalaxyWorkflowGenerator (tool-constrained generation)   │
│  ✅ EnhancedWorkflowGenerator (template adaptation)         │
│  ❌ BioMNIDatasetRAG (source missing, only .pyc)            │
│  ❌ WorkflowDatasetSelector (source missing, only .pyc)     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │
┌──────────────────────▼──────────────────────────────────────┐
│              GALAXY EXECUTION LAYER                         │
│  ❌ Workflow Execution Engine (not installed)               │
│  ❌ Job Management System (not installed)                   │
│  ❌ Data Storage & Histories (not installed)                │
│  ❌ Tool Execution Framework (not installed)                │
└─────────────────────────────────────────────────────────────┘
```

---

## Detailed Component Analysis

### ✅ WORKING - Frontend (GalaxyChat)

**Location:** `/Users/jingqiwang/biomate/frontend/`

**Components:**
- React + TypeScript chat interface
- Workflow builder with visual editor
- File upload with drag-and-drop
- 3-tier parameter configuration system
- Mock Galaxy API for development

**API Calls Expected:**
```typescript
// Dataset Operations
POST /api/datasets/search
GET  /api/datasets/category/{category}
GET  /api/datasets/{id}
POST /api/datasets/by_schema
POST /api/datasets/compatible

// Workflow Operations
POST /api/workflows/{id}/invocations
GET  /api/workflows/{id}/invocations/{inv_id}
GET  /api/jobs/{id}
GET  /api/jobs/{id}/stdout
```

**Status:** ✅ Complete, waiting for backend implementation

---

### ✅ WORKING - AI Workflow Generation

**Location:** `/Users/jingqiwang/biomate/backend/lib/galaxy/ai/`

**Available Modules (16 total):**
```
✅ ai_assistant.py               - Main orchestrator
✅ workflow_search_rag.py        - Template search
✅ galaxy_workflow_generator.py  - Tool-constrained generation
✅ enhanced_workflow_generator.py - Template adaptation
✅ galaxy_tool_rag.py            - Tool discovery
✅ workflow_templates.py         - Template library
✅ workflow_optimizer.py         - Optimization strategies
✅ intent_parser.py              - User intent analysis
✅ task_decomposer.py            - Task breakdown
✅ tool_recommender.py           - Tool suggestions
✅ tool_discovery.py             - Tool indexing
✅ llm_client.py                 - LLM integration
✅ config.py                     - Configuration
✅ types.py                      - Type definitions
✅ workflow_generator.py         - Base generator
❌ biomni_dataset_rag.py         - MISSING (only .pyc)
❌ workflow_dataset_selector.py  - MISSING (only .pyc)
```

**Tool Index:**
- Database: `backend/galaxy_ai_tools.db` (258 KB)
- Tools indexed: 2,169 tools
- Format: SQLite FTS5 (full-text search)

**Workflow Generation Strategy:**
```python
def generate_workflow_unified(user_intent, uploaded_datasets):
    # Step 1: Search templates
    search_results = self.workflow_search.search(user_intent)
    score = search_results[0]['score']

    # Step 2: Choose strategy based on confidence
    if score > 0.8:
        # High confidence - reuse template
        workflow = reuse_template(search_results[0])
    elif score > 0.5:
        # Medium confidence - adapt template
        workflow = enhanced_generator.generate(user_intent)
    else:
        # Low confidence - generate from scratch
        workflow = constrained_generator.generate(user_intent)

    # Step 3: Assign datasets (BLOCKED - missing components)
    dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
        user_intent, workflow_structure
    )  # ❌ FAILS - missing source code
```

**Status:** ✅ 90% Complete (missing dataset assignment)

---

### ❌ MISSING - Dataset RAG Components

**Critical Missing Files:**

1. **`biomni_dataset_rag.py`**
   - Purpose: Search and discover reference datasets
   - Expected methods:
     ```python
     def search_datasets(query, category=None, limit=10)
     def get_datasets_by_category(category)
     def get_dataset_by_id(dataset_id)
     def get_datasets_by_schema(required_fields)
     def get_compatible_datasets(input_format, required_fields, category)
     ```
   - Dataset catalog: 105+ reference datasets
   - Categories: metabolomics, proteomics, genomics, databases

2. **`workflow_dataset_selector.py`**
   - Purpose: Auto-assign datasets to workflow steps
   - Expected method:
     ```python
     def select_datasets_for_workflow(user_intent, workflow_structure):
         # Returns: { workflow_steps: [{ step: 1, datasets: [...] }] }
     ```
   - Logic: Match tool requirements with available datasets

**Evidence from Code:**
```python
# backend/lib/galaxy/ai/ai_assistant.py:58-59
self.dataset_selector = WorkflowDatasetSelector()  # ❌ Source missing
self.dataset_rag = BioMNIDatasetRAG()              # ❌ Source missing

# Line 237-240 in generate_workflow_unified()
dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
    user_intent=user_intent,
    workflow_structure=workflow_steps
)  # ❌ FAILS when called
```

**Impact:**
- Workflows can't auto-select reference databases (KEGG, HMDB, etc.)
- Tools requiring databases will have empty inputs
- Manual dataset assignment required

---

### ❌ MISSING - Backend API Endpoints

**Expected by Frontend but Not Implemented:**

```bash
# Dataset APIs (0/5 implemented)
POST /api/datasets/search           ❌ Not implemented
GET  /api/datasets/category/{cat}   ❌ Not implemented
GET  /api/datasets/{id}             ❌ Not implemented
POST /api/datasets/by_schema        ❌ Not implemented
POST /api/datasets/compatible       ❌ Not implemented

# Workflow Execution (0/7 implemented)
POST /api/workflows/{id}/invocations              ❌ Not implemented
GET  /api/workflows/{id}/invocations/{inv_id}     ❌ Not implemented
GET  /api/jobs/{id}                               ❌ Not implemented
GET  /api/jobs/{id}/stdout                        ❌ Not implemented
GET  /api/jobs/{id}/stderr                        ❌ Not implemented
POST /api/histories                               ❌ Not implemented
POST /api/tools/{id}/upload                       ❌ Not implemented
```

**Current Implementation:**
```typescript
// frontend/server/routes.ts:164-178
app.post("/api/galaxy/datasets/search", async (req, res) => {
  try {
    const results = await galaxyAPIProxy.searchDatasets(searchRequest);
    res.json(results);
  } catch (error) {
    // ❌ This will fail - backend doesn't have this endpoint
    res.status(500).json({ error: 'DatasetSearchError' });
  }
});
```

---

### ❌ MISSING - Galaxy Platform Core

**Status:** Galaxy core files are symlinks (broken) or missing entirely

```bash
backend/
├── lib/galaxy/ai/              ✅ Complete (AI components)
├── lib/galaxy/webapps/         ❌ Only 1 file (ai_assistant.py API)
├── lib/galaxy/main.py          ❌ Broken symlink
├── lib/galaxy/workflow/        ❌ Missing (execution engine)
├── lib/galaxy/jobs/            ❌ Missing (job management)
├── lib/galaxy/tools/           ❌ Missing (tool execution)
├── lib/galaxy/datatypes/       ❌ Missing (data handling)
├── lib/galaxy/model/           ❌ Missing (database models)
└── scripts/galaxy-main         ❌ Broken symlink
```

**What's Missing:**
- Workflow execution engine
- Job management system
- Tool execution framework
- Data storage and histories
- User authentication
- Database models (PostgreSQL/SQLite)
- Job runners (local/Docker/Slurm)

**Impact:** Cannot execute workflows, only generate .ga files for manual upload

---

## What Actually Works Today

### ✅ Workflow Generation (AI Only)

```
User: "Analyze LC-MS metabolomics data"
  ↓
[Frontend] Send request to chat API
  ↓
[Backend] GalaxyAssistant.chat(message)
  ↓
[AI Layer] AIAssistant.generate_workflow_unified(intent)
  ↓
3-Strategy Generation:
  - Template Search (score > 0.8) → Reuse existing workflow
  - Template Adapt (score 0.5-0.8) → Modify template
  - Tool-Constrained (score < 0.5) → Generate from scratch
  ↓
[Output] workflow.ga JSON file
  ↓
✅ User downloads .ga file
✅ User manually uploads to their Galaxy instance
```

### ✅ Tool Discovery

```
User: "Find tools for peak detection"
  ↓
[Backend] Tool Search Index (SQLite FTS5)
  ↓
✅ Returns: XCMS, MS-DIAL, OpenMS tools
✅ Includes: descriptions, categories, parameters
```

---

## What Doesn't Work

### ❌ End-to-End Workflow Execution

```
User: "Analyze my uploaded LC-MS data"
  ↓
[Frontend] Upload file
  ↓
❌ Can't assign reference datasets (missing dataset RAG)
  ↓
[AI] Generate workflow
  ↓
❌ Can't execute workflow (no Galaxy core)
  ↓
❌ Can't track progress (no job system)
  ↓
❌ Can't download results (no execution = no results)
```

---

## Implementation Plan

### Phase 1: Recreate Missing Dataset Components (Priority: CRITICAL)

**Time Estimate:** 1-2 days

#### Task 1.1: Recreate `biomni_dataset_rag.py`
**Location:** `backend/lib/galaxy/ai/biomni_dataset_rag.py`

**Requirements:**
- Implement dataset index/search functionality
- Support 105+ reference datasets catalog
- Categories: metabolomics, proteomics, genomics, databases

**Methods to Implement:**
```python
class BioMNIDatasetRAG:
    def __init__(self):
        self.dataset_index = self._load_dataset_index()

    def search_datasets(self, query: str, category: str = None, limit: int = 10) -> List[Dict]:
        """Search datasets using keywords"""

    def get_datasets_by_category(self, category: str) -> List[Dict]:
        """Get all datasets in a category"""

    def get_dataset_by_id(self, dataset_id: str) -> Dict:
        """Get specific dataset by ID"""

    def get_datasets_by_schema(self, required_fields: List[str]) -> List[Dict]:
        """Find datasets matching required schema fields"""

    def get_compatible_datasets(self, input_format: str, required_fields: List[str] = None,
                                category: str = None) -> List[Dict]:
        """Find datasets compatible with tool input requirements"""
```

**Dataset Index Structure (Expected):**
```json
{
  "dataset_id": "kegg_compounds_2024",
  "name": "KEGG Compounds Database",
  "category": "metabolomics",
  "description": "Complete KEGG compound database",
  "format": "JSON",
  "size_gb": 0.5,
  "path": "/path/to/kegg_compounds_complete.json",
  "schema": {
    "fields": ["compound_id", "name", "formula", "mass"],
    "format": "JSON"
  },
  "compatible_tools": ["xcms", "msdial", "metaboanalyst"],
  "source": "https://www.genome.jp/kegg/",
  "last_updated": "2024-09-15"
}
```

#### Task 1.2: Recreate `workflow_dataset_selector.py`
**Location:** `backend/lib/galaxy/ai/workflow_dataset_selector.py`

**Requirements:**
- Auto-assign datasets to workflow steps
- Match tool requirements with available datasets
- Support user-uploaded datasets + reference datasets

**Method to Implement:**
```python
class WorkflowDatasetSelector:
    def __init__(self):
        self.dataset_rag = BioMNIDatasetRAG()

    def select_datasets_for_workflow(self, user_intent: str,
                                     workflow_structure: List[Dict]) -> Dict:
        """
        Assign datasets to workflow steps based on:
        1. Tool input requirements (from workflow_structure)
        2. User intent (keywords like "metabolomics", "LC-MS")
        3. Available datasets in BioMNI catalog

        Returns:
        {
            "workflow_steps": [
                {
                    "step": 1,
                    "tool_id": "xcms_peak_detection",
                    "datasets": [
                        {
                            "name": "KEGG Compounds",
                            "path": "/path/to/kegg.json",
                            "input_name": "compound_db"
                        }
                    ]
                }
            ]
        }
        """
```

#### Task 1.3: Create Dataset Catalog Index
**Location:** `backend/data/dataset_catalog.json` or `backend/data/datasets.db`

**Format Options:**
- **Option A:** JSON file (simple, portable)
- **Option B:** SQLite database (searchable, FTS5 support)
- **Option C:** ChromaDB (vector embeddings, semantic search)

**Recommended:** SQLite FTS5 (matches tool index pattern)

**Content Requirements:**
- 105+ reference datasets
- Categories:
  - Metabolomics: KEGG, HMDB, LipidMaps, MassBank
  - Proteomics: UniProt, PDB, IntAct
  - Genomics: RefSeq, Ensembl, UCSC
  - Chemical: PubChem, ChEMBL, DrugBank
  - Bioactivity: BindingDB, ChEBI

---

### Phase 2: Implement Backend API Endpoints (Priority: HIGH)

**Time Estimate:** 2-3 days

#### Task 2.1: Create Dataset API Module
**Location:** `backend/lib/galaxy/webapps/galaxy/api/datasets.py`

**Endpoints to Implement:**
```python
from galaxy.webapps.base.api import GalaxyAPI
from galaxy.ai.biomni_dataset_rag import BioMNIDatasetRAG

class DatasetsAPI(GalaxyAPI):
    def __init__(self, app):
        super().__init__(app)
        self.dataset_rag = BioMNIDatasetRAG()

    @router.post('/api/datasets/search')
    def search_datasets(self, query: str, category: str = None, limit: int = 10):
        return self.dataset_rag.search_datasets(query, category, limit)

    @router.get('/api/datasets/category/{category}')
    def get_datasets_by_category(self, category: str):
        return self.dataset_rag.get_datasets_by_category(category)

    @router.get('/api/datasets/{dataset_id}')
    def get_dataset_by_id(self, dataset_id: str):
        return self.dataset_rag.get_dataset_by_id(dataset_id)

    @router.post('/api/datasets/by_schema')
    def get_datasets_by_schema(self, required_fields: List[str]):
        return self.dataset_rag.get_datasets_by_schema(required_fields)

    @router.post('/api/datasets/compatible')
    def get_compatible_datasets(self, input_format: str, required_fields: List[str] = None,
                                category: str = None):
        return self.dataset_rag.get_compatible_datasets(input_format, required_fields, category)
```

#### Task 2.2: Update Frontend Routes
**Location:** `frontend/server/routes.ts`

**Connect to Real Backend:**
```typescript
// Change from mock to real backend
const galaxyAPIProxy = new GalaxyAPIProxy(
  process.env.GALAXY_URL || 'http://localhost:8080',
  process.env.GALAXY_API_KEY
);

// Remove mock fallbacks once backend is ready
```

---

### Phase 3: Galaxy Platform Installation (Priority: HIGH)

**Time Estimate:** 1-3 hours (depending on approach)

#### Option A: Connect to Existing Galaxy (FASTEST)
**Time:** 1-2 hours
**Complexity:** Low

```bash
# 1. Deploy Galaxy Docker
docker run -d -p 8080:80 \
  -v /path/to/data:/export \
  --name galaxy \
  bgruening/galaxy-stable

# 2. Get API key from Galaxy UI
# Access http://localhost:8080
# User → Preferences → Manage API Key

# 3. Configure environment
echo "GALAXY_URL=http://localhost:8080" >> .env
echo "GALAXY_API_KEY=your-key" >> .env
```

**Pros:**
- ✅ Fastest setup
- ✅ Pre-installed tools
- ✅ Production-ready
- ✅ Easy updates

**Cons:**
- ❌ Limited customization
- ❌ Requires Docker

---

#### Option B: Install Full Galaxy (COMPLETE)
**Time:** 2-3 hours
**Complexity:** Medium

```bash
# 1. Clone Galaxy
git clone -b release_23.1 https://github.com/galaxyproject/galaxy.git

# 2. Copy AI components
cp -r backend/lib/galaxy/ai galaxy/lib/galaxy/

# 3. Install dependencies
cd galaxy
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 4. Configure Galaxy
cp config/galaxy.yml.sample config/galaxy.yml
# Edit: set database, admin users, tool config

# 5. Initialize database
./scripts/create_db.sh

# 6. Start Galaxy
./run.sh
```

**Pros:**
- ✅ Full control
- ✅ Native AI integration
- ✅ Custom tool installation

**Cons:**
- ❌ Longer setup
- ❌ Manual tool installation
- ❌ More maintenance

---

#### Option C: Hybrid Approach (RECOMMENDED)
**Time:** 1 hour
**Complexity:** Low-Medium

**Architecture:**
```
Frontend (5173)
    ↓
Backend Node.js (5000)
    ↓
    ├─→ AI Service (8081)        [Python standalone]
    │   - Dataset RAG
    │   - Workflow Generation
    │   - Tool Search
    │
    └─→ Galaxy Docker (8080)      [Workflow execution]
        - Job management
        - Tool execution
        - Data storage
```

**Setup:**
```bash
# 1. Start Galaxy Docker
docker run -d -p 8080:80 --name galaxy bgruening/galaxy-stable

# 2. Create AI Service wrapper
# File: backend/ai_service.py
from flask import Flask, request, jsonify
import sys
sys.path.insert(0, 'backend/lib')

from galaxy.ai.ai_assistant import AIAssistant

app = Flask(__name__)
assistant = AIAssistant()

@app.route('/api/ai_assistant/generate_workflow', methods=['POST'])
def generate_workflow():
    data = request.json
    result = assistant.generate_workflow_unified(
        user_intent=data['request_text'],
        uploaded_datasets=data.get('uploaded_datasets', [])
    )
    return jsonify(result)

@app.route('/api/datasets/search', methods=['POST'])
def search_datasets():
    data = request.json
    result = assistant.dataset_rag.search_datasets(
        query=data['query'],
        category=data.get('category'),
        limit=data.get('limit', 10)
    )
    return jsonify({'success': True, 'datasets': result})

if __name__ == '__main__':
    app.run(port=8081)

# 3. Update frontend proxy
# frontend/server/galaxy-api-proxy.ts
const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8081';
const GALAXY_URL = process.env.GALAXY_URL || 'http://localhost:8080';

# 4. Start all services
docker start galaxy           # Terminal 1
python backend/ai_service.py  # Terminal 2
npm run dev                   # Terminal 3 (in frontend/)
```

**Pros:**
- ✅ Fast setup (1 hour)
- ✅ Best of both worlds
- ✅ Easy debugging
- ✅ Scalable architecture
- ✅ Pre-installed Galaxy tools

**Cons:**
- ❌ Requires Docker
- ❌ Slightly more complex architecture

---

### Phase 4: Integration & Testing (Priority: MEDIUM)

**Time Estimate:** 1-2 days

#### Task 4.1: Frontend-Backend Connection
- Remove mock implementations
- Update API proxy endpoints
- Add error handling
- Test all API calls

#### Task 4.2: End-to-End Testing
- Upload dataset → Verify storage
- Generate workflow → Verify .ga format
- Assign datasets → Verify dataset mapping
- Execute workflow → Verify job submission
- Track progress → Verify SSE updates
- Download results → Verify output files

#### Task 4.3: Error Handling
- Network failures
- Galaxy API errors
- Missing datasets
- Tool installation failures
- Job execution errors

---

## Timeline Summary

| Phase | Tasks | Time | Priority |
|-------|-------|------|----------|
| **Phase 1** | Recreate dataset RAG components + catalog | 1-2 days | 🔴 CRITICAL |
| **Phase 2** | Implement backend dataset APIs | 2-3 days | 🟠 HIGH |
| **Phase 3** | Galaxy installation (Hybrid approach) | 1 hour | 🟠 HIGH |
| **Phase 4** | Integration & testing | 1-2 days | 🟡 MEDIUM |
| **Total** | | **4-8 days** | |

---

## Recommended Execution Order

### Week 1: Core Components
**Days 1-2:** Phase 1 - Dataset RAG
- Recreate `biomni_dataset_rag.py`
- Recreate `workflow_dataset_selector.py`
- Build dataset catalog (105+ datasets)

**Day 3:** Phase 3 - Galaxy Setup
- Deploy Docker Galaxy
- Create AI service wrapper
- Test Galaxy API access

**Days 4-5:** Phase 2 - Backend APIs
- Implement dataset API endpoints
- Update frontend routes
- Test dataset search/assignment

### Week 2: Integration & Polish
**Days 6-7:** Phase 4 - Integration
- Connect frontend ↔ backend ↔ Galaxy
- End-to-end testing
- Bug fixes

**Day 8:** Buffer
- Documentation
- Performance optimization
- Deployment preparation

---

## Success Criteria

### Minimum Viable Product (MVP)
- ✅ User can upload data files
- ✅ User can describe analysis goal in chat
- ✅ System generates workflow with auto-assigned datasets
- ✅ Workflow executes on Galaxy
- ✅ User can track progress in real-time
- ✅ User can download results

### Extended Goals
- Advanced parameter tuning
- Multi-workflow pipelines
- Dataset recommendations
- Tool installation on-demand
- AWS deployment

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Dataset catalog incomplete | HIGH | Use MetaboAnalyst + UniProt + BioMNI as baseline |
| Galaxy Docker resource limits | MEDIUM | Use local Galaxy install for production |
| API compatibility issues | MEDIUM | Thorough testing with mock data first |
| Missing tool dependencies | LOW | Pre-install common tools in Galaxy |

---

## Next Actions

1. **IMMEDIATE:** Recreate `biomni_dataset_rag.py` and `workflow_dataset_selector.py`
2. **TODAY:** Build dataset catalog from existing BioMNI data
3. **TOMORROW:** Set up hybrid architecture (AI service + Galaxy Docker)
4. **THIS WEEK:** Implement backend APIs and integrate frontend

---

**Document Version:** 1.0
**Last Updated:** October 9, 2025
**Author:** Analysis based on codebase exploration
**Next Review:** After Phase 1 completion
