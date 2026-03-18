# bioMate Frontend Enhancement - Implementation Progress

**Branch:** `enhance-with-galaxy-frontend`
**Started:** 2025-10-28
**Status:** Backend Complete ✅ | Frontend In Progress 🚧

---

## ✅ Completed: Backend Output Storage System

### What's Been Implemented

#### 1. Database Schema (`frontend/shared/schema.ts`)
```typescript
// New Types Added:
- WorkflowInvocation  // Tracks each workflow execution
- OutputDataset       // Tracks output files from workflows
- InputDataset        // References to input data
- CreateInvocation    // Schema for starting new workflow
```

**Key Fields:**
- `workflowInvocation`: Full execution tracking with status, timestamps, steps
- `outputDataset`: File metadata with visualization hints
- Smart file type classification: image, table, text, binary, interactive

#### 2. Storage Layer (`frontend/server/storage.ts`)
Extended `MemStorage` with:
- `createInvocation()` - Record workflow start
- `getInvocations()` - List all user workflows (sorted by date)
- `updateInvocation()` - Update status/progress
- `addOutput()` - Store output metadata
- `getInvocationOutputs()` - Get all files from a workflow

**Features:**
- Automatic output count/size tracking
- Cascade delete (deleting invocation removes outputs)
- User filtering support

#### 3. REST API Endpoints (`frontend/server/routes.ts`)

**Invocation Management:**
```
POST   /api/invocations              // Create when workflow starts
GET    /api/invocations              // List all (with pagination)
GET    /api/invocations/:id          // Get specific invocation
PATCH  /api/invocations/:id          // Update status/progress
DELETE /api/invocations/:id          // Delete invocation
GET    /api/invocations/:id/outputs  // Get output files
POST   /api/invocations/:id/fetch-outputs  // Auto-fetch from Galaxy
```

**Output File Access:**
```
GET /api/outputs/:id           // Get output metadata
GET /api/outputs/:id/download  // Download file
GET /api/outputs/:id/display   // Display inline (images, HTML)
GET /api/outputs/:id/preview   // Preview first N lines (tables)
```

#### 4. Galaxy API Integration (`frontend/server/galaxy-api-proxy.ts`)
Added methods:
- `getHistoryContents(historyId)` - List all datasets
- `downloadDataset(datasetId)` - Stream file from Galaxy
- `getDatasetMetadata(datasetId)` - Get file info

**Smart Features:**
- Automatic file type detection from extension
- Visualization hints (PNG, SVG, HTML, Plotly)
- Preview availability for tables/text

---

## 🚧 To Do: Frontend Components

### Phase 1: History Panel (Modern Drawer)

**File to Create:** `/home/yzhang/biomate/frontend/client/src/components/workflow-history-panel.tsx`

**Requirements:**
- Sheet/Drawer component (Radix UI)
- Real-time updates (poll every 5s for running workflows)
- Group by date ("Today", "Yesterday", "Last Week")
- Status badges with live animations
- Quick actions: View Results, Download All, Re-run

**Key Features:**
```tsx
<Sheet>
  <SheetTrigger>
    <Button>
      <History /> My Workflows
      <Badge>{runningCount}</Badge>
    </Button>
  </SheetTrigger>
  <SheetContent>
    {/* List of invocations grouped by date */}
    {/* Real-time status updates */}
    {/* Progress bars for running workflows */}
  </SheetContent>
</Sheet>
```

**Data Fetching:**
```typescript
const { data: invocations } = useQuery({
  queryKey: ['invocations'],
  queryFn: () => fetch('/api/invocations').then(r => r.json()),
  refetchInterval: 5000 // Poll every 5s
})
```

---

### Phase 2: Workflow Step Editing

**File to Modify:** `/home/yzhang/biomate/frontend/client/src/components/workflow-step.tsx`

**Requirements:**
- Click on any step card to edit parameters
- Modal/Dialog with parameter form
- Integration with existing ParameterDialog component
- Save changes back to workflow definition

**Implementation Pattern:**
```tsx
<Card onClick={() => setEditingStep(step)} className="cursor-pointer hover:shadow-lg">
  <CardHeader>
    <CardTitle>{step.title}</CardTitle>
  </CardHeader>
  {/* ... */}
</Card>

{editingStep && (
  <Dialog open={true} onOpenChange={() => setEditingStep(null)}>
    <ParameterDialog
      tool={editingStep.tool}
      parameters={editingStep.parameters}
      onSave={(newParams) => {
        updateStep(editingStep.id, newParams)
        setEditingStep(null)
      }}
    />
  </Dialog>
)}
```

---

### Phase 3: Smart Output Rendering in Chat

**File to Create:** `/home/yzhang/biomate/frontend/client/src/components/chat-output-attachments.tsx`

**Requirements:**
- Inline image display for PNG/SVG
- Iframe embed for interactive HTML (Plotly)
- Collapsible tables with preview
- Download buttons for all files
- File type icons

**Component Structure:**
```tsx
export function ChatOutputAttachments({ invocationId }: Props) {
  const { data: outputs } = useQuery({
    queryKey: ['outputs', invocationId],
    queryFn: () => fetch(`/api/invocations/${invocationId}/outputs`).then(r => r.json())
  })

  return (
    <div className="space-y-4">
      {outputs?.map(output => {
        if (output.fileType === 'image') return <ImageOutput {...output} />
        if (output.fileType === 'interactive') return <InteractiveOutput {...output} />
        if (output.fileType === 'table') return <TableOutput {...output} />
        return <FileOutput {...output} />
      })}
    </div>
  )
}
```

**Output Renderers:**
```tsx
function ImageOutput({ output }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{output.name}</CardTitle>
      </CardHeader>
      <CardContent>
        <img
          src={`/api/outputs/${output.id}/display`}
          className="max-w-full rounded-lg"
          alt={output.name}
        />
        <Button variant="outline" size="sm">
          <Download /> Download ({formatBytes(output.size)})
        </Button>
      </CardContent>
    </Card>
  )
}

function InteractiveOutput({ output }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{output.name}</CardTitle>
        <CardDescription>Interactive visualization</CardDescription>
      </CardHeader>
      <CardContent>
        <iframe
          src={`/api/outputs/${output.id}/display`}
          className="w-full h-96 border-0 rounded-lg"
          sandbox="allow-scripts"
        />
      </CardContent>
    </Card>
  )
}

function TableOutput({ output }) {
  const [showPreview, setShowPreview] = useState(false)
  const { data: preview } = useQuery({
    queryKey: ['preview', output.id],
    queryFn: () => fetch(`/api/outputs/${output.id}/preview`).then(r => r.json()),
    enabled: showPreview
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle>{output.name}</CardTitle>
        <CardDescription>
          {formatNumber(output.metadata?.rows)} rows, {formatBytes(output.size)}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setShowPreview(!showPreview)}>
            <Eye /> {showPreview ? 'Hide' : 'Show'} Preview
          </Button>
          <Button variant="outline">
            <Download /> Download Full Table
          </Button>
        </div>
        {showPreview && preview && (
          <ScrollArea className="h-64 mt-4">
            <pre className="text-xs font-mono">
              {preview.lines.join('\n')}
            </pre>
            {preview.hasMore && (
              <p className="text-sm text-muted-foreground mt-2">
                Showing first {preview.lines.length} of {preview.totalLines} lines
              </p>
            )}
          </ScrollArea>
        )}
      </CardContent>
    </Card>
  )
}
```

---

### Phase 4: Integration with Workflow Execution

**File to Modify:** `/home/yzhang/biomate/frontend/client/src/components/enhanced-workflow-builder.tsx`

**Requirements:**
- Create invocation record when workflow starts
- Track invocation ID throughout execution
- Fetch outputs when workflow completes
- Display outputs inline in chat

**Implementation:**
```typescript
async function handleRunWorkflow() {
  // 1. Start workflow in Galaxy (existing code)
  const galaxyResult = await fetch('/api/galaxy/workflows/invoke', {...})

  // 2. Create invocation record
  const invocation = await fetch('/api/invocations', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflowName: workflow.name,
      workflowDefinition: workflow,
      galaxyInvocationId: galaxyResult.id,
      galaxyHistoryId: galaxyResult.history_id,
      totalSteps: workflow.steps.length
    })
  }).then(r => r.json())

  // 3. Monitor via SSE (existing)
  const eventSource = new EventSource(`/api/galaxy/workflows/sse/${galaxyResult.id}`)

  eventSource.addEventListener('workflow_completed', async () => {
    // 4. Fetch outputs from Galaxy
    await fetch(`/api/invocations/${invocation.id}/fetch-outputs`, {
      method: 'POST'
    })

    // 5. Render outputs in chat
    setChatMessage({
      role: 'assistant',
      content: 'Workflow completed! Here are your results:',
      invocationId: invocation.id // Triggers <ChatOutputAttachments />
    })
  })

  // 6. Update progress during execution
  eventSource.addEventListener('step_completed', async (e) => {
    const data = JSON.parse(e.data)
    await fetch(`/api/invocations/${invocation.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        completedSteps: data.step_index + 1,
        currentStepIndex: data.step_index,
        currentStepName: data.step_name
      })
    })
  })
}
```

---

## 📋 Implementation Checklist

### Backend ✅
- [x] Add WorkflowInvocation schema
- [x] Add OutputDataset schema
- [x] Extend storage interface
- [x] Implement MemStorage methods
- [x] Add invocation API endpoints
- [x] Add output API endpoints
- [x] Add Galaxy proxy methods (getHistoryContents, downloadDataset)
- [x] Implement file type classification
- [x] Add output fetch automation
- [x] Commit backend changes

### Frontend 🚧
- [ ] Create WorkflowHistoryPanel component
- [ ] Add real-time polling for running workflows
- [ ] Implement workflow grouping by date
- [ ] Create status badges with animations
- [ ] Add workflow step click-to-edit
- [ ] Integrate with ParameterDialog
- [ ] Create ChatOutputAttachments component
- [ ] Implement ImageOutput renderer
- [ ] Implement InteractiveOutput renderer (iframe)
- [ ] Implement TableOutput with preview
- [ ] Integrate invocation creation in workflow execution
- [ ] Add SSE listener for completion → fetch outputs
- [ ] Display outputs inline in chat messages
- [ ] Add progress tracking during execution
- [ ] Test end-to-end flow

---

## 🎨 Design Principles

### Modern UI Standards
1. **Radix UI Components** - Use Sheet, Dialog, Card, Badge
2. **Tailwind Styling** - Utility-first, semantic colors
3. **Smooth Animations** - Loading states, progress bars, hover effects
4. **Real-time Updates** - useQuery with refetchInterval
5. **Responsive Design** - Mobile-friendly layouts
6. **Dark Mode Support** - Use semantic color variables

### Smart Features
1. **Auto-detect visualizations** - Inline display for images/HTML
2. **Lazy loading** - Preview tables on demand
3. **Progress indication** - Real-time step tracking
4. **Error handling** - Failed jobs with retry button
5. **Grouping & filtering** - By date, status, workflow type

---

## 🚀 Quick Start for Next Developer

```bash
# Switch to the branch
git checkout enhance-with-galaxy-frontend

# Backend is complete - test the APIs:
curl http://localhost:5000/api/invocations

# Start implementing frontend:
cd frontend/client/src/components

# Create the 3 main components:
1. workflow-history-panel.tsx
2. chat-output-attachments.tsx
3. Modify enhanced-workflow-builder.tsx

# Use existing patterns from:
- src/components/parameter-dialog.tsx (for modal patterns)
- src/components/workflow-step.tsx (for card patterns)
- src/hooks/useWorkflowExecution.ts (for SSE patterns)
```

---

## 📖 API Reference

### GET /api/invocations
Returns all workflow invocations for the current user, sorted by creation date (newest first).

**Response:**
```json
[
  {
    "id": "uuid",
    "workflowName": "RNA-seq Analysis",
    "status": "ok",
    "createdAt": "2025-10-28T10:30:00Z",
    "completedAt": "2025-10-28T10:45:00Z",
    "totalSteps": 4,
    "completedSteps": 4,
    "outputCount": 5,
    "totalOutputSize": 12345678
  }
]
```

### GET /api/invocations/:id/outputs
Returns all output files from a workflow execution.

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "volcano_plot.png",
    "extension": "png",
    "size": 234567,
    "fileType": "image",
    "isVisualizable": true,
    "metadata": {
      "width": 1024,
      "height": 768
    }
  },
  {
    "id": "uuid",
    "name": "deg_results.tsv",
    "extension": "tsv",
    "size": 2345678,
    "fileType": "table",
    "previewAvailable": true,
    "metadata": {
      "rows": 2340,
      "columns": 8
    }
  }
]
```

### GET /api/outputs/:id/display
Returns the actual file content with appropriate Content-Type headers for inline display.

**Supported Types:**
- Images: `image/png`, `image/svg+xml`, etc.
- HTML: `text/html` (for Plotly visualizations)
- PDF: `application/pdf`

---

## 🔗 Related Documents

- `BIOMATE_MISSING_FEATURES_ANALYSIS_20251028.md` - Original feature analysis
- `GALAXY_VS_BIOMATE_FRONTEND_COMPARISON_20251028.md` - Architecture comparison
- Backend implementation: Commit `6caa1a0`

---

**Status:** Ready for frontend implementation! Backend is fully functional and tested. 🎉
