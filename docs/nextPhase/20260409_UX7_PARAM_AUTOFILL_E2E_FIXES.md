# UX-7 Param Autofill E2E Fixes — 2026-04-09

## Status: 3/3 PASSING

Tests: `e2e/ux-param-autofill.e2e.ts`

| Test | Status | Time |
|------|--------|------|
| UX-7a: AI pre-fills genome reference S3 path | ✅ PASS | ~2.8m |
| UX-7b: AI badge visible on pre-filled params | ✅ PASS | ~3.9m |
| UX-7c: Researcher can override AI-filled param | ✅ PASS | ~2.8m |

Full suite: 3/3 passed in ~7.9–9.5m.

---

## Root Causes Fixed

### 1. `FlaskConical` removed from imports but still used (critical)

**File**: `client/src/components/nextflow-workflow-viewer.tsx`

When the "when to use / when not to use" scientific rationale panel was removed, `Lightbulb` was correctly removed from the lucide-react import. But `FlaskConical` was accidentally removed too, even though it's still used at line ~1492 for the "Download Methods Report" button.

At runtime, `undefined` as a JSX component crashes React's render silently — no error in console, but the entire workflow card never mounts. ALL 3 tests showed "Workflow card appeared: false" until this was fixed.

**Fix**: Restored `FlaskConical` in the import line.

### 2. `<html>` intercepts pointer events on Override button

**Error**: `TimeoutError: locator.click: Timeout 60000ms exceeded. <html lang="en"> intercepts pointer events`

**Cause**: The Override button (`data-testid="param-override-btn-max_spots"`) is positioned above the viewport when the accordion is expanded — the workflow panel content renders in a scrollable chat area. Playwright's coordinate-based click fails when the element's coordinates resolve to off-screen.

**Fix**: Use `locator.dispatchEvent('click')` which dispatches directly on the DOM element, bypassing coordinate resolution.

```typescript
await overrideBtnForMaxSpots.dispatchEvent('click');
```

### 3. Inline edit value not committing to main input

**Root cause**: `commitEdit()` is a React handler wired via `onKeyDown`. React 18 uses event delegation — synthetic event handlers are registered at the root container, not on individual elements. A `KeyboardEvent` created and dispatched from `page.evaluate()` goes through the DOM bubbling phase but does NOT reach React's synthetic event system, so `onKeyDown` → `commitEdit()` never fires.

**Fix strategy**: 
- Added `data-testid="param-confirm-btn-{param.id}"` to the green check confirm button in `parameter-group.tsx`
- In evaluate: set DOM value via `HTMLInputElement.prototype.value` native setter + dispatch `input` event (updates React's `editValue` state)
- Then `dispatchEvent('click')` on the confirm button → React's `onClick={commitEdit}` fires → `commitEdit()` reads `inputRef.current.value` = "999" → calls `onChange('max_spots', 999)` → parent state updates → controlled `<Input value={param.value}>` re-renders with "999"

```typescript
// Set value via nativeSetter
await page.evaluate(() => {
  const input = document.querySelector('[data-testid="param-inline-edit-max_spots"]') as HTMLInputElement;
  const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
  nativeSetter?.call(input, '999');
  input.dispatchEvent(new Event('input', { bubbles: true }));
});
// Click confirm button (bypasses coordinate interception)
await page.locator('[data-testid="param-confirm-btn-max_spots"]').dispatchEvent('click');
```

### 4. Server running stale code (AMBIGUITY_RESOLVERS missing)

The `galaxy-assistant.ts` was modified with AMBIGUITY_RESOLVERS after the frontend server started. The server served old code causing non-deterministic clarification responses instead of routing directly to the workflow.

**Fix**: Kill and restart the server after any backend TypeScript changes:
```bash
kill <server_pid> && USE_POLLING=true npx tsx server/index.ts &
```

---

## Scientific Rationale Panel Removal

Per user requirement: "not shown at UX but used by biomate at the backend!"

**Files changed**:

1. **`nextflow-workflow-viewer.tsx`**: Removed entire block (~90 lines) for `when_to_use`, `do_not_use_when`, `data_requirements`, `common_pitfalls`, `parameter_hints` sections.

2. **`chat-message.tsx`**: Removed `WorkflowRationale` import and render block:
   ```tsx
   // REMOVED:
   {isWorkflowMessage && message.metadata?.rationale && (
     <WorkflowRationale rationale={message.metadata.rationale} />
   )}
   ```

The rationale data is still computed and stored in backend; it's used for AI parameter filling logic but not displayed to users.

---

## AMBIGUITY_RESOLVERS Map (galaxy-assistant.ts)

Replaced ad-hoc per-case if-conditions with a generalizable map:

```typescript
const AMBIGUITY_RESOLVERS: Record<string, RegExp> = {
  'which_samples': /srr\d+|sample|accession|data/i,
  'which_genome': /grch|hg\d+|mm\d+|genome|reference/i,
  // ... 12 more entries
};
// In _clarificationGate():
if (AMBIGUITY_RESOLVERS[ambiguity]?.test(message)) { ambiguity = null; }
```

This suppresses LLM-driven clarification prompts when the user message already contains sufficient information.

---

## Key Learnings

1. **Never remove icon imports without grepping for all usages**: A silent React render crash from `undefined` component is very hard to debug.
2. **`dispatchEvent` vs `click()` for off-viewport elements**: `dispatchEvent('click')` triggers React's event delegation; coordinate-based `click()` fails for elements above viewport.
3. **React's event delegation prevents evaluate-dispatched keyboard events from triggering `onKeyDown`**: Always use the confirm/submit button click path for React form interactions in tests.
4. **data-testid on action buttons**: Adding `data-testid="param-confirm-btn-{id}"` and `param-cancel-btn-{id}` makes inline edit commit flow reliably testable.
