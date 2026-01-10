# Frontend Components Guide

This document describes the key React components in the Biomate frontend.

---

## Directory Structure

```
client/src/
├── components/
│   ├── ui/           # Reusable UI primitives (shadcn/ui based)
│   ├── chat-*.tsx    # Chat-related components
│   ├── workflow-*.tsx # Workflow builder components
│   └── galaxy-*.tsx  # Galaxy integration components
├── hooks/            # Custom React hooks
├── lib/              # Utilities and API clients
├── pages/            # Route pages
└── contexts/         # React contexts
```

---

## Core Components

### Chat Interface

**File**: `components/chat-interface.tsx`

The main chat component that handles user interactions with the AI assistant.

```tsx
<ChatInterface
  sessionId="uuid"
  onWorkflowGenerated={(workflow) => handleWorkflow(workflow)}
  onToolSelect={(tool) => handleToolSelect(tool)}
/>
```

**Key Features**:
- Real-time message streaming
- Thinking indicator display
- Tool and dataset suggestions
- Inline workflow artifacts
- File attachments

**State Management**:
- Uses `useState` for local message state
- Uses `useRef` for scroll management
- Connects to SSE for real-time updates

---

### Chat Message

**File**: `components/chat-message.tsx`

Renders individual chat messages with role-specific styling.

```tsx
<ChatMessage
  message={message}
  onCopy={() => copyToClipboard(message.content)}
  onRegenerate={() => regenerateResponse()}
  onRunWorkflow={(workflow, steps) => executeWorkflow(workflow, steps)}
/>
```

**Message Types**:
- User messages (right-aligned, blue)
- Assistant messages (left-aligned, gray)
- System messages (centered, subtle)

**Rich Content Support**:
- Markdown rendering
- Code syntax highlighting
- Embedded workflow artifacts
- Tool recommendations
- Dataset suggestions

---

### Chat with Artifacts

**File**: `components/chat-with-artifacts.tsx`

Extended chat view with a side panel for workflow artifacts.

```tsx
<ChatWithArtifacts
  initialWorkflow={workflow}
  onWorkflowUpdate={(updated) => saveWorkflow(updated)}
/>
```

**Layout**:
- Left panel: Chat interface
- Right panel: Workflow artifact (collapsible)
- Responsive: collapses to single column on mobile

---

### Workflow Artifact

**File**: `components/workflow-artifact.tsx`

Visual representation of a generated workflow.

```tsx
<WorkflowArtifact
  workflow={workflow}
  steps={steps}
  onRun={() => executeWorkflow()}
  onStop={() => stopWorkflow()}
  onParameterChange={(stepId, params) => updateParams(stepId, params)}
  isRunning={isExecuting}
  progress={currentProgress}
/>
```

**Features**:
- Step-by-step visualization
- Parameter editing per step
- Execution progress tracking
- Status indicators (pending, running, completed, error)
- Estimated time display

---

### Workflow History Panel

**File**: `components/workflow-history-panel.tsx`

Shows execution history and status timeline.

```tsx
<WorkflowHistoryPanel
  invocationId="inv_uuid"
  events={timelineEvents}
  onStepClick={(stepId) => viewStepDetails(stepId)}
/>
```

**Timeline Events**:
- Step start/complete
- Errors and warnings
- Output generation
- Total elapsed time

---

### Enhanced Workflow Builder

**File**: `components/enhanced-workflow-builder.tsx`

Full-featured workflow construction interface.

```tsx
<EnhancedWorkflowBuilder
  initialWorkflow={workflow}
  availableTools={tools}
  datasets={datasets}
  onSave={(workflow) => saveWorkflow(workflow)}
  onRun={(workflow) => runWorkflow(workflow)}
/>
```

**Capabilities**:
- Drag-and-drop step ordering
- Tool search and selection
- Dataset assignment
- Parameter configuration
- Connection validation

---

### Parameter Dialog

**File**: `components/parameter-dialog.tsx`

Modal for configuring tool parameters.

```tsx
<ParameterDialog
  tool={selectedTool}
  schema={toolSchema}
  currentValues={parameters}
  onSave={(params) => updateParameters(params)}
  templates={parameterTemplates}
/>
```

**Features**:
- Dynamic form generation from schema
- Parameter templates (quick fill)
- Validation feedback
- Help text display

---

### Galaxy Recommendations

**File**: `components/galaxy-recommendations.tsx`

Displays AI-suggested tools and datasets.

```tsx
<GalaxyRecommendations
  toolRecommendations={tools}
  datasetRecommendations={datasets}
  onToolClick={(tool) => selectTool(tool)}
  onDatasetClick={(dataset) => selectDataset(dataset)}
/>
```

**Display**:
- Relevance scores
- Reasoning explanations
- Category badges
- Quick action buttons

---

### Citation Panel

**File**: `components/citation-panel.tsx`

Manages citations for tools used in workflows.

```tsx
<CitationPanel
  citations={citations}
  format="apa"
  onExport={(format) => exportCitations(format)}
  onGenerateMethods={() => generateMethodsSection()}
/>
```

**Export Formats**:
- APA
- BibTeX
- Numbered
- Methods section (Nature/Cell style)

---

### Benchmark Evidence

**File**: `components/benchmark-evidence.tsx`

Shows benchmark data to support tool recommendations.

```tsx
<BenchmarkEvidence
  benchmarks={benchmarkData}
  scenario="rna_seq_de"
  onViewDetails={(benchmark) => showDetails(benchmark)}
/>
```

---

### Dataset Dialog

**File**: `components/dataset-dialog.tsx`

Dataset selection and upload dialog.

```tsx
<DatasetDialog
  open={isOpen}
  onClose={() => setOpen(false)}
  onSelect={(dataset) => selectDataset(dataset)}
  onUpload={(file) => uploadFile(file)}
  acceptedFormats={['fastq', 'fasta', 'bam']}
/>
```

---

### Tool Browser

**File**: `components/tool-browser.tsx`

Browse and search Galaxy tools.

```tsx
<ToolBrowser
  onToolSelect={(tool) => addToolToWorkflow(tool)}
  categories={categories}
  searchQuery={query}
/>
```

---

### Thinking Display

**File**: `components/thinking-display.tsx`

Shows AI reasoning process during workflow generation.

```tsx
<ThinkingDisplay
  thinking={thinkingContent}
  isVisible={showThinking}
  level="detailed"
/>
```

**Levels**:
- `none`: Hidden
- `summary`: Brief summary
- `detailed`: Full reasoning

---

## UI Primitives

Located in `components/ui/`, these are shadcn/ui-based components.

### Button

```tsx
import { Button } from "@/components/ui/button"

<Button variant="default" size="default">Click me</Button>
<Button variant="destructive">Delete</Button>
<Button variant="outline">Cancel</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="ghost">Ghost</Button>
<Button variant="link">Link</Button>
```

### Card

```tsx
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card"

<Card>
  <CardHeader>
    <CardTitle>Title</CardTitle>
    <CardDescription>Description</CardDescription>
  </CardHeader>
  <CardContent>
    Content here
  </CardContent>
</Card>
```

### Dialog

```tsx
import { Dialog, DialogTrigger, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"

<Dialog>
  <DialogTrigger asChild>
    <Button>Open</Button>
  </DialogTrigger>
  <DialogContent>
    <DialogHeader>
      <DialogTitle>Dialog Title</DialogTitle>
    </DialogHeader>
    Content here
  </DialogContent>
</Dialog>
```

### Badge

```tsx
import { Badge } from "@/components/ui/badge"

<Badge>Default</Badge>
<Badge variant="secondary">Secondary</Badge>
<Badge variant="destructive">Error</Badge>
<Badge variant="outline">Outline</Badge>
```

### Input

```tsx
import { Input } from "@/components/ui/input"

<Input placeholder="Enter text..." />
<Input type="email" />
<Input disabled />
```

### Select

```tsx
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"

<Select>
  <SelectTrigger>
    <SelectValue placeholder="Select option" />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="1">Option 1</SelectItem>
    <SelectItem value="2">Option 2</SelectItem>
  </SelectContent>
</Select>
```

### Tabs

```tsx
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"

<Tabs defaultValue="tab1">
  <TabsList>
    <TabsTrigger value="tab1">Tab 1</TabsTrigger>
    <TabsTrigger value="tab2">Tab 2</TabsTrigger>
  </TabsList>
  <TabsContent value="tab1">Content 1</TabsContent>
  <TabsContent value="tab2">Content 2</TabsContent>
</Tabs>
```

### ScrollArea

```tsx
import { ScrollArea } from "@/components/ui/scroll-area"

<ScrollArea className="h-[400px]">
  Long content here...
</ScrollArea>
```

### Toast

```tsx
import { useToast } from "@/hooks/use-toast"

const { toast } = useToast()

toast({
  title: "Success",
  description: "Operation completed",
  variant: "default"
})

toast({
  title: "Error",
  description: "Something went wrong",
  variant: "destructive"
})
```

---

## Custom Hooks

### useWorkflowExecution

**File**: `hooks/useWorkflowExecution.ts`

Manages workflow execution state and SSE updates.

```tsx
const {
  isRunning,
  progress,
  currentStep,
  events,
  startExecution,
  stopExecution,
  error
} = useWorkflowExecution(workflowId, invocationId)
```

### useToast

**File**: `hooks/use-toast.ts`

Toast notification system.

```tsx
const { toast, dismiss, toasts } = useToast()
```

---

## State Management

### Context Providers

**Auth Context** (`contexts/auth-context.tsx`):
```tsx
const { user, login, logout, isLoading } = useAuth()
```

### React Query

Used for server state management:

```tsx
import { useQuery, useMutation } from "@tanstack/react-query"

const { data, isLoading, error } = useQuery({
  queryKey: ['tools', query],
  queryFn: () => searchTools(query)
})

const mutation = useMutation({
  mutationFn: createWorkflow,
  onSuccess: () => queryClient.invalidateQueries(['workflows'])
})
```

---

## Styling

### Tailwind CSS

All components use Tailwind CSS for styling.

**Theme Variables** (CSS custom properties):
```css
--background: hsl(0 0% 100%);
--foreground: hsl(222.2 84% 4.9%);
--primary: hsl(221.2 83.2% 53.3%);
--secondary: hsl(210 40% 96.1%);
--destructive: hsl(0 84.2% 60.2%);
--muted: hsl(210 40% 96.1%);
```

**Class Naming Convention**:
```tsx
// Use cn() for conditional classes
import { cn } from "@/lib/utils"

<div className={cn(
  "base-class",
  isActive && "active-class",
  variant === "primary" && "primary-variant"
)}>
```

---

## Testing Components

### Setup
```tsx
import { render, screen, fireEvent } from '@testing-library/react'
import { vi } from 'vitest'

describe('Component', () => {
  it('should render', () => {
    render(<Component />)
    expect(screen.getByText('Text')).toBeInTheDocument()
  })
})
```

### Testing User Interactions
```tsx
it('should handle click', async () => {
  const handleClick = vi.fn()
  render(<Button onClick={handleClick}>Click</Button>)

  fireEvent.click(screen.getByText('Click'))

  expect(handleClick).toHaveBeenCalled()
})
```

---

**Last Updated**: January 9, 2026
