# BioMate Phase B: ADJUSTED Implementation Plan
**Date**: November 3, 2025
**Status**: Based on Current Implementation Audit
**Key Finding**: Much more infrastructure exists than initially assumed!

---

## 🔍 Current Implementation Audit Summary

### ✅ What ALREADY EXISTS

#### 1. Session Management (Frontend)
**Files**:
- `frontend/client/src/lib/chat-history.ts`
- `frontend/server/redis-session.ts`

**Current State**:
```typescript
// ChatSession stored in localStorage
interface ChatSession {
  id: string;
  title: string;
  timestamp: Date;
  lastActivity: Date;
  messages: Message[];
  workflows: WorkflowStepWithDatasets[];
  datasets: DatasetConfig[];
  status: "active" | "archived";
}

// Redis used for Express auth sessions, NOT chat history
```

**What Works**:
- ✅ Sessions saved to localStorage automatically
- ✅ Message history preserved
- ✅ Workflows attached to sessions
- ✅ Datasets tracked per session
- ✅ Recent sessions list (up to 10)
- ✅ Auto-title generation from first message

**What's Missing**:
- ❌ Backend persistence (only localStorage, lost if cleared)
- ❌ Cross-device sync
- ❌ Token counting
- ❌ Context compression
- ❌ Checkpoints/restore points
- ❌ Key facts extraction

---

#### 2. Workflow Templates (Backend Python)
**File**: `backend/lib/galaxy/ai/workflow_templates.py`

**Current State**:
```python
class WorkflowTemplateLibrary:
    templates = {
        "rna_seq_differential_expression": {...},  # COMPLETE
        "variant_calling_pipeline": {...},          # COMPLETE
        "chip_seq_analysis": {...},                 # EXISTS
        # More templates...
    }
```

**What Works**:
- ✅ Human-verified templates for RNA-seq, variant calling, ChIP-seq
- ✅ Template metadata: difficulty, estimated time, input requirements
- ✅ Detailed workflow steps with tool IDs
- ✅ Parameter defaults
- ✅ nf-core workflows repository exists (`backend/nf-core-workflows/`)

**What's Missing**:
- ❌ Template selection logic based on user history
- ❌ Template adaptation based on data characteristics
- ❌ Success rate tracking per template
- ❌ User-specific template recommendations

---

#### 3. ACE Learning System (TypeScript - Frontend Server)
**Files**:
- `reference/ACE_BIOMATE_INTEGRATION_PLAN_20251030.md` (DESIGN)
- `frontend/server/galaxy-assistant.ts` (EXECUTION)
- `frontend/server/workflow-repository.ts` (TRACKING)

**Current State - Designed but NOT Implemented**:
```typescript
// PLANNED (not yet coded):
- PlaybookDatabase (stores learned rules)
- ACEReflector (analyzes failures)
- ACECurator (updates playbook)

// PARTIALLY EXISTS:
WorkflowRepository.recordUsage(templateId, success) {
  // Tracks: usage_count, success_rate, average_runtime
}
```

**What Works**:
- ✅ Design document complete
- ✅ Integration points identified
- ✅ Basic usage tracking (success/failure)

**What's Missing**:
- ❌ PlaybookDatabase implementation
- ❌ ACEReflector service
- ❌ ACECurator service
- ❌ Rule extraction from failures
- ❌ Learned rules injection into prompts

---

#### 4. User Behavioral Tracking (Backend SQLite)
**Files**:
- `backend/database/galaxy_ai_tools.db`
- `backend/migrations/004_behavioral_user_profile.sql`

**Current State**:
```sql
-- ALREADY APPLIED:
CREATE TABLE users (...);
CREATE TABLE user_interactions (...);  -- logs searches, tool selections
CREATE TABLE user_patterns (...);     -- inferred patterns with confidence
CREATE TABLE data_type_detections (...);
CREATE TABLE context_inferences (...);

-- Test data exists with proteomics user patterns at 95% confidence
```

**What Works**:
- ✅ Database tables created
- ✅ Test data showing pattern inference works
- ✅ User interaction logging schema ready

**What's Missing**:
- ❌ API endpoints to write interactions
- ❌ Automatic pattern inference code
- ❌ Integration with frontend chat interface
- ❌ Real-time confidence updates

---

#### 5. Galaxy API Integration (Backend Python)
**Files**:
- `backend/lib/galaxy/webapps/galaxy/api/chat.py` (MINIMAL)
- `backend/lib/galaxy/webapps/galaxy/api/workflows.py` (COMPLETE)
- `backend/lib/galaxy/ai/enhanced_tool_search.py` (COMPLETE)

**Current State**:
```python
# chat.py - VERY BASIC (job-based chat only)
@router.post("/api/chat")
def query(job_id, payload):
    # Currently only supports job error explanations
    # No session management, no history, no context

# enhanced_tool_search.py - FULLY FUNCTIONAL
def search_tools(query, filters, user_context):
    # Uses scientific_context + nfcore_metadata
    # 7-factor scoring algorithm
    # READY FOR INTEGRATION
```

**What Works**:
- ✅ Enhanced tool search with dual metadata
- ✅ Workflow API complete
- ✅ Tool installation automation

**What's Missing**:
- ❌ Proper chat API with session support
- ❌ Context injection from user_patterns
- ❌ Agent invocation logic
- ❌ Thinking mode support
- ❌ Token monitoring

---

## 🎯 Key Architecture Insight

**Current Architecture is Hybrid**:
```
┌────────────────────────────────────────────────┐
│         Frontend (TypeScript/React)            │
│  - Chat UI                                     │
│  - LocalStorage session management             │
│  - Message rendering                           │
└──────────────────┬─────────────────────────────┘
                   │
                   ▼ HTTP/SSE
┌────────────────────────────────────────────────┐
│      Frontend Server (TypeScript/Node)         │
│  - galaxy-assistant.ts (main logic)            │
│  - workflow-sse.ts (real-time updates)         │
│  - ACE services (TO BE IMPLEMENTED)            │
└──────────────────┬─────────────────────────────┘
                   │
                   ▼ Galaxy API calls
┌────────────────────────────────────────────────┐
│        Backend Galaxy (Python/FastAPI)         │
│  - /api/chat (minimal, needs enhancement)      │
│  - /api/workflows (complete)                   │
│  - /api/tool_search/enhanced (ready)           │
│  - User behavior DB (ready but not integrated) │
└────────────────────────────────────────────────┘
```

**Implication**:
- Phase B features need to span BOTH TypeScript (frontend server) AND Python (backend)
- Some features like ACE are better in TypeScript (already designed there)
- Some features like user patterns are better in Python (database access)

---

## 📋 ADJUSTED Phase B Plan

### What to BUILD (Not Duplicate)

#### Priority 1: Backend Persistence for Sessions (NEW)
**Why**: LocalStorage is not enough for production

**Implementation**:
- Extend Galaxy Python `/api/chat` endpoint
- Create session persistence in SQLite (NOT localStorage)
- Sync localStorage to backend on every message

```python
# backend/lib/galaxy/webapps/galaxy/api/chat.py
@router.post("/api/chat/session")
def create_or_update_session(
    session_id: str,
    messages: List[Message],
    workflows: List[Workflow],
    datasets: List[Dataset]
):
    # Persist to SQLite
    # Return session_id for frontend
```

---

#### Priority 2: Context Compression (NEW)
**Where**: TypeScript frontend server (has access to message history)

**Implementation**:
```typescript
// frontend/server/context-compressor.ts
class ContextCompressor {
  async compressSession(sessionId: string): Promise<CompressedContext> {
    const session = chatHistoryService.getSession(sessionId);

    // Use Claude to summarize old messages
    const summary = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      messages: [{
        role: 'user',
        content: `Summarize this conversation, preserving:
          - User's research goals
          - Tool selections and reasoning
          - Data types discussed
          - Workflow decisions

          ${JSON.stringify(session.messages.slice(0, -3))}`
      }]
    });

    // Keep recent 3 messages + summary
    return {
      summary: summary.content[0].text,
      recentMessages: session.messages.slice(-3)
    };
  }
}
```

---

#### Priority 3: User Pattern Integration (CONNECT EXISTING)
**Where**: Bridge TypeScript frontend server → Python backend DB

**Implementation**:
```typescript
// frontend/server/galaxy-assistant.ts

// BEFORE (current):
async searchRelevantTools(query: string, filters: any) {
  // No user context
  return await galaxyAPI.post('/api/tool_search/enhanced', {
    query,
    filters
  });
}

// AFTER (with patterns):
async searchRelevantTools(query: string, filters: any, userId: string) {
  // Fetch user patterns from Python backend
  const patterns = await galaxyAPI.get(`/api/users/${userId}/patterns`);

  // Inject into search
  return await galaxyAPI.post('/api/tool_search/enhanced', {
    query,
    filters,
    user_context: {
      domain_preference: patterns.domain,
      preferred_tools: patterns.tools,
      complexity_level: patterns.complexity
    }
  });
}
```

---

#### Priority 4: Thinking Mode (NEW)
**Where**: TypeScript frontend server (already calls Claude)

**Implementation**:
```typescript
// frontend/server/thinking-detector.ts
class ThinkingDetector {
  shouldThink(query: string): string | null {
    const thinkingKeywords = {
      ultra: ['深度分析', 'comprehensive analysis'],
      mega: ['好好思考', 'thorough analysis'],
      hard: ['再想想', 'think carefully'],
      normal: ['想想', 'think', 'analyze', 'compare', 'which tool should']
    };

    for (const [level, keywords] of Object.entries(thinkingKeywords)) {
      if (keywords.some(kw => query.toLowerCase().includes(kw))) {
        return level;
      }
    }

    return null;
  }
}

// In galaxy-assistant.ts:
async processMessage(query: string) {
  const thinkingLevel = thinkingDetector.shouldThink(query);

  if (thinkingLevel) {
    const response = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      system: `You are a bioinformatics expert. Use explicit reasoning:

        <thinking>
        [Your step-by-step reasoning]
        </thinking>

        <answer>
        [Your final answer]
        </answer>`,
      messages: [{role: 'user', content: query}]
    });

    // Parse and return thinking + answer separately
    return {
      thinking: extractTag(response, 'thinking'),
      answer: extractTag(response, 'answer'),
      thinkingLevel
    };
  }

  // Normal flow
  return await this.normalProcessing(query);
}
```

---

#### Priority 5: ACE Playbook Implementation (FINISH DESIGN)
**Where**: TypeScript frontend server (already designed there)

**Status**: Design complete, just needs coding

**Files to Create**:
```
frontend/server/
├── playbook-database.ts      (NEW - store learned rules)
├── ace-reflector.ts           (NEW - analyze failures)
├── ace-curator.ts             (NEW - update playbook)
└── galaxy-assistant.ts        (MODIFY - inject playbook rules)
```

**Implementation**: Follow existing design in `ACE_BIOMATE_INTEGRATION_PLAN_20251030.md`

---

#### Priority 6: Hooks System (FORMALIZE EXISTING)
**Where**: TypeScript frontend server

**Current State**: Workflow tracking exists but not formalized

```typescript
// CURRENT (workflow-repository.ts):
recordUsage(templateId: string, success: boolean) {
  // Updates usage_count, success_rate
}

// ENHANCED (with hooks):
class HooksService {
  private hooks = {
    PreToolSearch: [],
    PostToolSearch: [],
    PreWorkflowExecution: [],
    PostWorkflowExecution: [],
    OnWorkflowFailure: []
  };

  async trigger(hookType: string, data: any) {
    const hooks = this.hooks[hookType] || [];
    for (const hook of hooks) {
      await hook.execute(data);
    }
  }
}

// Register hooks:
hooksService.register('PostWorkflowExecution', async (data) => {
  // Log to user_interactions
  await galaxyAPI.post('/api/users/interactions', {
    user_id: data.userId,
    interaction_type: 'workflow_run',
    workflow_id: data.workflowId,
    workflow_success: data.success ? 1 : 0
  });

  // Update user patterns
  if (data.success) {
    await galaxyAPI.post('/api/users/patterns/update', {
      user_id: data.userId,
      pattern_type: 'workflow_preference',
      workflow_id: data.workflowId
    });
  }
});
```

---

## 🗺️ Revised Implementation Roadmap

### Week 1: Bridge Existing Systems

**Day 1-2**: Backend Session Persistence
- [ ] Extend `/api/chat` endpoint in Galaxy Python
- [ ] Create SQLite tables for chat sessions
- [ ] Sync localStorage → backend on every message
- [ ] Test session save/restore

**Day 3**: User Pattern Integration
- [ ] Create `/api/users/{id}/patterns` endpoint (Python)
- [ ] Modify `galaxy-assistant.ts` to fetch patterns
- [ ] Inject patterns into tool search
- [ ] Test personalized recommendations

**Day 4-5**: Token Monitoring & Compression
- [ ] Add token counting to TypeScript chat service
- [ ] Implement context compression with Claude
- [ ] Add UI dialog for compression choice
- [ ] Test compression at 160k tokens

---

### Week 2: Autonomous Features

**Day 6-7**: Thinking Mode
- [ ] Implement `ThinkingDetector` class
- [ ] Modify Claude prompts for thinking mode
- [ ] Add frontend UI for showing/hiding thinking
- [ ] Test with complex bioinformatics questions

**Day 8-9**: Hooks System
- [ ] Create `HooksService` class
- [ ] Formalize existing workflow tracking as hooks
- [ ] Add PreToolSearch, PostToolSearch hooks
- [ ] Integrate with user_interactions logging

**Day 10**: Integration Testing
- [ ] Test full flow: query → patterns → thinking → hooks
- [ ] Performance testing
- [ ] Bug fixes

---

### Week 3: ACE Learning System

**Day 11-13**: ACE Implementation
- [ ] Implement `PlaybookDatabase` (follow existing design)
- [ ] Implement `ACEReflector` (failure analysis)
- [ ] Implement `ACECurator` (rule updates)
- [ ] Test learning loop

**Day 14-15**: ACE Integration
- [ ] Inject playbook rules into tool search
- [ ] Connect workflow failures to ACEReflector
- [ ] Test rule learning from real failures
- [ ] Measure improvement in tool selection accuracy

---

### Week 4: Polish & Testing

**Day 16-18**: End-to-End Testing
- [ ] User journey tests
- [ ] Performance optimization
- [ ] Bug fixes

**Day 19-20**: Documentation & Deployment
- [ ] API documentation
- [ ] User guide
- [ ] Deployment checklist

---

## ✂️ What to CUT from Original Plan

### ❌ DON'T Build (Already Exists)

1. **Session Management** - Already exists in localStorage, just needs backend persistence
2. **Workflow Templates** - Already exist in `workflow_templates.py` and nf-core repo
3. **User Behavior Database** - Already created and has test data
4. **Enhanced Tool Search** - Already complete and working

### ❌ DON'T Build (Lower Priority)

1. **Image Processing** - Nice-to-have, defer to Phase D
2. **Agent System** - Current architecture doesn't need this (ACE is sufficient)
3. **File Detection** - Frontend already handles file uploads

---

## 🎯 Success Metrics (ADJUSTED)

### Week 1 Success
- ✅ Sessions persist to backend (not just localStorage)
- ✅ User patterns correctly injected into searches
- ✅ Context compression working at 160k tokens
- ✅ Token count displayed in UI

### Week 2 Success
- ✅ Thinking mode shows reasoning for complex questions
- ✅ Hooks automatically log interactions to database
- ✅ User patterns update after every workflow execution
- ✅ No performance degradation

### Week 3 Success
- ✅ ACE learns from workflow failures
- ✅ Playbook rules prevent repeated mistakes
- ✅ Measurable improvement in tool selection accuracy (+4-10%)
- ✅ ACE updates visible in admin dashboard

### Week 4 Success
- ✅ All tests passing
- ✅ Documentation complete
- ✅ Ready for production deployment

---

## 🔑 Key Takeaways

1. **Don't reinvent the wheel** - Use existing `chat-history.ts`, `workflow_templates.py`, `enhanced_tool_search.py`
2. **Follow existing architecture** - ACE in TypeScript (frontend server), user patterns in Python (backend)
3. **Bridge the systems** - Focus on connecting TypeScript ↔ Python rather than rewriting
4. **Leverage existing designs** - ACE integration plan is already complete, just implement it
5. **Smaller scope** - 4 weeks instead of 6 weeks because infrastructure exists

---

## 📁 Updated File Manifest

### Files to CREATE
```
backend/lib/galaxy/webapps/galaxy/api/
├── chat.py                    (EXTEND - add session endpoints)
└── user_patterns.py           (CREATE - expose patterns API)

backend/migrations/
└── 005_chat_sessions.sql      (CREATE - persist chat sessions)

frontend/server/
├── context-compressor.ts      (CREATE)
├── thinking-detector.ts       (CREATE)
├── hooks-service.ts           (CREATE)
├── playbook-database.ts       (CREATE - implement ACE design)
├── ace-reflector.ts           (CREATE - implement ACE design)
├── ace-curator.ts             (CREATE - implement ACE design)
└── galaxy-assistant.ts        (MODIFY - integrate all services)

frontend/client/src/components/
├── thinking-display.tsx       (CREATE)
├── compression-dialog.tsx     (CREATE)
└── chat-interface.tsx         (MODIFY - add thinking + compression UI)
```

### Files to MODIFY
```
frontend/server/galaxy-assistant.ts  (integrate patterns, thinking, ACE)
frontend/client/src/lib/chat-history.ts  (add backend sync)
backend/lib/galaxy/webapps/galaxy/api/chat.py  (extend endpoints)
```

### Files to USE AS-IS
```
backend/lib/galaxy/ai/workflow_templates.py    (complete ✅)
backend/lib/galaxy/ai/enhanced_tool_search.py  (complete ✅)
backend/migrations/004_behavioral_user_profile.sql  (applied ✅)
frontend/client/src/lib/chat-history.ts  (working ✅)
```

---

## 🚀 Next Steps

1. ✅ Review this adjusted plan
2. ✅ Confirm architecture decisions (TypeScript vs Python placement)
3. ✅ Start Week 1 Day 1: Backend session persistence
4. Track progress with daily standups

**This plan is realistic, builds on existing work, and delivers in 4 weeks!** 🎯
