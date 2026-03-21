# BioMate Architecture Review - Deep Dive Analysis

**Date**: February 9, 2026  
**Scope**: Comprehensive review of BioMate implementation in `/home/yzhang/biomate_worktrees/connection_formal/`  
**Status**: READ-ONLY EXPLORATION

---

## Executive Summary

BioMate is a sophisticated **hybrid intelligence system** combining Galaxy workflow management with LLM-powered AI orchestration. The system is split into **two main services**:

1. **Frontend** (Node.js/Express, port 5000) - Chat interface, workflow visualization, execution control
2. **Backend** (Galaxy Python + custom AI modules, port 8081) - Workflow generation, tool discovery, execution

The architecture implements a **single unified pipeline** (not multi-agent) with:
- Intent routing (UnifiedIntentRouter — active)
- Research capabilities (ResearchAgent — active only for `research_question` intent)
- Long-term memory (AgenticMemoryService — schema complete, not fully wired)
- Parameter recommendation (ToolKnowledgeProvider — active, 12,274 tools in DB)
- Domain-specific knowledge injection (expert_knowledge JSON files, injected into tool_knowledge table)
- **NOTE**: AgentOrchestrator + DomainSpecialists are fully implemented but never called — dead code since the architecture pivoted to `generate_workflow_unified()`

---

## 1. BACKEND ARCHITECTURE

### 1.1 AI Assistant System

**Location**: `/backend/lib/galaxy/ai/`

The AIAssistant is the **unified orchestrator** that implements lazy-loading for ~12 core components:

```python
# Core Components (from ai_assistant.py)
├── UnifiedWorkflowSearch (2,285 workflows, database-backed)  # 1,818 bioconductor + 465 nextflow + 2 galaxy
├── GalaxyWorkflowGenerator (constrained workflow generation)
├── WorkflowDatasetSelector (input-output matching)
├── EnhancedWorkflowGenerator (legacy, lazy-loaded)
├── IntentParser (simple intent classification)
├── TaskDecomposer (multi-step task decomposition)
├── ToolRecommender (relevance scoring)
├── WorkflowTemplateLibrary (500+ templates)
├── WorkflowOptimizer & WorkflowValidator
├── UnifiedIntentRouter (active: intent classification)
├── ResearchAgent (active only for research_question intent)
├── BenchmarkKnowledgeDB (334 tools with benchmark papers in galaxy_ai_tools.db [active]; scientific_rationale in workflow generation surfaces this data — benchmark_knowledge.db advanced query DB is intentionally unused)
└── AgenticMemoryService (schema complete, not fully wired)
```

**Key Design Pattern: Lazy Loading**

Components are only initialized when first accessed. This reduces startup time dramatically:

```typescript
@property
def workflow_generator(self):
    if self._workflow_generator is None:
        self._workflow_generator = EnhancedWorkflowGenerator(...)
    return self._workflow_generator
```

### 1.2 Workflow Generation Pipeline

**Main Entry Point**: `AIAssistant.generate_workflow_unified()`

The pipeline:

1. **Intent Classification** (UnifiedIntentRouter)
   - Determines: workflow_generation, research_question, tool_search, benchmark_query
   - Returns: primary intent, secondary intents, confidence, handler recommendations

2. **Workflow Search** (UnifiedWorkflowSearch)
   - Searches 2,285 pre-indexed workflows (1,818 bioconductor + 465 nextflow + 2 galaxy)
   - Database-backed (galaxy_ai_tools.db, FTS5 index)
   - Two-pass LLM search: Haiku classify intent → FTS → Haiku rerank top-10

3. **Parameter Generation** (LLMParameterGenerator)
   - Uses Claude Sonnet 4.5 for parameter inference
   - Takes: tool_id, user_intent, tool_parameters, context
   - Returns: (parameters_dict, confidence_score, reasoning)

4. **Workflow Synthesis** (GalaxyWorkflowGenerator)
   - Constrained generation (only valid tools)
   - Validates tool IDs against Galaxy loaded tools
   - Normalizes biomni/X/Y → biomni_X_Y format
   - Generates workflow JSON

5. **Dataset Mapping** (WorkflowDatasetSelector)
   - Matches inputs to user datasets
   - Validates data formats/types

### 1.3 Knowledge Injection System

**Location**: `/backend/scripts/domain_knowledge/` + `inject_expert_knowledge.py`

**Domain-Specific Knowledge Files**:
- `expert_knowledge_cryoem.json` (620+ lines, 6 major stages)
- `expert_knowledge_genomics.json`
- `expert_knowledge_molecular_biology.json`
- `expert_knowledge_microbio_sysbio.json`
- `expert_knowledge_pharmacology.json`
- `expert_knowledge_cellbio_immuno.json`
- `expert_knowledge_bioimaging.json`

**Cryo-EM Knowledge Structure Example**:

```json
{
  "motion_correction": {
    "key_parameters": {
      "patch_size": {
        "situations": {
          "small_particles_high_resolution": {
            "value_or_range": "5-7",
            "when": "Particle size < 150Å, targeting resolution < 3Å",
            "why": "Smaller patches capture finer motion variations...",
            "source": "CryoSPARC Guide v4.5"
          }
        },
        "common_mistakes": [...]
      }
    }
  },
  "ctf_estimation": {...},
  "particle_picking": {...},
  "2d_classification": {...},
  "ab_initio_reconstruction": {...},
  "homogeneous_refinement": {...},
  "non_uniform_refinement": {...}
}
```

**Injection Process**:

1. Maps JSON topics → biomni tool IDs (via TOPIC_TO_TOOLS dict)
2. Inserts knowledge into `tool_knowledge.recommended_parameters` field
3. Situation-aware guidance tied to specific parameter values
4. Searchable by tool_id in Galaxy

**Cryo-EM Knowledge Coverage**:
- Motion correction (patch size, dose weighting, B-factor)
- CTF estimation (resolution range, defocus search, astigmatism)
- Particle picking (threshold, separation, filtering)
- 2D classification (class count, batch size, resolution limits)
- Ab initio reconstruction (class count, symmetry, initial resolution)
- Homogeneous refinement (masking, defocus refinement, alignment resolution)
- Non-uniform refinement (filter resolution, regularization, iterations)

### 1.4 Domain Workflow Patterns

**Location**: `/backend/lib/galaxy/ai/domain_workflow_patterns.py`

Defines **biologically meaningful workflow phases** for each domain:

```python
AnalysisDomain.TRANSCRIPTOMICS: [
    WorkflowPhase(name="Quality Control", typical_tools=["FastQC", "MultiQC"]),
    WorkflowPhase(name="Read Preprocessing", typical_tools=["Cutadapt", "Trimmomatic"]),
    WorkflowPhase(name="Alignment/Quantification", typical_tools=["STAR", "Salmon"]),
    WorkflowPhase(name="Count Generation", typical_tools=["featureCounts"]),
    WorkflowPhase(name="Differential Expression", typical_tools=["DESeq2", "edgeR"]),
    WorkflowPhase(name="Functional Enrichment", typical_tools=["gProfiler", "DAVID"]),
    WorkflowPhase(name="Visualization", typical_tools=[...])
]
```

Supported domains:
- TRANSCRIPTOMICS
- GENOMICS
- PROTEOMICS
- EPIGENOMICS
- METAGENOMICS
- METABOLOMICS
- DATA_QUERY
- GENERAL

### 1.5 Benchmark Knowledge Database

**Location**: `/backend/lib/galaxy/ai/benchmark_knowledge.py`

Integrates:
- Tool performance metrics (accuracy, speed, memory, cost)
- Best practices from literature
- Dataset compatibility matrices
- Enables semantic search for "what's best for my data"

**Enables**:
- Tool ranking by performance
- Cost-performance trade-off analysis
- Resolution estimates (cryo-EM: "5 particles → ~X resolution")

---

## 2. FRONTEND ARCHITECTURE

### 2.1 Core Server Components

**Location**: `/frontend/server/`

Key services:

| Component | Purpose |
|-----------|---------|
| `galaxy-assistant.ts` | LLM orchestrator (Claude Sonnet 4.5 + tool search) |
| `galaxy-api-proxy.ts` | HTTP bridge to Galaxy backend (port 8081) |
| `galaxy-state-poller.ts` | Polls workflow execution status every 2s |
| `workflow-sse.ts` | Server-sent events for real-time updates |
| `conversation-state.ts` | Multi-turn conversation state machine |
| `routes.ts` | Express API endpoints (194KB, main routing) |
| `storage.ts` | Persistent storage (invocations, workflows, datasets) |
| `memory-repository.ts` | Long-term memory for conversation context |
| `auth-service.ts` | User authentication & authorization |

### 2.2 Chat Interface Architecture

**Location**: `/frontend/client/src/components/chat-interface.tsx`

**Data Flow**:

```
User Input (chat-input.tsx)
    ↓
POST /api/chat (frontend/server/routes.ts)
    ↓
GalaxyAssistant.analyzeQuery()
    ├── Intent Classification (Claude Haiku)
    ├── Tool Search (UnifiedToolSearch)
    ├── Workflow Generation (Claude Sonnet)
    └── Dataset RAG matching
    ↓
Response includes:
  - intent: string (workflow_generation, research_question, etc.)
  - confidence: number (0-1)
  - tools: ToolRecommendation[]
  - datasets: DatasetRecommendation[]
  - workflow?: WorkflowDefinition
  - artifacts?: ChatArtifact[]
```

**Features**:
- Token counting and context compression (70-80% threshold)
- Compression dialog when token budget exceeded
- Chat history service for persistent session state
- Hybrid intelligence: intent → tools → datasets → workflow

### 2.3 Visualization Components

**Key Components**:

| Component | Purpose |
|-----------|---------|
| `execution-control-panel.tsx` | Mode selection, data scope, execution controls |
| `execution-timeline.tsx` | Step-by-step progress visualization |
| `chat-message.tsx` | Rich message rendering (text, code, artifacts) |
| `enhanced-workflow-builder.tsx` | Visual workflow editor (DAG) |
| `parameter-editor.tsx` | Tool parameter configuration UI |
| `job-log-viewer.tsx` | Real-time job output streaming |
| `galaxy-recommendations.tsx` | Tool/dataset suggestions |
| `benchmark-evidence.tsx` | Performance metrics display |

### 2.4 Execution Model

**Mode Selection**:
- **Sandbox**: Runs on reduced dataset (1% sampling or stratified subset)
- **Production**: Full dataset execution

**Data Scope Configuration**:
- Total samples slider (0-100%)
- Stratified sampling by category
- Cost/time estimation
- Estimated completion time

### 2.5 Conversation State Machine

**Location**: `/frontend/server/conversation-state.ts`

**Phases**:
1. **gathering** - Collecting initial information
2. **clarifying** - Asking for ambiguous parameters
3. **tool_selection** - Identifying candidate tools
4. **parameterizing** - Mapping facts to parameters
5. **ready** - All required parameters present
6. **generated** - Workflow created
7. **executing** - Running

**State Accumulation**:
- RawFact objects extracted per turn
- Supersession tracking (new facts override old ones)
- Confidence scoring (0-1)
- Persisted to Postgres after each turn
- Survives context compression

---

## 3. NEXTFLOW PIPELINE INTEGRATION

### 3.1 Cryo-ET Pipeline

**Location**: `/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/`

**5 Implemented Modules**:

1. **import_tiltseries** - Import raw tilt series from microscope
2. **tilt_alignment** - Align tilt images within series
3. **tomogram_reconstruction** - Reconstruct 3D tomogram from aligned tilts
4. **subtomogram_averaging** - Average particles to improve resolution
5. **et_full_pipeline** - Composite pipeline combining all 5

**Architecture Features**:
- **Parallelism**: All tilt series processed simultaneously (vs IMOD serial)
- **DSL2 Format**: Modular, composable workflow definitions
- **Mock Mode**: Realistic simulation for testing
- **Live Mode**: Integration with CryoSPARC via cryosparc-tools API
- **Configuration Profiles**:
  - standard (local execution)
  - docker (containerized)
  - local_gpu (single GPU machine)
  - multi_gpu (multiple GPUs)
  - slurm (HPC cluster)
  - singularity (container alternative)
  - aws (cloud execution)

**Status**: Mock mode validated on 3 tomograms, all 20 steps executed in parallel

### 3.2 Cryo-EM Pipeline Status

**Note**: Cryo-EM SPA pipeline exists in main branch (`/home/yzhang/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/`) but NOT in connection_formal worktree.

This indicates **cryo-EM integration is being worked on separately** and will be merged later.

### 3.3 Workflow Execution Path

**Frontend→Backend Workflow**:

```
Frontend:  POST /api/workflows/execute
           ├── workflowDefinition (Galaxy JSON)
           ├── executionConfig (mode, data scope)
           └── inputs (files, parameters)
              ↓
Backend:   POST /api/workflows (import)
           ↓ (returns workflow_id)
Backend:   POST /api/workflows/{id}/invocations (execute)
           ├── Creates Galaxy history
           ├── Submits jobs to backend
           └── Returns invocation_id
              ↓
Frontend:  GET /api/workflows/runs/{runId}/status (poll every 2s)
           ├── Fetches Galaxy invocation state
           ├── Updates SSE subscribers
           └── Triggers notifications on completion
```

---

## 4. MODEL CONFIGURATION & OPTIMIZATION

### 4.1 Model Selection Strategy

**From `galaxy-assistant.ts`**:

```typescript
const DEFAULT_MODEL_CONFIG: ModelConfig = {
  intentModel: 'claude-haiku-4-5',       // 2x faster, 11.5x cheaper
  toolRankingModel: 'claude-haiku-4-5',  // 1.4x faster
  responseModel: 'claude-sonnet-4-5',    // Highest quality
  enableThinking: true,                  // Extended thinking for complex tasks
  thinkingBudget: 2000,                  // Token budget
};
```

**Thinking Mode Heuristics**:

✅ **ENABLE for**:
- Complex workflow design ("design a metagenomics pipeline")
- Comparative analysis ("BWA vs Bowtie2")
- Technical explanations ("why did alignment fail?")
- Multi-step planning

❌ **DISABLE for**:
- Greetings ("Hello", "What can you do?")
- Intent classification (simple JSON task)
- Tool ranking (structured output)
- Short factual responses

### 4.2 Token Budget Management

**Critical Thresholds**:
- 70% (140k tokens) - Warning, show compression dialog
- 80% (160k tokens) - Critical, show compression immediately

**Compression Dialog**:
- Summarizes conversation history
- Uses Claude Opus 4.6 for quality
- Persists key facts to memory
- Resets token counter
- Seamlessly continues conversation

---

## 5. DATA MODELS & PERSISTENCE

### 5.1 Storage Layer

**Location**: `/frontend/server/storage.ts`

Persistent entities:
- **Users** - User profiles, API keys, preferences
- **ChatSessions** - Conversation history, state
- **Invocations** - Workflow execution records
- **Workflows** - Saved workflow definitions
- **Datasets** - Dataset metadata & paths
- **ExecutionRuns** - Run history with performance metrics
- **ParameterRecommendations** - User-specific parameter tuning

### 5.2 Memory Integration

**Location**: `/frontend/server/memory-repository.ts`

Two-tier memory:
1. **Session Memory** - Current turn facts (RawFact objects)
2. **Long-Term Memory** - Persistent facts across sessions

**AgenticMemoryService**:
- Stores accumulated knowledge
- Enables cross-session continuity
- Retrieval for context building

### 5.3 Conversation State Persistence

**PostgreSQL Schema** (via Drizzle):

```typescript
ltmSchema {
  conversationFacts: fact_id, category, value, source, confidence
  toolCandidates: toolId, relevanceScore, source
  parameterMappings: factId, toolId, parameterName, value, confidence
  clarificationRequests: type, question, options, status, answer
  readinessAssessments: score, missingRequired, missingOptional
}
```

---

## 6. KNOWLEDGE INTEGRATION PATTERNS

### 6.1 Intent→Knowledge Mapping

```
User Query: "I need to pick particles from cryo-EM micrographs"
         ↓
Intent: "workflow_generation" (confidence: 0.95)
Domain: "cryo_em"
Stage: "particle_picking"
         ↓
Knowledge Lookup: expert_knowledge_cryoem.json#particle_picking
         ↓
Retrieved Parameters:
  - picking_threshold: situation-dependent (0.1-0.7)
  - minimum_particle_separation: "1.5 × diameter"
  - lowpass_filter_picking: "20-30Å"
  - common_mistakes: [list of 3 mistakes with explanations]
         ↓
LLM Parameter Generation:
  "Based on this template data and user's micrographs,
   set picking_threshold=0.35, particle_separation=225Å"
         ↓
Tool Recommendation:
  ✓ CryoSPARC Template Picker (if reference available)
  ✓ CryoSPARC Blob Picker (initial screening)
  ✓ Topaz (if deep learning preferred)
```

### 6.2 Benchmark Knowledge Integration

**BenchmarkKnowledgeDB enables**:
- "Which tool is fastest for 100K particles?" → Tool ranking
- "What resolution can I expect?" → Estimation
- "Which picker has best precision?" → Metric-based comparison

---

## 7. CRITICAL FINDINGS

### 7.1 Architecture Strengths

✅ **Modular Design**:
- Lazy-loading avoids initialization overhead
- Components are independently testable
- Easy to swap implementations

✅ **Unified Pipeline with Specialized Agents**:
- Intent routing separates concerns (UnifiedIntentRouter — active on every request)
- Research agent for literature integration (active for research_question intent)
- ToolKnowledgeProvider injects citations + param recommendations into every workflow
- NOTE: AgentOrchestrator + DomainSpecialists exist but are dead code — architecture uses unified pipeline

✅ **Knowledge Integration**:
- Situation-aware parameter guidance
- Domain-specific best practices embedded
- Benchmark performance data available

✅ **Production Readiness**:
- Comprehensive error handling
- Token budget management & compression
- Persistent state across sessions
- Real-time status polling & SSE updates

✅ **Cryo-ET Integration**:
- Fully implemented Nextflow pipeline
- Mock mode validated
- All 5 modules working in parallel
- Configuration flexibility (local, GPU, HPC, cloud)

### 7.2 Knowledge Gaps & Future Work

❌ **Cryo-EM SPA Pipeline**:
- Not present in connection_formal worktree
- Exists in main branch → needs integration
- Will add 15 additional modules (import → sharpen)
- Full pipeline will have 4 levels of Nextflow parallelism

❌ **AlphaFold 3 Integration**:
- Not yet implemented
- Will enable structure prediction in workflows
- Needs domain routing to identify when applicable

❌ **Visualization Gaps**:
- No interactive 3D viewers for cryo-EM maps
- Alignment metrics not visualized
- Resolution maps (local resolution) not shown

❌ **Parameter Recommender Gaps**:
- Tool-specific parameter recommendations exist (knowledge JSON)
- But parameter recommender API not yet exposed to frontend
- Parameter editor is manual only

### 7.3 Integration Points Identified

**To Connect Everything**:

1. **AI Assistant → Workflow Execution**:
   - ✓ Intent parsing
   - ✓ Tool search
   - ✓ Workflow generation
   - ✓ Execution status polling
   - ❌ Parameter recommendation display in UI

2. **Knowledge → Tool Parameters**:
   - ✓ Knowledge stored in database
   - ✓ TOPIC_TO_TOOLS mapping exists
   - ❌ Frontend doesn't retrieve knowledge-based recommendations

3. **Cryo-EM/ET Pipeline → Chat Interface**:
   - ✓ Pipeline logic complete
   - ✓ Execution harness ready
   - ❌ Not yet callable via chat ("design a cryo-EM pipeline")

4. **Benchmark Data → Parameter Inference**:
   - ✓ 334 tools have curated benchmark papers in galaxy_ai_tools.db
   - ✓ scientific_rationale field in workflow generation response surfaces benchmark evidence
   - ✓ benchmark-evidence.tsx component renders it in the UI
   - No further action needed here

---

## 8. CODE ORGANIZATION REFERENCE

### Backend Structure
```
/backend/lib/galaxy/ai/
├── ai_assistant.py (main orchestrator)
├── unified_workflow_search.py (2,285 workflows, galaxy_ai_tools.db)
├── galaxy_workflow_generator.py (constrained generation)
├── llm_parameter_generator.py (parameter inference)
├── domain_workflow_patterns.py (phase definitions)
├── benchmark_knowledge.py (performance data)
├── enhanced_ai_assistant.py (legacy)
├── agents/
│   ├── unified_intent_router.py
│   ├── research_agent.py
│   └── literature_clients.py
└── memory/
    └── agentic_memory_service.py

/backend/scripts/
├── inject_expert_knowledge.py (knowledge injection script)
└── domain_knowledge/
    ├── expert_knowledge_cryoem.json (620 lines)
    ├── expert_knowledge_genomics.json
    └── [5 other domain files]

/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/
├── import_tiltseries/main.nf
├── tilt_alignment/main.nf
├── tomogram_reconstruction/main.nf
├── subtomogram_averaging/main.nf
└── et_full_pipeline/main.nf
```

### Frontend Structure
```
/frontend/server/
├── galaxy-assistant.ts (LLM orchestrator)
├── galaxy-api-proxy.ts (HTTP bridge)
├── galaxy-state-poller.ts (status polling)
├── workflow-sse.ts (real-time updates)
├── conversation-state.ts (state machine)
├── routes.ts (API endpoints - 194KB)
├── storage.ts (persistence)
├── memory-repository.ts (long-term memory)
└── [30+ other services]

/frontend/client/src/components/
├── chat-interface.tsx (main chat UI)
├── chat-message.tsx (message rendering)
├── execution-control-panel.tsx (mode selection)
├── enhanced-workflow-builder.tsx (DAG editor)
├── parameter-editor.tsx (param UI)
└── [40+ visualization components]
```

---

## 9. SYSTEM METRICS & CHARACTERISTICS

| Metric | Value |
|--------|-------|
| Total workflows indexed | 2,285 |
| — Bioconductor (R/Nextflow) | 1,818 |
| — BioMate Nextflow (biomni_nextflow) | 268 |
| — nf-core pipelines | 100 (stale, last indexed 2026-02-19) |
| — nf-core subworkflows | 93 |
| — Galaxy | 2 |
| Total tools in DB | 12,274 |
| Cryo-EM knowledge items | 7 (motion, CTF, picking, 2D, ab initio, homo, NU) |
| Parameter guidance entries | 28 (motion: 3, CTF: 3, picking: 4, 2D: 3, ab initio: 3, homo: 2, NU: 3) |
| Cryo-ET pipeline modules | 5 (all implemented) |
| Cryo-EM SPA modules (main branch) | 15 (in main, not in connection_formal) |
| Frontend API endpoints | 40+ (routes.ts) |
| Chat components | 45+ |
| Model inference time | Intent: 0.2s (Haiku), Response: 1-2s (Sonnet) |
| Status polling interval | 2 seconds |
| SSE update latency | < 500ms |
| Token budget | 200,000 tokens per session |
| Compression threshold | 70% (140k tokens) |

---

## 10. RECOMMENDATIONS FOR NEXT PHASE

### Priority 1: Connect Knowledge to UI
- [ ] Expose parameter recommendations in `/api/tools/{toolId}/recommendations`
- [ ] Display knowledge guidance in parameter-editor.tsx
- [ ] Add "why?" tooltips with source citations

### Priority 2: Cryo-EM Integration
- [ ] Merge cryo-EM SPA pipeline from main branch
- [ ] Add unified cryo-EM/ET domain router
- [ ] Update knowledge injection for full pipeline

### Priority 3: AlphaFold 3 Integration
- [ ] Implement structure prediction module
- [ ] Add domain routing detection
- [ ] Create protein_design domain knowledge

### Priority 4: Enhanced Visualization
- [ ] 3D map viewer for cryo-EM (three.js)
- [ ] Alignment quality metrics dashboard
- [ ] Parameter sensitivity analysis UI

### Priority 5: Search Index Maintenance
- [ ] Re-index nf-core pipelines (100/405 indexed, last run 2026-02-19)
- [ ] Schedule periodic re-index as a cron job or CI step
- [ ] Benchmark evidence already served via scientific_rationale + benchmark-evidence.tsx — no further action needed

---

## Conclusion

BioMate represents a **mature, well-engineered system** that successfully integrates:
- LLM-based natural language understanding
- Comprehensive tool & workflow database
- Domain-specific expert knowledge
- Real-time execution monitoring
- Persistent state management across sessions

The architecture is **extensible and production-ready**, with clear integration points for additional domains (cryo-EM, AlphaFold 3) and visualization enhancements.
