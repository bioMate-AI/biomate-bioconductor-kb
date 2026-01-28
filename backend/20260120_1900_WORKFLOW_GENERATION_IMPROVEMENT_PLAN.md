# Workflow Generation Improvement Plan

**Date:** 2026-01-20 19:00
**Status:** Analysis & Design

---

## Current Implementation Gaps

### 1. ProposeValidateWorkflowGenerator Issues

| Issue | Current State | Should Be |
|-------|---------------|-----------|
| LLM Knowledge Source | Training data only (unreliable) | Search workflows + tools + web |
| Iteration Limit | Fixed 2 iterations | Dynamic until confidence threshold |
| Reference Search | None | Search existing 951+ workflows first |
| Tool Discovery | Only validates after proposal | Proactively check available tools |
| Web Knowledge | None | Optional web search for best practices |

### 2. User Feedback Loop - Missing

**Current:**
```
User Request → Generate Workflow → Return to User → END
```

**Should Be:**
```
User Request → Generate Workflow → Return with Validation Info
      ↓
User Reviews → Approve / Modify / Reject
      ↓
If Modify: Refine with Feedback → Return Updated
      ↓
Repeat until User Satisfied
```

### 3. Frontend Capabilities

**Has:**
- Workflow step display with edit/remove buttons
- "Get Help" button
- Step status tracking

**Missing:**
- Feedback submission mechanism
- Step approval/rejection UI
- Natural language refinement input
- Validation info display (confidence, warnings)

---

## Improved Architecture

### Phase 1: Enhanced Proposal with Resource Search

```
User Intent
    │
    ▼
┌─────────────────────────────────────────┐
│ 1. Search Reference Resources           │
│    a. Search existing 951+ workflows    │
│    b. Get domain tool categories        │
│    c. Check benchmark knowledge rules   │
│    Output: Reference context            │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 2. LLM Proposes with Context            │
│    - Provide workflow examples          │
│    - Provide available tools list       │
│    - Provide domain best practices      │
│    Output: Informed proposal            │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 3. Validate & Refine Loop               │
│    While confidence < threshold:        │
│      - Validate tools against index     │
│      - Check knowledge rules            │
│      - Refine if needed                 │
│    Output: Validated workflow           │
└─────────────────────────────────────────┘
    │
    ▼
Return to User with Validation Info
```

### Phase 2: User Feedback Loop

```
┌─────────────────────────────────────────┐
│ User Reviews Workflow                   │
│    - See confidence scores              │
│    - See tool availability              │
│    - See warnings/suggestions           │
└─────────────────────────────────────────┘
    │
    ├── Approve → Execute Workflow
    │
    ├── Modify Step →
    │       User edits step parameters
    │       System validates changes
    │       Return updated workflow
    │
    ├── Remove Step →
    │       Remove step, revalidate connections
    │       Return updated workflow
    │
    ├── Add Step →
    │       User describes needed step
    │       LLM suggests tool + parameters
    │       Insert and revalidate
    │
    └── Refine via Chat →
            "Use Salmon instead of HISAT2"
            "Add a trimming step"
            LLM refines workflow
            Return updated workflow
```

---

## Implementation Plan

### Step 1: Enhance ProposeValidateWorkflowGenerator

```python
class EnhancedProposeValidateGenerator:

    CONFIDENCE_THRESHOLD = 0.85  # Continue refining until this
    MAX_ITERATIONS = 5  # Safety limit

    def generate_workflow(self, user_intent, ...):
        # Phase 1: Gather context
        context = self._gather_reference_context(user_intent)

        # Phase 2: Informed proposal
        proposal = self._propose_with_context(user_intent, context)

        # Phase 3: Dynamic refinement
        iteration = 0
        while (proposal.confidence < self.CONFIDENCE_THRESHOLD
               and iteration < self.MAX_ITERATIONS):
            proposal = self._refine_proposal(proposal)
            iteration += 1

        return proposal

    def _gather_reference_context(self, user_intent):
        """Search resources before proposing."""
        # 1. Search existing workflows
        similar_workflows = self.workflow_search.search(user_intent, limit=3)

        # 2. Get domain tool categories
        domain = detect_domain(user_intent)
        available_tools = self.tool_index.get_tools_by_category(domain)

        # 3. Get benchmark rules
        rules = self.knowledge_db.get_decision_rules(domain)

        return {
            'similar_workflows': similar_workflows,
            'available_tools': available_tools,
            'decision_rules': rules
        }
```

### Step 2: Add Feedback/Refinement API

```python
# New endpoint: POST /api/ai_assistant/workflow/refine
class WorkflowRefinementRequest(BaseModel):
    workflow_id: str
    feedback_type: str  # 'approve', 'modify_step', 'remove_step', 'add_step', 'chat_refine'
    step_id: Optional[str] = None
    modifications: Optional[Dict] = None
    chat_message: Optional[str] = None

@router.post("/api/ai_assistant/workflow/refine")
async def refine_workflow(request: WorkflowRefinementRequest, trans):
    """
    Refine workflow based on user feedback.

    Feedback types:
    - approve: Mark workflow as approved, ready to execute
    - modify_step: User edited a step's parameters
    - remove_step: User removed a step
    - add_step: User wants to add a step (describe in chat_message)
    - chat_refine: Natural language refinement request
    """
    ai_assistant = get_ai_assistant(trans)

    if request.feedback_type == 'approve':
        return {'status': 'approved', 'workflow_id': request.workflow_id}

    elif request.feedback_type == 'modify_step':
        return ai_assistant.modify_workflow_step(
            request.workflow_id,
            request.step_id,
            request.modifications
        )

    elif request.feedback_type == 'remove_step':
        return ai_assistant.remove_workflow_step(
            request.workflow_id,
            request.step_id
        )

    elif request.feedback_type == 'add_step':
        return ai_assistant.add_workflow_step(
            request.workflow_id,
            request.chat_message  # "Add a trimming step before alignment"
        )

    elif request.feedback_type == 'chat_refine':
        return ai_assistant.refine_workflow_via_chat(
            request.workflow_id,
            request.chat_message  # "Use Salmon instead of HISAT2"
        )
```

### Step 3: Frontend Enhancements

```typescript
// workflow-builder.tsx additions

interface WorkflowBuilderProps {
  // ... existing props
  onStepApprove?: (stepId: string) => void
  onStepModify?: (stepId: string, modifications: any) => void
  onChatRefine?: (message: string) => void
  validationInfo?: {
    confidence: number
    warnings: string[]
    toolAvailability: Record<string, boolean>
  }
}

// Add refinement chat input
<div className="refinement-input">
  <Input
    placeholder="Refine workflow: e.g., 'Use Salmon instead of HISAT2'"
    onSubmit={onChatRefine}
  />
</div>

// Add validation display
{validationInfo && (
  <ValidationPanel
    confidence={validationInfo.confidence}
    warnings={validationInfo.warnings}
    toolAvailability={validationInfo.toolAvailability}
  />
)}
```

---

## API Response Structure (Enhanced)

```json
{
  "success": true,
  "workflow_id": "wf-12345",
  "workflow_ga": { ... },
  "workflow_steps": [
    {
      "step": 1,
      "tool_name": "FastQC",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74",
      "purpose": "Quality control",
      "status": "available",
      "confidence": 1.0,
      "warnings": [],
      "alternatives": []
    },
    {
      "step": 2,
      "tool_name": "HISAT2",
      "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/hisat/hisat/1.0.3",
      "purpose": "Alignment",
      "status": "available",
      "confidence": 0.9,
      "warnings": ["Consider Salmon for transcript-level quantification"],
      "alternatives": ["salmon", "kallisto"]
    }
  ],
  "validation": {
    "overall_confidence": 0.92,
    "all_tools_available": true,
    "warnings": ["Step 2: Consider Salmon for DE analysis"],
    "suggestions": ["Add adapter trimming before alignment"]
  },
  "refinement_history": [...],
  "source": "propose_validate",
  "requires_user_review": true
}
```

---

## Next Steps

1. **Implement** `_gather_reference_context()` in ProposeValidateWorkflowGenerator
2. **Implement** dynamic confidence-based iteration
3. **Add** `/api/ai_assistant/workflow/refine` endpoint
4. **Add** feedback methods to AIAssistant class
5. **Update** frontend to display validation info and support refinement

---

## Questions for User

1. **Confidence threshold**: What confidence level should trigger user review? (0.85 suggested)
2. **Web search**: Should we add optional web search for best practices?
3. **Step-by-step approval**: Should users approve each step or the whole workflow?
4. **Auto-execute**: Should high-confidence workflows auto-execute or always require approval?
