# Chat-Stream Content Persistence Gap

**Date:** 2026-05-29
**Status:** Documented, not patched — requires design decision
**Severity:** Medium (real user impact)
**Discovered during:** HT-1 E2E smoke run (assistant message persisted with empty `content`)

## Symptom

After a successful chat turn, the assistant message in `chat_sessions.messages` is `{role:"assistant", content:""}`. The user sees their query but the AI response is lost from the persisted session — they can't refresh the page, switch devices, or resume from sidebar history.

Reproduced on HT-1 (2026-05-29 ~05:45 UTC):
- POST `/api/sessions` 201 → `chat-1780033490270-8ozqzx6b8`
- POST `/api/chat/stream` → SSE deltas flow to browser
- Test exited at 120 s timeout before stream completed
- `/api/sessions/chat-1780033490270-8ozqzx6b8` → assistant message content `""` permanently

## Root cause

The chat response flow is **client-mediated persistence**:

1. `frontend/server/routes.ts:4824` — `POST /api/chat/stream` writes SSE deltas to the response body via `res.write("event: delta\ndata: {...}\n\n")`
2. `frontend/client/src/components/chat-interface.tsx:667` — `fetch('/api/chat/stream')`; the React component reads the SSE stream and appends deltas to local state
3. On stream completion (`event: complete`), the component POSTs the accumulated `content` back to `/api/sessions/{id}` to persist
4. The server never sees the accumulated content — it only proxies the deltas

If the client disconnects mid-stream (closed tab, network blip, Playwright timeout), step 3 never fires and the content is lost permanently. The server has no record of what it streamed.

## Why this design

Originally chosen to keep the streaming hot path stateless and let the LLM provider's stream act as the single source of truth. Reasonable for low-stakes chat; problematic for scientific workflow conversations users expect to resume.

## Fix options

### Option A — Server-side accumulation (recommended)

`/api/chat/stream` accumulates the streamed deltas server-side and writes the final assistant message to `chat_sessions.messages` in the SSE `complete` handler (and on socket close / abort if partial content exists).

- **Pros:** Authoritative server-side record; survives client disconnect; simpler client (no persistence POST needed)
- **Cons:** Risk of duplicate persistence if client ALSO POSTs — must be coordinated (deprecate client POST, or make it idempotent via `message_index`)
- **Cost:** ~30-50 lines server-side; client-side change to drop the POST after stream complete
- **Race risk:** Manageable; well-known pattern (Anthropic Console, OpenAI playground, Replit AI all use server-mediated persistence)

### Option B — Client persistence on every delta (rejected)

POST the accumulated content to `/api/sessions/{id}` after each delta.

- **Pros:** Minimal server change
- **Cons:** ~10× write amplification (one PG write per token); race conditions if streams overlap; doesn't fix the disconnect case (final delta may not POST)
- **Verdict:** Don't.

### Option C — Stream into chat_sessions.messages incrementally via append-only (alternative)

Server appends each delta to a streaming-content JSONB array column; finalize on `complete`.

- **Pros:** No risk of losing partial content if server crashes mid-stream
- **Cons:** Heavy PG write load; complex schema; recovery semantics for orphan streams unclear
- **Verdict:** Over-engineered for the observed problem.

## Recommendation

**Adopt Option A.** Implementation plan:

1. In `routes.ts:4824` `/api/chat/stream`:
   - Initialize `let accumulated = ""` and `let workflowMetadata = null` at start
   - Inside `safeSend('delta', ...)` callers, also push to `accumulated`
   - On `event: complete`: write `{role:"assistant", content: accumulated, workflowMetadata}` to `chat_sessions.messages` via `pool.query(... messages = messages || $1 ...)`
   - On `req.socket.on('close')`: if `accumulated.length > 0`, persist with a `partial: true` flag

2. In `chat-interface.tsx:667`:
   - Remove the POST-to-sessions-on-complete branch (server now handles it)
   - Keep the local React state append for live UI updates

3. Migration 0012: add `partial BOOLEAN` to message JSON schema; document in `frontend/shared/schema.ts`

4. Regression test: `e2e/chat-disconnect-persistence.e2e.ts` — fire `/api/chat/stream`, abort connection after 2 s, verify message is persisted with `partial:true` and non-empty `content`

5. Backfill: existing empty-content assistant rows stay empty (no recovery path); document this in release notes

**Estimated effort:** 4-6 hr for code + migration + 1 regression test. Larger if existing chat-interface.tsx logic for workflow-card-after-message extraction needs reworking.

## Related fixes already applied

- **2026-05-29 / migration 0011** — `ConversationStateManager` was hitting the LTM `sessions` UUID column with TEXT chat IDs. Migration 0011 + conversation-state.ts now persists state on `chat_sessions.conversation_state`. That fix is orthogonal to this one (state ≠ message content), but it surfaced during the same HT-1 debug session.

## References

- `frontend/server/routes.ts:4824-4900` — current /api/chat/stream handler
- `frontend/client/src/components/chat-interface.tsx:667` — client fetch + SSE consumer
- `frontend/server/routes.ts:11602-11646` — chat_sessions CRUD raw SQL
- HT-1 audit: `frontend/e2e/screenshots/hts-ux/audit_1780033681991.json` (finalStatus: "skip_no_response")
- Node log corroboration: `[ConversationState] Failed to save state` + `[SSE] No clients for invocation ...` patterns in `/tmp/biomate-frontend-dev.log`
