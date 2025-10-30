# Workflow UI Update - Display Galaxy Workflow Details

**Date:** October 28, 2025
**Issue:** Workflow view showed AI-generated name instead of actual Galaxy workflow details
**Solution:** Update UI to display Galaxy-assigned workflow ID and name

---

## Problem

After creating workflows in Galaxy, the UI still showed the old AI-generated workflow name (e.g., "rna-seq-analysis-pipeline") instead of:
- Galaxy-assigned workflow ID (e.g., `f2db41e1fa331b3e`)
- Actual workflow name from Galaxy
- Total steps from Galaxy
- Other Galaxy workflow metadata

---

## Changes Made

### 1. Added State Variables for Galaxy Workflow Details

**File:** `/home/yzhang/biomate/frontend/client/src/components/enhanced-workflow-builder.tsx`

**Lines 137-138:**
```typescript
const [galaxyWorkflowId, setGalaxyWorkflowId] = useState<string | null>(null)
const [galaxyWorkflowName, setGalaxyWorkflowName] = useState<string>(workflowName)
```

### 2. Update State After Workflow Creation

**Lines 301-308:**
```typescript
// Update UI with Galaxy workflow details
setGalaxyWorkflowId(workflowId)
setGalaxyWorkflowName(createdWorkflow.name || workflowName)

// Update workflow definition with actual Galaxy details
if (createdWorkflow.steps) {
  console.log('[Workflow] Workflow has', Object.keys(createdWorkflow.steps).length, 'steps in Galaxy')
}
```

### 3. Display Galaxy Workflow ID in UI Header

**Lines 633-641:**
```typescript
<CardTitle className="text-2xl">{galaxyWorkflowName}</CardTitle>
<CardDescription>
  Graph-based workflow visualization with real-time execution tracking
  {galaxyWorkflowId && (
    <span className="block mt-1 text-xs">
      Galaxy Workflow ID: <code className="bg-muted px-1 py-0.5 rounded">{galaxyWorkflowId}</code>
    </span>
  )}
</CardDescription>
```

### 4. Updated All Workflow References

Replaced all instances of `workflowName` with `galaxyWorkflowName` in:

- **Line 332:** Invocation record creation
  ```typescript
  workflowName: galaxyWorkflowName,
  ```

- **Line 335:** Workflow definition
  ```typescript
  name: galaxyWorkflowName,
  ```

- **Line 337:** Added Galaxy workflow ID to definition
  ```typescript
  galaxyWorkflowId: workflowId
  ```

- **Line 391:** Dataset validation API call
  ```typescript
  workflow_name: galaxyWorkflowName,
  ```

- **Lines 588-591:** Workflow export (.ga format)
  ```typescript
  name: galaxyWorkflowName,
  annotation: `Exported workflow: ${galaxyWorkflowName}`,
  uuid: galaxyWorkflowId,
  ```

- **Line 611:** Download file name
  ```typescript
  link.download = `${galaxyWorkflowName.replace(/\s+/g, '_')}.ga`
  ```

- **Line 872:** Save workflow dialog
  ```typescript
  workflowName={galaxyWorkflowName}
  ```

---

## UI Display Changes

### Before
```
Title: RNA-seq Analysis Pipeline
Description: Graph-based workflow visualization...
```

### After
```
Title: RNA-seq Analysis Pipeline (or Galaxy-assigned name)
Description: Graph-based workflow visualization with real-time execution tracking
             Galaxy Workflow ID: f2db41e1fa331b3e
```

---

## Benefits

1. **Traceability:** Users can now see the actual Galaxy workflow ID
2. **Accuracy:** Workflow name reflects what's stored in Galaxy
3. **Debugging:** Easier to track workflows between UI and Galaxy
4. **Consistency:** All workflow references use Galaxy-assigned details
5. **Export:** Downloaded .ga files include the correct Galaxy UUID

---

## Visual Example

The workflow header now displays:

```
┌─────────────────────────────────────────────────┐
│ RNA-seq Analysis Pipeline                       │
│ Graph-based workflow visualization with         │
│ real-time execution tracking                    │
│ Galaxy Workflow ID: f2db41e1fa331b3e           │
│                                                 │
│ Progress: 3/4 steps | Status: idle             │
└─────────────────────────────────────────────────┘
```

The Galaxy Workflow ID appears in a monospace code block for easy copying.

---

## Testing

### Manual Test
1. Navigate to http://localhost:5000
2. Generate a workflow via chat
3. Click "Start Workflow"
4. **Before execution:** Workflow header shows original name
5. **After workflow creation:** Header updates with Galaxy workflow ID
6. Verify the ID matches the one in console logs

### Console Logs to Verify
```
[Workflow] Creating workflow in Galaxy: RNA-seq Analysis Pipeline
[Workflow] Created workflow in Galaxy with ID: f2db41e1fa331b3e
[Workflow] Workflow has 4 steps in Galaxy
```

### Verify in Galaxy
```bash
curl http://localhost:8081/api/workflows | jq '.[] | {id, name, steps: .steps | length}'
```

Expected output:
```json
{
  "id": "f2db41e1fa331b3e",
  "name": "RNA-seq Analysis Pipeline",
  "steps": 4
}
```

---

## Related Files

- `/home/yzhang/biomate/frontend/client/src/components/enhanced-workflow-builder.tsx` - Main changes
- `/home/yzhang/biomate/backend/WORKFLOW_EXECUTION_FIX_20251028.md` - Original workflow creation fix

---

## Next Steps

Consider adding:
1. **Step count verification:** Display Galaxy step count vs UI step count
2. **Workflow version:** Track workflow versions if re-created
3. **Creation timestamp:** Show when workflow was created in Galaxy
4. **Workflow status badge:** Show if workflow is published, shared, etc.
5. **Link to Galaxy:** Add button to view workflow in Galaxy UI

---

## Servers Running

- **Frontend:** http://localhost:5000 ✅
- **Galaxy Backend:** http://localhost:8081 ✅

Ready for testing!
