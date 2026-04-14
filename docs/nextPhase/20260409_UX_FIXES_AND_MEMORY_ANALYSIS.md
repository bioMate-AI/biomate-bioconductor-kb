# BioMate — UX Information Flow Fixes + Memory Architecture Analysis
**Date:** 2026-04-09  
**Branch:** integration/next-phase  
**Scope:** (1) UX information flow hardening; (2) Claude Code memory reverse-engineering; (3) BioMate memory gap analysis and improvement roadmap

---

## Part 1 — UX Information Flow Fixes

### Background

A systematic audit of all BioMate frontend information flows revealed seven categories where the system had information but wasn't surfacing it to the researcher. "Silent failures" — where the user clicks something, nothing visible happens, and no error appears — are particularly damaging in a research setting because the user re-tries, gives up, or assumes success when the operation failed.

### Fixes Implemented

#### 1. SSE JSON Parse Crashes Kill All Subsequent Updates
**File:** `frontend/client/src/hooks/useUnifiedExecution.ts`  
**Root cause:** Three event listener callbacks (`workflow_state`, `step_state`, `progress_milestone`) all called `JSON.parse(event.data)` without try/catch. Any malformed SSE frame (server restart, partial flush, network corruption) throws an uncaught exception inside the event callback, which terminates the callback silently. Because EventSource handlers are registered once, **all subsequent events for that session stop being processed**. The workflow continues running on AWS Batch; the UI freezes at whatever step it was on.

**Real scenario:** A user runs a germline variant calling workflow. At minute 12, a network blip causes the backend to emit a partial SSE frame. The `JSON.parse` throws. The step status display freezes at "Step 3 / 8" — but the workflow actually completes at minute 45. The user sees a stalled UI and force-refreshes, losing their session context.

**Fix:** `try/catch` on every `JSON.parse`. On `workflow_state` parse failure, surface to `state.error` ("Received a malformed status update. Monitoring continues.") which triggers the red banner. On `step_state`/`progress_milestone` parse failures, log + return — the status updates are best-effort and polling provides backup.

```typescript
// BEFORE — crashes callback, freezes all future updates
eventSource.addEventListener('workflow_state', (event) => {
  const update = JSON.parse(event.data); // throws on malformed frame
  ...
});

// AFTER — isolated parse failure, monitoring continues
eventSource.addEventListener('workflow_state', (event) => {
  let update: any;
  try {
    update = JSON.parse(event.data);
  } catch (e) {
    console.error('[UnifiedExecution] Failed to parse workflow_state SSE message:', e);
    setState((prev) => ({ ...prev, error: 'Received a malformed status update. Monitoring continues.' }));
    return;
  }
  ...
});
```

---

#### 2. SSE Disconnect During Active Run — Invisible State Change
**File:** `frontend/client/src/components/chat-with-artifacts.tsx`  
**Root cause:** `isConnected` from `useUnifiedExecution` was used to show a green "Live" dot when connected. When SSE disconnected, the dot disappeared — but there was no alternate state shown. During an active run, the user had no way to know whether they were watching live events or whether monitoring had silently stopped.

**Real scenario:** A researcher runs a 2-hour drug discovery MD simulation. They leave the tab open. At minute 40, SSE disconnects (idle timeout). The green "Live" dot disappears. The user doesn't notice. For the next 80 minutes, they watch a frozen UI, not knowing if the workflow is still running.

**Fix:** When `!isConnected && isRunning`, show an amber pulsing "Reconnecting…" dot instead of the green dot disappearing to nothing.

```tsx
{isConnected ? (
  <div data-testid="connection-status-live">
    <div className="h-2 w-2 rounded-full bg-green-500 animate-pulse" />
    <span>Live</span>
  </div>
) : isRunning ? (
  <div data-testid="connection-status-reconnecting">
    <div className="h-2 w-2 rounded-full bg-amber-400 animate-pulse" />
    <span className="text-amber-600">Reconnecting…</span>
  </div>
) : null}
```

---

#### 3. Polling Failures Silently Continue
**File:** `frontend/client/src/hooks/useUnifiedExecution.ts`  
**Root cause:** Polling errors were caught and logged (`console.error`) but the counter was never tracked. After N failures, the user had no indication that status updates had stopped arriving. The UI showed the last known status indefinitely.

**Real scenario:** The backend restarts mid-run (gunicorn SIGHUP for a deployment). Polling to `/api/runs/{id}/status` starts returning 502. The user sees "Running — Step 3 of 8" for 10 minutes after the backend is actually back up, because the polling errors are silently retrying without escalating.

**Fix:** Track consecutive failures with `consecutivePollErrorsRef`. After 3, set `state.error` which flows to the existing red banner: "Status updates are temporarily unavailable. Your workflow may still be running."

```typescript
const consecutivePollErrorsRef = useRef<number>(0);
// In poll():
// on success:
consecutivePollErrorsRef.current = 0;
// on error:
consecutivePollErrorsRef.current += 1;
if (consecutivePollErrorsRef.current >= 3) {
  setState((prev) => ({
    ...prev,
    error: 'Status updates are temporarily unavailable. Your workflow may still be running.',
  }));
}
```

---

#### 4. Error Explanation Stuck "Analyzing…" Forever
**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`  
**Root cause:** `POST /api/workflows/explain_error` had no timeout. If the backend was slow, overloaded, or unreachable, the fetch would hang indefinitely. `errorExplaining` stays `true`, the UI shows "Analyzing error log…" forever. The researcher is left staring at a spinner instead of the raw error message or a fallback.

**Fix:** 30-second `AbortController` timeout. On abort/network error, set a fallback explanation instead of leaving the state empty:

```typescript
const abortController = new AbortController();
const explainTimeout = setTimeout(() => abortController.abort(), 30000);
fetch('/api/workflows/explain_error', { signal: abortController.signal, ... })
  .catch(() => {
    setErrorExplanation({
      human_summary: 'Error analysis timed out. Check the log output above for details.',
      suggested_fix: 'Review the error log and retry, or contact support if the issue persists.',
      error_type: 'analysis_failed',
      chat_prompt: '',
      llm_used: false,
    });
  })
  .finally(() => { clearTimeout(explainTimeout); setErrorExplaining(false); });
```

---

#### 5. Compression Uses `alert()` — No Feedback on Success
**File:** `frontend/client/src/components/chat-interface.tsx`  
**Root cause:** Compression failure used the browser-native `alert()` call, which blocks the JS thread, cannot be styled, and has no retry action. Compression success had zero user-visible feedback — only a `console.log`. Users had no idea whether compression had occurred, succeeded, or reduced anything.

**Real scenario:** A researcher has a 3-hour drug discovery session. The context window warning appears. They click Compress. The compression endpoint returns 500. A browser alert fires, they dismiss it without reading it, and re-submit — not realising nothing was compressed and the window is still full.

**Fix:**
```typescript
// Success:
toast({
  title: 'Conversation compressed',
  description: `${result.messagesBeforeCount} → ${result.messagesAfterCount} messages (${(result.compressionRatio * 100).toFixed(0)}% reduction). Context window freed.`,
})
// Failure:
toast({
  title: 'Compression failed',
  description: 'Could not compress the conversation. Your session is unchanged — please try again.',
  variant: 'destructive',
})
```

---

#### 6. pause / resume / stop Failures Silent
**File:** `frontend/client/src/components/chat-with-artifacts.tsx`  
**Root cause:** `handlePauseWorkflow`, `handleResumeWorkflow`, `handleStopWorkflow` all had `catch` blocks that only called `console.error`. If the API call failed, the UI buttons appeared to work (no visual change), the workflow kept running, but the user believed it had been stopped.

**Real scenario:** A researcher clicks "Stop" on a workflow that's consuming expensive GPU-hours. The `cancelRun()` call fails because the run UUID wasn't found (race condition). The console logs an error. The researcher believes the workflow stopped. It runs for another 45 minutes at cost.

**Fix:** Destructive toasts with specific, actionable messages for each operation:
- Stop: "Could not stop workflow … The workflow may still be running — check the Run Manager."
- Pause: "Could not pause workflow … The workflow is still running."
- Resume: "Could not resume workflow … Try refreshing the page."

---

#### 7. Workflow Start Failures Before Run ID Exists
**File:** `frontend/client/src/components/chat-with-artifacts.tsx` + `chat-interface.tsx`  
**Root cause:** Two early-return paths in `handleRunWorkflow` had no user feedback:
- `if (!workflow)` — no workflow object: `console.error` only
- `if (!isNextflow && (!steps || steps.length === 0))` — Galaxy workflow with no steps: `console.error` only

Additionally, `workflowError` (local state) was passed as a prop to `ChatInterface` but `ChatInterface` never rendered it. Start failures that throw before `executeWorkflow` returns do set the hook's `error` state (which shows the red banner), but the early-return cases don't reach `executeWorkflow` at all.

**Fix:**
```typescript
if (!workflow) {
  toast({ title: 'No workflow selected', description: 'Ask BioMate to recommend a workflow first, then click Run.', variant: 'destructive' });
  return;
}
if (!isNextflow && (!steps || steps.length === 0)) {
  toast({ title: 'Workflow definition incomplete', description: 'No steps were generated. Try asking BioMate to regenerate the workflow.', variant: 'destructive' });
  return;
}
// Belt-and-suspenders in ChatInterface:
useEffect(() => {
  if (workflowError) {
    toast({ title: 'Workflow could not start', description: workflowError, variant: 'destructive' });
  }
}, [workflowError]);
```

---

#### 8. "Continue in chat →" Prereq Button Not Wired
**Files:** `prereq-normalizer.ts`, `nextflow-workflow-viewer.tsx`  
**Root cause:** `PrereqItem` had no `chatPrompt` field. The normalizer never set one. The viewer never rendered a button for it. The previous session summary claimed it was implemented — it was not.

**Fix:** Added `chatPrompt?: string` to `PrereqItem`; both warning input_data cases now set it to a pre-written message. Viewer renders a "Continue in chat →" button per item when `chatPrompt && onAdjustViaChat`, with `data-testid="prereq-chat-link-{item.id}"`.

---

#### 9. Missing data-testids on Key Components
**Files:** `thinking-display.tsx`, `parameter-group.tsx`

Added:
- `data-testid="thinking-display"` on the `ThinkingDisplay` Card wrapper
- `data-testid="thinking-display-toggle"` on the header clickable div
- `data-testid="param-knowledge-badge-{param.id}"` on the KnowledgeBadge tooltip trigger
- `data-testid="param-override-btn-{param.id}"` on the EditableParamRow override button

---

### Real-Case Test: UX Recovery Suite (ux-workflow-recovery.e2e.ts)

**UX-10:** Germline workflow without FASTQ file provided. Expected:
1. AI shows workflow card (or asks clarifying question)
2. Prereq checklist visible with "Input data" warning item
3. "Continue in chat →" button pre-fills textarea with guidance message
4. Hard-assert: textarea value length > 5 characters after click

**UX-11a:** Germline workflow run with `max_spots=50` (fast, intentionally likely to fail on missing refs). Expected:
- Terminal status within 90s
- If failed: AI-analyzed badge or pattern-matched badge visible

**UX-11b:** Direct POST to `/api/workflows/explain_error`. Expected:
- `human_summary` > 50 chars
- No Java stack trace in human_summary
- `error_type` matches known enum

---

## Part 2 — Claude Code Memory Architecture (Reference: `clawdbot/src/memory/`)

### What Claude Code's Memory Is

**Storage unit:** `MemoryChunk` — a contiguous block of lines from a markdown file, with SHA256 hash, line range, and L2-normalized embedding vector.

**Database:** SQLite (single-file per agent, `~/.openclaw/memory/{agentId}.sqlite`) with three virtual tables:
- `chunks_vec` (sqlite-vec) — float32 embedding vectors for ANN search
- `chunks_fts` (FTS5) — BM25 full-text search
- `embedding_cache` — avoids re-embedding unchanged text

**Two memory sources:**
| Source | Files | Written by |
|---|---|---|
| `"memory"` | `MEMORY.md`, `memory/**/*.md` | Human writes markdown files |
| `"sessions"` | `~/.openclaw/sessions/{agentId}/**/*.jsonl` | Auto-converted from conversation transcripts |

### How Claude Code Retrieves Memories

Every query goes through a hybrid retrieval pipeline:

1. **Keyword search:** FTS5 BM25 ranking → scores normalized to `[0,1]` via `1/(1+rank)`, returns top `4×maxResults` candidates
2. **Vector search:** embed the query → cosine distance via sqlite-vec → top `4×maxResults` candidates  
3. **Hybrid merge:** `score = 0.7 × vectorScore + 0.3 × textScore`  
4. **Filter:** drop scores below `minScore=0.35`, return top `maxResults=6`

**Embedding provider priority:** local llama (if model downloaded) → OpenAI `text-embedding-3-small` → Gemini `gemini-embedding-001`

**Chunking:** Markdown is split into ~400-token chunks with 80-token overlap. Each chunk gets its own embedding and row.

**Cache:** Embeddings keyed by `(provider, model, SHA256(text))` — unchanged text is never re-embedded.

**Sync triggers:**
- File watcher (chokidar): debounced 1500ms after any markdown change
- Session start: warm-up sync on `onSessionStart: true`
- Search: sync before query if dirty (`onSearch: true`)
- Interval: disabled by default (`intervalMinutes: 0`)

### What Claude Code Injects Into Context

```
<memory>
[chunk1 snippet from MEMORY.md lines 12-28]
[chunk2 snippet from project/goals.md lines 3-15]
</memory>
```

Retrieved chunks are injected into the system prompt before each turn. Chunks ranked by hybrid score; top 6 included.

### What Claude Code Does NOT Do

- No LLM call to decide what to remember — humans write markdown files
- No automatic memory extraction from conversations (sessions source requires opt-in)  
- No per-user or per-project isolation — single SQLite per agent
- No memory types/categories enforced by the system — directory structure is user convention only
- No cross-session learning from workflow outcomes

---

## Part 3 — BioMate Memory Architecture (Accurate Current State)

BioMate has a **five-tier hierarchical memory system** by design. This is more architecturally ambitious than Claude Code's two-source model. The critical distinction is which tiers are **wired into the active request path** versus which are **schema/service without data flow**.

### Tier 1 — Session Memory (IMPLEMENTED, NOT PERSISTED)
**File:** `galaxy-assistant.ts` — `SessionMemoryUpdater` class (lines 738–857)

**What it does:** After every turn, a debounced (30s) Haiku call extracts six typed fields from the conversation and stores them in a Node.js in-memory Map:

| Field | Description |
|---|---|
| `active_task` | What the researcher is currently trying to accomplish (1 sentence, present tense) |
| `key_decisions` | Technical choices made, each with a confidence score 0–1 |
| `uploaded_files` | All files uploaded or mentioned this session |
| `attempted_workflows` | Workflows tried, with outcome (success/failed/ongoing) |
| `current_parameters` | Active parameter set from last workflow |
| `open_questions` | Unresolved questions or unknowns, with confidence |

**Injection:** `_buildSessionMemoryBlock()` formats only high-confidence items (≥ 0.7) and prepends them as `<session_memory>` XML tags into every system prompt call. Both `analyzeIntent()` and `generateWorkflow()` see this block.

**Advantage over Claude Code:** BioMate's session memory is semantically richer — Haiku actively extracts and classifies facts, assigns confidence scores, tracks workflow outcomes, and maintains a context stack for tangent dialogues. Claude Code's session indexing is passive (raw JSONL transcripts chunked for similarity search).

**Critical gap:** The Map is in-process only. Server restart or 2-hour idle TTL evicts all sessions. No write to PostgreSQL occurs anywhere.

### Tier 2 — ConversationState (IMPLEMENTED, PERSISTED)
**File:** `conversation-state.ts` — `ConversationStateManager`

**Stored in:** PostgreSQL `sessions.conversationState` JSONB column after every turn.

**Contents:** `facts[]` (typed RawFact objects extracted by LLM), `intent` (primary type + confidence + history), `candidateTools`, `workflowSteps` (pipeline chain — survives compression), `contextStack` (tangent sub-dialogue frames), `readiness`.

**Retrieval:** Loaded by exact session ID — not searched across sessions.

### Tier 3 — Episodic Memory (SCHEMA + SERVICE, NOT IN REQUEST PATH)
**Files:** `agentic_memory.py` (`EpisodicMemoryService`) + `ltm-schema.ts` (`project_episodes`)

**Schema:** `project_episodes` — stores user_query, tools_used, outcomeSuccess, lessonsLearned, importanceScore, accessCount, whatWorked[], whatFailed[].

**What exists:** `record_interaction()`, `learn_from_outcome()`, `get_similar_episodes()` — all implemented in `agentic_memory.py`.

**What's missing:** These are **never called automatically** in the main `processMessage()` request path. Episodes are not inserted after workflow completion, and past episodes are never retrieved and injected into future prompts. `memory-integration.ts` (`processWithMemory()`) was designed to do this but is instantiated at server start and then never called (routes.ts line 644).

**Episode retrieval** uses substring matching on the intent string (`.includes()`), not semantic similarity — so "somatic mutation detection" would not match a stored episode about "WGS variant calling for cancer."

### Tier 4 — Procedural Memory (SCHEMA ONLY)
**File:** `ltm-schema.ts` (`project_procedures`)

**Schema:** `project_procedures` — stores triggerPattern, steps[], preconditions, successRate, learnedFrom[] (episode IDs).

**Status:** Table exists. No code populates it. The `learnedFrom` field (episode → procedure consolidation) is never written. `findMatchingProcedures()` exists in `agentic_memory.py` but uses substring matching and is never called in the request path.

### Tier 5 — Project Knowledge / User Profile (SCHEMA + API, NOT IN PROMPT)
**Files:** `ltm-schema.ts` (`project_knowledge`, `user_preferences`, `correction_log`) + `agentic_memory.py`

**What exists:** REST endpoints for writing and reading project knowledge, user preferences, and correction logs. `buildMemoryContextPrompt()` in `memory-integration.ts` (line 403) formats these into a system prompt block.

**What's missing:** `buildMemoryContextPrompt()` is **never called** in `processMessage()`. User corrections are stored but never consulted before generating a new workflow suggestion. Project knowledge is retrieved only via the REST API, not injected into the LLM context.

### Summary Table

| Tier | Storage | Active in Request Path? | Persists Across Restarts? |
|---|---|---|---|
| Session Memory (Tier 1) | Node.js heap Map | **YES** — injected every turn | **NO** — lost on restart |
| ConversationState (Tier 2) | PostgreSQL JSONB | **YES** — loaded/saved every turn | **YES** |
| Episodic Memory (Tier 3) | PostgreSQL `project_episodes` | **NO** — service exists, never called | YES (when written) |
| Procedural Memory (Tier 4) | PostgreSQL `project_procedures` | **NO** — schema only | YES (when written) |
| Project Knowledge / Prefs (Tier 5) | PostgreSQL `project_knowledge` etc. | **NO** — `memory-integration.ts` dead code | YES |

---

## Part 4 — Honest Comparison: BioMate vs Claude Code

### Where Claude Code Wins

**1. Full implementation of its simpler design.**
Claude Code has 2 memory sources. Both are fully wired: markdown files are chunked, embedded, and retrieved on every query. BioMate has 5 tiers but only 2 are in the active path (Tiers 1 and 2).

**2. Semantic retrieval via hybrid vector + keyword search.**
Claude Code: cosine similarity on L2-normalized embeddings (70%) + BM25 FTS5 (30%). BioMate Tier 3/4: substring matching. This means Claude Code can find a relevant past interaction even when the query uses different words. BioMate cannot.

**3. Session transcripts auto-indexed as searchable context.**
Claude Code's sessions source: JSONL transcripts are chunked and embedded; past conversations surface automatically via semantic search. BioMate's past sessions are stored in PostgreSQL but never semantically searched.

**4. Session memory persists across restarts.**
Claude Code: JSONL files on disk, watched and synced. BioMate Tier 1: dies when the Node.js process exits.

**5. Memory is transparent and editable.**
Claude Code: `MEMORY.md` is human-readable markdown. Researchers can read, edit, and version-control exactly what the AI knows. BioMate: opaque PostgreSQL rows.

### Where BioMate Wins (or Has Superior Design)

**1. Semantically richer session memory extraction.**
Claude Code passively chunks raw transcripts. BioMate's `SessionMemoryUpdater` actively calls Haiku to extract typed, confidence-scored facts — distinguishing `active_task` from `key_decisions` from `open_questions`. This is architecturally superior for a scientific assistant where the intent behind decisions matters more than the raw text.

**2. Per-user, per-project isolation.**
Claude Code has one SQLite per agent — all users share it. BioMate's LTM is scoped by `userId` and `projectId`, enabling personalized memory that doesn't leak between researchers.

**3. Correction feedback loop (designed).**
BioMate has `correction_log` — when a researcher corrects a workflow suggestion, the correction is typed and stored. Claude Code has no equivalent. Once the correction injection is wired (Tier 5 → request path), BioMate can avoid repeating mistakes Claude Code would make indefinitely.

**4. Workflow outcome learning (designed).**
BioMate has `project_procedures` with `successRate`, `timesUsed`, `learnedFrom` — a first-class schema for accumulating procedural knowledge from episodes. Claude Code has no equivalent concept.

**5. Context stack for tangent dialogues.**
BioMate's `contextStack` in ConversationState pushes/pops sub-dialogue frames so the assistant can handle "quick question" interruptions and return to the main workflow. Claude Code has no equivalent.

---

## Part 5 — What Needs to Be Wired

The gaps are not architectural redesign — the design is sound. The work is completing the data flow for Tiers 3–5 and fixing Tier 1's persistence.

### Priority 1: Persist Session Memory (Tier 1)
**Effort:** 1 day. Add `session_memory JSONB` column to `sessions` table. Write in `_update()`. Read and restore in `processMessage()` on session resume.

**Real-case impact:** A researcher runs a 4-hour GROMACS MD simulation session. Server restarts overnight. Next morning, `active_task` ("optimizing EGFR inhibitor leads"), `current_parameters` (force field, timestep), and `attempted_workflows` (3 iterations) are all gone. With persistence, the AI resumes knowing exactly where they were.

### Priority 2: Wire Episodic Recording After Workflow Completion (Tier 3)
**Effort:** 2 days. In the workflow completion handler (routes.ts), call `record_interaction()` + `learn_from_outcome()`. This is the data source for all future retrieval.

**Real-case impact:** Without recording, `get_similar_episodes()` always returns nothing — the table is empty. There is nothing to search across.

### Priority 3: Add pgvector Embeddings to Episodes + Procedures (Tier 3/4)
**Effort:** 2 days. Add `embedding vector(1536)` columns to `project_episodes` and `project_procedures`. Embed `user_query + lessons_learned` on insert using `text-embedding-3-small`. Replace substring search with `embedding <=> $query_vec ORDER BY ... LIMIT 5`.

**Real-case impact:** Researcher asks "run somatic variant calling on tumor sample." Semantic search finds a past episode where they ran "cancer WGS germline-somatic comparison" and surfaces the params that worked — even though the query words differ.

### Priority 4: Inject Prior Experience into System Prompt (Tier 3/4 → Request Path)
**Effort:** 1 day once P3 done. Query `find_matching_procedures()` at intent resolution time; prepend `<prior_experience>` block. This is the direct quality improvement.

### Priority 5: Inject Project Knowledge + Correction Log (Tier 5 → Request Path)
**Effort:** 2 days. Call `buildMemoryContextPrompt()` (already written in `memory-integration.ts`) from `processMessage()`. Add correction log check before workflow suggestion. This activates entirely dead but complete code.

### Priority 6: Session Context UI Panel (Tier 1 transparency)
**Effort:** 2 days. Sidebar component reading `/api/memory/sessions/{id}/context`. Shows `active_task`, `key_decisions`, `uploaded_files`. Allows researcher to correct or clear items.

---

## Part 6 — Implementation Priority Table

| Priority | Tier | Work | Impact |
|---|---|---|---|
| P1 | Tier 1 | Persist SessionMemory to `sessions.session_memory` JSONB | Eliminates silent context loss on restart |
| P1 | Tier 3 | Auto-record episodes on workflow completion | Populates the episode store — required before any retrieval works |
| P2 | Tier 3/4 | Add pgvector embeddings; replace substring search | Semantic "you did this before" matching |
| P2 | Tier 3/4 | Inject `<prior_experience>` block in system prompt | Direct workflow quality improvement |
| P2 | Tier 5 | Call `buildMemoryContextPrompt()` from `processMessage()` | Activates project knowledge + correction log (zero schema work needed) |
| P3 | Tier 1 | Retry + session-end flush for Haiku update | Eliminates silent update failures |
| P3 | UI | Session Context sidebar panel | Memory transparency for pilot study researchers |

---

## Appendix — Files Changed This Session

| File | Change |
|---|---|
| `frontend/client/src/hooks/useUnifiedExecution.ts` | SSE parse try/catch; consecutive poll failure counter; startPolling reset counter |
| `frontend/client/src/components/chat-with-artifacts.tsx` | pause/resume/stop error toasts; early-return toasts; SSE reconnecting indicator |
| `frontend/client/src/components/chat-interface.tsx` | useToast import; workflowError useEffect toast; compression success/failure toasts; upload failure toast |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Error explanation AbortController timeout; fallback explanation object |
| `frontend/client/src/lib/prereq-normalizer.ts` | `chatPrompt` field on `PrereqItem`; populated on warning input_data items |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | "Continue in chat →" button per prereq item |
| `frontend/client/src/components/thinking-display.tsx` | data-testid on Card and header toggle |
| `frontend/client/src/components/parameter-group.tsx` | data-testid on KnowledgeBadge and override button |
