# BioMate System Audit and Improvement Plan

**Priority**: Get system online ASAP
**Created**: January 12, 2026
**Status**: Active

---

## Executive Summary

BioMate is a large system with many modules that need systematic audit and integration verification. This plan provides a structured approach to:

1. **Audit** each module for completeness and functionality
2. **Validate** connections between modules
3. **Test** use cases end-to-end
4. **Fix** critical issues preventing production deployment

---

## System Health Overview

### Module Status Summary

| Module | Completeness | Critical Issues | Priority |
|--------|--------------|-----------------|----------|
| Frontend Client | 70% | OAuth incomplete, payment flow missing | HIGH |
| Frontend Server | 75% | Routes integration gaps, missing tests | CRITICAL |
| Backend AI Assistant | 85% | Conditional imports, error handling | MEDIUM |
| Database/LTM | 80% | Memory sync untested | HIGH |
| Authentication | 85% | OAuth providers incomplete | HIGH |
| Galaxy Integration | 75% | Tool execution errors | CRITICAL |
| **Galaxy Features** | **30%** | **Notifications, Teams NOT USED** | **CRITICAL** |
| Payment (Stripe) | 40% | Not implemented | MEDIUM |
| Auto-Update | 95% | Cron not installed | LOW |

### Galaxy Integration Gap Summary

**BioMate is using only ~30% of Galaxy's mature capabilities:**
- Workflow Notifications: **NOT IMPLEMENTED** (Galaxy has full email/webhook/browser)
- Team Management: **NOT USED** (Galaxy has groups, RBAC, permissions)
- Interactive Tools: **NOT USED** (Galaxy has Jupyter, RStudio, VS Code)
- Data Libraries: **NOT USED** (Galaxy has shared repositories)
- Visualizations: **NOT USED** (Galaxy has plugin-based system)
- Quotas: **NOT USED** (Galaxy has user/group limits)

**See `docs/03-api/20260113_GALAXY_CAPABILITIES_ANALYSIS.md` for full details.**

### Critical Path to Production

```
Week 1: Core Functionality
├── Fix Galaxy API integration errors
├── Verify chat → workflow → execution flow
└── Test authentication (email/password)

Week 2: Integration Testing
├── End-to-end workflow execution tests
├── Memory persistence verification
└── Error handling validation

Week 3: Polish & Deploy
├── Fix remaining UI issues
├── Performance optimization
└── Production deployment
```

---

## PHASE 1: MODULE-BY-MODULE AUDIT

### 1.1 Frontend Server (CRITICAL)

**Location**: `frontend/server/`

#### Files to Audit

| File | Priority | Purpose | Status |
|------|----------|---------|--------|
| `routes.ts` | CRITICAL | All API endpoints | Review all routes |
| `galaxy-api-proxy.ts` | CRITICAL | Galaxy communication | Verify all methods |
| `galaxy-assistant.ts` | CRITICAL | AI chat integration | Test chat flow |
| `auth-service.ts` | HIGH | User authentication | Test login/register |
| `workflow-sse.ts` | HIGH | Real-time updates | Test polling |
| `db.ts` | HIGH | Database connection | Verify schema |
| `storage.ts` | MEDIUM | Data persistence | Check interface |

#### Audit Checklist for `routes.ts`

```
[ ] POST /api/chat - Chat endpoint working?
[ ] POST /api/workflows/invoke - Workflow execution?
[ ] GET /api/workflows/:id/status - Status polling?
[ ] POST /api/auth/login - Login working?
[ ] POST /api/auth/register - Registration working?
[ ] GET /api/tools/search - Tool search?
[ ] POST /api/datasets/upload - File upload?
[ ] GET /api/projects - Project listing?
```

#### Audit Checklist for `galaxy-api-proxy.ts`

```
[ ] searchTools() - Returns valid tool list?
[ ] getToolSchema() - Returns tool parameters?
[ ] invokeWorkflow() - Creates Galaxy invocation?
[ ] getInvocationStatus() - Returns status correctly?
[ ] uploadDataset() - Uploads to Galaxy history?
[ ] getDatasetInfo() - Retrieves dataset metadata?
```

#### Known Issues to Fix

1. **Route handler errors** - Many routes may have incomplete error handling
2. **Galaxy URL configuration** - Verify `GALAXY_URL` is correct
3. **API key validation** - Test with valid Galaxy API key
4. **Session persistence** - Check Redis/memory fallback works

---

### 1.2 Backend AI Module (HIGH)

**Location**: `backend/lib/galaxy/ai/`

#### Files to Audit

| File | Priority | Purpose | Status |
|------|----------|---------|--------|
| `ai_assistant.py` | CRITICAL | Main orchestrator | Verify imports |
| `llm_client.py` | CRITICAL | LLM communication | Test API calls |
| `galaxy_workflow_generator.py` | HIGH | Workflow creation | Test generation |
| `tool_discovery.py` | HIGH | Tool search | Verify index |
| `config.py` | HIGH | Configuration | Check env vars |
| `agents/agent_orchestrator.py` | MEDIUM | Multi-agent | Test routing |

#### Audit Checklist for `ai_assistant.py`

```
[ ] Module imports successfully?
[ ] Intent parsing working?
[ ] Tool search integration?
[ ] Workflow generation pipeline?
[ ] Error handling for missing components?
[ ] Memory service connection?
```

#### Audit Checklist for `llm_client.py`

```
[ ] Anthropic API connection?
[ ] Token counting accurate?
[ ] Error handling for API failures?
[ ] Streaming responses working?
[ ] Fallback to other providers?
```

#### Known Issues to Fix

1. **Conditional imports** - Many components loaded conditionally (may fail silently)
2. **320 try/except blocks** - Review for overly broad exception handling
3. **Database connection** - Verify PostgreSQL URL for memory service
4. **Tool index** - Ensure 2,177 tools are properly indexed

---

### 1.3 Frontend Client (HIGH)

**Location**: `frontend/client/src/`

#### Files to Audit

| File | Priority | Purpose | Status |
|------|----------|---------|--------|
| `components/chat-interface.tsx` | CRITICAL | Main chat UI | Test interactions |
| `components/workflow-artifact.tsx` | HIGH | Workflow display | Test rendering |
| `hooks/useWorkflowExecution.ts` | HIGH | Execution state | Test SSE |
| `lib/api.ts` | HIGH | API client | Verify endpoints |
| `contexts/auth-context.tsx` | HIGH | Auth state | Test flows |

#### Audit Checklist for Chat Interface

```
[ ] Message sending works?
[ ] Response rendering correct?
[ ] Workflow artifacts display?
[ ] Parameter dialog opens?
[ ] Run button triggers execution?
[ ] Error messages shown?
```

#### Known Issues to Fix

1. **BASE_URL configuration** - Check `lib/api.ts` for production URL
2. **Token counting** - Server-side token counter not integrated
3. **OAuth buttons** - Google/GitHub login incomplete
4. **File upload** - Dataset upload UI incomplete

---

### 1.4 Database & Memory (HIGH)

**Location**: `frontend/shared/schema.ts`, `frontend/shared/ltm-schema.ts`

#### Audit Checklist

```
[ ] PostgreSQL connection working?
[ ] Drizzle migrations applied?
[ ] Users table accessible?
[ ] Sessions persisted correctly?
[ ] LTM tables created?
[ ] Foreign key constraints valid?
```

#### Schema Verification Commands

```bash
# Check database connection
npx drizzle-kit studio

# Run migrations
npx drizzle-kit push:pg

# Verify tables exist
psql $DATABASE_URL -c "\dt"
```

---

### 1.5 Authentication (HIGH)

**Location**: `frontend/server/auth-service.ts`, `frontend/server/auth-middleware.ts`

#### Audit Checklist

```
[ ] User registration creates user?
[ ] Password hashing (bcrypt 12 rounds)?
[ ] JWT token generation?
[ ] Token validation middleware?
[ ] Session cookie setting?
[ ] Email verification working?
[ ] Password reset flow?
```

#### Test Commands

```bash
# Test registration
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123","fullName":"Test User"}'

# Test login
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

---

## PHASE 2: CONNECTION VALIDATION

### 2.1 Frontend → Frontend Server

| Connection | Test Method | Expected Result |
|------------|-------------|-----------------|
| Chat API | Send message | Get AI response |
| Auth API | Login | Get JWT token |
| Workflow API | Invoke | Get invocation ID |
| Tool Search | Query | Get tool list |
| Dataset Upload | Upload file | Get dataset ID |

#### Test Script for Chat Flow

```javascript
// Test: frontend/client → frontend/server → backend AI
async function testChatFlow() {
  const response = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: 'What tools are available for RNA-seq analysis?',
      sessionId: 'test-session'
    })
  });

  const data = await response.json();
  console.log('Chat response:', data);

  // Verify response structure
  assert(data.message, 'Response should have message');
  assert(data.toolSuggestions || data.workflowSuggestion, 'Should have suggestions');
}
```

---

### 2.2 Frontend Server → Backend Python

| Connection | Test Method | Expected Result |
|------------|-------------|-----------------|
| AI Assistant API | HTTP call | Workflow generation |
| Tool Search API | Query | Tool metadata |
| Galaxy Proxy | API call | Galaxy response |
| Memory Service | Save/Load | Persistence |

#### Test Script for Backend Integration

```python
# Test: frontend server → backend AI
import requests

def test_backend_integration():
    # Test AI assistant endpoint
    response = requests.post(
        'http://localhost:8080/api/ai/assistant',
        json={
            'query': 'Analyze RNA-seq data',
            'user_id': 'test-user',
            'project_id': 'test-project'
        }
    )

    assert response.status_code == 200
    data = response.json()
    assert 'workflow' in data or 'message' in data
```

---

### 2.3 Frontend Server → Galaxy

| Connection | Test Method | Expected Result |
|------------|-------------|-----------------|
| Tool List | GET /api/tools | 2,177+ tools |
| Workflow Invoke | POST /api/workflows | Invocation ID |
| Status Poll | GET /api/invocations/:id | Status object |
| History | GET /api/histories | History list |
| Dataset | GET /api/datasets/:id | Dataset info |

#### Galaxy Integration Test

```bash
# Test Galaxy connectivity
curl -X GET "http://localhost:8080/api/tools?key=$GALAXY_API_KEY"

# Test tool search
curl -X GET "http://localhost:8080/api/tools?q=fastqc&key=$GALAXY_API_KEY"

# Test workflow invocation
curl -X POST "http://localhost:8080/api/workflows/$WORKFLOW_ID/invocations" \
  -H "Content-Type: application/json" \
  -d '{"inputs": {}}'
```

---

### 2.4 Database Connections

| Connection | Test Method | Expected Result |
|------------|-------------|-----------------|
| PostgreSQL | Query | Data returned |
| Redis | Set/Get | Value stored |
| SQLite (fallback) | Query | Data returned |
| LTM Tables | CRUD ops | Success |

#### Database Connection Test

```typescript
// Test database connectivity
import { db } from './db';
import { users } from '../shared/schema';

async function testDatabaseConnection() {
  try {
    const result = await db.select().from(users).limit(1);
    console.log('Database connection OK');
    return true;
  } catch (error) {
    console.error('Database connection FAILED:', error);
    return false;
  }
}
```

---

## PHASE 3: USE CASE TESTING

### 3.1 Critical Use Cases (Must Work for Launch)

#### UC1: User Registration & Login

```
Steps:
1. Navigate to /register
2. Fill registration form
3. Submit form
4. Verify email (or skip for testing)
5. Login with credentials
6. Verify dashboard access

Expected:
- User created in database
- JWT token issued
- Session established
- Dashboard loads
```

#### UC2: Basic Chat Interaction

```
Steps:
1. Login as user
2. Navigate to chat interface
3. Send message: "What tools are available for quality control?"
4. Wait for response
5. Verify tool suggestions appear

Expected:
- AI responds within 10 seconds
- Tool suggestions displayed
- No error messages
```

#### UC3: Workflow Generation

```
Steps:
1. Send message: "Create a workflow for RNA-seq analysis"
2. Wait for workflow suggestion
3. Verify workflow artifact displays
4. Click "View Details" button

Expected:
- Workflow JSON generated
- Artifact UI renders
- Steps visible
- Parameters editable
```

#### UC4: Workflow Execution

```
Steps:
1. Generate workflow from UC3
2. Click "Run" button
3. Select input datasets (or use sample)
4. Start execution
5. Monitor progress via SSE
6. Wait for completion

Expected:
- Invocation created in Galaxy
- Progress updates in real-time
- Completion status shown
- Output datasets accessible
```

---

### 3.2 Secondary Use Cases (Should Work)

#### UC5: Project Management

```
Steps:
1. Create new project
2. Add description and tags
3. Save project
4. Navigate to project list
5. Verify project appears

Expected:
- Project saved to database
- List displays correctly
- Can navigate to project detail
```

#### UC6: Tool Search

```
Steps:
1. Navigate to tool search
2. Enter search term: "alignment"
3. Filter by category
4. View tool details

Expected:
- Search returns relevant tools
- Filter works correctly
- Tool details display
```

#### UC7: Workflow History

```
Steps:
1. Run multiple workflows
2. Navigate to history panel
3. View past executions
4. Check status of each

Expected:
- All executions listed
- Status accurate
- Can view details
```

---

### 3.3 Edge Cases (Should Handle Gracefully)

```
EC1: Invalid API key → Should show clear error message
EC2: Galaxy unavailable → Should show maintenance message
EC3: LLM timeout → Should retry or show timeout message
EC4: Invalid workflow → Should show validation errors
EC5: Large file upload → Should show progress
EC6: Session expiry → Should redirect to login
EC7: Rate limiting → Should show retry message
```

---

## PHASE 4: SYSTEMATIC FIXES

### 4.1 Critical Fixes (Week 1)

| Issue | File | Fix |
|-------|------|-----|
| Galaxy API errors | `galaxy-api-proxy.ts` | Add retry logic, better error messages |
| Chat not responding | `galaxy-assistant.ts` | Verify LLM connection, add timeout |
| Auth token issues | `auth-middleware.ts` | Fix token validation, check expiry |
| Database connection | `db.ts` | Add connection pooling, error handling |
| SSE disconnects | `workflow-sse.ts` | Add reconnection logic |

### 4.2 High Priority Fixes (Week 2)

| Issue | File | Fix |
|-------|------|-----|
| Memory not persisting | `ltm-schema.ts` | Verify migrations, test CRUD |
| Tool search slow | `tool_discovery.py` | Add caching, optimize queries |
| Workflow validation | `workflow_validator.py` | Add comprehensive checks |
| UI error states | `chat-interface.tsx` | Add error boundaries, messages |
| Session management | `redis-session.ts` | Test Redis connection, fallback |

### 4.3 Medium Priority Fixes (Week 3)

| Issue | File | Fix |
|-------|------|-----|
| OAuth incomplete | `oauth-service.ts` | Complete Google/GitHub flows |
| Payment not working | `stripe-service.ts` | Implement checkout flow |
| File upload | `routes.ts` | Complete upload to Galaxy |
| Email service | `email-service.ts` | Configure SMTP, test emails |
| Rate limiting | `rate-limit.ts` | Configure appropriate limits |

---

## PHASE 4B: GALAXY INTEGRATION OPPORTUNITIES

**Reference**: `docs/03-api/20260113_GALAXY_CAPABILITIES_ANALYSIS.md`

Galaxy is a mature, multi-year platform with capabilities BioMate is underutilizing (~30% usage). This section identifies high-value integrations.

### 4B.1 Critical Missing Integrations

| Feature | Galaxy Has | BioMate Has | Impact | Effort |
|---------|-----------|-------------|--------|--------|
| **Workflow Notifications** | Full email/webhook/browser | NONE | HIGH | LOW |
| **Team Management** | Groups, RBAC, permissions | Only "organization" text field | HIGH | MEDIUM |
| **Interactive Tools** | Jupyter, RStudio, VS Code | NOT USED | HIGH | HIGH |
| **Data Libraries** | Shared data repositories | NOT USED | MEDIUM | MEDIUM |
| **Visualizations** | Plugin-based charts/genome browser | NOT USED | MEDIUM | HIGH |
| **Quotas** | User/group resource limits | NOT USED | MEDIUM | MEDIUM |

### 4B.2 Workflow Notifications - CRITICAL GAP

**Current State**: `email-service.ts` only handles:
- `sendVerificationEmail()`
- `sendPasswordResetEmail()`
- `sendWelcomeEmail()`

**Missing**: No `sendWorkflowCompletedEmail()` or `sendWorkflowErrorEmail()`

**Fix Required**:

```typescript
// Add to email-service.ts
async sendWorkflowCompletedEmail(
  email: string, userName: string, workflowName: string,
  invocationId: string, outputsUrl: string
): Promise<boolean>

async sendWorkflowErrorEmail(
  email: string, userName: string, workflowName: string,
  invocationId: string, errorMessage: string
): Promise<boolean>

// Connect to galaxy-state-poller.ts
this.on('workflow_completed', async (data) => {
  await emailService.sendWorkflowCompletedEmail(...);
});
```

**User Preference Fields** (add to schema.ts):
```typescript
notifyOnCompletion: boolean("notify_on_completion").default(true),
notifyOnError: boolean("notify_on_error").default(true),
```

### 4B.3 Team Management - CRITICAL GAP

**Current State**: `schema.ts` only has `organization: text("organization")` - a plain text field

**Galaxy Has**:
- `managers/groups.py` - Full group CRUD
- `managers/roles.py` - Role-based access control
- `api/groups.py` - REST endpoints for team management

**Fix Required**:

```typescript
// Add to schema.ts
export const teams = pgTable("teams", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  galaxyGroupId: text("galaxy_group_id"),  // Link to Galaxy group
  createdAt: timestamp("created_at").defaultNow(),
});

export const teamMembers = pgTable("team_members", {
  id: serial("id").primaryKey(),
  teamId: integer("team_id").references(() => teams.id),
  userId: integer("user_id").references(() => users.id),
  role: text("role").default("member"),  // owner, admin, member
});
```

**Galaxy API Endpoints to Use**:
- `POST /api/groups` - Create team
- `PUT /api/groups/{id}/users/{user_id}` - Add member
- `DELETE /api/groups/{id}/users/{user_id}` - Remove member

### 4B.4 Concurrent Workflow Management - WORKING

**Good News**: `galaxy-state-poller.ts` properly manages multiple concurrent workflows:
- Uses `Map<string, InvocationPoller>` for tracking
- 2-second polling interval
- Emits state change events
- SSE streaming to browser

**Gap**: No email notification on completion/error (see 4B.2)

### 4B.5 Galaxy Features to Consider for Phase 2

| Feature | Galaxy Endpoint | Use Case |
|---------|----------------|----------|
| Interactive Jupyter | `/api/entry_points` | Result exploration |
| Data Libraries | `/api/libraries` | Shared reference data |
| Visualizations | `/api/visualizations` | Genome browser, charts |
| Quotas | `/api/quotas` | Subscription tier limits |
| Webhooks | `/api/notifications` | Third-party integrations |

### 4B.6 Integration Priority for Launch

**Week 1 (Must Have)**:
1. Add workflow notification emails (low effort, high impact)
2. Add user notification preferences

**Week 2 (Should Have)**:
1. Add team tables to schema
2. Create Galaxy group sync
3. Basic team sharing for workflows

**Post-Launch**:
1. Interactive tools integration
2. Data library integration
3. Visualization plugins

---

## PHASE 5: TESTING STRATEGY

### 5.1 Test Categories

| Category | Current | Target | Priority |
|----------|---------|--------|----------|
| Unit Tests | 40% | 80% | HIGH |
| Integration Tests | 10% | 60% | CRITICAL |
| E2E Tests | 5% | 40% | HIGH |
| Performance Tests | 0% | 20% | MEDIUM |

### 5.2 Test Files to Create

```
frontend/server/
├── __tests__/
│   ├── routes.test.ts        # API endpoint tests
│   ├── galaxy-api.test.ts    # Galaxy integration
│   ├── chat-flow.test.ts     # Chat E2E tests
│   └── auth-flow.test.ts     # Auth E2E tests

backend/lib/galaxy/ai/
├── tests/
│   ├── test_ai_assistant.py  # AI module tests
│   ├── test_workflow_gen.py  # Workflow generation
│   └── test_tool_search.py   # Tool search tests
```

### 5.3 Test Running Commands

```bash
# Frontend tests
cd frontend && npm run test

# Backend tests
cd backend && python -m pytest lib/galaxy/ai/tests/

# E2E tests (Playwright)
cd frontend && npx playwright test

# Coverage report
cd frontend && npm run test:coverage
```

---

## EXECUTION TIMELINE

### Week 1: Core Functionality (Days 1-7)

| Day | Focus | Tasks |
|-----|-------|-------|
| 1 | Galaxy Connection | Fix API proxy, test connectivity |
| 2 | Chat Flow | Fix LLM integration, test responses |
| 3 | Authentication | Fix login/register, test sessions |
| 4 | Database | Verify migrations, test CRUD |
| 5 | Workflow Execution | Fix invocation, test SSE |
| 6 | Integration Testing | Run E2E tests, fix failures |
| 7 | Bug Fixes | Address critical issues found |

### Week 2: Integration & Testing (Days 8-14)

| Day | Focus | Tasks |
|-----|-------|-------|
| 8 | Memory System | Test LTM persistence |
| 9 | Tool Search | Verify index, test search |
| 10 | Error Handling | Add error boundaries, messages |
| 11 | Unit Tests | Write missing tests |
| 12 | Integration Tests | Test module connections |
| 13 | Performance | Profile, optimize slow paths |
| 14 | Bug Fixes | Address issues found |

### Week 3: Polish & Deploy (Days 15-21)

| Day | Focus | Tasks |
|-----|-------|-------|
| 15 | UI Polish | Fix UI issues, improve UX |
| 16 | Documentation | Update docs, create guides |
| 17 | Security Review | Verify auth, check injection |
| 18 | Load Testing | Test concurrent users |
| 19 | Staging Deploy | Deploy to staging env |
| 20 | UAT | User acceptance testing |
| 21 | Production | Deploy to production |

---

## MONITORING & TRACKING

### Daily Standup Questions

1. What did we fix yesterday?
2. What are we fixing today?
3. What blockers exist?
4. What tests are passing/failing?

### Progress Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Critical bugs fixed | 100% | 0% |
| Core use cases working | 4/4 | 0/4 |
| Integration tests passing | 80% | 0% |
| Performance targets met | Yes | Unknown |

### Issue Tracking

```
GitHub Issues Labels:
- P0-Critical: Must fix for launch
- P1-High: Should fix for launch
- P2-Medium: Fix after launch
- P3-Low: Nice to have
```

---

## APPENDIX: Quick Reference

### Environment Setup

```bash
# Frontend
cd frontend
npm install
cp .env.example .env
# Edit .env with correct values
npm run dev

# Backend
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# Set environment variables
python -m galaxy
```

### Key Environment Variables

```
DATABASE_URL=postgresql://user:pass@host:5432/biomate
ANTHROPIC_API_KEY=sk-ant-xxx
GALAXY_URL=http://localhost:8080
GALAXY_API_KEY=xxx
SESSION_SECRET=xxx
REDIS_URL=redis://localhost:6379
```

### Common Commands

```bash
# Start frontend
cd frontend && npm run dev

# Start backend
cd backend && python -m galaxy

# Run tests
npm run test

# Check database
npx drizzle-kit studio

# View logs
tail -f logs/*.log
```

---

## PHASE 6: iFlow Framework Integration (NEW)

**Reference Documents**:
- `docs/05-data/20260113_IFLOW_INTEGRATION_UPDATE.md` - Feature comparison
- `docs/05-data/20260113_IFLOW_AGENT_TASK_ARCHITECTURE.md` - **Deep architectural analysis**
- `docs/architecture/28_iflow_integration_architecture.drawio.xml` - Integration diagram
- `docs/architecture/29_agent_task_orchestration.drawio.xml` - **Agent task orchestration diagram**

This section focuses on **architectural patterns** to adopt from iFlow, not just features. The key learning is how iFlow structures agent task creation, execution, and management.

### 6.1 Core Architectural Patterns from iFlow

#### 6.1.1 Agent Communication Protocol (ACP)

iFlow uses a **standardized message protocol** for all agent communication:

```
Message Types: AssistantMessage | ToolCallMessage | PlanMessage | TaskFinishMessage
Each message includes: AgentInfo { agent_id, task_id, agent_index, timestamp }
```

**BioMate Implementation**: Create **BioMate Communication Protocol (BCP)**
- Add `learning` message type (for LTM updates)
- Add `auditLevel` field for compliance
- Route all messages through AuditService

#### 6.1.2 Domain Agent Specialization

iFlow defines **specialized agents** per domain with explicit tool boundaries:

```yaml
agentType: "code-reviewer"
allowedTools: ["Read", "Grep"]     # Tool whitelist
isInheritTools: true               # Permission inheritance
```

**BioMate Implementation**: Create **Bioinformatics Domain Agents**
- `genomics-analyst` - scRNA, ChIP-seq, GSEA tools
- `proteomics-analyst` - docking, binding affinity tools
- `imaging-analyst` - segmentation, registration tools
- Each agent has scoped tool access (security)

#### 6.1.3 Task Lifecycle State Machine

iFlow tracks task states: `Created → Planning → Executing → Completed/Suspended`

**BioMate Implementation**: Extend with bioinformatics states
- `agent_selected` - After domain detection
- `waiting_user` - For parameter confirmation
- `checkpoint` - For long-running workflow preservation

### 6.2 BioMate Strengths (Keep & Enhance)

| Capability | BioMate Implementation | iFlow Status |
|------------|------------------------|--------------|
| **Self-Learning** | 10-table LTM with auto-learning | Manual curation only |
| **Auditing** | Full AuditService with compliance | Hooks + Telemetry only |
| **Workflow Execution** | Galaxy SSE streaming | N/A |
| **Tool Search** | 2,177 indexed tools | N/A |
| **Memory Consolidation** | Episodic → Procedural | N/A |

**Key Differentiator**: BioMate's automatic learning from corrections is a major advantage. iFlow requires manual agent curation. Our approach: **structured agents** (from iFlow) + **automatic personalization** (BioMate LTM).

**Action**: Document these as competitive advantages in marketing materials.

### 6.2 iFlow Features to Adopt (HIGH PRIORITY)

#### 6.2.1 Workflow Checkpointing System

**Problem**: BioMate workflows can fail mid-execution with no rollback.

**IMPORTANT - Galaxy Does NOT Have True Checkpointing**:

Galaxy provides state TRACKING, not checkpoint/resume:

| Galaxy Feature | What It Does | Why It's NOT Checkpointing |
|----------------|--------------|----------------------------|
| `InvocationState` | Track: NEW → READY → SCHEDULED → FAILED | No state persistence for recovery |
| Job `RESUBMITTED` | Mark jobs that were manually re-run | Manual action, not automatic resume |
| Step-level tracking | Each step: NEW/READY/SCHEDULED | Tracks progress, doesn't save it |
| `cancel_invocation()` | Stop a running workflow | No "resume cancelled workflow" API |

**Galaxy's limitation**: If workflow fails at step 15 of 20, must restart from step 1.

**What iFlow has that Galaxy doesn't**: Full state serialization to Redis/SQLite - suspend mid-execution, resume later with all context preserved.

---

**NEXTFLOW HAS BUILT-IN CHECKPOINT/RESUME** (Future Execution Engine):

When we switch to Nextflow for workflow execution, checkpoint/resume is solved:

| Nextflow Feature | How It Works |
|------------------|--------------|
| **`-resume` flag** | `nextflow run pipeline.nf -resume` skips completed tasks |
| **Automatic caching** | Every task cached in `.nextflow/cache` (LevelDB) |
| **Hash-based validation** | Re-runs only if inputs/scripts/containers change |
| **Work directory** | Outputs preserved in `work/` for resumption |
| **Cloud support** | Works with S3, GCS, Azure blob storage |

**Example usage**:
```bash
# First run - fails at step 15
nextflow run rnaseq.nf

# Resume - skips steps 1-14, continues from 15
nextflow run rnaseq.nf -resume
```

**What still needs custom checkpointing** (even with Nextflow):

| Component | Needs Custom Checkpoint? | Why |
|-----------|-------------------------|-----|
| Workflow Execution | **NO** - Nextflow handles | Built-in `-resume` |
| Agent Orchestration | **YES** | Conversation context, routing decisions |
| Test Harness | **YES** | Benchmarks don't use Nextflow |

**BioMate already has Nextflow support**:
- `backend/nf-core-modules/` - nf-core module library
- `backend/biomni_workflows/nextflow/` - 100+ converted workflows
- `backend/lib/galaxy/ai/workflow_converters/nextflow_converter.py` - Galaxy→Nextflow converter

---

**BioMate Implementation for Agent Orchestration Checkpointing** (still needed):

```typescript
// Add to frontend/server/lib/checkpointing.ts
export class WorkflowCheckpointer {
  async createCheckpoint(workflowId: string): Promise<Checkpoint> {
    return {
      id: `checkpoint_${Date.now()}`,
      workflowId,
      timestamp: new Date(),
      state: {
        historyId: await this.getHistorySnapshot(),
        datasetStates: await this.getDatasetStates(),
        conversationContext: await this.getConversationContext()
      }
    };
  }

  async restore(checkpointId: string): Promise<void> {
    // Restore to previous state
  }
}
```

**Database Addition**:
```sql
CREATE TABLE workflow_checkpoints (
  id SERIAL PRIMARY KEY,
  workflow_id VARCHAR(100),
  checkpoint_data JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

**Priority**: HIGH (Week 2)

#### 6.2.1b Test Harness Checkpointing (NEW)

**Problem**: `backend/lib/galaxy/ai/test_harness/benchmark_suite.py` has NO checkpointing.

Current status tracking:
```python
class BenchmarkStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETE = "complete"
    FAILED = "failed"
    CANCELLED = "cancelled"
```

**Limitation**: If running 100 benchmark runs and failure occurs at run 50, ALL progress is lost.

**Required Implementation**:

```python
# Add to benchmark_suite.py

def save_checkpoint(self, results: BenchmarkResults, checkpoint_dir: str = None):
    """Save checkpoint after each successful run for resume capability."""
    if checkpoint_dir is None:
        checkpoint_dir = Path(__file__).parent / "checkpoints"
    checkpoint_dir = Path(checkpoint_dir)
    checkpoint_dir.mkdir(exist_ok=True)

    checkpoint_path = checkpoint_dir / f"{results.scenario_name}_checkpoint.json"
    with open(checkpoint_path, 'w') as f:
        json.dump({
            "results": results.to_dict(),
            "completed_run_ids": [r.run_id for r in results.runs if r.status == BenchmarkStatus.COMPLETE],
            "checkpoint_time": datetime.now().isoformat()
        }, f, indent=2)
    log.info(f"Checkpoint saved: {checkpoint_path}")

def resume_from_checkpoint(self, scenario_name: str, checkpoint_dir: str = None) -> Optional[BenchmarkResults]:
    """Resume benchmark from last checkpoint, skipping completed runs."""
    if checkpoint_dir is None:
        checkpoint_dir = Path(__file__).parent / "checkpoints"

    checkpoint_path = Path(checkpoint_dir) / f"{scenario_name}_checkpoint.json"
    if not checkpoint_path.exists():
        return None

    with open(checkpoint_path) as f:
        data = json.load(f)

    # Reconstruct results with completed runs
    results = BenchmarkResults(
        scenario_name=data["results"]["scenario_name"],
        started_at=data["results"]["started_at"],
        status=BenchmarkStatus.RUNNING
    )
    # ... restore completed runs
    return results

def _run_sequential(self, runs, executor, scenario) -> List[BenchmarkRun]:
    """Modified to checkpoint after each run."""
    completed_runs = []
    for i, run in enumerate(runs):
        # ... execute run ...
        completed_runs.append(run)

        # CHECKPOINT after each successful run
        if run.success:
            self.save_checkpoint(BenchmarkResults(
                scenario_name=scenario.name,
                started_at=datetime.now().isoformat(),
                runs=completed_runs
            ))
    return completed_runs
```

**Benefits**:
- Long benchmark suites (hours/days) survive interruptions
- Can pause overnight and resume next day
- Single run failure doesn't lose all completed runs
- Essential for AI Scientist integration (benchmarks can take days)

**Priority**: HIGH (Week 2 - alongside workflow checkpointing)

#### 6.2.2 Pre/Post Tool Execution Hooks

**Problem**: No way to validate workflow steps before/after execution.

**iFlow Solution**: 9 hook types for lifecycle events.

**BioMate Implementation**:

```typescript
// Add to frontend/server/lib/hooks.ts
export type HookType =
  | 'PreWorkflowExecution'
  | 'PreToolExecution'
  | 'PostToolExecution'
  | 'WorkflowComplete';

export class WorkflowHooks {
  async executePreToolHook(tool: Tool, params: ToolParams): Promise<{ proceed: boolean }> {
    // Validate tool compatibility
    // Check data type requirements
    // Log audit event
  }

  async executePostToolHook(tool: Tool, result: ToolResult): Promise<void> {
    // Update LTM with success/failure
    // Trigger learning if error occurred
    // Update audit log
  }
}
```

**Priority**: HIGH (Week 2)

#### 6.2.3 BIOMATE.md Context Files

**Problem**: No standardized way to document AI workflow patterns per project.

**iFlow Solution**: Hierarchical IFLOW.md context loading.

**BioMate Implementation**:

```markdown
# BIOMATE.md (Example)

## Project: DIA Proteomics Analysis

## Analysis Type
- Data: DIA mass spectrometry
- Instrument: Orbitrap Exploris 480
- Goal: Quantitative proteomics

## Preferred Tools
- Primary: DIA-NN
- Avoid: MaxQuant (DDA-only)

## Parameters
- FDR: 0.01
```

**Priority**: MEDIUM (Week 3)

### 6.3 iFlow Features to Consider (MEDIUM PRIORITY)

#### 6.3.1 Python SDK for Programmatic Access

**Use Case**: CI/CD integration, headless automation.

**iFlow Pattern**:
```python
async with IFlowClient() as client:
    await client.send_message("Generate workflow")
    async for message in client.receive_messages():
        handle(message)
```

**BioMate Equivalent**:
```python
# biomate-sdk (proposed)
from biomate_sdk import BiomateClient

async with BiomateClient() as client:
    workflow = await client.generate_workflow(
        "Analyze RNA-seq data",
        data_type="RNA-seq"
    )
    async for status in client.execute_workflow(workflow.id):
        print(status)
```

**Priority**: MEDIUM (Post-Launch)

#### 6.3.2 GitHub Action Integration

**Use Case**: Automated workflow generation in CI/CD.

```yaml
- name: 'Generate BioMate Workflow'
  uses: biomate/biomate-action@main
  with:
    api_key: ${{ secrets.BIOMATE_API_KEY }}
    prompt: "Create RNA-seq pipeline"
```

**Priority**: LOW (Post-Launch)

### 6.4 iFlow Features NOT to Adopt

| Feature | Reason |
|---------|--------|
| MCP Integration | Low bioinformatics-specific MCPs available |
| Agent Marketplace | BioMate's LTM-based routing is better |
| Thinking Levels | Not needed for domain-specific workflows |
| Vim Mode | Not relevant for bioinformatics users |

### 6.5 Integration Timeline

**Week 2 (Add to existing plan)**:
- [ ] Add workflow checkpointing system
- [ ] Add Pre/Post tool execution hooks
- [ ] Connect hooks to LTM for learning

**Week 3 (Add to existing plan)**:
- [ ] Add BIOMATE.md parser
- [ ] Auto-generate BIOMATE.md from LTM preferences
- [ ] Add `/restore` API endpoint for checkpoint rollback

**Post-Launch**:
- [ ] Create biomate-sdk Python package
- [ ] Create biomate-action GitHub Action
- [ ] Consider OTLP telemetry integration

---

## PHASE 7: Self-Learning & Auditing Documentation (COMPLETED)

**Reference Documents Created**:
- `docs/05-data/20260113_SELF_LEARNING_SYSTEM.md` - 10-table LTM documentation
- `docs/05-data/20260113_AUDITING_SYSTEM.md` - AuditService documentation
- `docs/architecture/26_self_learning_system.drawio.xml` - LTM architecture diagram
- `docs/architecture/27_auditing_system.drawio.xml` - Auditing architecture diagram
- `docs/05-data/20260113_IFLOW_INTEGRATION_UPDATE.md` - iFlow integration analysis
- `docs/architecture/28_iflow_integration_architecture.drawio.xml` - Integration diagram

**Key Findings**:

| System | Status | Key Metrics |
|--------|--------|-------------|
| LTM Database | 10 tables implemented | user_preferences, correction_log, project_episodes, etc. |
| Preference Learning | Working | Confidence 0.3 → 1.0, +0.1/use, +0.2/correction |
| Correction Learning | 3-layer | Direct update → Keyword extraction → Router update |
| Memory Consolidation | Implemented | 3+ similar episodes → Procedural |
| Audit Service | 6 methods | logAuth, logWorkflowGeneration, etc. |
| Audit Middleware | Working | Automatic API request logging |
| Compliance Fields | Complete | WHO/WHAT/WHEN/WHERE/WHY/OUTCOME |

**Action**: These systems are production-ready. Focus on testing and validation.

---

## PHASE 8: Agent Hierarchy Analysis (COMPLETED)

**Reference Documents Created**:
- `docs/05-data/20260113_BIOMATE_AGENT_HIERARCHY.md` - Complete documentation of existing agent system
- `docs/architecture/30_biomate_agent_hierarchy.drawio.xml` - 3-layer architecture diagram
- `docs/architecture/31_biomate_vs_iflow_comparison.drawio.xml` - Gap analysis visualization

### 8.1 BioMate's Existing Agent Hierarchy

BioMate already has a sophisticated **3-layer agent hierarchy**:

```
LAYER 1: Intent Classification (UnifiedIntentRouter)
├── 10 intent types (workflow_generation, research_question, etc.)
├── Keyword matching (<10ms)
├── LLM fallback (confidence < 0.6)
└── Entity extraction (tools, organisms, data types)
         │
         ▼
LAYER 2: Agent Orchestration (AgentOrchestrator)
├── Phase 1: EnhancedDomainRouter (15 bioinformatics domains)
├── Phase 2: DomainSpecialistPool (parallel execution, max_workers=3)
└── Phase 3: WorkflowAssembler (synthesis + validation)
         │
         ▼
LAYER 3: Supporting Components
├── UserPatternsAdapter (domain prefs, tool prefs, learned keywords)
├── BenchmarkKnowledgeDB (tool benchmarks, citations)
└── AuditService (per-phase timing, request logging)
```

### 8.2 15 Bioinformatics Domains

| Domain | Key Keywords |
|--------|-------------|
| genomics | genome, dna, sequencing, variant calling |
| transcriptomics | rna-seq, gene expression, deseq2 |
| proteomics | protein, mass spec, dia, dda |
| metabolomics | metabolite, lcms, gcms |
| single-cell | scrna-seq, scatac, 10x |
| metagenomics | microbiome, 16s, shotgun |
| structural_biology | pdb, alphafold, docking |
| pharmacology | drug, compound, admet |
| immunology | immune, tcr, bcr, epitope |
| cancer_biology | tumor, oncology, somatic |
| bioimaging | microscopy, image, segmentation |
| molecular_biology | pcr, cloning, primer |
| biochemistry | enzyme, kinetics, assay |
| database | query, search, fetch |
| literature | papers, pubmed, citations |

### 8.3 BioMate vs iFlow Comparison Summary

| Feature | BioMate Status | iFlow Status | Gap? |
|---------|----------------|--------------|------|
| Intent Classification | 10 types | Task routing | NO |
| Domain Routing | 15 domains + LRU cache | Generic | NO |
| Parallel Execution | ThreadPoolExecutor | asyncio | NO |
| User Learning | SQLite persistence | Memory system | NO |
| **Message Protocol** | Ad-hoc dicts | ACP (typed) | **YES** |
| **Checkpointing** | None | Full state | **YES** |
| **Planning Stage** | Implicit | Explicit | **YES** |
| **Tool Permissions** | Soft filtering | Strict enforcement | **PARTIAL** |

### 8.4 Genuine Gaps to Address (Prioritized)

| Priority | Gap | Effort | Impact |
|----------|-----|--------|--------|
| P1 | Standardized Message Protocol (BCP) | Low | Medium |
| P2 | Checkpoint/Resume Capability | Medium | High |
| P3 | Explicit Planning Stage | Medium | High |
| P4 | Tool Permission Enforcement | Low | Medium |

**Conclusion**: BioMate already has ~80% of iFlow's agent capabilities. The remaining 4 gaps are addressable with moderate effort and would significantly improve reliability and user trust.

### 8.5 Tool Permissions - Detailed Clarification

**Current Implementation (Soft Filtering)**:

In `domain_specialist.py`:
```python
def consult_specialists(
    self,
    query: str,
    domains: List[str],
    tools_per_domain: int = 15  # <-- SOFT FILTER
):
```

**How it works now**:
1. Genomics specialist REQUESTS genomics-related tools
2. Tool search returns 15 filtered tools
3. LLM sees those 15 tools in its prompt
4. BUT: Nothing PREVENTS the LLM from recommending ANY tool it knows about

**Problem scenarios**:
- LLM might hallucinate tool names that don't exist
- Cross-domain recommendations (proteomics tool for genomics data)
- Inconsistent tool suggestions across sessions

**iFlow's Strict Approach**:
```yaml
agentType: "genomics-analyst"
allowedTools: ["bwa", "gatk", "deepvariant", "samtools"]  # WHITELIST - agent CANNOT use other tools
```

**Proposed BioMate Implementation**:

```python
# Add to domain_specialist.py

DOMAIN_TOOL_PERMISSIONS: Dict[str, Set[str]] = {
    "genomics": {"bwa", "bwa-mem2", "gatk", "deepvariant", "samtools", "bcftools", "freebayes", "strelka2"},
    "transcriptomics": {"star", "salmon", "kallisto", "deseq2", "edger", "htseq", "rsem", "featurecounts"},
    "proteomics": {"maxquant", "dia-nn", "msfragger", "percolator", "comet", "msgf+"},
    "single-cell": {"scanpy", "seurat", "cellranger", "scvi", "harmony", "scanorama"},
    "metagenomics": {"kraken2", "metaphlan", "humann", "qiime2", "dada2", "vsearch"},
    "structural_biology": {"alphafold", "colabfold", "autodock-vina", "pymol", "chimera"},
    "pharmacology": {"rdkit", "openbabel", "admet-ai", "pkcsm", "swissadme"},
    # ... more domains
}

def validate_tool_recommendation(self, domain: str, tool_id: str) -> Tuple[bool, str]:
    """
    Validate that recommended tool is within domain's permission scope.

    Returns:
        (is_valid, message)
    """
    allowed = DOMAIN_TOOL_PERMISSIONS.get(domain, set())
    if not allowed:
        return True, "No restrictions for this domain"

    tool_lower = tool_id.lower()
    if tool_lower in allowed:
        return True, f"Tool {tool_id} is approved for {domain}"

    # Check for partial matches (e.g., "gatk_haplotypecaller" matches "gatk")
    for approved_tool in allowed:
        if tool_lower.startswith(approved_tool) or approved_tool in tool_lower:
            return True, f"Tool {tool_id} matches approved pattern {approved_tool}"

    return False, f"Tool {tool_id} not in {domain} approved list. Allowed: {allowed}"

def _consult_single(self, query: str, domain: str, tools_per_domain: int) -> DomainRecommendation:
    """Modified to validate recommendations."""
    recommendation = self._get_llm_recommendation(query, domain, tools_per_domain)

    # VALIDATE each recommended tool
    validated_tools = []
    for tool in recommendation.recommended_tools:
        is_valid, message = self.validate_tool_recommendation(domain, tool.tool_id)
        if is_valid:
            validated_tools.append(tool)
        else:
            log.warning(f"Rejected tool recommendation: {message}")

    recommendation.recommended_tools = validated_tools
    return recommendation
```

**Benefits**:
- Guaranteed tool validity (no hallucinated tools)
- Domain-appropriate recommendations
- Consistent, predictable behavior
- Easier to audit and debug

**Priority**: MEDIUM (can implement after core functionality)

### 8.6 Key Implementation Files

| Component | Location |
|-----------|----------|
| UnifiedIntentRouter | `backend/lib/galaxy/ai/agents/unified_intent_router.py` |
| AgentOrchestrator | `backend/lib/galaxy/ai/agents/agent_orchestrator.py` |
| EnhancedDomainRouter | `backend/lib/galaxy/ai/agents/enhanced_domain_router.py` |
| DomainSpecialistPool | `backend/lib/galaxy/ai/agents/domain_specialist.py` |
| WorkflowAssembler | `backend/lib/galaxy/ai/agents/workflow_assembler.py` |
| UserPatternsAdapter | `backend/lib/galaxy/ai/agents/user_patterns_adapter.py` |

---

**Next Action**: Start with Phase 1, Section 1.1 - Frontend Server Audit

**Owner**: Development Team
**Deadline**: 3 weeks from start date
**Review Cadence**: Daily standups, weekly progress reviews
