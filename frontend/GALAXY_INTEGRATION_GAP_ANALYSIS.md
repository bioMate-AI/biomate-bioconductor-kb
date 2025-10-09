# Galaxy Integration Gap Analysis

**Date:** October 4, 2025

## Executive Summary

Phase 5 completed the **repository and UI layer** but **Galaxy execution integration** is incomplete. The system can save/load templates and files, but cannot execute workflows on real Galaxy instances.

---

## ✅ What Phase 5 Actually Completed

### Repository Layer (100% Complete)
- ✅ Parameter template storage and retrieval
- ✅ Workflow template storage and retrieval
- ✅ Use case metadata management
- ✅ Template search and filtering

### UI Layer (100% Complete)
- ✅ Save workflow dialog
- ✅ Export workflow (.ga) button
- ✅ Parameter template loading in ParameterEditor
- ✅ File upload component (drag-and-drop, progress)

### Data Persistence (100% Complete)
- ✅ JSON file storage for templates
- ✅ File storage for uploads (`data/uploads/`)
- ✅ Auto-seeding with example templates

---

## ❌ What's MISSING - Galaxy Execution Integration

### 1. Dataset Upload to Galaxy (0% Complete)

**Current State:**
```typescript
// server/routes.ts line 183
app.post("/api/datasets/upload", upload.single('file'), async (req, res) => {
  // Files saved to: data/uploads/
  // Returns: local dataset_id
  // ❌ Does NOT upload to Galaxy
});
```

**What's Needed:**
```typescript
// Upload file to Galaxy's dataset library
async function uploadToGalaxy(filePath: string): Promise<string> {
  const formData = new FormData();
  formData.append('file', fs.createReadStream(filePath));

  const response = await galaxyAPI.post('/api/histories/{history_id}/contents', formData);
  return response.data.id; // Galaxy dataset ID
}
```

**Missing Methods in GalaxyAPIProxy:**
- `uploadDataset(file, historyId)` - Upload file to Galaxy history
- `createHistory(name)` - Create new history for user session
- `getHistoryDatasets(historyId)` - List datasets in history

---

### 2. Workflow Execution with Parameters (30% Complete)

**Current State:**
```typescript
// client/src/components/enhanced-workflow-builder.tsx line 204
const handleWorkflowAction = async (action: 'start') => {
  const mockWorkflowId = 'mock-rna-seq-workflow'; // ❌ Mock only
  const mockInputs = { /* ... */ };                // ❌ Not using templates
  await invokeWorkflow(mockWorkflowId, mockInputs); // ❌ Not using real Galaxy
}
```

**What Exists:**
- ✅ `GalaxyAPIProxy.invokeWorkflow()` method exists
- ✅ `WorkflowSSEManager` for real-time tracking exists
- ✅ `useWorkflowExecution` hook exists

**What's Missing:**
```typescript
// Map template parameters to workflow inputs
function buildWorkflowInputs(
  workflowSteps: WorkflowStep[],
  uploadedDatasets: Dataset[]
): Record<string, any> {
  return workflowSteps.reduce((inputs, step) => {
    // Apply parameter template for this step
    const template = await parameterRepository.getTemplateForTool(step.tool);
    inputs[step.id] = {
      ...template.parameters,
      // Map uploaded datasets to step inputs
      input_datasets: uploadedDatasets.filter(d => d.stepId === step.id)
    };
    return inputs;
  }, {});
}
```

**Integration Gap:**
- ❌ Workflow invocation uses mock data instead of saved workflows
- ❌ Parameter templates not applied during execution
- ❌ Uploaded datasets not linked to workflow inputs
- ❌ No history management (workflows run in user's history)

---

### 3. Step-by-Step Execution Control (0% Complete)

**Current State:**
- Local state updates only
- No individual step submission to Galaxy
- No per-step job tracking

**What's Needed:**
```typescript
// Execute workflow step-by-step instead of all at once
async function executeStepByStep(steps: WorkflowStep[]) {
  for (const step of steps) {
    // Submit single tool job to Galaxy
    const job = await galaxyAPI.submitToolJob({
      tool_id: step.tool,
      inputs: step.parameters,
      history_id: currentHistoryId
    });

    // Wait for completion
    await pollJobStatus(job.id);

    // Get outputs for next step
    const outputs = await galaxyAPI.getJobOutputs(job.id);
  }
}
```

**Missing Methods in GalaxyAPIProxy:**
- `submitToolJob(toolId, inputs, historyId)` - Run single tool
- `pollJobStatus(jobId)` - Check job progress
- `getJobOutputs(jobId)` - Get output datasets

---

### 4. Dataset Integration in Workflow Builder (0% Complete)

**Current Problem:**
- User uploads file → gets local `dataset_id`
- Workflow executes → has no idea about uploaded files
- No UI to link datasets to workflow step inputs

**What's Needed:**
1. **Dataset Selection UI in ParameterEditor**
```typescript
// When user configures a step, show available datasets
<Select label="Input Dataset">
  {uploadedDatasets.map(d => (
    <option value={d.galaxy_id}>{d.name}</option>
  ))}
</Select>
```

2. **Dataset Mapper**
```typescript
interface StepDatasetMapping {
  stepId: string;
  inputName: string; // e.g., "fastq_input"
  datasetId: string; // Galaxy dataset ID
}

// Store mappings when user selects datasets
function mapDatasetToStep(stepId: string, inputName: string, datasetId: string) {
  workflowDatasetMappings.push({ stepId, inputName, datasetId });
}
```

3. **Apply Mappings During Execution**
```typescript
async function invokeWorkflowWithDatasets(workflow: Workflow) {
  const inputs = {};
  for (const mapping of workflowDatasetMappings) {
    inputs[mapping.stepId] = {
      [mapping.inputName]: { id: mapping.datasetId, src: "hda" }
    };
  }
  await galaxyAPI.invokeWorkflow(workflow.id, inputs);
}
```

---

## 📊 Completion Status

| Component | Repository Layer | UI Layer | Galaxy Integration |
|-----------|-----------------|----------|-------------------|
| Parameter Templates | ✅ 100% | ✅ 100% | ❌ 0% |
| Workflow Templates | ✅ 100% | ✅ 100% | ❌ 30% |
| File Upload | ✅ 100% | ✅ 100% | ❌ 0% |
| Workflow Execution | N/A | ✅ 100% | ❌ 20% |
| Step Control | N/A | ✅ 100% | ❌ 0% |

**Overall Integration:** ~26% Complete

---

## 🎯 What Needs to Be Done

### Phase 6: Galaxy Execution Integration

#### Sprint 1: Dataset Management (2-3 days)
1. Add `uploadDataset()` to `GalaxyAPIProxy`
2. Add `createHistory()` and `getHistories()` to `GalaxyAPIProxy`
3. Modify `/api/datasets/upload` to call Galaxy upload API
4. Add dataset selection UI to `ParameterEditor`
5. Implement dataset-to-step mapping

#### Sprint 2: Workflow Execution (2-3 days)
6. Modify `EnhancedWorkflowBuilder` to use real workflow IDs
7. Build workflow inputs from parameter templates + dataset mappings
8. Call real `galaxyAPI.invokeWorkflow()` instead of mock
9. Connect `WorkflowSSEManager` to real invocations
10. Display real job logs from Galaxy

#### Sprint 3: Step-by-Step Execution (2-3 days)
11. Add `submitToolJob()` to `GalaxyAPIProxy`
12. Implement step-by-step execution mode
13. Add per-step job tracking
14. Handle step dependencies and outputs

#### Sprint 4: Testing & Polish (1-2 days)
15. End-to-end testing with real Galaxy instance
16. Error handling for Galaxy API failures
17. User feedback for failed jobs
18. Documentation

**Total Estimated Time:** 7-11 days

---

## 🔧 Required API Methods

### New Methods Needed in `GalaxyAPIProxy`:

```typescript
// Dataset Management
async uploadDataset(file: File, historyId: string): Promise<string>
async createHistory(name: string): Promise<string>
async getHistories(): Promise<History[]>
async getHistoryDatasets(historyId: string): Promise<Dataset[]>

// Tool Execution
async submitToolJob(toolId: string, inputs: any, historyId: string): Promise<Job>
async getJobOutputs(jobId: string): Promise<Dataset[]>

// Workflow Execution (enhanced)
async importWorkflow(workflowGa: any): Promise<string> // Import .ga file
async getWorkflowInputs(workflowId: string): Promise<WorkflowInput[]>
```

---

## 🚨 Critical Blockers

1. **No Galaxy Instance Running**
   - Need real Galaxy server URL and API key
   - Mock API only supports limited operations

2. **No History Management**
   - Workflows must run in a user's history
   - Need to create/manage histories per session

3. **No Dataset Library Integration**
   - Uploaded files must be in Galaxy before workflow runs
   - Need to track Galaxy dataset IDs vs local file IDs

4. **No Step Input Discovery**
   - Don't know which step inputs require datasets
   - Need to parse workflow .ga to find input slots

---

## 💡 Recommended Approach

### Option 1: Full Galaxy Integration (7-11 days)
- Implement all missing methods
- Connect to real Galaxy instance
- Full production-ready execution

### Option 2: Enhanced Mock Mode (2-3 days)
- Improve mock API to simulate execution
- File upload → mock Galaxy dataset
- Workflow execution → simulated progress
- Good for demo/testing without Galaxy server

### Option 3: Hybrid Approach (4-6 days)
- Keep mock execution for workflows
- Add real dataset upload to Galaxy
- Add real job submission for individual tools
- Gradually migrate to full Galaxy

---

**Recommendation:** Start with **Option 2 (Enhanced Mock)** to validate the full flow, then migrate to **Option 1 (Full Integration)** once Galaxy instance is available.

---

**Last Updated:** October 4, 2025, 1:30 PM
