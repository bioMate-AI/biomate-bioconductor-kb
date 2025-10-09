# GalaxyChat v2 - Backend Integration & UI Enhancement Plan

## Overview
Integrate the production-ready Galaxy backend (from `/tmp/lcms-platform-galaxy/`) with the GalaxyChat UI, enhance the workflow graph view, implement end-to-end execution with Galaxy's native progress tracking, and establish clear semantic separation between chat and workflow interfaces.

---

## Part 1: Backend Integration Strategy

### 1.1 Galaxy API Proxy Layer
**Create**: `server/galaxy-api-proxy.ts`

Connect to Galaxy's existing REST API and leverage native capabilities:
- Proxy requests to Galaxy backend (`/api/workflows`, `/api/jobs`, `/api/invocations`)
- Handle authentication via Galaxy API keys
- Connect to on-demand tool installer (already production-ready)
- Connect to BioMNI Dataset RAG system

**Key Endpoints to Proxy:**
```typescript
// Tool Management
POST /api/galaxy/tool-search         // Search Galaxy ToolShed (2,177 tools indexed)
POST /api/galaxy/tool-install        // On-demand tool installation with retry logic

// Workflow Execution (leverage Galaxy's native tracking)
POST /api/galaxy/workflows/invoke    // Invoke workflow, returns invocation_id
GET  /api/galaxy/invocations/{id}    // Get invocation status and step states
GET  /api/galaxy/jobs/{id}           // Get individual job state (new/running/ok/error)

// Dataset Discovery
GET  /api/galaxy/datasets            // BioMNI dataset search and recommendations
```

### 1.2 Galaxy State Polling Service
**Create**: `server/galaxy-state-poller.ts`

**DO NOT create custom time estimation or progress calculation.**
Instead, poll Galaxy's native state endpoints:

```typescript
interface GalaxyJobState {
  state: 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused' | 'deleted';
  // Galaxy does NOT provide accurate time estimates
  // Only use actual state transitions
}

interface GalaxyInvocationState {
  id: string;
  state: 'new' | 'ready' | 'scheduled' | 'cancelled' | 'failed';
  steps: Array<{
    workflow_step_id: number;
    jobs: Array<{
      id: string;
      state: GalaxyJobState['state'];
      tool_id: string;
      create_time: string;
      update_time: string;
    }>;
  }>;
}
```

**Polling Strategy:**
- Poll Galaxy invocation endpoint every 2-5 seconds during execution
- Extract actual job states from Galaxy (don't estimate)
- Stream state changes to frontend via Server-Sent Events (SSE)
- Display Galaxy's native logging output (don't create fake logs)

### 1.3 Replace OpenAI-Only Chat with Hybrid Approach
**Modify**: `server/routes.ts`

Hybrid intelligence system:
1. **OpenAI**: Natural language understanding, conversational responses
2. **Galaxy Tool Search**: Real tool recommendations from indexed ToolShed
3. **BioMNI Dataset RAG**: Real dataset recommendations with schemas
4. **Galaxy API**: Generate workflows using actual Galaxy tools (not hardcoded mock tools)

**Workflow Generation Flow:**
```
User: "I need to analyze RNA-seq data"
  ↓
OpenAI: Understand intent → RNA-seq analysis pipeline
  ↓
Galaxy Tool Search: Find real tools (HISAT2, featureCounts, DESeq2)
  ↓
BioMNI RAG: Suggest compatible reference datasets
  ↓
Generate Workflow: Create Galaxy-compatible workflow JSON
  ↓
Return to UI: Display graph with real tools + suggested datasets
```

---

## Part 2: Graph-Only Workflow View

### 2.1 Remove List View
**Modify**: `client/src/components/enhanced-workflow-builder.tsx`
- Remove `currentView` state and tab switching UI
- Remove all list view rendering code
- Make `WorkflowGraph` the default and only visualization
- Keep workflow-level controls (currently in list view) and add to graph view header

### 2.2 Enhance Graph View with Parameter Configuration
**Create**: `client/src/components/workflow-graph-parameter-dialog.tsx`

**Three-Tier Progressive Parameter Disclosure:**

```typescript
interface ParameterTier {
  tier: 1 | 2 | 3;
  label: string;
  description: string;
}

// Tier 1: Essential (always visible, 3-5 params max)
// Tier 2: Common (expandable, 5-10 params)
// Tier 3: Advanced (collapsed by default, all remaining params)
```

**Parameter Dialog Features:**
- **Smart Defaults**: Load from Galaxy tool metadata
- **AI Suggestions**: Use chat context to pre-fill parameters
  Example: User mentioned "human RNA-seq" → auto-suggest reference genome = hg38
- **Validation**: Use Galaxy tool schema for parameter validation
- **Help Text**: Display Galaxy tool parameter descriptions
- **Presets**: Common parameter combinations ("Quick", "Sensitive", "Custom")

**Visual Design:**
```
┌─────────────────────────────────────┐
│ Configure: Quality Control (FastQC) │
│                                     │
│ ⚙️ Essential Parameters             │
│   Input Format: [FASTQ      ▼]     │
│   Quality Encoding: [Sanger  ▼]     │
│   Contaminant File: [Default ▼]     │
│                                     │
│ 📊 Common Adjustments [Expand ▼]    │
│                                     │
│ 🔧 Advanced [45 more...] [Expand ▼] │
│                                     │
│ 💡 AI Suggestion:                   │
│ "Based on your Illumina data, I     │
│  recommend Phred+33 encoding"       │
│                                     │
│ [Cancel]  [Apply]  [Apply & Run]    │
└─────────────────────────────────────┘
```

### 2.3 Add Run Controls to Graph View
**Enhance**: `client/src/components/workflow-graph.tsx`

**Workflow-Level Controls** (add to graph view header):
```typescript
<div className="workflow-controls">
  <Button onClick={executeWorkflow}>
    <Play /> Run Entire Workflow
  </Button>
  <Button onClick={pauseWorkflow} disabled={status !== 'running'}>
    <Pause /> Pause All
  </Button>
  <Button onClick={stopWorkflow}>
    <StopCircle /> Stop
  </Button>
  <Button onClick={restartWorkflow}>
    <RotateCcw /> Restart from Beginning
  </Button>
</div>
```

**Node-Level Controls** (on click/hover):
- **Run This Step**: Execute single step (if dependencies complete)
- **Skip This Step**: Mark as skipped, continue workflow
- **Retry This Step**: Re-run failed step
- **View Parameters**: Open parameter dialog
- **View Logs**: Show Galaxy job logs for this step

**Visual Execution State:**
- Node border color indicates state:
  - Gray: `pending` / `new`
  - Blue pulsing: `queued` / `running`
  - Green: `ok` / `completed`
  - Red: `error` / `failed`
  - Yellow: `paused`
- **NO progress bars** (Galaxy doesn't provide accurate progress %)
- Show actual state text from Galaxy
- Show elapsed time: `update_time - create_time`

**Dependency Visualization:**
- Hover node → highlight all dependencies (incoming edges)
- Show which dependencies are blocking this step
- Disable "Run This Step" if dependencies not complete

---

## Part 3: End-to-End Workflow Execution with Galaxy Native Tracking

### 3.1 Backend Execution Orchestrator
**Create**: `server/workflow-executor.ts`

**Leverage Galaxy's native execution, don't recreate it:**

```typescript
class GalaxyWorkflowExecutor {
  async executeWorkflow(workflowSteps: WorkflowStep[]): Promise<InvocationResult> {
    // 1. Convert UI workflow to Galaxy workflow format
    const galaxyWorkflow = this.convertToGalaxyFormat(workflowSteps);

    // 2. Check tool availability → install on-demand if needed
    for (const step of workflowSteps) {
      const toolAvailable = await this.checkToolInstalled(step.tool);
      if (!toolAvailable) {
        await this.installToolOnDemand(step.tool);
      }
    }

    // 3. Invoke workflow via Galaxy API
    const invocation = await galaxyAPI.invokeWorkflow({
      workflow_id: galaxyWorkflow.id,
      inputs: this.prepareInputs(workflowSteps),
      parameters: this.prepareParameters(workflowSteps)
    });

    // 4. Return invocation_id (Galaxy handles execution)
    return invocation;
  }

  // Poll Galaxy for ACTUAL state (not estimated)
  async pollInvocationState(invocationId: string): Promise<InvocationState> {
    const state = await galaxyAPI.getInvocation(invocationId);

    // Extract real job states from Galaxy
    return {
      invocation_id: invocationId,
      state: state.state,  // new/ready/scheduled/cancelled/failed
      steps: state.steps.map(step => ({
        step_id: step.workflow_step_id,
        jobs: step.jobs.map(job => ({
          job_id: job.id,
          state: job.state,           // Use Galaxy's actual state
          tool: job.tool_id,
          created: job.create_time,   // Actual timestamps
          updated: job.update_time,   // from Galaxy
          // NO estimated time remaining
          // NO fake progress percentage
        }))
      }))
    };
  }
}
```

### 3.2 Real-time State Updates via Server-Sent Events
**Create**: `server/workflow-sse.ts`

Stream Galaxy's actual state to frontend:

```typescript
// SSE endpoint
app.get('/api/galaxy/invocations/:id/stream', async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  const invocationId = req.params.id;

  const interval = setInterval(async () => {
    // Poll Galaxy every 3 seconds
    const state = await galaxyAPI.getInvocation(invocationId);

    // Send ACTUAL state (not estimated/fake data)
    res.write(`data: ${JSON.stringify({
      type: 'state_update',
      invocation_id: invocationId,
      state: state.state,
      steps: state.steps  // Galaxy's real step states
    })}\n\n`);

    // Stop polling when workflow complete
    if (['failed', 'cancelled', 'scheduled'].includes(state.state)) {
      clearInterval(interval);
      res.end();
    }
  }, 3000);

  req.on('close', () => clearInterval(interval));
});
```

### 3.3 Mock Implementation for UI Development
**Create**: `server/mock-galaxy-api.ts`

Mock Galaxy responses with realistic behavior for UI development:

```typescript
class MockGalaxyAPI {
  async invokeWorkflow(params): Promise<Invocation> {
    return {
      id: `inv_${Date.now()}`,
      state: 'new',
      create_time: new Date().toISOString(),
      steps: params.steps.map((step, i) => ({
        workflow_step_id: i,
        jobs: [{
          id: `job_${i}_${Date.now()}`,
          state: 'new',  // Will transition: new→queued→running→ok
          tool_id: step.tool,
          create_time: new Date().toISOString(),
          update_time: new Date().toISOString()
        }]
      }))
    };
  }

  async getInvocation(invocationId: string): Promise<InvocationState> {
    // Simulate realistic state transitions
    // new → queued → running → ok (for each job)
    // Vary timing by tool complexity
    return this.simulateRealisticExecution(invocationId);
  }

  private simulateRealisticExecution(invocationId: string): InvocationState {
    // Use variable delays based on tool:
    // - FastQC: 30-60s
    // - Alignment: 2-5 minutes
    // - Variant calling: 5-15 minutes
    // But DON'T show fake progress bars
    // Just show state transitions at realistic intervals
  }
}
```

### 3.4 Execution Panel with Real Galaxy Outputs
**Create**: `client/src/components/workflow-execution-panel.tsx`

Display Galaxy's actual execution information:

```typescript
interface ExecutionPanelProps {
  invocationId: string;
}

// Components to show:
// 1. Timeline: Step state transitions (based on actual Galaxy states)
// 2. Step Details: Show Galaxy job logs (actual stdout/stderr)
// 3. Outputs: Display Galaxy dataset outputs (download links)
// 4. Errors: Show Galaxy error messages (not made-up errors)
```

**Visual Timeline Design:**
```
Step 1: Quality Control [✓ Completed]
  └─ Job job_123 | FastQC | State: ok
     Created: 14:23:10 | Completed: 14:23:47 | Elapsed: 37s
     [View Logs] [Download Output]

Step 2: Read Alignment [⟳ Running]
  └─ Job job_124 | HISAT2 | State: running
     Created: 14:23:50 | Running for: 2m 15s
     [View Live Logs]

Step 3: Gene Quantification [⊙ Queued]
  └─ Job job_125 | featureCounts | State: queued
     Waiting for Step 2 to complete...
```

**Key Principles:**
- ✅ Show actual Galaxy job states
- ✅ Show real elapsed time from Galaxy timestamps
- ✅ Display Galaxy's stdout/stderr logs
- ✅ Link to Galaxy dataset outputs
- ❌ NO fake progress percentages
- ❌ NO estimated time remaining
- ❌ NO made-up log messages

### 3.5 Result Visualization Components
**Create**: `client/src/components/workflow-result-viewer.tsx`

Display Galaxy dataset outputs:

```typescript
interface DatasetOutput {
  dataset_id: string;
  name: string;
  file_ext: string;  // Galaxy file extension (tabular, fastqsanger, bam, etc.)
  file_size: number;
  download_url: string;
  peek?: string;     // Galaxy's dataset preview
}

// Viewers based on Galaxy file types:
// - Tabular/CSV: Data table with pagination
// - Images (PNG/PDF): Image viewer
// - Text/logs: Syntax-highlighted text viewer
// - BAM/VCF: Genomics-specific viewers (IGV.js integration)
```

---

## Part 4: Semantic Integration (Chat ↔ Workflow)

### 4.1 Interaction Model - Clear Separation of Concerns

**CHATBOT VIEW** (Left Panel) - *Conversational Assistant & Guide*

**Responsible for:**
- 🗣️ **Natural language interaction**: Understanding user queries
- 💡 **Suggestions & recommendations**: "I recommend using HISAT2 for RNA-seq alignment"
- 📚 **Explanations & education**: "DESeq2 uses negative binomial distribution to..."
- 🔍 **Tool discovery**: Search Galaxy ToolShed, explain tool capabilities
- 📊 **Dataset recommendations**: Suggest BioMNI datasets based on analysis type
- ⚙️ **Parameter guidance**: "For Illumina data, use quality offset 33"
- 🆘 **Error interpretation**: "This error means your reference genome is missing"
- 📖 **Documentation**: Link to tool docs, tutorials, best practices
- 🎯 **Workflow suggestions**: Propose analysis pipelines

**Example Chat Interactions:**
```
User: "I have human RNA-seq data, what should I do?"
AI: "I'll help you build an RNA-seq analysis pipeline! Here's what I recommend:

1. Quality Control with FastQC
2. Alignment with HISAT2 (optimized for RNA-seq)
3. Quantification with featureCounts
4. Differential expression with DESeq2

I've generated a workflow in the right panel. Would you like me to suggest
compatible reference datasets from BioMNI?"

User: "Yes, and explain why HISAT2?"
AI: "HISAT2 is specifically designed for RNA-seq because it handles splice
junctions efficiently. Unlike DNA aligners, it can map reads that span exon
boundaries. For your human data, I'll add the hg38 reference genome to the
workflow."
```

**What Chat Should NOT Do:**
- ❌ Display workflow graph (that's workflow view's job)
- ❌ Show execution progress bars (workflow view handles this)
- ❌ Display detailed parameters (workflow view has parameter dialog)
- ❌ Show job logs (workflow view shows Galaxy logs)

---

**WORKFLOW VIEW** (Right Panel) - *Visual Execution Workspace*

**Responsible for:**
- 🔀 **Workflow visualization**: Graph representation of pipeline
- ⚙️ **Parameter configuration**: Edit tool parameters with 3-tier UI
- ▶️ **Execution control**: Run, pause, stop, retry workflow
- 📊 **Progress monitoring**: Real-time Galaxy job state tracking
- 📁 **Dataset management**: Input/output dataset configuration
- 📝 **Execution logs**: Display Galaxy stdout/stderr logs
- 📥 **Result downloads**: Access Galaxy dataset outputs
- 🔍 **Step inspection**: View details for each workflow step
- 🎨 **Visual customization**: Rearrange nodes, add annotations
- 💾 **Workflow saving**: Save/load workflow configurations

**Example Workflow Interactions:**
- Click node → Open parameter dialog with AI suggestions pre-filled
- Click "Run" → Execute workflow via Galaxy API
- While running → Display Galaxy's actual job states (not fake progress)
- Step completes → Show output datasets with download links
- Error occurs → Display Galaxy error, ask chat for help

**What Workflow View Should NOT Do:**
- ❌ Explain WHY to use a tool (chat explains this)
- ❌ Provide tutorials or documentation (chat provides links)
- ❌ Recommend alternative tools (chat makes recommendations)
- ❌ Interpret error messages (chat interprets, workflow shows raw error)

---

### 4.2 Bidirectional Communication Patterns

**Pattern 1: Chat Generates → Workflow Displays**
```
User asks chat: "Create RNA-seq pipeline"
  ↓
Chat queries Galaxy Tool Search API
  ↓
Chat generates workflow with real Galaxy tools
  ↓
Workflow view receives workflow object
  ↓
Workflow graph renders with nodes
```

**Pattern 2: Workflow Action → Chat Provides Context**
```
User clicks node in workflow
  ↓
Workflow sends tool_id + current_params to chat
  ↓
Chat provides parameter suggestions based on conversation context
  ↓
Parameter dialog shows AI suggestions
```

**Pattern 3: Execution Error → Chat Helps Debug**
```
Galaxy job fails with error
  ↓
Workflow displays raw Galaxy error message
  ↓
User clicks "Ask Chat for Help"
  ↓
Chat receives: tool_id + error_message + workflow_context
  ↓
Chat explains error and suggests fixes
  ↓
Chat offers: "Would you like me to adjust the workflow?"
```

**Pattern 4: Parameter Confusion → Chat Explains**
```
User opens parameter dialog, confused by options
  ↓
User clicks "Help" button in parameter dialog
  ↓
Chat receives: tool_id + parameter_name
  ↓
Chat explains: "The quality offset parameter specifies the encoding
scheme. Illumina data after 2011 uses Phred+33, which means quality
scores start at ASCII 33. For your data, I recommend Phred+33."
```

### 4.3 Synchronization Implementation
**Create**: `client/src/hooks/use-workflow-sync.ts`

```typescript
interface WorkflowSyncState {
  // Workflow state
  currentWorkflow: WorkflowProgress | null;
  selectedNode: WorkflowNode | null;

  // Chat state
  chatContext: {
    user_intent: string;
    suggested_tools: string[];
    suggested_datasets: string[];
    conversation_history: Message[];
  };

  // Sync actions
  onWorkflowGenerated: (workflow: Workflow) => void;
  onNodeSelected: (node: WorkflowNode) => void;
  onExecutionError: (error: GalaxyError) => void;
  onParameterHelp: (tool: string, param: string) => void;
}

// Bidirectional sync
const {
  currentWorkflow,
  syncChatToWorkflow,   // Chat generates → update workflow
  syncWorkflowToChat,   // Workflow action → update chat context
} = useWorkflowSync();
```

**State Synchronization Rules:**
1. **Chat generates workflow** → Update `currentWorkflow` state → Workflow view re-renders
2. **Node clicked** → Send tool context to chat → Chat updates suggestions
3. **Workflow starts execution** → Chat displays friendly status message
4. **Execution error** → Chat receives error context → Provides help
5. **User edits parameters** → Chat updates its understanding of user intent

---

## Part 5: Implementation Phases

### **Phase 1: Backend Foundation** (Week 1)
- [ ] Create Galaxy API proxy layer (`server/galaxy-api-proxy.ts`)
- [ ] Implement Galaxy state poller (`server/galaxy-state-poller.ts`)
- [ ] Set up SSE endpoint for real-time updates (`server/workflow-sse.ts`)
- [ ] Create mock Galaxy API for UI development (`server/mock-galaxy-api.ts`)
- [ ] Test mock workflow execution end-to-end

**Deliverable**: Backend can invoke mock Galaxy workflows and stream state updates

### **Phase 2: Graph Enhancement** (Week 1-2)
- [ ] Remove list view from `enhanced-workflow-builder.tsx`
- [ ] Add workflow-level controls to graph view header
- [ ] Create parameter dialog component with 3-tier UI
- [ ] Add parameter button to graph nodes
- [ ] Implement node-level execution controls
- [ ] Add visual state indicators (colors, not progress bars)

**Deliverable**: Graph-only workflow view with full parameter configuration

### **Phase 3: Execution & Progress** (Week 2)
- [ ] Build execution timeline component
- [ ] Create result viewer components (tables, images, logs)
- [ ] Implement real-time state updates via SSE
- [ ] Add Galaxy log viewer integration
- [ ] Test with mock Galaxy API for realistic execution simulation

**Deliverable**: End-to-end mock execution with realistic Galaxy state transitions

### **Phase 4: Chat Integration** (Week 2-3)
- [ ] Replace OpenAI-only chat with hybrid approach
- [ ] Integrate Galaxy tool search into chat responses
- [ ] Add BioMNI dataset recommendations
- [ ] Generate workflows using real Galaxy tools (not hardcoded)
- [ ] Implement bidirectional chat ↔ workflow sync
- [ ] Add parameter suggestions from chat context
- [ ] Implement error interpretation in chat

**Deliverable**: Intelligent chat that generates real Galaxy workflows

### **Phase 5: Real Backend Connection** (Week 3)
- [ ] Connect to real Galaxy backend API
- [ ] Test on-demand tool installation
- [ ] Execute real workflows on Galaxy
- [ ] Verify job state tracking with real Galaxy jobs
- [ ] Production testing and bug fixes

**Deliverable**: Production-ready integration with Galaxy backend

---

## Part 6: Key Design Principles

### Progress Tracking (CRITICAL)
✅ **DO:**
- Use Galaxy's actual job states (new/queued/running/ok/error)
- Display real elapsed time from Galaxy timestamps
- Show Galaxy's native log output
- Poll Galaxy invocation endpoint for real states

❌ **DON'T:**
- Create fake progress percentages
- Estimate time remaining
- Generate mock log messages
- Calculate "progress" based on step numbers

**Why**: Galaxy's execution time varies wildly based on:
- Tool complexity (FastQC: 30s, GATK: 30min)
- Input data size (1GB vs 100GB)
- Compute resources (local vs cluster)
- Queue wait time (depends on cluster load)

**Accurate progress is impossible to estimate.**
Show actual state and elapsed time only.

### Tool Integration
✅ **DO:**
- Use Galaxy's 2,177 indexed real tools
- On-demand installation with retry logic
- Real tool metadata for parameters
- Actual Galaxy workflow format

❌ **DON'T:**
- Hardcode mock tools (FastQC, HISAT2, etc.)
- Create fake tool parameters
- Bypass Galaxy's tool installation system

### Chat-Workflow Separation
✅ **DO:**
- Chat: Explains, suggests, guides
- Workflow: Executes, configures, displays results
- Clear semantic boundaries

❌ **DON'T:**
- Mix conversational UI with execution controls
- Show workflow graph in chat area
- Duplicate functionality between views

### Parameter Configuration
✅ **DO:**
- Three-tier progressive disclosure
- AI-powered suggestions from chat context
- Galaxy tool schema validation
- Smart defaults from Galaxy metadata

❌ **DON'T:**
- Show all 100+ parameters at once
- Make users guess parameter values
- Ignore chat context when suggesting parameters

---

## Part 7: Files to Create/Modify

### **New Files (12)**

**Backend (6):**
1. `server/galaxy-api-proxy.ts` - Proxy to Galaxy REST API
2. `server/galaxy-state-poller.ts` - Poll Galaxy invocations for state
3. `server/workflow-executor.ts` - Orchestrate Galaxy workflow execution
4. `server/workflow-sse.ts` - Server-Sent Events for real-time updates
5. `server/mock-galaxy-api.ts` - Mock Galaxy responses for UI development
6. `shared/galaxy-types.ts` - TypeScript types for Galaxy API

**Frontend (6):**
7. `client/src/components/workflow-graph-parameter-dialog.tsx` - 3-tier parameter UI
8. `client/src/components/workflow-execution-panel.tsx` - Execution timeline & status
9. `client/src/components/workflow-result-viewer.tsx` - Dataset output viewers
10. `client/src/components/galaxy-log-viewer.tsx` - Display Galaxy stdout/stderr
11. `client/src/hooks/use-workflow-sync.ts` - Bidirectional chat/workflow sync
12. `client/src/lib/galaxy-client.ts` - Frontend Galaxy API client

### **Modified Files (4)**
1. `server/routes.ts` - Add Galaxy endpoints, hybrid chat with tool search
2. `client/src/components/enhanced-workflow-builder.tsx` - Remove list view
3. `client/src/components/workflow-graph.tsx` - Add controls, parameters, states
4. `client/src/components/chat-with-artifacts.tsx` - Add workflow sync logic

---

## Part 8: Technology Stack

### Backend
- **Node.js/Express**: Current backend framework
- **Server-Sent Events (SSE)**: Real-time Galaxy state streaming
- **OpenAI API**: Natural language understanding
- **Galaxy REST API**: Tool search, workflow execution, job tracking
- **BioMNI Dataset RAG**: Dataset discovery and recommendations

### Frontend
- **React + TypeScript**: Current frontend stack
- **Vite**: Build tool
- **Tailwind CSS + shadcn/ui**: UI components
- **SVG + foreignObject**: Workflow graph rendering
- **EventSource API**: SSE client for real-time updates

### Integration
- **Galaxy ToolShed API**: 2,177 indexed tools with metadata
- **Galaxy On-Demand Installer**: Production-ready tool installation
- **Galaxy Invocation API**: Workflow execution tracking
- **Galaxy Jobs API**: Job state monitoring

---

## Part 9: Success Criteria

### Phase 1-3 (Mock Implementation)
- ✅ User can see graph-only workflow view
- ✅ User can configure parameters with 3-tier UI
- ✅ User can execute mock workflow
- ✅ User sees realistic Galaxy state transitions
- ✅ User can view mock execution logs
- ✅ UI performs well with mock data

### Phase 4 (Chat Integration)
- ✅ Chat generates workflows using real Galaxy tools
- ✅ Chat suggests parameters based on conversation
- ✅ Chat provides tool recommendations from Galaxy ToolShed
- ✅ Chat suggests BioMNI datasets
- ✅ Chat explains errors and provides fixes
- ✅ Workflow and chat stay synchronized

### Phase 5 (Real Backend)
- ✅ Workflows execute on real Galaxy backend
- ✅ Tools install on-demand when needed
- ✅ Real Galaxy job states displayed accurately
- ✅ Real Galaxy logs shown in UI
- ✅ Real Galaxy datasets downloadable
- ✅ End-to-end workflow completes successfully

---

## Part 10: Next Steps for Discussion

### Questions for Review:
1. **Approve overall architecture?**
   - Galaxy native tracking instead of custom progress estimation
   - Graph-only view with enhanced parameter configuration
   - Clear semantic separation (chat = guide, workflow = workspace)

2. **Phase approach acceptable?**
   - Start with mock Galaxy API for rapid UI development
   - Connect real backend in final phase
   - Allows UI refinement without backend dependencies

3. **Progress tracking approach?**
   - Use Galaxy's actual job states only
   - No fake progress bars or time estimates
   - Show elapsed time and state transitions

4. **Parameter UI design?**
   - 3-tier progressive disclosure (Essential/Common/Advanced)
   - AI suggestions from chat context
   - Smart defaults from Galaxy tool metadata

5. **Chat-Workflow interaction model?**
   - Chat: Explains, suggests, guides, interprets
   - Workflow: Visualizes, executes, configures, displays
   - Bidirectional sync for seamless UX

6. **Galaxy features to prioritize?**
   - On-demand tool installation (already implemented)
   - BioMNI dataset integration (already implemented)
   - Real-time job state tracking (to be implemented)
   - Log viewing and result downloads (to be implemented)

7. **Additional requirements?**
   - Specific visualization needs?
   - Additional Galaxy API endpoints?
   - Performance requirements?
   - Deployment considerations?

---

## Appendix: Galaxy API Endpoints Reference

Based on Galaxy's BioBlend documentation and existing implementation:

### Workflows
```
POST /api/workflows                    # Create workflow
GET  /api/workflows/{id}               # Get workflow details
POST /api/workflows/{id}/invocations   # Invoke workflow
GET  /api/invocations/{id}             # Get invocation status
```

### Jobs
```
GET  /api/jobs/{id}                    # Get job details
GET  /api/jobs/{id}/stdout             # Get job stdout
GET  /api/jobs/{id}/stderr             # Get job stderr
```

### Tools
```
GET  /api/tools                        # List installed tools
POST /api/tool_search                  # Search ToolShed (custom endpoint)
POST /api/tool_search/install          # On-demand install (custom endpoint)
```

### Datasets
```
GET  /api/datasets/{id}                # Get dataset details
GET  /api/datasets/{id}/display        # Download dataset
GET  /api/datasets                     # List datasets
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-03
**Status**: Ready for Review & Discussion