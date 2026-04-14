# BioMate: Optimization Gaps vs Claude Code Design

**Date:** 2026-04-01  
**Based on:** Deep audit of 7 existing BioMate subsystems vs Claude Code v2.1.88  
**Scope:** Existing implementations only — not missing features

This document focuses on *how* BioMate's existing implementations differ from Claude Code's design in ways that cause concrete runtime problems. Each section names the problem, the relevant code location, and the specific fix.

---

## 1. Agent Loop — Single-Turn vs Agentic Loop

### Current: `routes.ts:2983`
```typescript
assistantResponse = await galaxyAssistant.processMessage(message, enrichedContext);
```

One shot. `processMessage()` returns once and the turn is over. If the LLM internally wants to chain tool calls (search → disambiguate → refine), each of those steps is stateless relative to each other. There is no loop feeding tool results back into the LLM for the next reasoning step.

### The Problem
- Tool execution happens inside `processMessage()` as a side effect, not as a first-class step the LLM can reason about
- If a tool fails mid-turn, the LLM never learns about it — the error is swallowed in a catch block
- Multi-step analyses (e.g., search for tools → check prerequisites → adjust parameters → submit) require the user to send multiple messages, where Claude Code would handle them in one agentic turn

### Claude Code's Approach (`query.ts`)
```typescript
// Simplified version of the core loop
while (true) {
  const response = await claudeAPI.messages.create({ messages, tools, system })
  messages.push({ role: 'assistant', content: response.content })
  
  const toolUseBlocks = response.content.filter(b => b.type === 'tool_use')
  if (toolUseBlocks.length === 0) break  // LLM done
  
  const toolResults = await executeToolsInParallel(toolUseBlocks)
  // Tool errors are passed back to LLM as tool_result with is_error: true
  messages.push({ role: 'user', content: toolResults })
}
```

The LLM sees each tool result and decides whether to call more tools or stop. Errors are surfaced to the LLM for adaptive recovery.

### Fix for BioMate
Wrap `processMessage()` in an explicit loop in `routes.ts`. The LLM response is inspected for tool call blocks; if found, execute tools and loop back. This doesn't require a full rewrite — `galaxy-assistant.ts` can emit structured `{ type: 'tool_call', ... }` objects that `routes.ts` dispatches and feeds back.

**Effort:** Medium (2–3 weeks). Requires refactoring `galaxy-assistant.ts` to separate LLM call from tool dispatch, and adding the loop in `routes.ts`.

---

## 2. Context Compression — Lost Tool Call IDs

### Current: `context-compressor.ts:94–169`
```typescript
const oldMessages = messages.slice(0, -keepRecentCount)
const recentMessages = messages.slice(-keepRecentCount)
const summary = await this.generateSummary(oldMessages, maxSummaryTokens)
// summary is a plain text string — all tool call IDs are gone
const compressedMessages = [summaryMessage, ...recentMessages]
```

### The Problem
When `oldMessages` contains `tool_use` / `tool_result` blocks, the Anthropic API requires that every `tool_use` has a matching `tool_result` in the same message array. After compression, the `tool_use` blocks from old turns are gone, but any later `tool_result` blocks that reference them by ID are now orphaned — causing API errors or silent mismatches.

Additional issue: the token estimate is heuristic (`chars / 4`, line ~243) rather than using the actual `usage.input_tokens` returned by the Anthropic API. This means the 160k threshold check can be off by 20–30%.

### Claude Code's Approach
- Tool invocation IDs are preserved in the summary as metadata, not inline text
- Before calling the API, messages are scanned to ensure every `tool_use` ID has a corresponding `tool_result`; orphaned blocks are removed
- Token counts come from `response.usage.input_tokens` (actual), fed back into the budget tracker per turn

### Fix for BioMate

**Part A — orphan cleanup** (1 day):
```typescript
function sanitizeToolPairs(messages: Message[]): Message[] {
  const toolUseIds = new Set(
    messages.flatMap(m => 
      (m.content as ContentBlock[])
        .filter(b => b.type === 'tool_use')
        .map(b => (b as ToolUseBlock).id)
    )
  )
  return messages.map(m => ({
    ...m,
    content: Array.isArray(m.content)
      ? m.content.filter(b => 
          b.type !== 'tool_result' || toolUseIds.has((b as ToolResultBlock).tool_use_id)
        )
      : m.content
  }))
}
```
Call this in `context-compressor.ts` after slicing old messages.

**Part B — real token tracking** (2 days):
Capture `response.usage` from every Anthropic API call in `galaxy-assistant.ts` and pass the running `inputTokens` total to `ContextCompressor.shouldCompress()` instead of re-estimating from string length.

**Effort:** Low (3–4 days total).

---

## 3. Parallel Execution — No Timeout, No Retry, Partial Failure Handling

### Current: `domain_specialist.py:122–146`
```python
with ThreadPoolExecutor(max_workers=min(len(domains), self.max_workers)) as executor:
    futures = {
        executor.submit(self._consult_single, query, domain): domain
        for domain in domains
    }
    for future in as_completed(futures):
        try:
            results[domain] = future.result()  # blocks indefinitely
        except Exception as e:
            results[domain] = DomainRecommendation(domain=domain, error=str(e))
```

### The Problems
1. `future.result()` has no timeout — a slow LLM call or Galaxy API hang stalls the entire batch
2. No retry on transient errors (rate limits, 5xx from Galaxy)
3. `as_completed()` with no timeout means the executor context can hold threads for 30+ seconds if one specialist is slow
4. `max_workers=3` (line 102) is a hardcoded constant — no configuration, no dynamic adjustment based on load

### Claude Code's Approach
- Each tool call has an explicit timeout (default 30s)
- `asyncio.wait_for()` wraps every call; `TimeoutError` is treated as a retriable error
- Exponential backoff: first retry after 1s, then 2s, then 4s (max 3 retries)
- Concurrency limit is a configurable semaphore, not a ThreadPoolExecutor cap

### Fix for BioMate (`domain_specialist.py`)
```python
import asyncio
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8))
async def _consult_single_with_retry(self, query, domain, timeout=25):
    return await asyncio.wait_for(
        self._consult_single_async(query, domain),
        timeout=timeout
    )

async def consult_specialists(self, query, domains):
    semaphore = asyncio.Semaphore(self.max_workers)
    async def bounded_consult(domain):
        async with semaphore:
            try:
                return domain, await self._consult_single_with_retry(query, domain)
            except Exception as e:
                return domain, DomainRecommendation(domain=domain, error=str(e), confidence=0.0)
    
    results = await asyncio.gather(*[bounded_consult(d) for d in domains])
    return dict(results)
```

`tenacity` is already a common Python dependency; `asyncio` is in stdlib. No new packages needed.

**Effort:** Low (2 days). Drop-in replacement for the ThreadPoolExecutor block.

---

## 4. Session Persistence — Already Fully Implemented

**This item was incorrect and has been retracted.**

BioMate has a production-grade PostgreSQL persistence layer via Drizzle ORM. `MemStorage` (`storage.ts:68`) handles only workflow execution tracking (`ExecutionRun`, `WorkflowInvocation`) — it is not the chat persistence layer.

Chat messages are persisted to the `conversation_messages` table (`frontend/shared/ltm-schema.ts:159–184`) on every turn via `SessionMemoryRepository.addMessage()` (`memory-repository.ts:445–463`). The schema includes role, content, tool_use records, thinking content, and token counts. Conversation state (facts, intent history, task arcs) is persisted to the `sessions` table via `ConversationStateManager.saveState()` (`conversation-state.ts:287–325`). Complete interaction episodes are stored in `project_episodes`. All writes go to PostgreSQL via `DATABASE_URL`.

---

## 6. SSE Streaming — No Backpressure, No Disconnect Handling

### Current: `routes.ts:3498–3515`
```typescript
res.setHeader("Content-Type", "text/event-stream")
res.flushHeaders?.()

const assistantResponse = await galaxyAssistant.processMessage(
  String(message),
  enrichedContext,
  (chunk) => sendEvent("delta", { text: chunk })  // fire-and-forget write
)
```

### The Problems
1. `res.write()` is called with no check on return value. If the client disconnects, Node.js buffers writes internally. When the buffer fills, `res.write()` silently drops events or throws — depending on Node.js version.
2. There is no `res.on('close', ...)` handler. The LLM keeps generating tokens and `processMessage()` keeps running even after the client has gone away. This burns tokens and holds a slot in the concurrency pool.
3. No heartbeat. If the LLM takes >15s without emitting a token (e.g., thinking with extended budget), proxies and load balancers close the connection.
4. Tool execution progress is not streamed. The user sees nothing during a 30-second Nextflow prereq check.

### Claude Code's Approach
- Registers a `close` handler immediately; any pending async work is cancelled via `AbortController`
- Heartbeat event every 10s when no other events are sent
- Separate event types: `delta` (text), `tool_start`, `tool_end`, `state_update`, `error`, `done`
- `res.write()` return value checked; if `false`, awaits the `drain` event before continuing

### Fix for BioMate

```typescript
// routes.ts — /api/chat/stream
const abortController = new AbortController()
res.on('close', () => abortController.abort())

let heartbeatTimer = setInterval(() => {
  if (!res.writableEnded) res.write(': heartbeat\n\n')
}, 10_000)

const safeSend = (event: string, data: unknown): boolean => {
  if (res.writableEnded || abortController.signal.aborted) return false
  const ok = res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)
  // if ok===false, the write was buffered; for text deltas this is fine
  // for large tool results, we should await 'drain' — add that when tool streaming lands
  return ok
}

try {
  const assistantResponse = await galaxyAssistant.processMessage(
    String(message), enrichedContext,
    (chunk) => safeSend('delta', { text: chunk }),
    abortController.signal  // pass to processMessage so it can abort LLM call
  )
  // ...
} finally {
  clearInterval(heartbeatTimer)
  safeSend('done', { ok: true })
}
```

Pass `abortController.signal` into `galaxy-assistant.ts` and forward it to the Anthropic SDK call via `signal` option.

**Effort:** Low (1–2 days). The changes are localized to the SSE handler in routes.ts and a small change in galaxy-assistant.ts to accept the signal.

---

## 7. Pre-execution Validation — No Schema Cache, No Timeout

### Current: `workflow-prerequisites-validator.ts:96–97, 425–432`
```typescript
// Called on every validate() invocation — no cache
const toolDocs = await this.getToolDocumentation(requirements)  // fetches from Galaxy API
const analysis = await this.claude.messages.create({ ... })     // no timeout
```

### The Problems
1. `getToolDocumentation()` calls `galaxyAPI.getToolSchema()` for each tool in the workflow — typically 3–8 calls per validation. No TTL cache. Re-validating after fixing one parameter re-fetches all schemas.
2. `this.claude.messages.create()` has no `signal` / timeout. If the Anthropic API is slow (extended thinking budget active), validation hangs.
3. Validation result is `fulfilled: boolean` — a soft flag. Nothing prevents the workflow submission if `fulfilled === false`. Enforcement has to be re-implemented at every call site.

### Claude Code's Approach
- Tool schemas cached in memory with 1-hour TTL; populated eagerly at startup for known tools
- All LLM calls accept an `AbortSignal` with a 15s timeout; on timeout, falls back to rule-based validation (no LLM)
- Validation result is enforced at the API route level: if `fulfilled === false` and no override token, the route returns `403`

### Fix for BioMate

**Schema cache** (1 day):
```typescript
// workflow-prerequisites-validator.ts
private schemaCache = new Map<string, { schema: ToolSchema; fetchedAt: number }>()
private SCHEMA_TTL = 60 * 60 * 1000  // 1 hour

async getToolSchema(toolId: string): Promise<ToolSchema> {
  const cached = this.schemaCache.get(toolId)
  if (cached && Date.now() - cached.fetchedAt < this.SCHEMA_TTL) return cached.schema
  const schema = await this.galaxyAPI.getToolSchema(toolId)
  this.schemaCache.set(toolId, { schema, fetchedAt: Date.now() })
  return schema
}
```

**LLM timeout** (30 min):
```typescript
const controller = new AbortController()
const timeout = setTimeout(() => controller.abort(), 15_000)
try {
  const analysis = await this.claude.messages.create({ ... }, { signal: controller.signal })
} catch (e) {
  if (e.name === 'AbortError') return this.ruleBasedFallback(requirements, available)
  throw e
} finally {
  clearTimeout(timeout)
}
```

**Route-level enforcement** (1 hour): In `routes.ts`, after calling `validate()`, check `result.fulfilled` before allowing workflow submission. Return a structured error with `result.conversationalResponse` as the user-facing message.

**Effort:** Low (2 days total).

---

## Priority Summary

| Area | Severity | Effort | Fix |
|---|---|---|---|
| SSE disconnect + backpressure | High — can cause token waste + crashed requests | Low (1–2 days) | `AbortController` + `close` handler + heartbeat |
| Context compression orphan tool IDs | High — causes API errors on long sessions | Low (1 day) | `sanitizeToolPairs()` before API call |
| Validation schema cache + timeout | Medium — slow re-validations + potential hangs | Low (2 days) | In-memory TTL cache + `AbortSignal` |
| Parallel execution timeout + retry | Medium — hangs on slow specialists | Low (2 days) | `asyncio.wait_for` + `tenacity` retry |
| Session persistence | **N/A — already implemented** | — | `conversation_messages` table exists in `ltm-schema.ts` |
| Agent loop (true agentic loop) | Low now, High for future agentic features | Medium (2–3 weeks) | Refactor to tool-call loop in routes.ts |

Recommended order: SSE fixes → context compression fix → validation cache → parallel timeout — all are localized changes to individual files, low risk, and high reliability payoff.

---

## Reference Files

| BioMate file | Key lines | Claude Code reference |
|---|---|---|
| `routes.ts` | 3479–3700 (SSE), 2983 (processMessage) | `src/query.ts` (agent loop) |
| `context-compressor.ts` | 94–169 (compression), 243 (token est.) | `src/services/compact/compact.ts` |
| `domain_specialist.py` | 113–146 (ThreadPoolExecutor) | `src/services/tools/StreamingToolExecutor.ts` |
| `agent_orchestrator.py` | 214–224 (assemble) | `src/tools/AgentTool/AgentTool.tsx` |
| `storage.ts` | 68–78 (MemStorage) | `~/.claude/sessions/*.jsonl` pattern |
| `workflow-prerequisites-validator.ts` | 96–97, 425–432 | `src/utils/permissions/permissions.ts` |
