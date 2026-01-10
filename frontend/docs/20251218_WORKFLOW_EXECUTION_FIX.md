# Workflow Execution Fix - December 18, 2025

## Problem

E2E tests were failing because workflow execution was never happening. The user would:
1. Request a workflow from the AI
2. AI generates workflow successfully
3. User clicks "Run" button
4. **Nothing happens** - workflow never executes

## Root Cause Analysis

### Investigation Path

1. **E2E test logs** showed workflows generating correctly with proper tools
2. **`handleRunWorkflow`** in `chat-with-artifacts.tsx` was a stub:
   ```typescript
   const handleRunWorkflow = async () => {
     console.log('ChatWithArtifacts: Running workflow');
     setIsWorkflowRunning(true);
     setWorkflowProgress(0);
     // TODO: Integrate with Galaxy workflow execution
   };
   ```
3. **Callback chain** wasn't passing workflow data:
   - `WorkflowArtifact` → called `onRun()` with no arguments
   - `ChatMessage` → passed empty callback
   - `ChatInterface` → passed empty callback
   - `ChatWithArtifacts` → received no workflow data

### Galaxy Workflow Execution Requirements

Compared with original Galaxy code in:
- `backend/lib/galaxy/webapps/galaxy/api/workflows.py`
- `backend/lib/galaxy/webapps/galaxy/services/workflows.py`
- `backend/lib/galaxy/schema/workflows.py`

Galaxy requires:
1. **Workflow in `.ga` format** with `a_galaxy_workflow: "true"`
2. **History** for outputs (`history_id` or `new_history_name`)
3. **Input mappings** for datasets: `{"step_id": {"src": "hda", "id": "..."}}`

## Solution

### Files Modified

#### 1. `frontend/client/src/components/workflow-artifact.tsx`

**Change**: Updated `onRun` prop to pass workflow data

```typescript
// Before
interface WorkflowArtifactProps {
  onRun?: () => void
}
// Button: onClick={onRun}

// After
interface WorkflowArtifactProps {
  onRun?: (workflow: any, steps: WorkflowStep[]) => void
}
// Button: onClick={() => onRun?.(workflow, normalizedSteps)}
```

#### 2. `frontend/client/src/components/chat-message.tsx`

**Change**: Updated type signature

```typescript
// Before
onRunWorkflow?: () => void

// After
onRunWorkflow?: (workflow: any, steps: any[]) => void
```

#### 3. `frontend/client/src/components/chat-interface.tsx`

**Change**: Updated type signature

```typescript
// Before
onRunWorkflow?: () => void

// After
onRunWorkflow?: (workflow: any, steps: any[]) => void
```

#### 4. `frontend/client/src/components/chat-with-artifacts.tsx`

**Complete rewrite** of workflow execution logic:

```typescript
import { useWorkflowExecution } from "@/hooks/useWorkflowExecution"

// Added real-time execution tracking
const {
  invocationId,
  workflowState,
  steps: executionSteps,
  error: executionError,
  isConnected,
  isComplete,
  invokeWorkflow,
  cancelWorkflow,
} = useWorkflowExecution()

// Implemented handleRunWorkflow
const handleRunWorkflow = async (workflow: any, steps: any[]) => {
  // Step 1: Detect workflow format
  if (workflow.a_galaxy_workflow) {
    // Use AI-generated .ga format directly
    workflowDefinition = workflow;
  } else {
    // Build Galaxy workflow from simplified format
    workflowDefinition = { a_galaxy_workflow: "true", ... };
  }

  // Step 2: Create workflow in Galaxy
  const createResponse = await fetch('/api/galaxy/workflows', {
    method: 'POST',
    body: JSON.stringify({ workflow: workflowDefinition })
  });

  // Step 3: Extract dataset inputs from AI assignments
  const workflowInputs = {};
  if (workflow.dataset_assignments?.workflow_steps) {
    // Map datasets to step inputs
  }

  // Step 4: Invoke workflow with SSE tracking
  const galaxyInvocation = await invokeWorkflow(workflowId, workflowInputs);
};
```

**Added UI elements**:
- Connection status indicator (green "Live" badge)
- Execution progress bar with percentage
- Error display banner

#### 5. `frontend/server/routes.ts`

**Change**: Updated invoke endpoint to handle history

```typescript
// Before
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
  const { workflow_id, inputs, parameters } = req.body;
  const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
});

// After
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
  const { workflow_id, inputs, parameters, history_id, new_history_name } = req.body;

  const invokeParams = {
    ...parameters,
    // Auto-create history if not provided
    ...(history_id
      ? { history_id }
      : { new_history_name: new_history_name || `bioMate Workflow Run ${new Date().toISOString()}` }
    )
  };

  const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, invokeParams);
});
```

## Data Flow After Fix

```
User clicks "Run" in WorkflowArtifact
    │
    ▼
WorkflowArtifact.onRun(workflow, normalizedSteps)
    │
    ▼
ChatMessage.onRunWorkflow(workflow, steps)
    │
    ▼
ChatInterface.onRunWorkflow(workflow, steps)
    │
    ▼
ChatWithArtifacts.handleRunWorkflow(workflow, steps)
    │
    ├─► Check if workflow.a_galaxy_workflow exists
    │   ├─ Yes: Use AI-generated .ga format directly
    │   └─ No: Build .ga format from steps array
    │
    ├─► POST /api/galaxy/workflows
    │   └─ Creates workflow in Galaxy, returns workflow_id
    │
    ├─► Extract dataset inputs from workflow.dataset_assignments
    │
    ├─► invokeWorkflow(workflowId, inputs) via useWorkflowExecution hook
    │   └─ POST /api/galaxy/workflows/invoke
    │       ├─ workflow_id
    │       ├─ inputs: {"step_id": {"src": "hda", "id": "..."}}
    │       └─ new_history_name: "bioMate Workflow Run 2025-..."
    │
    └─► SSE connection established
        └─ GET /api/galaxy/workflows/sse/{invocationId}
            └─ Real-time step progress updates
```

## Testing

Run E2E tests to verify workflow execution now works:

```bash
cd /home/yzhang/biomate/Biomni/biomni_galaxy/tests
ANTHROPIC_API_KEY='...' /home/yzhang/biomate/backend/.venv/bin/python e2e_biomni_ai_agent_test.py
```

### E2E Test Results (December 18, 2025)

After fixes, test results improved from **0/8 to 3/8 scenarios passing**:

| Scenario | Result | Notes |
|----------|--------|-------|
| Database Query (UniProt) | FAIL | Tools not installed in Galaxy |
| Genomics (gene enrichment) | PASS | Execution completed |
| Molecular Biology (primers) | FAIL | biomni/molecular_biology/design_primer not installed |
| Bioimaging (segmentation) | FAIL | Cellpose tools not installed |
| Pharmacology (drug targets) | FAIL | ChEMBL/ADMET tools not installed |
| scRNA Cell Type | PASS | Execution completed |
| Batch Image Registration | PASS | Execution completed |
| PCR Analysis | FAIL | Primer design tools not installed |

### Root Cause of Remaining Failures

Galaxy returns 400 Bad Request with message:
```
"Workflow was not invoked; the following required tools are not installed: [tool_ids]"
```

The AI generates workflows with tool IDs that don't exist in Galaxy:
- `biomni/molecular_biology/design_primer` - not installed
- `toolshed.g2.bx.psu.edu/repos/bgruening/uniprot_rest_interface/...` - not installed
- `toolshed.g2.bx.psu.edu/repos/bgruening/cellpose/...` - not installed

### Fix for Remaining Issues

1. **Install missing tools in Galaxy** via Tool Shed
2. **Or** update AI to only use tools that are installed (tool index should reflect actual Galaxy installation)

### E2E Test Fix Applied

Also fixed the E2E test to look for "Run" button (not "Execute"):

```python
# e2e_biomni_ai_agent_test.py line 262
run_btn = page.locator("button:has-text('Run')").first  # Added this
execute_btn = page.locator("button:has-text('Execute')").first
start_workflow_btn = page.locator("button:has-text('Start Workflow')").first
```

## Related Files

- `frontend/client/src/hooks/useWorkflowExecution.ts` - SSE workflow tracking hook
- `frontend/server/galaxy-api-proxy.ts` - Galaxy API proxy layer
- `backend/lib/galaxy/ai/galaxy_workflow_generator.py` - AI workflow generator
- `backend/lib/galaxy/webapps/galaxy/api/workflows.py` - Galaxy workflow API
