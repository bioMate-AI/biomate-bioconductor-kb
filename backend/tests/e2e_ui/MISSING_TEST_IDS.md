# Missing Test IDs for E2E Testing

**Status**: Needs implementation
**Purpose**: Add `data-testid` attributes to existing frontend components for Playwright automation

---

## ✅ Already Have (Good!)

From `chat-interface.tsx`:
- ✅ `data-testid="chat-messages"` - Chat scroll area (line 395)
- ✅ `data-testid="button-toggle-progress"` - Progress toggle (line 415)
- ✅ `data-testid="button-view-logs"` - View logs button (line 496)
- ✅ `data-testid="button-workflow-settings"` - Settings button (line 499)

---

## ❌ Missing (Need to Add)

### 1. Chat Input Field
**File**: `frontend/client/src/components/chat-interface.tsx` (or wherever ChatInput is defined)
**Component**: The actual `<input>` or `<textarea>` where user types
**Add**:
```tsx
<input
  data-testid="chat-input"
  // ... other props
/>
```
**Why**: Playwright needs to type the user query here

---

### 2. Send Button
**File**: Same as chat input
**Component**: Button to submit the chat message
**Add**:
```tsx
<button
  data-testid="chat-send-button"
  // ... other props
>
  Send
</button>
```
**Why**: Playwright needs to click this to send the query

---

### 3. Workflow Generated Indicator
**File**: `frontend/client/src/components/chat-message.tsx`
**Component**: The chat message that contains workflow info
**Add**:
```tsx
<div
  data-testid="workflow-generated-message"
  // ... other props
>
  {/* Workflow details */}
</div>
```
**Why**: Playwright needs to detect when workflow generation is complete

---

### 4. View Workflow Button
**File**: Likely in `chat-message.tsx` or similar
**Component**: Button that opens workflow in builder
**Add**:
```tsx
<button
  data-testid="button-view-workflow"
  onClick={() => onWorkflowGenerated(workflow)}
  // ... other props
>
  View Workflow
</button>
```
**Why**: Playwright needs to click this to navigate to workflow builder

---

### 5. Execute Workflow Button
**File**: `frontend/client/src/components/enhanced-workflow-builder.tsx` or `workflow-graph.tsx`
**Component**: Button to start workflow execution
**Add**:
```tsx
<button
  data-testid="button-execute-workflow"
  // ... other props
>
  Execute Workflow
</button>
```
**Why**: Playwright needs to click this to start execution

---

### 6. Workflow Status Indicator
**File**: Workflow builder or execution component
**Component**: Element showing workflow execution status
**Add**:
```tsx
<div
  data-testid={`workflow-status-${status}`}  // e.g., "workflow-status-completed"
  // ... other props
>
  Status: {status}
</div>
```
**Why**: Playwright needs to wait for `workflow-status-completed`

---

## 📋 Quick Add Checklist

1. [ ] Find ChatInput component and add `data-testid="chat-input"` to input field
2. [ ] Add `data-testid="chat-send-button"` to send button
3. [ ] Add `data-testid="workflow-generated-message"` to workflow chat message
4. [ ] Add `data-testid="button-view-workflow"` to view workflow button
5. [ ] Add `data-testid="button-execute-workflow"` to execute button
6. [ ] Add `data-testid="workflow-status-{status}"` to status indicator

---

## Alternative: Use CSS Selectors (Fallback)

If you don't want to add test IDs immediately, tests can use CSS selectors:

```python
# Instead of:
page.locator('[data-testid="chat-input"]')

# Can use:
page.locator('textarea[placeholder*="Type your message"]')
page.locator('button:has-text("Send")')
page.locator('button:has-text("View Workflow")')
```

**But test IDs are better because:**
- More stable (won't break if text changes)
- Faster (direct attribute selector)
- Clearer intent (shows this element is for testing)

---

## Summary

**Total Test IDs Needed**: 6
**Estimated Time**: 10-15 minutes to add all
**Files to Modify**: 2-3 components (ChatInput, ChatMessage, WorkflowBuilder)

Once these are added, Playwright tests can fully automate the user journey!
