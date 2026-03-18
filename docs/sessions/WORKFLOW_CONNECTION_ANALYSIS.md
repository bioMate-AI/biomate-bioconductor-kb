# Workflow Frontend-Backend Connection Analysis

## Current Issues Summary

1. **Workflow Generation**: Backend returns `success: false` for DIA LC-MS queries
2. **Workflow Data Format**: Mismatch between demo workflow format and Galaxy .ga format
3. **Workflow Execution**: `/api/workflow/step/execute` returns "No Galaxy history found"
4. **Session Management**: Old workflows persist across new chat sessions

---

## Flow Analysis

### 1. Workflow Generation Flow

```
User Query
  ↓
ChatInterface.handleSendMessage()
  ↓
POST /api/ai_assistant/generate_workflow
  ↓
Galaxy Backend (workflow generation)
  ↓
Response: { success: boolean, workflow_ga: object, message: string }
  ↓
ChatInterface.onSuccess()
  ↓
Store in message.metadata.workflow
  ↓
User clicks "Create Workflow"
  ↓
onWorkflowGenerated(workflow)
  ↓
setWorkflowFromChat() in chat-with-artifacts
```

**Issues Found:**
- ❌ Backend doesn't have DIA LC-MS workflow template
- ❌ Demo workflow format != Galaxy .ga format
- ❌ Demo workflow has `{id, title, type, steps: [{id, title, description, tool}]}`
- ❌ Galaxy .ga has `{name, annotation, steps: {0: {tool_id, name, type}}}`

### 2. Workflow Execution Flow

```
User clicks "Run Step"
  ↓
EnhancedWorkflowBuilder.executeStep()
  ↓
POST /api/workflow/step/execute
  {
    workflowId: string,
    stepId: string,
    inputs: object
  }
  ↓
Backend needs:
  - Galaxy history_id (from session)
  - Workflow uploaded to Galaxy
  - Tool available in Galaxy
  ↓
Returns: { job_id, status }
  ↓
Frontend polls for status
```

**Issues Found:**
- ❌ No Galaxy history_id in session
- ❌ Workflow not uploaded to Galaxy before execution
- ❌ Demo workflow tools (FastQC, HISAT2) may not match Galaxy tool IDs

---

## Data Format Analysis

### Demo Workflow Format (generateDemoWorkflow)
```json
{
  "id": "workflow-123",
  "title": "RNA-seq Analysis Pipeline",
  "description": "...",
  "type": "rna-seq",
  "steps": [
    {
      "id": "step1",
      "title": "Quality Control",
      "description": "...",
      "tool": "FastQC",
      "complexity": "simple",
      "estimatedTime": "5 min"
    }
  ]
}
```

### Galaxy .ga Format
```json
{
  "name": "RNA-seq DE Analysis",
  "annotation": "...",
  "format-version": "0.1",
  "steps": {
    "0": {
      "id": 0,
      "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72",
      "name": "FastQC",
      "type": "tool",
      "tool_state": "..."
    }
  }
}
```

### Required Frontend Format (EnhancedWorkflowBuilder)
```typescript
interface WorkflowStep {
  id: string;
  name: string;
  tool?: string;
  type: 'input' | 'tool' | 'subworkflow';
  status?: 'idle' | 'running' | 'completed' | 'failed';
}
```

---

## Root Causes

### 1. Workflow Format Incompatibility
- Demo workflow uses simple format for UI display
- Galaxy .ga uses complex nested format
- Frontend builder expects flat array of steps
- **Solution**: Create adapter to convert between formats

### 2. Missing Galaxy Integration
- No Galaxy history created for chat session
- Workflow not imported to Galaxy before execution
- **Solution**: Create/get history on first workflow generation

### 3. Session State Management
- Sessions persist in localStorage
- Old workflows remain loaded
- **Solution**: Already fixed with start_new_chat()

### 4. Tool ID Mismatch
- Demo uses simple names: "FastQC"
- Galaxy needs full IDs: "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72"
- **Solution**: Map simple names to Galaxy tool IDs

---

## Comprehensive Fix Plan

### Phase 1: Workflow Format Standardization ✓ PRIORITY
**File**: `frontend/client/src/lib/workflow-adapter.ts` (NEW)

```typescript
export interface StandardWorkflow {
  id: string;
  name: string;
  description?: string;
  annotation?: string;
  steps: StandardStep[];
  galaxyFormat?: any; // Original Galaxy .ga if available
}

export interface StandardStep {
  id: string;
  name: string;
  tool: string;
  toolId?: string; // Galaxy full tool ID
  description?: string;
  type: 'input' | 'tool' | 'subworkflow';
  status?: 'idle' | 'running' | 'completed' | 'failed';
}

export class WorkflowAdapter {
  // Convert demo workflow → standard format
  static fromDemoWorkflow(demo: any): StandardWorkflow

  // Convert Galaxy .ga → standard format
  static fromGalaxyGA(ga: any): StandardWorkflow

  // Convert standard → Galaxy .ga for import
  static toGalaxyGA(standard: StandardWorkflow): any
}
```

### Phase 2: Galaxy History Management ✓ PRIORITY
**File**: `frontend/server/routes.ts`

```typescript
// Add to session type
interface ChatSession {
  galaxyHistoryId?: string;
  galaxyWorkflowId?: string;
}

// On workflow generation, create/get history
app.post("/api/ai_assistant/generate_workflow", async (req, res) => {
  // ... generate workflow ...

  // Get or create Galaxy history for this session
  if (!req.session.galaxyHistoryId) {
    const history = await galaxyAPIProxy.createHistory({
      name: `BioMate Chat ${Date.now()}`
    });
    req.session.galaxyHistoryId = history.id;
  }

  // Import workflow to Galaxy
  const galaxyWorkflow = await galaxyAPIProxy.importWorkflow(workflowData);
  req.session.galaxyWorkflowId = galaxyWorkflow.id;

  res.json({
    success: true,
    workflow_ga: workflowData,
    galaxyHistoryId: req.session.galaxyHistoryId,
    galaxyWorkflowId: galaxyWorkflow.id
  });
});
```

### Phase 3: Workflow Execution Fix ✓ PRIORITY
**File**: `frontend/server/routes.ts`

```typescript
app.post("/api/workflow/step/execute", async (req, res) => {
  const { workflowId, stepId, inputs } = req.body;

  // Get history from session
  const historyId = req.session.galaxyHistoryId;
  if (!historyId) {
    return res.status(400).json({
      error: "No Galaxy history found. Please generate a workflow first."
    });
  }

  // Execute single tool from workflow
  const result = await galaxyAPIProxy.executeWorkflowStep({
    historyId,
    workflowId: req.session.galaxyWorkflowId,
    stepId,
    inputs
  });

  res.json(result);
});
```

### Phase 4: Frontend Integration
**File**: `frontend/client/src/components/enhanced-workflow-builder.tsx`

```typescript
// Store Galaxy IDs from workflow generation
const [galaxyHistoryId, setGalaxyHistoryId] = useState<string>();
const [galaxyWorkflowId, setGalaxyWorkflowId] = useState<string>();

// When workflow loaded
useEffect(() => {
  if (workflow?.metadata?.galaxyHistoryId) {
    setGalaxyHistoryId(workflow.metadata.galaxyHistoryId);
    setGalaxyWorkflowId(workflow.metadata.galaxyWorkflowId);
  }
}, [workflow]);

// Execute step with Galaxy context
const executeStep = async (stepId: string) => {
  const response = await fetch('/api/workflow/step/execute', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflowId: galaxyWorkflowId,
      stepId,
      inputs: {}
    })
  });
  // ... handle response ...
};
```

---

## Testing Strategy

### Unit Tests

1. **WorkflowAdapter Tests**
   - ✓ Convert demo → standard
   - ✓ Convert Galaxy .ga → standard
   - ✓ Convert standard → Galaxy .ga
   - ✓ Handle missing fields gracefully

2. **Session Management Tests**
   - ✓ Create Galaxy history on first workflow
   - ✓ Reuse history for same session
   - ✓ Clear history on new chat

3. **Workflow Execution Tests**
   - ✓ Fail gracefully without history
   - ✓ Execute with valid history
   - ✓ Return job status correctly

### Integration Tests

1. **Workflow Generation Flow**
   - Send query → receive workflow → store in session

2. **Workflow Loading Flow**
   - Click "Create Workflow" → load to builder → display correctly

3. **Step Execution Flow**
   - Click "Run Step" → execute in Galaxy → poll status → update UI

### E2E Test

- Run test_07_monitor_step_execution after all fixes

---

## Implementation Priority

1. ✅ **HIGH**: WorkflowAdapter - unifies all formats
2. ✅ **HIGH**: Galaxy history creation - enables execution
3. ✅ **HIGH**: Workflow execution fix - core functionality
4. ✅ **MEDIUM**: Store Galaxy IDs in message metadata
5. ✅ **LOW**: Tool ID mapping for demo workflows

---

## Files to Modify

1. **NEW**: `frontend/client/src/lib/workflow-adapter.ts`
2. **MODIFY**: `frontend/client/src/components/chat-interface.tsx`
3. **MODIFY**: `frontend/server/routes.ts`
4. **MODIFY**: `frontend/client/src/components/enhanced-workflow-builder.tsx`
5. **MODIFY**: `frontend/client/src/components/chat-with-artifacts.tsx`

---

## Success Criteria

- [ ] All workflow formats (demo, .ga, standard) convert correctly
- [ ] Galaxy history created on workflow generation
- [ ] Workflow imported to Galaxy automatically
- [ ] Step execution returns valid job IDs
- [ ] Status polling works correctly
- [ ] test_07 passes end-to-end
