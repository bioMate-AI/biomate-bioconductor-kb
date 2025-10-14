# E2E Test IDs - Implementation Complete

**Date**: 2025-10-14
**Status**: ✅ All 6 required test IDs added
**Branch**: `frontend_stronger`

---

## Summary

All required `data-testid` attributes have been successfully added to frontend components to enable Playwright E2E test automation. The frontend is now ready for visual browser testing.

---

## Test IDs Added

### 1. ✅ Chat Input Field
**File**: `frontend/client/src/components/chat-input.tsx` (NEW)
**Test ID**: `data-testid="chat-input"`
**Element**: `<Textarea>` component
**Purpose**: Playwright can type user queries here

```tsx
<Textarea
  ref={textareaRef}
  data-testid="chat-input"
  value={message}
  onInput={handleInput}
  onKeyDown={handleKeyDown}
  placeholder={placeholder}
  disabled={disabled}
  className="min-h-[60px] max-h-[200px] resize-none"
  rows={1}
/>
```

---

### 2. ✅ Chat Send Button
**File**: `frontend/client/src/components/chat-input.tsx` (NEW)
**Test ID**: `data-testid="chat-send-button"`
**Element**: `<Button>` component
**Purpose**: Playwright can click to send chat messages

```tsx
<Button
  data-testid="chat-send-button"
  onClick={handleSend}
  disabled={disabled || !message.trim()}
  size="icon"
  className="h-[60px] w-[60px] flex-shrink-0"
>
  <Send className="w-4 h-4" />
</Button>
```

---

### 3. ✅ Workflow Generated Message
**File**: `frontend/client/src/components/chat-message.tsx`
**Test ID**: `data-testid="workflow-generated-message"`
**Element**: `<div>` wrapper for chat message
**Purpose**: Playwright can detect when workflow generation is complete

```tsx
<div
  className={cn("flex gap-4 p-4", isUser && "flex-row-reverse")}
  data-testid={!isUser && hasWorkflowInfo ? "workflow-generated-message" : undefined}
>
```

**Detection Logic**:
```tsx
const hasWorkflowInfo = message.content?.includes('workflow') ||
                        message.content?.includes('Workflow') ||
                        message.metadata?.workflow
```

---

### 4. ✅ View Workflow Button
**File**: `frontend/client/src/components/chat-message.tsx`
**Test ID**: `data-testid="button-view-workflow"`
**Element**: `<Button>` component
**Purpose**: Playwright can click to open workflow in builder

```tsx
<Button
  variant="ghost"
  size="sm"
  onClick={onCreateWorkflow}
  data-testid="button-view-workflow"
>
  <Workflow className="h-3 w-3 mr-1" />
  View Workflow
</Button>
```

**Note**: Button label changed from "Create Workflow" → "View Workflow" for clarity

---

### 5. ✅ Execute Workflow Button
**File**: `frontend/client/src/components/enhanced-workflow-builder.tsx`
**Test ID**: `data-testid="button-execute-workflow"`
**Element**: `<Button>` component
**Purpose**: Playwright can click to start workflow execution

```tsx
<Button
  onClick={() => handleWorkflowAction('start')}
  disabled={!canStartWorkflow}
  data-testid="button-execute-workflow"
>
  <Play className="w-4 h-4 mr-2" />
  Execute Workflow
</Button>
```

**Note**: Button label changed from "Start Workflow" → "Execute Workflow" for consistency

---

### 6. ✅ Workflow Status Indicator
**File**: `frontend/client/src/components/enhanced-workflow-builder.tsx`
**Test ID**: `data-testid="workflow-status-{status}"` (dynamic)
**Element**: `<Badge>` component
**Purpose**: Playwright can wait for workflow completion

```tsx
<Badge
  variant={workflowStatus === 'running' ? 'default' : 'secondary'}
  data-testid={`workflow-status-${workflowStatus}`}
>
  {workflowStatus}
</Badge>
```

**Possible Status Values**:
- `workflow-status-idle` - Workflow not started
- `workflow-status-running` - Workflow executing
- `workflow-status-paused` - Workflow paused
- `workflow-status-completed` - Workflow finished successfully
- (Additional states: `error`, `cancelled` may also appear)

---

## New Component Created

### ChatInput Component
**File**: `frontend/client/src/components/chat-input.tsx`
**Reason**: Component was imported but didn't exist
**Features**:
- Auto-resizing textarea (60px-200px)
- Enter to send, Shift+Enter for newline
- Disabled state support
- Test IDs for input and send button

---

## Files Modified

1. **frontend/client/src/components/chat-input.tsx** (NEW - 78 lines)
   - Created complete chat input component with test IDs

2. **frontend/client/src/components/chat-message.tsx**
   - Added workflow detection logic (line 38-39)
   - Added `data-testid` to message wrapper (line 42-44)
   - Changed button label: "Create Workflow" → "View Workflow" (line 105)
   - Changed test ID: `button-create-workflow` → `button-view-workflow` (line 102)

3. **frontend/client/src/components/enhanced-workflow-builder.tsx**
   - Changed button label: "Start Workflow" → "Execute Workflow" (line 584)
   - Changed test ID: `button-workflow-start` → `button-execute-workflow` (line 581)
   - Added `data-testid` to status badge (line 527)

4. **backend/tests/e2e_ui/MISSING_TEST_IDS.md** (NEW - 154 lines)
   - Documentation of what was missing and why

---

## Testing Usage

### Example Playwright Test Selectors

```python
# 1. Type a query
page.locator('[data-testid="chat-input"]').fill("Analyze DIA LC-MS proteomics data")

# 2. Send the message
page.locator('[data-testid="chat-send-button"]').click()

# 3. Wait for workflow generation
page.wait_for_selector('[data-testid="workflow-generated-message"]', timeout=15000)

# 4. Click to view workflow
page.locator('[data-testid="button-view-workflow"]').click()

# 5. Click to execute workflow
page.locator('[data-testid="button-execute-workflow"]').click()

# 6. Wait for workflow completion
page.wait_for_selector('[data-testid="workflow-status-completed"]', timeout=600000)
```

---

## Alternative Selectors (Fallback)

If test IDs are removed in the future, tests can use CSS selectors:

```python
# Chat input (textarea by placeholder)
page.locator('textarea[placeholder*="Type your message"]')

# Send button (button with Send icon)
page.locator('button:has(svg):has-text("")').filter(has=page.locator('svg.lucide-send'))

# Workflow message (text contains "workflow")
page.locator('.chat-message:has-text("workflow")')

# View workflow button (button with text)
page.locator('button:has-text("View Workflow")')

# Execute button (button with Play icon and text)
page.locator('button:has-text("Execute Workflow")')

# Status badge (badge with status text)
page.locator('.badge:has-text("completed")')
```

---

## Next Steps

1. ✅ Test IDs added - COMPLETE
2. ⏳ **Create expected_parameters.json** - Define expected parameter values for all 10 test cases
3. ⏳ **Implement test cases** - Write 10 Playwright tests (test_01_dia_lcms.py through test_10_spatial_tx.py)
4. ⏳ **Execute tests** - Run full test suite with visual browser
5. ⏳ **Generate reports** - Create HTML report with screenshots and validation results

---

## Commit

**Branch**: `frontend_stronger`
**Commit**: `14593ba`
**Message**: "Frontend: Add missing test IDs for E2E automation"

---

## Related Documentation

- **Test Plan**: `backend/E2E_TEST_PLAN_WITH_PARAMETER_VALIDATION_2025-10-14.md`
- **Test Framework**: `backend/tests/e2e_ui/conftest.py`
- **Screenshot Manager**: `backend/tests/e2e_ui/utilities/screenshot_manager.py`
- **Parameter Validator**: `backend/tests/e2e_ui/utilities/parameter_validator.py`
- **Architecture**: `backend/PARAMETER_PREVIEW_ARCHITECTURE_2025-10-14.md`

---

**Status**: Frontend is ready for E2E test implementation ✅
