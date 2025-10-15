# Frontend-Backend Integration TODO
**Created: October 15, 2025**

## Current Status

### ✅ Backend Working
- Galaxy workflow generation API fully functional at `http://localhost:8080/api/ai_assistant/generate_workflow`
- Claude Sonnet 4.5 integrated with temperature=0.0
- FTS5 tool search working with OR queries
- Successfully generating workflows for:
  - DIA-LCMS proteomics (12 steps)
  - RNA-seq differential expression (6 steps)
  - Genome assembly with QC (8 steps)

### ❌ Frontend Not Connected
- Frontend calls `/api/chat` (OpenAI endpoint)
- Does NOT call Galaxy workflow generation endpoint
- Missing `data-testid="workflow-generated-message"` element
- E2E tests timing out waiting for workflow display

---

## Required Changes

### 1. Update Chat Interface API Call

**File**: `/Users/jingqiwang/biomate/frontend/client/src/components/chat-interface.tsx`

**Current** (line 77-84):
```typescript
const chatMutation = useMutation({
  mutationFn: async (content: string) => {
    const response = await apiRequest('POST', '/api/chat', {
      message: content,
      context: 'bioinformatics_workflow'
    })
    return await response.json()
  },
```

**Should be**:
```typescript
const chatMutation = useMutation({
  mutationFn: async (content: string) => {
    // Call Galaxy workflow generation API
    const response = await apiRequest('POST', 'http://localhost:8080/api/ai_assistant/generate_workflow', {
      request_text: content
    })
    return await response.json()
  },
```

### 2. Update Response Handler

**Current** (line 85-100):
```typescript
onSuccess: (data) => {
  const aiMessage: Message = {
    id: (Date.now() + 1).toString(),
    content: data.response,
    role: "assistant",
    timestamp: new Date(),
    suggestions: data.suggestions || ["Tell me more", "Show me tools", "Create workflow"],
    metadata: data.metadata
  }
```

**Should be**:
```typescript
onSuccess: (data) => {
  // data structure from Galaxy:
  // {
  //   success: true,
  //   workflow_ga: { ... },
  //   workflow_structure: { steps: [...] },
  //   message: "Generated new workflow with 12 steps",
  //   ...
  // }

  if (data.success && data.workflow_ga) {
    // Display workflow in UI
    const workflowMessage: Message = {
      id: (Date.now() + 1).toString(),
      content: `✅ ${data.message}\n\n${data.workflow_ga.annotation}`,
      role: "assistant",
      timestamp: new Date(),
      metadata: {
        type: 'workflow',
        workflow: data.workflow_ga,
        steps: data.workflow_structure?.steps || [],
        confidence: data.confidence,
        source: data.source
      }
    }

    // Trigger workflow builder display
    if (onWorkflowGenerated) {
      onWorkflowGenerated(data.workflow_ga)
    }
```

### 3. Add Workflow Display Component

**New Component Needed**: Workflow message display with testid

```typescript
// In chat-message.tsx or create new workflow-message.tsx
if (message.metadata?.type === 'workflow') {
  return (
    <div data-testid="workflow-generated-message" className="workflow-display">
      <Card>
        <CardHeader>
          <CardTitle>{message.metadata.workflow.name}</CardTitle>
          <CardDescription>
            {message.metadata.steps.length} steps •
            Confidence: {(message.metadata.confidence * 100).toFixed(1)}%
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p>{message.metadata.workflow.annotation}</p>

          {/* Display workflow steps */}
          <div className="workflow-steps mt-4">
            {message.metadata.steps.map((step, idx) => (
              <div key={idx} className="step-card">
                <Badge>{idx + 1}</Badge>
                <span>{step.name}</span>
              </div>
            ))}
          </div>

          {/* Action buttons */}
          <div className="actions mt-4">
            <Button onClick={() => onWorkflowGenerated(message.metadata.workflow)}>
              Open in Workflow Builder
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
```

### 4. Update API Configuration

**File**: `/Users/jingqiwang/biomate/frontend/client/src/lib/queryClient.ts` or API config

Add Galaxy backend URL configuration:

```typescript
const GALAXY_API_URL = import.meta.env.VITE_GALAXY_URL || 'http://localhost:8080'

export async function generateWorkflow(requestText: string) {
  const response = await fetch(`${GALAXY_API_URL}/api/ai_assistant/generate_workflow`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ request_text: requestText })
  })

  if (!response.ok) {
    throw new Error(`Workflow generation failed: ${response.statusText}`)
  }

  return await response.json()
}
```

### 5. Add Loading State for Workflow Generation

Workflow generation takes 15-30 seconds, so add proper loading UI:

```typescript
const [isGeneratingWorkflow, setIsGeneratingWorkflow] = useState(false)

const handleSendMessage = async (content: string) => {
  setIsGeneratingWorkflow(true)

  try {
    await chatMutation.mutateAsync(content)
  } finally {
    setIsGeneratingWorkflow(false)
  }
}

// In render:
{isGeneratingWorkflow && (
  <div className="workflow-loading">
    <Loader2 className="animate-spin" />
    <p>Generating workflow with Claude Sonnet 4.5...</p>
    <p className="text-sm text-muted-foreground">
      This may take 15-30 seconds
    </p>
  </div>
)}
```

---

## Testing Requirements

### E2E Test Expectations

The test looks for this specific element:
```typescript
await page.locator('[data-testid="workflow-generated-message"]').waitFor({
  state: 'visible',
  timeout: 60000
})
```

**Requirements**:
1. Element MUST have `data-testid="workflow-generated-message"`
2. Element must be visible within 60 seconds of sending message
3. Element should contain workflow information

### Manual Testing Steps

1. Start Galaxy backend: `cd backend && ./run.sh start`
2. Start frontend: `cd frontend/client && npm run dev`
3. Open browser to `http://localhost:5173`
4. Type: "DIA-LCMS proteomics analysis"
5. Click send
6. **Expected**:
   - Loading indicator appears
   - After 15-30 seconds, workflow card displays
   - Card shows workflow name, annotation, steps
   - "Open in Workflow Builder" button appears
7. Click "Open in Workflow Builder"
8. **Expected**: Workflow builder opens with generated workflow

---

## Priority Tasks

### P0 (Critical - Blocks E2E Tests)
- [ ] Update chat-interface.tsx to call Galaxy API
- [ ] Add `data-testid="workflow-generated-message"` to workflow display
- [ ] Handle Galaxy API response format

### P1 (High - User Experience)
- [ ] Add proper loading state (15-30 second wait)
- [ ] Display workflow steps in chat
- [ ] "Open in Workflow Builder" button
- [ ] Error handling for failed workflow generation

### P2 (Medium - Polish)
- [ ] Workflow confidence score display
- [ ] Step-by-step breakdown
- [ ] Workflow preview/editing before opening builder
- [ ] Save workflow to history

### P3 (Low - Future Enhancements)
- [ ] Multiple workflow suggestions
- [ ] Workflow comparison
- [ ] Parameter editing in chat
- [ ] Dataset attachment in chat

---

## API Response Format Reference

### Galaxy `/api/ai_assistant/generate_workflow` Response

```json
{
  "success": true,
  "workflow_ga": {
    "a_galaxy_workflow": "true",
    "format-version": "0.1",
    "name": "DIA-LCMS Proteomics Analysis Workflow",
    "annotation": "This workflow implements...",
    "tags": ["ai-generated", "comprehensive-index"],
    "steps": {
      "0": {
        "id": 0,
        "tool_id": "toolshed.g2.bx.psu.edu/repos/galaxyp/mz_to_sqlite",
        "name": "mz_to_sqlite",
        "tool_state": "{}",
        "annotation": "mz_to_sqlite",
        "position": {"left": 200, "top": 200}
      },
      // ... more steps
    }
  },
  "workflow_structure": {
    "steps": [
      {
        "id": "step_0",
        "name": "mz_to_sqlite",
        "tool_id": "toolshed.g2.bx.psu.edu/repos/galaxyp/mz_to_sqlite",
        "description": "Convert mass spec data to SQLite format"
      },
      // ... more steps
    ]
  },
  "source": "tool_constrained",
  "confidence": 0.105,
  "template_match_score": 0.105,
  "datasets_assigned": true,
  "generated_parameters": [],
  "message": "Generated new workflow with 12 steps (tool-constrained)",
  "note": "Generated using tool_constrained strategy"
}
```

### Error Response

```json
{
  "success": false,
  "error": "No tools found matching query",
  "message": "Workflow generation failed: No tools found matching query"
}
```

---

## Environment Variables

Add to `.env.local` or `.env.production`:

```bash
# Galaxy Backend URL
VITE_GALAXY_URL=http://localhost:8080

# For production
# VITE_GALAXY_URL=https://yourdomain.com
```

---

## Implementation Checklist

### Phase 1: Minimal Working Integration
- [ ] Update API call to Galaxy endpoint
- [ ] Add basic workflow display with testid
- [ ] Test E2E workflow generation

### Phase 2: User Experience
- [ ] Add loading states
- [ ] Format workflow display nicely
- [ ] Add error handling
- [ ] Connect to workflow builder

### Phase 3: Polish
- [ ] Workflow preview cards
- [ ] Confidence indicators
- [ ] Step details expansion
- [ ] Save/share workflows

---

## Quick Fix Script

```bash
# Run from project root

# 1. Update frontend API call
cd /Users/jingqiwang/biomate/frontend/client

# 2. Create .env.local
cat > .env.local << EOF
VITE_GALAXY_URL=http://localhost:8080
EOF

# 3. Restart frontend
npm run dev

# 4. Test manually
open http://localhost:5173
```

---

## Notes

- Backend is 100% working and tested
- All workflow generation logic is functional
- Only frontend display/integration needs work
- E2E tests will pass once frontend shows workflow with correct testid

---

## Contact

For questions about this integration:
- Backend API docs: `http://localhost:8080/docs`
- Test the API directly: See `AWS_DEPLOYMENT_GUIDE.md` Step 10.2
