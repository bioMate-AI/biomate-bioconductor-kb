# Parameter Preview Architecture - Corrected Flow

**Created**: 2025-10-14
**Status**: IMPLEMENTATION IN PROGRESS
**Purpose**: Document the correct architecture for LLM parameter generation and user confirmation

---

## ❌ Incorrect Flow (Initial Design)

```
User Query → Generate Parameters → Show Dialog → Generate Workflow
```

**Problems:**
- Can't generate parameters without knowing workflow structure
- Dialog blocks workflow generation
- User can't see workflow context while reviewing parameters
- Premature optimization - generates params before knowing if they're needed

---

## ✅ Correct Flow (Revised Architecture)

```
User Query → Generate Workflow (with LLM params) → Workflow Builder → Execute Button → Parameter Preview Dialog → Confirm → Execute
```

**Why This Works:**
1. **Workflow First**: Backend generates complete workflow with LLM-inferred parameters
2. **Visual Context**: User sees workflow structure in builder before execution
3. **Just-in-Time Confirmation**: Parameters reviewed immediately before execution
4. **Optional Dialog**: Only shown if parameters need confirmation (low confidence, required input)
5. **Edit Capability**: User can modify parameters based on workflow context

---

## Detailed Flow Diagram

```
┌────────────────────────────────────────────────────────────────┐
│ STEP 1: User Input                                             │
│ User types: "Get mouse genes from Ensembl related to kinase"  │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 2: Backend Workflow Generation                            │
│ ┌────────────────────────────────────────────────────────────┐ │
│ │ LLMParameterGenerator.generate_parameters():               │ │
│ │   tool_id: "biomate_dm_ensembl_genes"                      │ │
│ │   user_intent: "Get mouse genes... kinase"                 │ │
│ │   → parameters: {                                           │ │
│ │       "organism": "mouse",                                  │ │
│ │       "filter_column": "description",                       │ │
│ │       "filter_value": "kinase"                              │ │
│ │     }                                                        │ │
│ │   → confidence: 0.85                                        │ │
│ │   → reasoning: "Inferred organism and search term from      │ │
│ │                 user query"                                 │ │
│ └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ WorkflowGenerator builds complete .ga JSON:                    │
│   - Step 0: Ensembl Gene Query (params auto-filled)           │
│   - Step 1: Filter by Expression (default params)             │
│   - Step 2: Enrichment Analysis (default params)              │
│   - Connections: 0→1→2                                         │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 3: API Response                                           │
│ POST /api/ai_assistant/generate_workflow                       │
│ Response:                                                       │
│ {                                                               │
│   "success": true,                                              │
│   "workflow_ga": { ... },  // Complete Galaxy workflow         │
│   "generated_parameters": [                                     │
│     {                                                           │
│       "step_id": 0,                                             │
│       "tool_id": "biomate_dm_ensembl_genes",                   │
│       "tool_name": "Ensembl Gene Query",                       │
│       "parameters": {                                           │
│         "organism": "mouse",                                    │
│         "filter_column": "description",                         │
│         "filter_value": "kinase"                                │
│       },                                                        │
│       "confidence": 0.85,                                       │
│       "reasoning": "Inferred organism and search term..."       │
│     }                                                           │
│   ],                                                            │
│   "source": "tool_constrained_generation",                     │
│   "confidence": 0.85                                            │
│ }                                                               │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 4: Frontend - Workflow Builder Display                   │
│ ┌────────────────────────────────────────────────────────────┐ │
│ │ Workflow appears in visual builder                         │ │
│ │                                                             │ │
│ │ ┌──────────────────┐                                       │ │
│ │ │ Step 1           │                                       │ │
│ │ │ Ensembl Genes    │  ⚡ Auto-filled (85% confidence)      │ │
│ │ │ organism: mouse  │                                       │ │
│ │ └────────┬─────────┘                                       │ │
│ │          │                                                  │ │
│ │          ▼                                                  │ │
│ │ ┌──────────────────┐                                       │ │
│ │ │ Step 2           │                                       │ │
│ │ │ Filter Expression│                                       │ │
│ │ └────────┬─────────┘                                       │ │
│ │          │                                                  │ │
│ │          ▼                                                  │ │
│ │ ┌──────────────────┐                                       │ │
│ │ │ Step 3           │                                       │ │
│ │ │ GO Enrichment    │                                       │ │
│ │ └──────────────────┘                                       │ │
│ │                                                             │ │
│ │ [Edit Workflow]  [Execute Workflow]                        │ │
│ └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ User can:                                                       │
│ - Inspect workflow structure                                   │
│ - Edit connections/steps                                       │
│ - See which parameters were auto-generated (⚡ indicator)      │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 5: User Clicks "Execute Workflow"                        │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 6: Parameter Preview Dialog (CONDITIONAL)                │
│                                                                 │
│ Dialog shows IF:                                                │
│ - Any parameter has confidence < 0.7 (needs review)            │
│ - Any parameter is marked as "required user input"             │
│ - User has enabled "Always review parameters" setting          │
│                                                                 │
│ ┌────────────────────────────────────────────────────────────┐ │
│ │ Review Generated Parameters                                │ │
│ │                                                             │ │
│ │ ⚠️ Some parameters have low confidence. Please review.     │ │
│ │                                                             │ │
│ │ ┌──────────────────────────────────────────────────────┐  │ │
│ │ │ Step 1: Ensembl Gene Query          [High 85%]       │  │ │
│ │ │                                                       │  │ │
│ │ │ organism: [mouse        ]  ✏️                        │  │ │
│ │ │ filter_column: [description ]  ✏️                    │  │ │
│ │ │ filter_value: [kinase       ]  ✏️                    │  │ │
│ │ │                                                       │  │ │
│ │ │ Reasoning: "Inferred organism from 'mouse' mention   │  │ │
│ │ │            and search term from 'kinase' keyword"    │  │ │
│ │ └──────────────────────────────────────────────────────┘  │ │
│ │                                                             │ │
│ │ [Cancel]  [Confirm & Execute Workflow]                     │ │
│ └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ User can:                                                       │
│ - Review all generated parameters                              │
│ - Edit any value inline                                        │
│ - See confidence scores and reasoning                          │
│ - Cancel execution or confirm with edited values               │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 7: User Confirms                                          │
│ - Edited parameters are saved to workflow                      │
│ - Workflow metadata updated with confirmed params              │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│ STEP 8: Workflow Execution                                     │
│ - Galaxy executes workflow with confirmed parameters           │
│ - Progress tracking in UI                                      │
│ - Results appear when complete                                 │
└────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### Backend Components

#### 1. `LLMParameterGenerator` (backend/lib/galaxy/ai/llm_parameter_generator.py)
**Responsibility**: Intelligent parameter inference from user intent

```python
def generate_parameters(
    tool_id: str,
    tool_name: str,
    user_intent: str,
    tool_parameters: List[Dict[str, Any]],
    context: Optional[Dict[str, Any]] = None
) -> Tuple[Dict[str, Any], float, str]:
    """
    Returns:
        (parameters_dict, confidence_score, reasoning_string)
    """
```

**Called By**: `GalaxyWorkflowGenerator._build_galaxy_workflow_json()`
**When**: During workflow generation for data source tools
**Output**: Parameter values, confidence score (0-1), reasoning text

#### 2. `GalaxyWorkflowGenerator` (backend/lib/galaxy/ai/galaxy_workflow_generator.py)
**Responsibility**: Build complete Galaxy .ga workflow with populated parameters

**Key Method**:
```python
def _build_galaxy_workflow_json(
    workflow_structure: Dict[str, Any],
    dataset_assignments: Dict[str, Any],
    user_intent: Optional[str] = None
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """
    Returns:
        (workflow_ga_json, generated_parameters_list)
    """
```

**Process**:
1. Iterate through workflow steps
2. For data source tools: call `LLMParameterGenerator`
3. For other tools: use default parameters
4. Build connections
5. Track generated parameters with metadata
6. Return complete workflow + parameter metadata

#### 3. `AIAssistant` (backend/lib/galaxy/ai/ai_assistant.py)
**Responsibility**: Propagate generated parameters through response

**Key Update**:
```python
return {
    'success': True,
    'workflow_ga': workflow_ga,
    'generated_parameters': generated_parameters,  # NEW
    ...
}
```

#### 4. API Endpoint (backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py)
**Responsibility**: Return parameters in HTTP response

**Endpoint**: `POST /api/ai_assistant/generate_workflow`

**Response**:
```json
{
  "success": true,
  "workflow_ga": {...},
  "generated_parameters": [...]
}
```

---

### Frontend Components

#### 1. `ParameterPreviewDialog` (frontend/client/src/components/parameter-preview-dialog.tsx)
**Responsibility**: Visual parameter review and editing interface

**Props**:
```typescript
interface ParameterPreviewDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  generatedParameters: GeneratedParameter[]
  onConfirm: (editedParameters: GeneratedParameter[]) => void
  onCancel: () => void
}
```

**Features**:
- Color-coded confidence badges (green/yellow/red)
- Inline parameter editing
- Warning banner for low confidence
- Reasoning display per step
- Confirm/Cancel actions

#### 2. Workflow Builder (TODO: Integration Point)
**Responsibility**: Show dialog before execution

**Pseudo-code**:
```typescript
function handleExecuteWorkflow() {
  // Get generated_parameters from workflow metadata
  const genParams = currentWorkflow.metadata?.generated_parameters || []

  // Determine if dialog should show
  const needsReview = genParams.some(p => p.confidence < 0.7)
    || userSettings.alwaysReviewParams

  if (needsReview && genParams.length > 0) {
    // Show parameter preview dialog
    setParameterDialogOpen(true)
    setPendingExecution(true)
  } else {
    // Execute directly
    executeWorkflow(currentWorkflow)
  }
}

function handleParameterConfirm(editedParams: GeneratedParameter[]) {
  // Update workflow with edited parameters
  updateWorkflowParameters(currentWorkflow.id, editedParams)

  // Close dialog
  setParameterDialogOpen(false)

  // Execute workflow
  executeWorkflow(currentWorkflow)
}
```

#### 3. `GalaxyAssistant` (frontend/server/galaxy-assistant.ts)
**Responsibility**: Pass generated_parameters through to frontend

**Current State**: ✅ Already working
- `generateWorkflow()` returns full API response
- Response includes `generated_parameters`
- Passed to chat via `generatedWorkflow` field

---

## Data Flow Summary

```
Backend:
  LLMParameterGenerator → WorkflowGenerator → AIAssistant → API Endpoint

Frontend:
  API Response → GalaxyAssistant → Chat Metadata → Workflow Builder → ParameterDialog
```

**Key Insight**: Parameters flow WITH the workflow, not BEFORE it.

---

## Implementation Status

### ✅ Completed (Phase 1 Day 1-2)

1. **Backend Parameter Generation**:
   - ✅ `LLMParameterGenerator` module (363 lines)
   - ✅ Integration into `GalaxyWorkflowGenerator`
   - ✅ `AIAssistant` propagation
   - ✅ API endpoint response format

2. **Frontend Component**:
   - ✅ `ParameterPreviewDialog` component (274 lines)
   - ✅ `GalaxyAssistant` logging update

3. **Architecture Documentation**:
   - ✅ This document

### ⏳ Remaining Work

1. **Workflow Builder Integration** (Phase 2 Day 3-4):
   - [ ] Attach `generated_parameters` to workflow metadata
   - [ ] Add "Execute Workflow" button handler
   - [ ] Show dialog conditionally before execution
   - [ ] Update workflow with edited parameters

2. **E2E Testing** (Phase 3-5):
   - [ ] Detailed test plan document
   - [ ] Playwright framework setup
   - [ ] 10 test cases with full execution
   - [ ] Visual test report with screenshots

---

## Edge Cases & Considerations

### 1. No Generated Parameters
**Scenario**: Workflow has no data source tools (all regular tools)
**Handling**: Skip parameter dialog, execute directly

### 2. All High Confidence
**Scenario**: All parameters have confidence >= 0.8
**Handling**: Optional dialog (user setting), or execute directly

### 3. User Edits Workflow After Generation
**Scenario**: User adds/removes steps in workflow builder
**Handling**: Re-run parameter generation for new data source tools

### 4. API Returns No Parameters (Fallback)
**Scenario**: Backend fails to generate parameters
**Handling**: Use defaults, show warning in dialog

### 5. User Cancels Dialog
**Scenario**: User clicks "Cancel" in parameter preview
**Handling**: Return to workflow builder, do not execute

---

## Success Criteria

### Functional Requirements
- ✅ Backend generates parameters for data source tools
- ✅ Parameters have confidence scores and reasoning
- ✅ API returns parameters in response
- ✅ Frontend dialog displays parameters with editing
- ⏳ Dialog appears before workflow execution (not generation)
- ⏳ User can edit parameters inline
- ⏳ Edited parameters are saved to workflow
- ⏳ Workflow executes with confirmed parameters

### User Experience
- ⏳ User sees complete workflow before parameter review
- ⏳ Low-confidence parameters are visually highlighted
- ⏳ Reasoning helps user understand parameter choices
- ⏳ Editing is intuitive (hover-to-edit pattern)
- ⏳ Workflow execution feels natural and transparent

### E2E Testing
- ⏳ All 10 test cases pass with parameter generation
- ⏳ Visual evidence (screenshots/videos) of parameter dialog
- ⏳ Parameter accuracy >80% for critical fields
- ⏳ Workflow executes successfully end-to-end

---

## Lessons Learned

### ❌ Initial Mistake
**What**: Planned to show parameter dialog BEFORE workflow generation
**Why Wrong**: Can't know what parameters to generate without workflow structure
**Impact**: Would have required complete redesign

### ✅ Correction
**What**: Show parameter dialog BEFORE workflow execution (after generation)
**Why Right**: User has full context, parameters are already in workflow
**Impact**: Clean separation of concerns, better UX

### 💡 Key Insight
**User-centric flow**: Generate first, review second, execute third
This mirrors how users think: "Show me what you'll do, let me adjust, then do it"

---

**Document Version**: 1.0
**Last Updated**: 2025-10-14
**Next Review**: After workflow builder integration complete
