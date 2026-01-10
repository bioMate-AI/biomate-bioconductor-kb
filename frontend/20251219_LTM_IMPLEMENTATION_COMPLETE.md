# Long-Term Memory (LTM) System Implementation
**Date:** 2025-12-19
**Status:** Core Implementation Complete, Tests Passing

---

## Overview

This document summarizes the implementation of an agentic memory system for BioMate, based on the survey in `20251220_AGENTIC_MEMORY_SURVEY_AND_PLAN.md` and prior architecture design in `LONG_TERM_MEMORY_ARCHITECTURE_20251031.md`.

---

## What Was Implemented

### 1. Database Schema (`frontend/shared/ltm-schema.ts`)

10 PostgreSQL tables using Drizzle ORM:

| Table | Purpose |
|-------|---------|
| `ltm_users` | Extended user profiles with expertise, domain, learning style |
| `projects` | Project context with domain, organisms, data modalities |
| `sessions` | Conversation sessions with summaries and key decisions |
| `conversation_messages` | Individual messages within sessions |
| `user_preferences` | Learned preferences (tools, parameters, workflows) |
| `correction_log` | User corrections for learning from mistakes |
| `project_knowledge` | Project-specific knowledge base |
| `workflows` | Workflow history with parameters and outcomes |
| `project_episodes` | Episodic memory - interaction records with outcomes |
| `project_procedures` | Procedural memory - learned multi-step procedures |

### 2. Memory Repository (`frontend/server/memory-repository.ts`)

6 repository classes providing data access:

```typescript
// Unified service combining all repositories
export const memoryService = {
  users: UserMemoryRepository,      // User profiles, preferences, corrections
  projects: ProjectMemoryRepository, // Projects, knowledge base
  sessions: SessionMemoryRepository, // Session management
  episodes: EpisodicMemoryRepository, // Episode recording, similar episode search
  procedures: ProceduralMemoryRepository, // Procedure matching
  workflows: WorkflowMemoryRepository, // Workflow history

  // High-level methods
  initializeSession(userId, projectId),
  endSessionWithSummary(sessionId, summary, keyDecisions),
};
```

**Key Features:**
- Context loading: `loadUserContext()`, `loadProjectContext()`
- Episode recording with outcome tracking
- Preference learning from repeated usage
- Procedure matching via pattern search
- Memory consolidation (scoring episodes by importance)

### 3. Memory Integration Layer (`frontend/server/memory-integration.ts`)

Wraps the AI assistant to add memory capabilities:

```typescript
export class MemoryIntegration {
  // Initialize session with loaded context
  async initializeSession(userId, projectId): Promise<{session, context}>

  // Process message with memory enhancement
  async processWithMemory(message, context): Promise<MemoryEnhancedResponse>

  // Record workflow execution outcomes
  async recordOutcome(episodeId, outcome): Promise<void>

  // End session with summary
  async endSession(sessionId, summary, keyDecisions): Promise<Session>

  // Record user corrections for learning
  async recordCorrection(userId, sessionId, projectId, correction): Promise<void>
}
```

**Memory Enhancement Flow:**
1. Load user and project context at session start
2. Find matching procedures for current query
3. Get similar past episodes
4. Add memory hints to conversation context
5. Process with AI assistant
6. Record episode automatically
7. Learn from interaction (update preferences)

### 4. API Endpoints (`frontend/server/routes.ts`)

15+ new endpoints under `/api/memory/*`:

```
POST   /api/memory/users                    - Create/get user
GET    /api/memory/users/:userId/context    - Load user context
POST   /api/memory/users/:userId/preferences - Record preference
POST   /api/memory/users/:userId/corrections - Record correction

POST   /api/memory/projects                 - Create project
GET    /api/memory/projects/:projectId/context - Load project context
POST   /api/memory/projects/:projectId/knowledge - Add knowledge
GET    /api/memory/projects/:projectId/episodes - Get episodes
POST   /api/memory/projects/:projectId/procedures - Create procedure

POST   /api/memory/sessions                 - Create session
POST   /api/memory/sessions/:sessionId/end  - End session
POST   /api/memory/episodes                 - Record episode
PUT    /api/memory/episodes/:episodeId/outcome - Update outcome
```

### 5. Chat Integration

Modified `/api/chat` endpoint to use memory when available:

```typescript
// Uses memory integration if session/project context provided
const useMemory = memoryIntegration && (context?.memorySessionId || context?.projectId);
if (useMemory) {
  const memoryResponse = await memoryIntegration.processWithMemory(message, context);
  assistantResponse = memoryResponse;
  episodeId = memoryResponse.episodeId;
}
```

---

## Test Results

### Memory Repository Tests (13/13 passed)
```
1. Creating test LTM user...           ✓
2. Creating test project...            ✓
3. Creating session...                 ✓
4. Recording episode...                ✓
5. Updating episode outcome...         ✓
6. Recording user preference...        ✓
7. Loading user context...             ✓
8. Loading project context...          ✓
9. Adding project knowledge...         ✓
10. Creating procedure...              ✓
11. Finding matching procedures...     ✓
12. Getting similar episodes...        ✓
13. Ending session with summary...     ✓
```

### Memory Integration Tests (7/7 passed)
```
1. Setting up test data...             ✓
2. Initializing memory session...      ✓
3. Processing message with memory...   ✓
4. Recording episode outcome...        ✓
5. Building memory context prompt...   ✓
6. Processing second message...        ✓
7. Ending session...                   ✓
```

---

## Files Changed/Created

| File | Action | Lines |
|------|--------|-------|
| `frontend/shared/ltm-schema.ts` | Created | ~575 |
| `frontend/server/memory-repository.ts` | Created | ~600 |
| `frontend/server/memory-integration.ts` | Created | ~450 |
| `frontend/server/routes.ts` | Modified | +150 |
| `frontend/server/db.ts` | Modified | +10 |
| `frontend/drizzle.config.ts` | Modified | +5 |
| `frontend/shared/schema.ts` | Modified | +10 |
| `frontend/client/src/lib/projects.ts` | Modified | +100 |
| `frontend/test-memory.ts` | Created (test) | ~165 |
| `frontend/test-memory-integration.ts` | Created (test) | ~135 |

---

## Framework Analysis

### Currently Used Frameworks

**React 18.3.1** - Yes, used for the frontend UI
- Located in `frontend/client/src/`
- Uses Vite as build tool
- Component-based architecture with hooks

**Backend: Express.js + Custom AI Integration**
- Express for API routing
- Custom `GalaxyAssistant` class for AI interactions
- Direct Anthropic Claude API integration

### Agent Frameworks (LangChain, CrewAI) - NOT Currently Used

**Current Architecture Analysis:**

Looking at `GalaxyAssistant` (`server/galaxy-assistant.ts`), the current flow is **sequential**:

```
User Query
    ↓
1. analyzeIntent()          ← LLM call
    ↓
2. searchRelevantTools()    ← API + LLM ranking call
    ↓
3. searchRelevantDatasets() ← API + LLM ranking call
    ↓
4. analyzeWorkflowNeed()    ← Logic
    ↓
5. generateWorkflow()       ← Galaxy backend (parallel execution happens HERE)
    ↓
6. generateResponse()       ← LLM call
```

**The User's Valid Point:** Galaxy handles parallel *execution* of tools/jobs, but the *AI reasoning* is sequential. Steps 2 and 3 could run in parallel. A review step could validate workflows before execution.

### Why Not LangChain?

1. **Abstraction overhead** - Direct Claude API is simpler for our specific prompts
2. **Custom memory** - Our LTM system is bioinformatics-specific (episodic, procedural)
3. **Dependency weight** - LangChain brings many transitive dependencies
4. **Prompt control** - We need fine-grained prompt engineering for tool ranking

### Why Not CrewAI (Yet)?

1. **Current scope** - Single assistant handles intent→tools→workflow adequately
2. **Galaxy orchestration** - Parallel execution already handled by Galaxy
3. **Latency** - Multi-agent adds LLM round-trips

### When Multi-Agent WOULD Help

**Proposed Multi-Agent Architecture (Future Consideration):**

```
                    ┌─────────────────┐
                    │  Orchestrator   │
                    │    Agent        │
                    └────────┬────────┘
           ┌─────────────────┼─────────────────┐
           ↓                 ↓                 ↓
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   Planner    │  │   Reviewer   │  │  Researcher  │
    │    Agent     │  │    Agent     │  │    Agent     │
    │ (workflow    │  │ (validates   │  │ (queries DBs │
    │  design)     │  │  outputs)    │  │  in parallel)│
    └──────────────┘  └──────────────┘  └──────────────┘
```

**Existing Validation (Already Implemented):**

| Component | Location | What It Does |
|-----------|----------|--------------|
| `_validate_tool_ids()` | `galaxy_workflow_generator.py:544` | Ensures all tool IDs exist in Galaxy |
| `_validate_workflow_structure()` | `enhanced_workflow_generator.py:409` | Validates tools exist, finds alternatives |
| `DatasetValidator` | `dataset-validator.ts` | LLM validates datasets match workflow inputs |

**What's NOT Validated (Potential Multi-Agent Benefit):**

| Gap | Current | Multi-Agent Solution |
|-----|---------|---------------------|
| Scientific logic review | None - workflows may not make biological sense | Domain expert agent reviews scientific validity |
| Parameter optimization | Default parameters used | Parameter tuning agent optimizes for data type |
| Cross-step data flow | Basic connection | Data flow validator ensures output→input compatibility |
| Multi-omics coordination | Sequential | Parallel domain experts (genomics, proteomics, metabolomics) |
| Error recovery | Manual retry | Debugger agent analyzes failures, suggests fixes |

### Recommendation

**Current:** Continue with direct Claude API + custom memory (simpler, sufficient)

**Future:** Consider multi-agent when:
1. Users request complex multi-domain analyses (genomics + proteomics + metabolomics)
2. Workflow failure rates increase (add Reviewer agent)
3. Query latency becomes bottleneck (parallelize with Researcher agents)

**Implementation path if needed:**
1. Start with simple parallelization in `GalaxyAssistant` (no framework)
2. Add Reviewer agent as post-processing step
3. If complexity grows, evaluate CrewAI vs custom orchestration

---

## Multi-Agent Architecture (IMPLEMENTED)

**Status:** Complete - All 8 implementation steps done

### Overview

```
User Request
     │
     ▼
┌─────────────────────────────────┐
│  DomainRouter (NO LLM)          │  ← Fast keyword matching + user patterns
│  Routes to 1-3 domains          │
└─────────────────────────────────┘
     │
     ├──────────────────┬──────────────────┐
     ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Specialist 1 │  │ Specialist 2 │  │ Tool/Dataset │
│ (Primary)    │  │ (Secondary)  │  │ Search (RAG) │
│ [1 LLM]      │  │ [1 LLM]      │  │ [NO LLM]     │
└──────────────┘  └──────────────┘  └──────────────┘
     │                  │                  │
     └──────────────────┴──────────────────┘
                        │
                        ▼
┌─────────────────────────────────┐
│  WorkflowAssembler [1 LLM]      │  ← Merge + validate + cite
└─────────────────────────────────┘
```

### Agents

| Agent | Purpose | LLM Calls |
|-------|---------|-----------|
| **DomainRouter** | Route to 1-3 domains via keyword matching + user patterns | 0 (fast) |
| **DomainSpecialist** | Domain-specific tool selection and parameters | 1 per domain (parallel) |
| **WorkflowAssembler** | Merge recommendations, validate scientifically, add citations | 1 |

### Files Created

```
backend/lib/galaxy/ai/agents/
├── __init__.py              # Package exports
├── domain_router.py         # Agent 1: No LLM, keyword-based routing
├── domain_specialist.py     # Agent 2: Parallel LLM specialists
├── workflow_assembler.py    # Agent 3: Validate + cite
├── agent_orchestrator.py    # Coordinates all agents
└── test_agents.py           # Test script
```

### Files Modified

| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | Added Promise.all for parallel tool/dataset search |
| `backend/lib/galaxy/ai/ai_assistant.py` | Added `generate_workflow_multi_agent()` method |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Added `/api/ai_assistant/generate_workflow_multi_agent` endpoint |

### Test Results

```
=== Testing DomainRouter ===
Query: RNA-seq differential expression → transcriptomics (conf: 1.00)
Query: 10X single-cell RNA sequencing → single-cell (conf: 0.67)
Query: variant calling WGS → genomics (conf: 0.83)
All tests passed!
```

---

## TODOs and Future Work

### Immediate (Quick Wins)

0. **Parallelize AI Reasoning in GalaxyAssistant**
   - [ ] Run `searchRelevantTools()` and `searchRelevantDatasets()` in parallel with `Promise.all()`
   - [ ] Run `analyzeIntent()` concurrently with initial searches
   - Estimated improvement: 30-50% latency reduction
   - No framework needed, just refactor existing code

### High Priority

1. **Frontend UI for Memory**
   - [ ] Project memory panel in sidebar
   - [ ] Session history viewer
   - [ ] Knowledge base editor
   - [ ] Preference management UI

2. **Memory Consolidation Cron**
   - [ ] Scheduled job to consolidate old episodes
   - [ ] Extract patterns from successful workflows
   - [ ] Generate procedures from repeated patterns

3. **Vector Search Enhancement**
   - [ ] Install pgvector extension
   - [ ] Add embedding columns to episodes/knowledge
   - [ ] Implement semantic similarity search

### Medium Priority

4. **Mem0 Integration** (optional)
   - [ ] Evaluate Mem0 for graph-based knowledge representation
   - [ ] Consider for cross-project knowledge sharing

5. **Memory Export/Import**
   - [ ] Export project memory to JSON
   - [ ] Import knowledge from external sources
   - [ ] Backup/restore functionality

6. **Analytics Dashboard**
   - [ ] Memory usage statistics
   - [ ] Learning effectiveness metrics
   - [ ] Episode outcome analysis

### Low Priority

7. **Advanced Features**
   - [ ] Prospective memory (scheduled reminders)
   - [ ] Cross-user knowledge sharing (with consent)
   - [ ] Memory decay/forgetting curves

8. **Performance Optimization**
   - [ ] Cache frequently accessed context
   - [ ] Batch episode recording
   - [ ] Async memory operations

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        BioMate Frontend                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Chat UI     │  │ Project     │  │ Workflow Artifact       │ │
│  │ Component   │  │ Selector    │  │ Viewer                  │ │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘ │
└─────────┼────────────────┼─────────────────────┼───────────────┘
          │                │                     │
          ▼                ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Express.js API Server                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   Memory Integration Layer                   ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │ initSession() │  │ processWithMem│  │ recordOutcome() │ ││
│  │  └───────────────┘  └───────────────┘  └─────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Memory Repository                         ││
│  │  ┌────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌───────┐││
│  │  │ Users  │ │Projects │ │ Episodes │ │Procedures│ │Prefs  │││
│  │  └────────┘ └─────────┘ └──────────┘ └──────────┘ └───────┘││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   Galaxy Assistant                           ││
│  │  (AI Processing with Claude API)                             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                           │
│  ┌───────────┐ ┌───────────┐ ┌────────────┐ ┌────────────────┐ │
│  │ ltm_users │ │ projects  │ │  sessions  │ │ user_prefs     │ │
│  └───────────┘ └───────────┘ └────────────┘ └────────────────┘ │
│  ┌───────────┐ ┌───────────┐ ┌────────────┐ ┌────────────────┐ │
│  │ episodes  │ │ knowledge │ │ procedures │ │ correction_log │ │
│  └───────────┘ └───────────┘ └────────────┘ └────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Running Tests

```bash
# Run memory repository tests
cd frontend
npx tsx test-memory.ts

# Run memory integration tests
npx tsx test-memory-integration.ts
```

---

## Related Documents

- `20251220_AGENTIC_MEMORY_SURVEY_AND_PLAN.md` - Initial research and planning
- `LONG_TERM_MEMORY_ARCHITECTURE_20251031.md` - Prior architecture design (reused)
- `frontend/shared/ltm-schema.ts` - Database schema source
- `frontend/server/memory-repository.ts` - Repository implementation
- `frontend/server/memory-integration.ts` - AI integration layer
