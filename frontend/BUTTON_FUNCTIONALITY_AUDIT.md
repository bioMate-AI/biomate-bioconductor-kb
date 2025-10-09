# Button Functionality Audit Report

## Executive Summary

**Audit Date:** October 3, 2025
**Status:** ⚠️ **CRITICAL ISSUES FOUND**

This audit reveals **significant gaps** in button functionality across the chat interface and workflow builder. Most buttons are placeholder implementations that only log to console. A critical missing component (`DatasetDialog`) is causing potential runtime errors.

---

## Critical Issues 🔴

### 1. Missing DatasetDialog Component
- **Severity:** CRITICAL
- **Location:** `client/src/components/chat-input.tsx:6`
- **Issue:** `DatasetDialog` is imported but doesn't exist
- **Impact:**
  - Attach button (Paperclip) cannot function
  - Component will crash when attach button is clicked
  - TypeScript compilation may fail
- **Fix Required:** Create DatasetDialog component or remove import

### 2. No File Upload Functionality
- **Severity:** HIGH
- **Issue:** No file upload implementation exists anywhere in codebase
- **Current Behavior:** Attach button opens dataset selection (not file upload)
- **User Expectation:** Upload files for analysis
- **Gap:** Complete file upload system needed

### 3. Hardcoded API Bug in cancelWorkflow
- **Severity:** MEDIUM
- **Location:** `client/src/hooks/useWorkflowExecution.ts:210`
- **Issue:** `WORKFLOW_ID` is hardcoded string, not actual workflow ID
- **Code:**
```typescript
await fetch(`/api/galaxy/workflows/WORKFLOW_ID/invocations/${state.invocationId}`, {
  method: 'DELETE',
});
```
- **Impact:** Stop workflow button will fail with 404

---

## Chat Interface Buttons

### Input Area Buttons

| Button | Icon | Status | Implementation | Location |
|--------|------|--------|----------------|----------|
| **Attach** | 📎 Paperclip | ❌ BROKEN | Opens missing DatasetDialog | `chat-input.tsx:61` |
| **Voice** | 🎤 Mic | ❌ PLACEHOLDER | `console.log('Voice input triggered')` | `chat-input.tsx:84` |
| **Send** | ➤ Send | ✅ WORKING | Sends message with datasets | `chat-input.tsx:92` |

**Attach Button Details:**
- **Current:** Opens DatasetDialog for selecting existing datasets
- **Expected by User:** Upload files from computer
- **Action Required:**
  1. Create DatasetDialog OR
  2. Replace with actual file upload `<input type="file">`

### Message Action Buttons

| Button | Icon | Status | Implementation | Location |
|--------|------|--------|----------------|----------|
| **Copy** | 📋 Copy | ❌ PLACEHOLDER | `console.log('Copy message triggered')` | `chat-message.tsx:78` |
| **Regenerate** | ↻ RotateCcw | ❌ PLACEHOLDER | `console.log('Regenerate message triggered')` | `chat-message.tsx:86` |
| **Create Workflow** | ⚙ Workflow | ❌ PLACEHOLDER | `console.log('Create workflow triggered')` | `chat-message.tsx:95` |

### Suggestion Buttons

| Button | Status | Implementation | Location |
|--------|--------|----------------|----------|
| **Suggestions** | ❌ PLACEHOLDER | `console.log('Suggestion clicked:', suggestion)` | `chat-message.tsx:111` |

---

## Workflow Builder Buttons

### Workflow-Level Controls

| Button | Icon | Status | Implementation | Issues | Location |
|--------|------|--------|----------------|--------|----------|
| **Start Workflow** | ▶ Play | ⚠️ PARTIAL | Calls `invokeWorkflow()` with mock data | Uses hardcoded mock data, TODO comment | `enhanced-workflow-builder.tsx:386` |
| **Pause Workflow** | ⏸ Pause | ❌ UI ONLY | Updates local state to 'paused' | No backend API call | `enhanced-workflow-builder.tsx:396` |
| **Resume Workflow** | ▶ Play | ❌ UI ONLY | Updates local state to 'running' | No backend API call | `enhanced-workflow-builder.tsx:407` |
| **Stop Workflow** | ⏹ Square | ⚠️ BUGGY | Calls `cancelWorkflow()` | Hardcoded WORKFLOW_ID bug | `enhanced-workflow-builder.tsx:417` |
| **Restart Workflow** | ↻ RotateCcw | ❌ UI ONLY | Resets UI state | No backend API call | `enhanced-workflow-builder.tsx:427` |

**Start Workflow Implementation:**
```typescript
// Line 208-220: enhanced-workflow-builder.tsx
case 'start':
  setWorkflowStatus('running')
  try {
    // TODO: Replace with actual workflow ID from Galaxy
    const mockWorkflowId = 'mock-rna-seq-workflow'
    const mockInputs = {
      fastq_files: ['sample1.fastq', 'sample2.fastq'],
      reference_genome: 'hg38',
    }
    await invokeWorkflow(mockWorkflowId, mockInputs)
  } catch (error) {
    setWorkflowStatus('error')
  }
  break
```

**Pause/Resume Implementation:**
```typescript
// Lines 222-231
case 'pause':
  setWorkflowStatus('paused')
  // Pause all running steps (local UI state only for now)
  setSteps(prev => prev.map(s =>
    s.status === 'running' ? { ...s, status: 'pending' as const } : s
  ))
  break
case 'resume':
  setWorkflowStatus('running')
  break  // No implementation!
```

### Workflow Management Buttons

| Button | Icon | Status | Implementation | Location |
|--------|------|--------|----------------|----------|
| **Save** | 💾 Save | ❌ PLACEHOLDER | `console.log('Save workflow')` | `enhanced-workflow-builder.tsx:440` |
| **Export** | ⬇ Download | ❌ PLACEHOLDER | `console.log('Export workflow')` | `enhanced-workflow-builder.tsx:448` |
| **Add Step** | ➕ Plus | ✅ WORKING | Adds new step with default values | `enhanced-workflow-builder.tsx:456` |
| **Get Help** | 💬 MessageCircle | ❌ PLACEHOLDER | `console.log('Get help triggered')` | `enhanced-workflow-builder.tsx:352` |

### Execution Mode Buttons

| Button | Status | Implementation | Location |
|--------|--------|----------------|----------|
| **Sequential** | ✅ WORKING | Updates `executionMode` state | `enhanced-workflow-builder.tsx:368` |
| **Step by Step** | ✅ WORKING | Updates `executionMode` state | `enhanced-workflow-builder.tsx:376` |

**Note:** Execution mode buttons update UI state only. Backend workflow execution doesn't use this setting yet.

---

## Step-Level Controls

### Individual Step Actions

| Action | Status | Implementation | Issues | Location |
|--------|--------|----------------|--------|----------|
| **Run** | ⚠️ SIMULATED | Sets status to 'running', setTimeout to 'completed' | Fake execution, no API call | `enhanced-workflow-builder.tsx:256` |
| **Pause** | ❌ UI ONLY | Sets status to 'pending' | No backend control | `enhanced-workflow-builder.tsx:267` |
| **Restart** | ❌ UI ONLY | Sets status to 'pending' | No backend control | `enhanced-workflow-builder.tsx:272` |
| **Edit** | ✅ WORKING | Opens edit dialog | Functional | `enhanced-workflow-builder.tsx:277` |
| **Delete** | ✅ WORKING | Removes step from array | Functional | `enhanced-workflow-builder.tsx:283` |

**Simulated Run Implementation:**
```typescript
// Lines 256-266
case 'run':
  setSteps(prev => prev.map(s =>
    s.id === stepId ? { ...s, status: 'running' as const } : s
  ))
  // Simulate completion
  setTimeout(() => {
    setSteps(prev => prev.map(s =>
      s.id === stepId ? { ...s, status: 'completed' as const } : s
    ))
  }, 3000)
  break
```

---

## Parameter Configuration

### Status: ❌ NOT IMPLEMENTED

**User Question:** "You have not implemented the parameter configuration and workflow/specific step start, resume, pause, stop control, yet, right?"

**Answer:** Correct. Parameter configuration UI is **not implemented**.

**What Exists:**
- `handleSaveParameters()` function exists (line 289)
- Parameters are stored in step state
- No UI for editing parameters

**What's Missing:**
- Parameter editing dialog/form
- Parameter validation
- Parameter type handling (text, number, file, etc.)
- Tool-specific parameter schemas

**Required Implementation:**
```typescript
// Need to create:
// 1. ParameterEditor component
// 2. Parameter form with dynamic fields based on tool schema
// 3. Validation logic
// 4. Save/cancel functionality
```

---

## File Upload Functionality

### Status: ❌ NOT IMPLEMENTED

**Current Situation:**
- Attach button exists but opens dataset selection (not file upload)
- No `<input type="file">` anywhere in codebase
- No file upload API endpoint
- No file handling logic

**What's Needed:**
1. **Frontend:**
   - File input element
   - File size validation
   - File type validation
   - Upload progress indicator
   - Preview for uploaded files

2. **Backend:**
   - File upload endpoint (`/api/upload`)
   - File storage (temp or permanent)
   - File metadata tracking
   - Integration with Galaxy datasets

3. **Integration:**
   - Link uploaded files to workflow inputs
   - Convert uploads to Galaxy datasets
   - Handle multiple file uploads

**Recommended Implementation:**
```typescript
// client/src/components/file-upload.tsx
export function FileUpload({ onUpload }) {
  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files
    if (!files) return

    const formData = new FormData()
    for (let i = 0; i < files.length; i++) {
      formData.append('files', files[i])
    }

    const response = await fetch('/api/upload', {
      method: 'POST',
      body: formData,
    })

    const result = await response.json()
    onUpload(result.datasets)
  }

  return (
    <input
      type="file"
      multiple
      accept=".fastq,.fasta,.txt,.csv"
      onChange={handleFileChange}
    />
  )
}
```

---

## Real-Time Workflow Execution

### Status: ⚠️ PARTIALLY IMPLEMENTED

**What Works:**
- ✅ SSE connection for real-time updates
- ✅ Step state tracking
- ✅ Log streaming
- ✅ Progress monitoring
- ✅ Timeline visualization

**What's Missing:**
- ❌ Start workflow with actual data
- ❌ Pause workflow execution
- ❌ Resume workflow execution
- ❌ Cancel individual steps
- ❌ Retry failed steps

**Backend API Status:**
| Endpoint | Status | Notes |
|----------|--------|-------|
| `POST /api/galaxy/workflows/invoke` | ✅ EXISTS | Starts workflow |
| `DELETE /api/galaxy/workflows/{id}/invocations/{id}` | ⚠️ BUGGY | Hardcoded WORKFLOW_ID |
| `GET /api/galaxy/workflows/sse/{id}` | ✅ EXISTS | SSE for updates |
| `PUT /api/galaxy/workflows/{id}/pause` | ❌ MISSING | No pause endpoint |
| `PUT /api/galaxy/workflows/{id}/resume` | ❌ MISSING | No resume endpoint |

---

## Summary Matrix

### By Status
| Status | Count | Buttons |
|--------|-------|---------|
| ✅ **Working** | 5 | Send, Add Step, Sequential/Step-by-step modes, Edit/Delete step |
| ⚠️ **Partial** | 2 | Start Workflow (mock data), Stop Workflow (hardcoded bug) |
| ❌ **Placeholder** | 8 | Copy, Regenerate, Create Workflow, Suggestions, Voice, Save, Export, Get Help |
| ❌ **UI Only** | 5 | Pause/Resume Workflow, Restart Workflow, Pause/Restart Step |
| ⚠️ **Simulated** | 1 | Run Step (setTimeout fake) |
| 🔴 **Broken** | 1 | Attach (missing component) |

### By Priority
| Priority | Issue | Impact | Effort |
|----------|-------|--------|--------|
| 🔴 **P0** | Fix missing DatasetDialog | App crashes | 2 hours |
| 🔴 **P0** | Implement file upload | Core feature missing | 8 hours |
| 🟠 **P1** | Fix cancelWorkflow bug | Stop button fails | 30 min |
| 🟠 **P1** | Implement parameter configuration | Can't edit parameters | 6 hours |
| 🟠 **P1** | Implement Copy/Regenerate | UX expectation | 2 hours |
| 🟡 **P2** | Implement Save/Export | Workflow persistence | 4 hours |
| 🟡 **P2** | Real Pause/Resume workflow | Execution control | 6 hours |
| 🟢 **P3** | Voice input | Nice to have | 12 hours |

---

## Detailed Implementation Requirements

### 1. DatasetDialog (P0 - 2 hours)

**Option A: Create Component**
```typescript
// client/src/components/dataset-dialog.tsx
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { DatasetConfig } from "@shared/schema"

interface DatasetDialogProps {
  isOpen: boolean
  onClose: () => void
  onDatasetsSelected: (inputs: DatasetConfig[], outputs: DatasetConfig[]) => void
  initialInputs?: DatasetConfig[]
  initialOutputs?: DatasetConfig[]
}

export function DatasetDialog({ isOpen, onClose, onDatasetsSelected, ... }: DatasetDialogProps) {
  // Implementation: List available datasets from Galaxy
  // Allow selection of inputs and outputs
  // Save selections and close
}
```

**Option B: Replace with File Upload**
```typescript
// Remove DatasetDialog import
// Replace with file upload functionality
// Update attach button to open file picker
```

### 2. File Upload System (P0 - 8 hours)

**Frontend Component:**
```typescript
// client/src/components/file-upload-dialog.tsx
export function FileUploadDialog({ isOpen, onClose, onFilesUploaded }) {
  const [files, setFiles] = useState<File[]>([])
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState(0)

  const handleUpload = async () => {
    setUploading(true)
    const formData = new FormData()
    files.forEach(file => formData.append('files', file))

    // Upload with progress
    const xhr = new XMLHttpRequest()
    xhr.upload.addEventListener('progress', (e) => {
      setProgress((e.loaded / e.total) * 100)
    })

    xhr.open('POST', '/api/upload')
    xhr.send(formData)

    xhr.onload = () => {
      const result = JSON.parse(xhr.responseText)
      onFilesUploaded(result.datasets)
      onClose()
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      {/* File input, progress bar, file list */}
    </Dialog>
  )
}
```

**Backend Endpoint:**
```typescript
// server/routes.ts
import multer from 'multer'

const upload = multer({
  dest: 'uploads/',
  limits: { fileSize: 500 * 1024 * 1024 } // 500MB
})

app.post('/api/upload', upload.array('files'), async (req, res) => {
  try {
    const uploadedFiles = req.files as Express.Multer.File[]

    // Convert to Galaxy datasets
    const datasets = await Promise.all(
      uploadedFiles.map(async (file) => {
        // Upload to Galaxy
        const galaxyDataset = await galaxyAPIProxy.uploadDataset({
          path: file.path,
          filename: file.originalname,
          file_type: detectFileType(file.originalname),
        })

        return {
          id: galaxyDataset.id,
          name: file.originalname,
          size: file.size,
          type: galaxyDataset.file_ext,
        }
      })
    )

    res.json({ datasets })
  } catch (error) {
    res.status(500).json({ error: error.message })
  }
})
```

### 3. Parameter Configuration (P1 - 6 hours)

**Component Structure:**
```typescript
// client/src/components/parameter-editor.tsx
export function ParameterEditor({ step, onSave, onCancel }) {
  const [parameters, setParameters] = useState(step.parameters)

  // Fetch tool schema from Galaxy
  const { data: toolSchema } = useQuery(['tool-schema', step.tool], () =>
    fetch(`/api/galaxy/tools/${step.tool}/schema`).then(r => r.json())
  )

  return (
    <Dialog>
      <DialogHeader>Edit Parameters: {step.title}</DialogHeader>
      <DialogContent>
        {toolSchema?.inputs.map(input => (
          <ParameterField
            key={input.name}
            input={input}
            value={parameters[input.name]}
            onChange={(value) => setParameters({ ...parameters, [input.name]: value })}
          />
        ))}
        <Button onClick={() => onSave(step.id, parameters)}>Save</Button>
      </DialogContent>
    </Dialog>
  )
}
```

### 4. Fix cancelWorkflow Bug (P1 - 30 min)

**Current Code (BUGGY):**
```typescript
// client/src/hooks/useWorkflowExecution.ts:210
await fetch(`/api/galaxy/workflows/WORKFLOW_ID/invocations/${state.invocationId}`, {
  method: 'DELETE',
});
```

**Fixed Code:**
```typescript
// Store workflowId in state
interface WorkflowExecutionState {
  workflowId: string | null  // ADD THIS
  invocationId: string | null
  // ... rest
}

// Update invokeWorkflow to store workflowId
const invokeWorkflow = async (workflowId: string, inputs: Record<string, any>) => {
  // ...
  setState(prev => ({
    ...prev,
    workflowId,  // ADD THIS
    invocationId: invocation.id,
    // ...
  }));
};

// Fix cancelWorkflow
const cancelWorkflow = async () => {
  if (!state.invocationId || !state.workflowId) return;

  try {
    await fetch(`/api/galaxy/workflows/${state.workflowId}/invocations/${state.invocationId}`, {
      method: 'DELETE',
    });
    // ...
  }
};
```

### 5. Copy/Regenerate Buttons (P1 - 2 hours)

**Copy Implementation:**
```typescript
// client/src/components/chat-message.tsx
const handleCopy = () => {
  navigator.clipboard.writeText(message.content)
  toast({
    title: "Copied to clipboard",
    description: "Message content copied successfully",
  })
}

<Button onClick={handleCopy}>
  <Copy className="h-3 w-3 mr-1" />
  Copy
</Button>
```

**Regenerate Implementation:**
```typescript
// client/src/components/chat-interface.tsx
const handleRegenerate = async (messageId: string) => {
  const message = messages.find(m => m.id === messageId)
  if (!message) return

  // Find previous user message
  const userMessage = messages[messages.indexOf(message) - 1]
  if (!userMessage) return

  // Remove assistant message and regenerate
  setMessages(prev => prev.filter(m => m.id !== messageId))
  await sendMessage(userMessage.content)
}
```

### 6. Workflow Pause/Resume (P2 - 6 hours)

**Backend Implementation:**
```typescript
// server/routes.ts
app.put('/api/galaxy/workflows/:workflowId/invocations/:invocationId/pause', async (req, res) => {
  // Call Galaxy API to pause workflow
  const result = await galaxyAPIProxy.pauseWorkflow(
    req.params.workflowId,
    req.params.invocationId
  )
  res.json(result)
})

app.put('/api/galaxy/workflows/:workflowId/invocations/:invocationId/resume', async (req, res) => {
  // Call Galaxy API to resume workflow
  const result = await galaxyAPIProxy.resumeWorkflow(
    req.params.workflowId,
    req.params.invocationId
  )
  res.json(result)
})
```

**Frontend Implementation:**
```typescript
// Update handleWorkflowAction
case 'pause':
  setWorkflowStatus('paused')
  try {
    await fetch(`/api/galaxy/workflows/${state.workflowId}/invocations/${invocationId}/pause`, {
      method: 'PUT',
    })
  } catch (error) {
    console.error('Failed to pause:', error)
    setWorkflowStatus('running')
  }
  break

case 'resume':
  setWorkflowStatus('running')
  try {
    await fetch(`/api/galaxy/workflows/${state.workflowId}/invocations/${invocationId}/resume`, {
      method: 'PUT',
    })
  } catch (error) {
    console.error('Failed to resume:', error)
    setWorkflowStatus('paused')
  }
  break
```

---

## Testing Checklist

### Before Implementation
- [x] Audit all buttons in chat interface
- [x] Audit all buttons in workflow builder
- [x] Document missing functionality
- [x] Identify critical issues
- [x] Prioritize fixes

### After Implementation (TODO)
- [ ] Test DatasetDialog functionality
- [ ] Test file upload with various file types
- [ ] Test parameter editing for different tools
- [ ] Test workflow start with real data
- [ ] Test workflow pause/resume
- [ ] Test workflow cancellation
- [ ] Test Copy button
- [ ] Test Regenerate button
- [ ] Verify all placeholder buttons work
- [ ] End-to-end workflow execution test

---

## Recommendations

### Immediate Actions (Next 24 hours)
1. **Fix DatasetDialog** - Create stub component to prevent crashes
2. **Fix cancelWorkflow bug** - Add workflowId to state
3. **Implement basic file upload** - Core feature requirement

### Short Term (Next Week)
1. **Parameter configuration UI** - Essential for workflow customization
2. **Copy/Regenerate buttons** - Basic UX expectations
3. **Real workflow pause/resume** - Better execution control

### Long Term (Next Month)
1. **Save/Export workflows** - Workflow persistence
2. **Voice input** - Advanced feature
3. **Advanced file handling** - Batch uploads, validation, preview

---

## Conclusion

**Key Findings:**
- **22 total buttons** identified across chat interface and workflow builder
- **Only 5 buttons (23%)** are fully functional
- **1 critical broken component** (DatasetDialog)
- **No file upload functionality** exists
- **Parameter configuration** not implemented
- **Most workflow controls** are UI state only

**Recommendation:** Prioritize P0 and P1 fixes before release. The missing DatasetDialog and file upload functionality are **blocking issues** that prevent core features from working.

**Total Implementation Effort:** ~40 hours for all P0-P1 items

---

*Generated by Button Functionality Audit*
*Last Updated: October 3, 2025*
