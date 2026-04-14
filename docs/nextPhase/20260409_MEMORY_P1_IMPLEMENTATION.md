# Memory P1 Implementation — 2026-04-09

## Summary

Implemented the two highest-priority memory improvements identified in the Claude Code memory analysis. BioMate's SessionMemory was previously lost on every server restart; `processWithMemory()` existed but was never called. Both are now active.

---

## Fix 1: SessionMemory Persistence

### Problem
`SessionMemoryUpdater._update()` (galaxy-assistant.ts:807) wrote Haiku-extracted session context (active_task, key_decisions, uploaded_files, etc.) only to an in-memory `Map`. Server restart or new gunicorn worker → complete session context loss.

### Root Cause
No DB write path existed. The 30-second debounced Haiku call had nowhere to persist its output.

### Solution

**`conversation-state.ts`**
- Added `sessionMemory?: Record<string, any>` field to `ConversationState` interface — piggybacks on the existing `conversationState JSONB` column that is already persisted every turn
- Added `saveSessionMemory(sessionId, memory)` to `ConversationStateManager`: load-modify-save pattern (read current state, merge sessionMemory in, write back)

**`galaxy-assistant.ts` — `SessionMemoryUpdater`**
- Added `private onPersist?` callback field
- Added `setPersistCallback(cb)` — wires the DB write path from outside (avoids circular dep)
- Added `restoreIfEmpty(sessionId, memory)` — seeds in-memory map from DB snapshot on session resume, no-op if session already in memory
- `_update()` now calls `onPersist?.(sessionId, updated)` after each successful Haiku summary (non-blocking)

**`galaxy-assistant.ts` — `GalaxyAssistant` constructor**
```typescript
this.sessionMemory.setPersistCallback((sid, mem) => {
  conversationStateManager.saveSessionMemory(sid, mem as any).catch(
    (err) => console.warn('[GalaxyAssistant] SessionMemory DB persist failed (non-fatal):', err)
  );
});
```

**`galaxy-assistant.ts` — `processMessage()`**
After `loadState()`:
```typescript
this.sessionMemory.restoreIfEmpty(context.sessionId || 'anon', conversationState.sessionMemory);
```
→ On server restart, session memory is recovered from the DB snapshot taken at last 30s checkpoint.

### Effect
Session context (active_task, decisions, files, workflows, parameters) now survives:
- Server restarts
- gunicorn worker scaling (new workers pick up context from DB)
- 24h idle eviction (in-memory eviction no longer causes permanent context loss)

---

## Fix 2: Wire processWithMemory() into Main Request Path

### Problem
`MemoryIntegration.processWithMemory()` (memory-integration.ts:103) was fully implemented — it loads user preferences, past corrections, similar episodes, and injects them as memory hints into the assistant context. But `routes.ts` was calling `galaxyAssistant.processMessage()` directly, bypassing the memory layer entirely.

Additionally, `processWithMemory()` had no streaming callback parameters, making it impossible to wire at the SSE endpoint.

### Solution

**`memory-integration.ts`**
- Added `onChunk?: (chunk: string) => void` and `onToolEvent?: (event: any) => void` params to `processWithMemory()`
- Passed them through to `this.assistant.processMessage()` at Step 5

**`routes.ts` — chat stream handler (line ~3266)**
- Added `userId: req.user ? Number(req.user.id) : context?.userId` to `enrichedContext` — ensures `enhanceContextWithMemory()` can load user context even when the frontend doesn't send userId
- Replaced direct `galaxyAssistant.processMessage()` with:

```typescript
const assistantResponse = memoryIntegration
  ? await memoryIntegration.processWithMemory(
      String(message),
      enrichedContext as any,
      (chunk) => safeSend("delta", { text: chunk }),
      (event) => safeSend("tool_event", event)
    )
  : await galaxyAssistant.processMessage(
      String(message),
      enrichedContext,
      (chunk) => safeSend("delta", { text: chunk }),
      (event) => safeSend("tool_event", event)
    );
```

### What Now Activates Per Request
1. **User context loading** — loads user preferences (tool preferences, organism preferences, confidence ≥ 0.5) and recent corrections from the LTM database
2. **Memory hints injection** — matching procedures and similar past episodes are prepended as context hints in `previousMessages`
3. **Project knowledge** — loaded if `projectId` is set in the context
4. **Episode recording** — if `memorySessionId` and `projectId` are both present, the interaction is recorded as an episode for future retrieval
5. **Learning** — user tool preferences updated from each interaction

---

## Test Fixes (UX-7b, UX-7c, UX-9a)

Three E2E test bugs fixed in the same session:

| Test | Bug | Fix |
|------|-----|-----|
| UX-7b | `CSS.escape(labelFor)` crashes in Node.js — `CSS` is a browser global | Replaced with inline `cssEscape()` regex function |
| UX-7c | `fill("999")` on React controlled input resets to prop value | Added Override button click flow: `param-override-btn-max_spots` → inline edit Input → Enter |
| UX-9a | Survey modal dismissed AFTER `waitForWorkflowCard`, potentially blocking card | Moved survey dismiss to immediately after `waitForAIResponse` |

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/server/conversation-state.ts` | +`sessionMemory` field; +`saveSessionMemory()` |
| `frontend/server/galaxy-assistant.ts` | +`onPersist`, `setPersistCallback()`, `restoreIfEmpty()`; wired in constructor + processMessage() |
| `frontend/server/memory-integration.ts` | +streaming callbacks to `processWithMemory()` |
| `frontend/server/routes.ts` | Switch to `memoryIntegration.processWithMemory()`; inject `userId` |
| `frontend/e2e/ux-param-autofill.e2e.ts` | Fix `CSS.escape` (UX-7b + UX-7c); Override button flow (UX-7c) |
| `frontend/e2e/ux-execution-triage.e2e.ts` | Move survey dismiss before `waitForWorkflowCard` (UX-9a) |

---

## Remaining P1/P2 Items (From Memory Analysis)

| Priority | Item | Status |
|----------|------|--------|
| P1 | SessionMemory persistence | ✅ Done |
| P1 | Wire processWithMemory() | ✅ Done |
| P1 | LTM episode/procedure search is keyword-only | ❌ Not yet — needs pgvector |
| P2 | Cross-session workflow learning injection | ❌ Not yet — needs episodic DB rows |
| P2 | Memory UI panel (sidebar showing active_task, decisions) | ❌ Not yet |
| P3 | Chunk-based knowledge injection with token budget | ❌ Not yet |
