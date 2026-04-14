# UX Recovery + Param Type E2E Fixes — 2026-04-09

## Status: 9/9 PASSING across 3 test files

| File | Tests | Status | Time |
|------|-------|--------|------|
| `ux-param-autofill.e2e.ts` | UX-7a/7b/7c | ✅ 3/3 | ~8–9.5m |
| `ux-param-types.e2e.ts` | UX-4/5/6 | ✅ 3/3 | ~2.5m |
| `ux-workflow-recovery.e2e.ts` | UX-10/11a/11b | ✅ 3/3 | ~1.9m |

---

## UX-10: "Continue in Chat" Pre-fill Fix

### Problem
The "Continue in chat →" button existed in the viewer's prereq checklist and correctly had `chatPrompt` set by the normalizer. But clicking it did nothing — the textarea stayed empty.

### Root Cause (2 issues)
1. **`onAdjustViaChat` not passed to `ChatMessage`** — `chat-interface.tsx` renders `<ChatMessage>` without `onAdjustViaChat` prop. So it was `undefined` in the component tree, the viewer checked `item.chatPrompt && onAdjustViaChat && (...)` and rendered nothing.

2. **`ChatInput` had no way to receive external text** — `ChatInput` owns its own `message` state with `useState("")`. There was no prop to pre-fill from outside.

### Fix

**`client/src/components/chat-input.tsx`**:
- Added `externalDraft?: string` prop
- Added `useEffect(() => { if (externalDraft) { setMessage(externalDraft); textareaRef.current?.focus(); } }, [externalDraft])`

**`client/src/components/chat-interface.tsx`**:
- Added `const [chatDraft, setChatDraft] = useState<string | undefined>(undefined)`
- Added `onAdjustViaChat={(msg) => msg && setChatDraft(msg)}` to `<ChatMessage>`
- Added `externalDraft={chatDraft}` to `<ChatInput>`
- `onSend` clears the draft: `onSend={(msg, files) => { setChatDraft(undefined); handleSendOrQueue(msg, files); }}`

### Test result
```
[UX-10] Chat-link button found via selector: [data-testid^="prereq-chat-link"]
[UX-10] Textarea value after chat-link click: "I need to provide the input data for this workflow. Here is the file I want to use: "
```

---

## UX-4/5/6: Param Type Tests — Timeout Fix

### Problem
UX-5 and UX-6 timed out at 3 minutes (then 6 minutes). Test ran `waitForWorkflowCard` successfully but then hung in the accordion loop.

### Root Cause: Live locator + `nth(i)` = infinite hang
```typescript
// BUG: closedAccordions is a live locator
const closedCount = await closedAccordions.count(); // = 5
for (let i = 0; i < closedCount; i++) {
  await closedAccordions.nth(i).click(); // after 3 opens, nth(3) waits forever
}
```
After each accordion click, it opens and leaves the "closed" list. `nth(3)` on a live locator of 2 remaining elements waits indefinitely for a 4th element to appear. Playwright never throws — it just polls forever.

### Fix: Always click `first()`
```typescript
const closedCount = await closedAccordions.count();
for (let i = 0; i < closedCount; i++) {
  await closedAccordions.first().click({ force: true }).catch(() => {});
  await page.waitForTimeout(100);
}
```

### Additional fixes
- `test.setTimeout(180000)` → `360000` (AI response + card wait can take 50s combined; old 3min wasn't enough)
- Vague queries (`"Run germline variant calling for a human WGS sample"`) → specific (`"Run WGS germline variant calling for SRR1518169 using GATK, genome GRCh38, max_spots=100"`) to avoid clarification round-trip
- `click()` → `click({ force: true })` on accordion triggers (some may be above viewport)

---

## Key Learnings

1. **Live locator + `nth(i)` on shrinking list = silent infinite hang**: Always click `first()` when the list shrinks after each click (accordions, tabs, etc.).

2. **`ChatInput` state isolation**: Any component that owns its own `useState` needs an explicit prop + `useEffect` to accept imperative external pre-fills. Don't use DOM manipulation — use React's state system.

3. **`onAdjustViaChat` prop chain must be complete**: If any intermediate component in the chain (`chat-interface` → `chat-message` → `nextflow-workflow-viewer`) omits the prop, the button renders as nothing (the viewer guards with `onAdjustViaChat &&`).
