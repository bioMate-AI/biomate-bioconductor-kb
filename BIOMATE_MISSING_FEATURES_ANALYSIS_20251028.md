# bioMate Missing Features: Output Storage & Results Management

**Created:** 2025-10-28 19:45 UTC
**Author:** Claude Code Analysis
**Purpose:** Document the ACTUAL missing features causing E2E test failures and user workflow gaps

---

## Executive Summary

**Current State:**
- ✅ AI workflow generation works
- ✅ Tool discovery and parameter configuration works
- ✅ Workflow execution works
- ✅ Real-time job monitoring works (SSE)
- ❌ **Output storage NOT implemented**
- ❌ **No history panel to browse past work**
- ❌ **No way to retrieve results after chat scrolls away**

**Root Cause of E2E Test Failures:**
Tests expect to find and verify workflow outputs, but there's no persistent results storage or browsing interface.

---

## Part 1: What's Missing

### 1. Output File Storage System

**Current Behavior:**
```
User: "Run RNA-seq analysis on /data/sample1/"
bioMate: Generates workflow, executes
Galaxy: Runs tools, produces outputs
Outputs: ??? Where do they go?
```

**What Needs to Happen:**
```
User: "Run RNA-seq analysis on /data/sample1/"
bioMate: Generates workflow, executes
Galaxy: Runs tools, produces outputs
bioMate Backend:
  ├─ Track output dataset IDs from Galaxy
  ├─ Store metadata (filename, size, type, job_id)
  ├─ Associate with workflow invocation
  └─ Make available for download/display

bioMate Frontend:
  ├─ Display outputs inline in chat (if small/images)
  ├─ Provide download links
  └─ Show in history/results panel
```

---

### 2. History/Results Panel

**User Need:**
"I ran 5 workflows yesterday. I want to see all my results without scrolling through chat history."

**Required Features:**

#### A. Workflow Execution History
```
┌─────────────────────────────────────────────────┐
│  My Workflows                    [Filter ▼]     │
├─────────────────────────────────────────────────┤
│ Today                                           │
│                                                 │
│ ✅ RNA-seq Differential Expression              │
│    Started: 2:34 PM | Completed: 2:47 PM       │
│    Outputs: 5 files (12.3 MB)                  │
│    [View Results] [Download All]               │
│                                                 │
│ 🏃 Proteomics Analysis (Running...)             │
│    Started: 3:15 PM | 73% complete             │
│    Step 3/4: Protein Identification            │
│    [View Progress]                             │
│                                                 │
├─────────────────────────────────────────────────┤
│ Yesterday                                       │
│                                                 │
│ ✅ Variant Calling Pipeline                     │
│    Started: Oct 27, 4:22 PM                    │
│    Outputs: 3 files (456 MB)                   │
│    [View Results] [Re-run]                     │
│                                                 │
│ ❌ Genome Assembly (Failed)                     │
│    Started: Oct 27, 2:10 PM                    │
│    Error: Insufficient memory                  │
│    [View Logs] [Retry]                         │
└─────────────────────────────────────────────────┘
```

#### B. Output File Browser (When clicking "View Results")
```
┌─────────────────────────────────────────────────┐
│  RNA-seq Results - Oct 28, 2:47 PM             │
├─────────────────────────────────────────────────┤
│                                                 │
│ 📊 Visualizations                               │
│   🖼️ volcano_plot.png (234 KB)                 │
│      [Preview] [Download] [Open in Chat]       │
│                                                 │
│   🖼️ expression_heatmap.png (892 KB)           │
│      [Preview] [Download]                      │
│                                                 │
│ 📄 Data Tables                                  │
│   📋 deg_results.tsv (2.3 MB, 2,340 rows)      │
│      [Preview First 100] [Download Full]       │
│                                                 │
│   📋 normalized_counts.csv (5.1 MB)            │
│      [Download]                                │
│                                                 │
│ 📁 Workflow Definition                          │
│   ⚙️ rna_seq_workflow.ga (12 KB)               │
│      [View] [Re-run with New Data]             │
│                                                 │
│ 📝 Execution Logs                               │
│   [View Full Logs] [Download]                  │
└─────────────────────────────────────────────────┘
```

---

### 3. Inline Visualization Rendering

**For Interactive Outputs:**

Galaxy visualization tools can produce:
- **Static images** (PNG, SVG) → Display directly in chat
- **Plotly HTML** → Embed iframe in chat
- **Interactive widgets** (genome browsers) → Need special handling

**Implementation:**

```tsx
// Enhanced chat message with output rendering
<ChatMessage>
  <MessageContent>
    ✅ Differential expression analysis complete!
  </MessageContent>

  <OutputAttachments>
    {outputs.map(output => {
      // Static images - show inline
      if (output.ext === 'png' || output.ext === 'svg') {
        return (
          <Card className="mt-4">
            <CardHeader>
              <CardTitle>{output.name}</CardTitle>
            </CardHeader>
            <CardContent>
              <img
                src={`/api/datasets/${output.id}/display`}
                alt={output.name}
                className="max-w-full rounded"
              />
              <Button variant="outline" size="sm">
                <Download className="h-4 w-4 mr-2" />
                Download ({formatBytes(output.size)})
              </Button>
            </CardContent>
          </Card>
        )
      }

      // Interactive HTML (Plotly, etc)
      if (output.ext === 'html' && output.metadata?.interactive) {
        return (
          <Card className="mt-4">
            <CardHeader>
              <CardTitle>{output.name}</CardTitle>
            </CardHeader>
            <CardContent>
              <iframe
                src={`/api/datasets/${output.id}/display`}
                className="w-full h-96 border-0 rounded"
                sandbox="allow-scripts"
              />
            </CardContent>
          </Card>
        )
      }

      // Large tables - show summary
      if (output.ext === 'tsv' || output.ext === 'csv') {
        return (
          <Card className="mt-4">
            <CardHeader>
              <CardTitle>{output.name}</CardTitle>
              <CardDescription>
                {formatNumber(output.metadata?.rows)} rows,
                {formatBytes(output.size)}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex gap-2">
                <Button variant="outline" size="sm">
                  <Eye className="h-4 w-4 mr-2" />
                  Preview
                </Button>
                <Button variant="outline" size="sm">
                  <Download className="h-4 w-4 mr-2" />
                  Download Full Table
                </Button>
              </div>
            </CardContent>
          </Card>
        )
      }

      // Everything else - download link
      return (
        <div className="flex items-center gap-2 p-2 border rounded">
          <FileIcon className="h-4 w-4" />
          <span>{output.name}</span>
          <Button variant="ghost" size="sm">
            <Download className="h-4 w-4" />
          </Button>
        </div>
      )
    })}
  </OutputAttachments>
</ChatMessage>
```

---

## Part 2: Backend Implementation

### Database Schema for Output Tracking

```typescript
// Add to existing schema
interface WorkflowInvocation {
  id: string
  user_id: string
  workflow_id: string
  workflow_name: string
  status: 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused'
  created_at: Date
  updated_at: Date
  completed_at?: Date
  error_message?: string

  // Galaxy integration
  galaxy_invocation_id: string
  galaxy_history_id: string

  // Metadata
  input_datasets: InputDataset[]
  output_datasets: OutputDataset[]
  workflow_definition: object  // .ga file content
  execution_logs: string
}

interface OutputDataset {
  id: string
  invocation_id: string
  galaxy_dataset_id: string

  // File metadata
  name: string
  extension: string  // 'png', 'tsv', 'html', 'bam', etc
  size: number
  created_at: Date

  // Display metadata
  file_type: 'image' | 'table' | 'text' | 'binary' | 'interactive'
  is_visualizable: boolean
  preview_available: boolean

  // Optional metadata (from Galaxy)
  metadata?: {
    rows?: number          // For tables
    columns?: number
    width?: number         // For images
    height?: number
    interactive?: boolean  // For Plotly/interactive viz
  }
}

interface InputDataset {
  step_id: number
  parameter_name: string
  source: 'upload' | 'library' | 'history' | 'url'
  path?: string
  galaxy_dataset_id?: string
}
```

---

### Backend API Endpoints to Add

```typescript
// 1. Track workflow invocations
POST   /api/invocations
GET    /api/invocations                    // List all user invocations
GET    /api/invocations/:id                // Get invocation details
GET    /api/invocations/:id/outputs        // Get output files
DELETE /api/invocations/:id                // Delete invocation record

// 2. Output file access
GET    /api/outputs/:id/download           // Download file
GET    /api/outputs/:id/display            // Display inline (images, HTML)
GET    /api/outputs/:id/preview            // Preview (first N rows of table)
GET    /api/outputs/:id/metadata           // Get file metadata

// 3. Re-execution
POST   /api/invocations/:id/rerun          // Re-run workflow with same inputs
POST   /api/invocations/:id/rerun-with     // Re-run with different inputs
```

---

### Integration with Galaxy API

**When Workflow Executes:**

```typescript
// In workflow execution handler
async function executeWorkflow(workflowData: WorkflowRequest) {
  // 1. Invoke workflow in Galaxy
  const invocation = await galaxyApi.invokeWorkflow({
    workflow_id: workflowData.workflow_id,
    history_id: workflowData.history_id,
    inputs: workflowData.inputs
  })

  // 2. Store invocation record
  const dbRecord = await db.invocations.create({
    user_id: req.user.id,
    workflow_name: workflowData.name,
    galaxy_invocation_id: invocation.id,
    galaxy_history_id: workflowData.history_id,
    status: 'running',
    workflow_definition: workflowData.workflow,
    input_datasets: workflowData.inputs
  })

  // 3. Monitor via SSE (existing)
  const eventStream = monitorInvocation(invocation.id)

  // 4. When complete, fetch outputs from Galaxy
  eventStream.on('completed', async () => {
    const historyContents = await galaxyApi.getHistoryContents(
      workflowData.history_id
    )

    // Find outputs created by this invocation
    const outputs = historyContents.filter(item =>
      item.create_time >= invocation.create_time &&
      !item.deleted &&
      item.state === 'ok'
    )

    // Store output metadata
    for (const output of outputs) {
      await db.outputs.create({
        invocation_id: dbRecord.id,
        galaxy_dataset_id: output.id,
        name: output.name,
        extension: output.extension,
        size: output.file_size,
        file_type: classifyFileType(output.extension),
        is_visualizable: isVisualizable(output.extension),
        metadata: output.metadata
      })
    }

    // Update invocation status
    await db.invocations.update(dbRecord.id, {
      status: 'ok',
      completed_at: new Date()
    })
  })

  return { invocation_id: dbRecord.id }
}

function classifyFileType(ext: string): string {
  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf']
  const tableExts = ['tsv', 'csv', 'tabular', 'txt']
  const interactiveExts = ['html']

  if (imageExts.includes(ext)) return 'image'
  if (tableExts.includes(ext)) return 'table'
  if (interactiveExts.includes(ext)) return 'interactive'
  return 'binary'
}

function isVisualizable(ext: string): boolean {
  return ['png', 'jpg', 'svg', 'html', 'pdf'].includes(ext)
}
```

---

## Part 3: Frontend Implementation

### Component: History Panel (Sidebar/Drawer)

```tsx
// /frontend/client/src/components/invocation-history-panel.tsx

import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { History, Download, Play, XCircle, CheckCircle, Loader2 } from "lucide-react"
import { useQuery } from "@tanstack/react-query"
import { formatDistanceToNow } from "date-fns"

export function InvocationHistoryPanel() {
  const { data: invocations } = useQuery({
    queryKey: ['invocations'],
    queryFn: () => fetch('/api/invocations').then(r => r.json()),
    refetchInterval: 5000 // Refresh every 5s for running workflows
  })

  const groupedByDate = groupByDate(invocations || [])

  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button variant="outline">
          <History className="h-4 w-4 mr-2" />
          My Workflows
          {invocations?.filter(i => i.status === 'running').length > 0 && (
            <Badge variant="secondary" className="ml-2">
              {invocations.filter(i => i.status === 'running').length} running
            </Badge>
          )}
        </Button>
      </SheetTrigger>

      <SheetContent side="right" className="w-[600px]">
        <SheetHeader>
          <SheetTitle>Workflow History</SheetTitle>
        </SheetHeader>

        <ScrollArea className="h-full mt-4">
          {Object.entries(groupedByDate).map(([date, items]) => (
            <div key={date} className="mb-6">
              <h3 className="text-sm font-medium text-muted-foreground mb-2">
                {date}
              </h3>

              <div className="space-y-3">
                {items.map(invocation => (
                  <InvocationCard
                    key={invocation.id}
                    invocation={invocation}
                  />
                ))}
              </div>
            </div>
          ))}
        </ScrollArea>
      </SheetContent>
    </Sheet>
  )
}

function InvocationCard({ invocation }) {
  const statusConfig = {
    running: { icon: Loader2, color: "orange", label: "Running", animate: true },
    ok: { icon: CheckCircle, color: "green", label: "Completed" },
    error: { icon: XCircle, color: "red", label: "Failed" },
    queued: { icon: Loader2, color: "yellow", label: "Queued" }
  }

  const config = statusConfig[invocation.status]
  const Icon = config.icon

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex-1">
            <CardTitle className="text-base">{invocation.workflow_name}</CardTitle>
            <CardDescription className="text-xs">
              Started {formatDistanceToNow(new Date(invocation.created_at), { addSuffix: true })}
            </CardDescription>
          </div>

          <Badge variant={config.color}>
            <Icon className={`h-3 w-3 mr-1 ${config.animate ? 'animate-spin' : ''}`} />
            {config.label}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="pt-0">
        {invocation.status === 'ok' && (
          <div className="space-y-2">
            <div className="text-sm text-muted-foreground">
              {invocation.output_count} outputs ({formatBytes(invocation.total_output_size)})
            </div>

            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => viewResults(invocation.id)}
              >
                View Results
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => downloadAll(invocation.id)}
              >
                <Download className="h-4 w-4 mr-1" />
                Download All
              </Button>
            </div>
          </div>
        )}

        {invocation.status === 'running' && (
          <div className="space-y-2">
            <div className="text-sm text-muted-foreground">
              Step {invocation.current_step}/{invocation.total_steps}
            </div>
            <Progress value={invocation.progress_percent} />
          </div>
        )}

        {invocation.status === 'error' && (
          <div className="space-y-2">
            <div className="text-sm text-destructive">
              {invocation.error_message}
            </div>
            <Button
              size="sm"
              variant="outline"
              onClick={() => retry(invocation.id)}
            >
              <Play className="h-4 w-4 mr-1" />
              Retry
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
```

---

### Component: Results Detail Dialog

```tsx
// /frontend/client/src/components/invocation-results-dialog.tsx

import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"

export function InvocationResultsDialog({ invocationId, open, onClose }) {
  const { data: invocation } = useQuery({
    queryKey: ['invocations', invocationId],
    queryFn: () => fetch(`/api/invocations/${invocationId}`).then(r => r.json()),
    enabled: open
  })

  const { data: outputs } = useQuery({
    queryKey: ['invocations', invocationId, 'outputs'],
    queryFn: () => fetch(`/api/invocations/${invocationId}/outputs`).then(r => r.json()),
    enabled: open
  })

  if (!invocation || !outputs) return null

  const visualizations = outputs.filter(o => o.file_type === 'image' || o.file_type === 'interactive')
  const tables = outputs.filter(o => o.file_type === 'table')
  const otherFiles = outputs.filter(o => !['image', 'interactive', 'table'].includes(o.file_type))

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl h-[80vh]">
        <DialogHeader>
          <DialogTitle>{invocation.workflow_name} - Results</DialogTitle>
        </DialogHeader>

        <Tabs defaultValue="visualizations" className="flex-1">
          <TabsList>
            <TabsTrigger value="visualizations">
              Visualizations ({visualizations.length})
            </TabsTrigger>
            <TabsTrigger value="tables">
              Data Tables ({tables.length})
            </TabsTrigger>
            <TabsTrigger value="files">
              Files ({otherFiles.length})
            </TabsTrigger>
            <TabsTrigger value="workflow">
              Workflow
            </TabsTrigger>
          </TabsList>

          <TabsContent value="visualizations" className="flex-1">
            <ScrollArea className="h-full">
              <div className="space-y-4">
                {visualizations.map(output => (
                  <OutputVisualization key={output.id} output={output} />
                ))}
              </div>
            </ScrollArea>
          </TabsContent>

          <TabsContent value="tables">
            <ScrollArea className="h-full">
              <div className="space-y-4">
                {tables.map(output => (
                  <OutputTable key={output.id} output={output} />
                ))}
              </div>
            </ScrollArea>
          </TabsContent>

          {/* ... other tabs ... */}
        </Tabs>
      </DialogContent>
    </Dialog>
  )
}

function OutputVisualization({ output }) {
  if (output.extension === 'html' && output.metadata?.interactive) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{output.name}</CardTitle>
        </CardHeader>
        <CardContent>
          <iframe
            src={`/api/outputs/${output.id}/display`}
            className="w-full h-96 border rounded"
            sandbox="allow-scripts"
          />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{output.name}</CardTitle>
        <CardDescription>{formatBytes(output.size)}</CardDescription>
      </CardHeader>
      <CardContent>
        <img
          src={`/api/outputs/${output.id}/display`}
          alt={output.name}
          className="max-w-full rounded"
        />
        <Button variant="outline" size="sm" className="mt-2">
          <Download className="h-4 w-4 mr-2" />
          Download
        </Button>
      </CardContent>
    </Card>
  )
}
```

---

## Part 4: Implementation Priority

### Phase 1: Core Output Storage (Week 1-2)
**Goal:** Outputs persist and are retrievable

1. **Backend:**
   - Add database schema for invocations and outputs
   - Track Galaxy outputs after workflow completion
   - API endpoints for listing/downloading outputs

2. **Frontend:**
   - Display outputs inline in chat messages
   - Download buttons for each output

**Deliverable:** Users can see and download workflow outputs in chat

---

### Phase 2: History Panel (Week 3)
**Goal:** Browse past workflows

1. **Backend:**
   - GET /api/invocations endpoint with pagination
   - Filter by status, date

2. **Frontend:**
   - Sidebar/drawer with workflow list
   - Status badges and timestamps
   - Link to view results

**Deliverable:** Users can browse all past workflows

---

### Phase 3: Results Detail View (Week 4)
**Goal:** Dedicated view for exploring outputs

1. **Frontend:**
   - Dialog/page for invocation results
   - Tabs for visualizations/tables/files
   - Inline preview for images and interactive HTML

**Deliverable:** Users can explore outputs without re-running

---

### Phase 4: Advanced Features (Week 5+)
**Goal:** Power user workflows

1. **Re-run workflows** with same or different inputs
2. **Download all outputs** as zip
3. **Share invocation** with team members
4. **Export workflow** definition (.ga file)
5. **Table preview** (first 100 rows inline)
6. **Search/filter** invocation history

---

## Part 5: E2E Test Fixes

Once Phase 1-2 are complete, update E2E tests:

```python
# backend/tests/e2e_ui/test_workflow_outputs.py

def test_workflow_outputs_appear_in_history(page):
    # Navigate to chat
    page.goto("http://localhost:5000")

    # Submit workflow query
    page.fill("[data-testid='chat-input']", "Run RNA-seq on test data")
    page.click("[data-testid='send-button']")

    # Wait for completion
    page.wait_for_selector("[data-testid='workflow-complete']", timeout=120000)

    # Open history panel
    page.click("[data-testid='history-panel-trigger']")

    # Verify workflow appears
    assert page.is_visible("text='RNA-seq'")
    assert page.is_visible("text='Completed'")

    # Click to view results
    page.click("text='View Results'")

    # Verify outputs are listed
    assert page.is_visible("text='volcano_plot.png'")
    assert page.is_visible("text='deg_results.tsv'")

    # Verify visualization renders
    assert page.is_visible("[data-testid='output-image']")
```

---

## Conclusion

**What bioMate Actually Needs:**

1. ✅ **Output Storage System** - Track and persist workflow outputs
2. ✅ **History Panel** - Browse all past workflows
3. ✅ **Results Display** - Inline visualization rendering in chat
4. ✅ **Download Management** - Easy access to all output files

**What bioMate Doesn't Need (from Galaxy):**
- ❌ Dataset Collections (folder input is better)
- ❌ Data Libraries (not multi-user yet)
- ❌ Complex history operations (start simple)
- ❌ Interactive framework (iframe HTML is enough)

**Estimated Effort:** 4-5 weeks for Phases 1-3

This gives you the critical missing piece: **results persistence and browsing**, which is what's causing the E2E test failures.
