# E2E Test Issues and Fixes

**Date**: 2026-02-09
**Branch**: connection_formal
**Status**: In Progress

---

## Bug #1: Missing Engine Badge in UI

### Issue
E2E tests expect to see "Nextflow" or "Galaxy" text in the UI as engine badges, but the frontend doesn't display them.

**Test Case**: `Generate workflow and verify tags are set` (line 25-54)
- Looks for `text=/Nextflow|Galaxy/i` (line 41)
- Also checks for `data-engine` attribute (test case 6, line 202-207)

**Root Cause**:
1. Backend returns `execution_engine` and `workflow_tags` in API response
2. Frontend receives these fields but doesn't pass them to WorkflowArtifact component
3. WorkflowArtifact component doesn't have props or UI for displaying engine badge

### Fix Applied
**3 files modified**:

#### 1. `frontend/client/src/components/workflow-artifact.tsx`
- **Line ~107-109**: Added props to interface
  ```typescript
  // Execution engine (galaxy or nextflow)
  executionEngine?: 'galaxy' | 'nextflow'
  workflowTags?: string[]
  ```

- **Line ~165-168**: Added to destructuring
  ```typescript
  // Execution engine detection
  executionEngine,
  workflowTags = [],
  ```

- **Line ~318-328**: Added engine badge display
  ```typescript
  {/* Execution Engine Badge */}
  {executionEngine && (
    <Badge
      variant={executionEngine === 'nextflow' ? 'default' : 'outline'}
      className="text-xs"
      data-engine={executionEngine}
    >
      {executionEngine === 'nextflow' ? 'Nextflow' : 'Galaxy'}
    </Badge>
  )}
  ```

#### 2. `frontend/client/src/components/chat-message.tsx`
- **Line ~156-158**: Pass props to WorkflowArtifact
  ```typescript
  // Execution engine detection
  executionEngine={message.metadata.execution_engine}
  workflowTags={message.metadata.workflow_tags || []}
  ```

#### 3. Backend (already correct)
- `backend/lib/galaxy/ai/ai_assistant.py` line 1542-1543
- Already returns `execution_engine` and `workflow_tags`

### Expected Test Results
After this fix:
- ✅ Test 1: "Generate workflow and verify tags are set" should PASS
- ✅ Test 6: "Verify engine detection in workflow execution" should PASS
- UI will display "Nextflow" or "Galaxy" badge next to steps count
- Badge has `data-engine` attribute for test selectors

---

## Bug #2: Execution Engine Not Added to Message Metadata

### Issue
Backend returns `execution_engine` and `workflow_tags` in the workflow generation response, but the chat-interface.tsx component doesn't extract these fields and add them to message metadata.

**Impact**:
- Even though chat-message.tsx tries to read `message.metadata.execution_engine` (after Bug #1 fix), it would be undefined
- WorkflowArtifact would receive `undefined` for executionEngine prop
- Engine badge wouldn't display

**Root Cause**:
- `chat-interface.tsx` line ~227-251: Constructs message metadata from API response
- Missing: extraction of `execution_engine` and `workflow_tags` from `data.workflow`

### Fix Applied
**1 file modified**:

#### `frontend/client/src/components/chat-interface.tsx`
- **Line ~251-253**: Added to metadata object
  ```typescript
  // Execution engine detection (from workflow generation response)
  execution_engine: data.workflow?.execution_engine,
  workflow_tags: data.workflow?.workflow_tags || []
  ```

### Data Flow After Fix
1. Backend returns: `{ workflow: { execution_engine: 'nextflow', workflow_tags: [...] } }`
2. Chat-interface extracts: `metadata.execution_engine` and `metadata.workflow_tags`
3. Chat-message passes: `executionEngine={message.metadata.execution_engine}`
4. WorkflowArtifact receives: `executionEngine` prop
5. UI displays: "Nextflow" or "Galaxy" badge

### Expected Test Results
After this fix:
- ✅ Complete data flow from backend → message metadata → component props → UI
- ✅ Engine badge will display correctly

---

---

## Bug #3: Missing TypeScript Type Definitions

### Issue
`WorkflowGenerationResponse` type definition doesn't include `execution_engine` and `workflow_tags` fields, which could cause TypeScript compilation issues.

**Impact**:
- TypeScript would not recognize these fields as valid
- Could cause type errors in strict mode
- Reduces code documentation and IDE autocomplete

**Root Cause**:
- Type definition in `galaxy-types.ts` was created before execution engine detection was added
- Backend returns these fields but frontend types don't reflect them

### Fix Applied
**1 file modified**:

#### `frontend/shared/galaxy-types.ts`
- **Line ~420-422**: Added fields to interface
  ```typescript
  // Execution engine detection (added 2026-02-09)
  execution_engine?: 'galaxy' | 'nextflow'; // Explicit execution engine for frontend
  workflow_tags?: string[]; // Tags for engine detection (galaxy-reuse, nextflow, ai-generated)
  ```

### Expected Test Results
After this fix:
- ✅ TypeScript compilation will recognize the fields
- ✅ Better IDE autocomplete for developers
- ✅ Type safety for execution engine detection

---

## Bugs Summary

| Bug # | Issue | Files Modified | Status |
|-------|-------|----------------|--------|
| #1 | Missing engine badge in UI | workflow-artifact.tsx, chat-message.tsx | ✅ Fixed |
| #2 | Execution engine not in metadata | chat-interface.tsx | ✅ Fixed |
| #3 | Missing TypeScript type definitions | galaxy-types.ts | ✅ Fixed |

**Total Files Modified**: 4
**Total Lines Added**: ~25

---

## Test Execution Status

**Prerequisites**:
- [ ] Backend running on port 8081
- [ ] Frontend running on port 5000

**Test Results**: Not yet executed (awaiting service startup)

