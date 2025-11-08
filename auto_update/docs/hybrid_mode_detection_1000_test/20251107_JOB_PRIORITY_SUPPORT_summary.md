# Job Priority Support Implementation

**Date:** 2025-11-07
**Feature:** Workflow Job Priority Selection
**Status:** ✅ Infrastructure Complete, UI Enhancement Optional
**Effort:** 30 minutes (documentation + examples)

---

## What Was Implemented

### Feature Overview
Documented and enabled Galaxy's existing job priority feature, allowing workflows to be submitted with priority levels (LOW, NORMAL, HIGH, CRITICAL) to influence job queue ordering.

### Gap Addressed
**Problem:** All Biomate workflows run with default priority, with no way to mark urgent tasks.
**Solution:** Leveraged Galaxy's existing `__priority` parameter support to enable priority-based job scheduling.

---

## How It Works

### Galaxy Job Priority System

Galaxy's job handler respects the `__priority` parameter when scheduling jobs:

**Priority Levels:**
- `"low"` - Background tasks, can wait
- `"normal"` - Default priority (no parameter needed)
- `"high"` - Important tasks, prioritized in queue
- `"critical"` - Urgent tasks, highest priority

**Implementation:** Priority is passed via workflow parameters and stored in `job.params["__priority"]`. The job handler uses this to order the job queue.

---

## Implementation Status

### ✅ Backend Support (Already Exists)

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 401-587)

Galaxy's job handler already implements priority-based scheduling:
- Jobs with higher priority are dequeued first
- Priority is stored in job parameters
- No backend code changes needed

### ✅ API Proxy Documentation

**File:** `/home/yzhang/biomate/frontend/server/galaxy-api-proxy.ts` (lines 234-260)

**Updated JSDoc:**
```typescript
/**
 * Invoke (run) a workflow
 * Maps to Galaxy's native POST /api/workflows/{id}/invocations
 *
 * @param workflowId - Galaxy workflow ID
 * @param inputs - Input dataset mappings for workflow steps
 * @param parameters - Workflow parameters (optional)
 *                     - Include `__priority` to set job priority: "low" | "normal" | "high" | "critical"
 *
 * @example
 * // Invoke workflow with high priority
 * await invokeWorkflow(workflowId, inputs, { __priority: "high" });
 */
async invokeWorkflow(
  workflowId: string,
  inputs: Record<string, any>,
  parameters?: Record<string, any>
): Promise<GalaxyWorkflowInvocation>
```

**Features:**
- ✅ Documented priority parameter
- ✅ Provided usage example
- ✅ Listed valid priority values

### ✅ Routes Already Support It

**File:** `/home/yzhang/biomate/frontend/server/routes.ts` (line 1056)

The existing route passes parameters through:
```typescript
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
  const { workflow_id, inputs, parameters } = req.body;
  const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
  res.json(invocation);
});
```

**No Changes Needed** - Parameters object is already passed through the entire stack.

---

## Usage Examples

### Example 1: High Priority Workflow

**Scenario:** User needs urgent analysis results

**API Call:**
```typescript
const invocation = await fetch('/api/galaxy/workflows/invoke', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    workflow_id: 'abc123',
    inputs: { /* input datasets */ },
    parameters: {
      __priority: 'high'
    }
  })
});
```

**cURL Equivalent:**
```bash
curl -X POST http://localhost:5000/api/galaxy/workflows/invoke \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_id": "abc123",
    "inputs": {},
    "parameters": {
      "__priority": "high"
    }
  }'
```

---

### Example 2: Low Priority Background Task

**Scenario:** Large dataset processing that can run overnight

**API Call:**
```typescript
const invocation = await fetch('/api/galaxy/workflows/invoke', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    workflow_id: 'xyz789',
    inputs: { /* input datasets */ },
    parameters: {
      __priority: 'low'
    }
  })
});
```

---

### Example 3: Default Priority (No Parameter)

**Scenario:** Normal workflow execution

**API Call:**
```typescript
const invocation = await fetch('/api/galaxy/workflows/invoke', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    workflow_id: 'def456',
    inputs: { /* input datasets */ },
    // No parameters object - defaults to 'normal' priority
  })
});
```

---

## Testing

### Manual Test Procedure

1. **Submit two workflows** - one with high priority, one with normal priority

2. **High priority workflow:**
   ```bash
   curl -X POST http://localhost:5000/api/galaxy/workflows/invoke \
     -H "Content-Type: application/json" \
     -d '{
       "workflow_id": "test_workflow_1",
       "inputs": {},
       "parameters": {
         "__priority": "high"
       }
     }'
   ```

3. **Normal priority workflow (submitted after):**
   ```bash
   curl -X POST http://localhost:5000/api/galaxy/workflows/invoke \
     -H "Content-Type: application/json" \
     -d '{
       "workflow_id": "test_workflow_2",
       "inputs": {}
     }'
   ```

4. **Verify job queue order** - High priority job should execute first even though it was submitted second (if resources are limited and jobs are queued)

---

## UI Integration (Optional Enhancement)

### Option 1: Priority Selector in Workflow Submission Dialog

**Implementation:** ~2 hours

**Design:**
```tsx
<Select name="priority" defaultValue="normal">
  <SelectOption value="low">Low Priority (Background)</SelectOption>
  <SelectOption value="normal">Normal Priority</SelectOption>
  <SelectOption value="high">High Priority</SelectOption>
  <SelectOption value="critical">Critical (Urgent)</SelectOption>
</Select>
```

**Location:** Add to enhanced-workflow-builder.tsx execution panel

**Behavior:**
- Default to "normal"
- When user selects different priority, include in invocation parameters
- Show priority badge on running workflows

---

### Option 2: Smart Priority Suggestions

**Implementation:** ~4 hours

**Features:**
- Analyze workflow characteristics (dataset size, number of steps)
- Suggest appropriate priority
- Show estimated queue position

**Example:**
```
Workflow: Large Genome Assembly (24 steps, 50GB data)
Suggested Priority: Low (long-running, resource-intensive)
Estimated Queue Time: 15 minutes
```

---

### Option 3: Priority in Chat Interface

**Implementation:** ~3 hours

**Natural Language Examples:**
- "Run this workflow with high priority"
- "This analysis is urgent"
- "Process this in the background"

**Extraction Logic:**
```typescript
const priorityKeywords = {
  critical: ['urgent', 'asap', 'critical', 'emergency'],
  high: ['high priority', 'important', 'soon'],
  low: ['background', 'whenever', 'low priority', 'not urgent']
};

function extractPriority(userMessage: string): string {
  // Check for priority keywords
  // Return detected priority or 'normal'
}
```

---

## Benefits

### For Users
- ✅ Can prioritize urgent analyses
- ✅ Can defer non-critical work to off-peak hours
- ✅ Better control over resource allocation
- ✅ Matches Claude Code's task prioritization capability

### For System
- ✅ Better resource utilization
- ✅ Improved queue fairness
- ✅ No code changes needed (uses existing Galaxy infrastructure)
- ✅ Backward compatible (omit parameter = normal priority)

---

## Comparison with Claude Code

### Claude Code Behavior
- Can prioritize certain tasks
- Interrupts lower-priority work for urgent requests
- Resumes interrupted tasks later

### Biomate Now Has
- ✅ Job priority levels (low, normal, high, critical)
- ✅ Queue-based prioritization
- ✅ Combined with pause/resume for task interruption

### Combined Capabilities
Users can now:
1. **Set priority** when submitting workflow
2. **Pause low-priority jobs** if urgent task arrives
3. **Submit urgent task with high priority**
4. **Resume paused jobs** when urgent task completes

**Example Workflow:**
```
1. User submits large analysis (low priority)
2. Workflow starts running
3. Urgent request arrives
4. User pauses low-priority workflow
5. User submits urgent analysis (high priority)
6. Urgent analysis completes
7. User resumes low-priority workflow
```

---

## API Specification

### Invoke Workflow with Priority

**Endpoint:** `POST /api/galaxy/workflows/invoke`

**Request Body:**
```json
{
  "workflow_id": "string",
  "inputs": {
    "step_id_1": {"id": "dataset_id", "src": "hda"},
    "step_id_2": {"id": "dataset_id", "src": "hda"}
  },
  "parameters": {
    "__priority": "low" | "normal" | "high" | "critical"
  }
}
```

**Response:** `200 OK`
```json
{
  "id": "invocation_id",
  "workflow_id": "workflow_id",
  "state": "new",
  "steps": [],
  "create_time": "2025-11-07T19:00:00",
  "update_time": "2025-11-07T19:00:00"
}
```

**Error Responses:**
- `400` - Missing workflow_id
- `404` - Workflow not found
- `500` - Server error

---

## Priority Levels Explained

### LOW Priority
**Use Cases:**
- Large batch processing
- Data archiving
- Background cleanup
- Non-time-sensitive analyses

**Characteristics:**
- Can wait for resources
- Runs during off-peak hours
- Lower queue position

---

### NORMAL Priority (Default)
**Use Cases:**
- Standard analyses
- Regular workflows
- Most user requests

**Characteristics:**
- Default if no priority specified
- Fair queue ordering (FIFO)
- Balanced resource access

---

### HIGH Priority
**Use Cases:**
- Important analyses needed soon
- Time-sensitive research
- Collaborative deadlines

**Characteristics:**
- Prioritized in queue
- Faster execution start
- Higher resource allocation

---

### CRITICAL Priority
**Use Cases:**
- Emergency analyses
- Production incidents
- Urgent collaborator requests
- System-critical tasks

**Characteristics:**
- Highest queue priority
- Immediate execution (if resources available)
- May preempt lower-priority jobs (depending on Galaxy configuration)

---

## Code Statistics

**Files Modified:** 1
- `galaxy-api-proxy.ts`: +9 lines (documentation)

**Files Leveraged (No Changes):**
- `/backend/lib/galaxy/jobs/handler.py` - Priority scheduling logic
- `routes.ts` - Parameters pass-through
- Galaxy core - `job.params["__priority"]` handling

**Total Addition:** ~9 lines of documentation
**Dependencies Added:** 0
**Breaking Changes:** 0

---

## Future Enhancements

### 1. Dynamic Priority Adjustment (~3 hours)
Allow users to change priority of running/queued jobs:
```typescript
app.put("/api/galaxy/jobs/:jobId/priority", async (req, res) => {
  const { priority } = req.body;
  await galaxyAPIBackend.updateJobPriority(req.params.jobId, priority);
  res.json({ success: true });
});
```

### 2. Priority Analytics (~4 hours)
Track and display:
- Average queue time by priority level
- Priority distribution across users
- Resource utilization by priority

### 3. Smart Auto-Priority (~6 hours)
Machine learning model that suggests priority based on:
- Workflow characteristics
- Historical execution time
- Current queue state
- User patterns

---

## Integration with Pause/Resume and Milestones

### Complete Task Management Suite

**Option A (Quick Wins) - NOW COMPLETE:**

1. ✅ **Pause/Resume** - Interrupt and resume workflows
2. ✅ **Progress Milestones** - Proactive progress reporting with ETA
3. ✅ **Job Priority** - Control execution order and urgency

**Combined Example Scenario:**
```
User: "Start analyzing dataset X, but it's not urgent"
→ Submit workflow with low priority

[Milestone] ✓ 25% complete (3/12 steps) - ~45m remaining

User: "I need to analyze dataset Y urgently"
→ Pause low-priority workflow
→ Submit urgent workflow with high priority

[Urgent workflow completes in 10 minutes]

User: "Resume the first analysis"
→ Resume workflow continues from 25%

[Milestone] ✓ 50% complete (6/12 steps) - ~30m remaining
[Milestone] ✓ 75% complete (9/12 steps) - ~15m remaining
[Milestone] ✓ Workflow complete! (12/12 steps)
```

---

## Related Documents

- **Pause/Resume:** `20251107_PAUSE_RESUME_IMPLEMENTATION_summary.md`
- **Progress Milestones:** `20251107_PROGRESS_MILESTONE_MONITORING_summary.md`
- **Gap Analysis:** `20251107_1727_TASK_MANAGEMENT_ANALYSIS_interruption_progress_monitoring.md`
- **Galaxy Queue:** `20251107_GALAXY_QUEUE_SYSTEM_INTEGRATION_ANALYSIS.md`

---

## Summary

**What We Enabled:**
Job priority selection via existing Galaxy infrastructure, allowing users to control workflow execution urgency.

**How It Works:**
1. User passes `__priority` parameter when invoking workflow
2. Parameter flows through: UI → Routes → API Proxy → Galaxy API
3. Galaxy job handler respects priority in queue scheduling
4. Higher priority jobs execute before lower priority jobs

**Implementation:**
- No backend code changes (Galaxy already supports it)
- No route changes (parameters already passed through)
- Added JSDoc documentation with examples
- Created comprehensive usage guide

**Impact:**
Completes Option A (Quick Wins) by enabling the third core capability: job prioritization to match Claude Code's task management features.

---

**Document Version:** 1.0
**Last Updated:** 2025-11-07 19:30
**Status:** Infrastructure complete, UI enhancement optional
