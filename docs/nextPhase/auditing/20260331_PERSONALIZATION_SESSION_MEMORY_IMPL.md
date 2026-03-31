# Personalization + Session Memory — Implementation Record
**Date:** 2026-03-31
**Branch:** `integration/next-phase`
**Companion plans:** `20260330_HARNESS_ANALYSIS_AND_PERSONALIZATION_PLAN.md`, `20260330_LLM_REPLACEMENT_TEST_PLAN.md`

---

## Summary

This session implemented two features from the personalization audit and the harness analysis plan:

| Feature | Status |
|---------|--------|
| R1: Domain profile must not suppress clarification (Use Case 5) | ✅ Implemented + tested |
| R2: Async session memory for long-session coherence (Use Case 6, Phase 1) | ✅ Implemented |
| Audit of all new code by subagent | ✅ Complete — 4 issues found |
| All audit issues fixed | ✅ Fixed |
| Test count: 42/42 passing | ✅ Green |
| TypeScript: zero errors | ✅ Clean |

---

## Feature 1 — Use Case 5: Clarification Not Suppressed by Domain Profile

### Problem

When a user has an oncology domain profile, queries like "analyze my expression data" were being resolved without clarification. The LLM saw `preferred_domains=["transcriptomics"]` in the system prompt and treated it as sufficient to disambiguate bulk RNA-seq from single-cell RNA-seq. It should not — the domain tells you which tools to rank higher *after* the answer is known, not what the user wants.

### Fix

**File:** `frontend/server/galaxy-assistant.ts`

The clarification-guard rule was added at the very **start** of the `## Ambiguity Detection` section in the `analyzeIntent()` system prompt (before the fork-point list, not after). Placing it first uses LLM primacy to ensure the rule is active when each ambiguity type is evaluated.

```
## Ambiguity Detection

IMPORTANT: Domain profile and research context do NOT resolve workflow ambiguity.
If a user's query would normally trigger a clarification question, it MUST still
trigger that question even when their domain profile suggests a context.

The domain profile tells you WHICH tools to rank higher after you know the answer —
it does NOT tell you WHAT the user wants.

Examples:
- User profile: oncology. Query: "analyze my expression data" → STILL ask:
  is this bulk RNA-seq (differential expression) or single-cell RNA-seq (clustering)?
- User profile: drug_discovery. Query: "run a docking analysis" → STILL ask:
  blind docking (DiffDock) or site-directed (AutoDock Vina)?

Rule: set workflowAmbiguity whenever the query is genuinely ambiguous at the
technical level, regardless of what the user's domain profile contains.

GENERAL RULE: When a workflow request could map to two or more pipelines...
Known fork points:
  [existing list unchanged]
```

**Why placement matters:** If the rule was only at the end (after the list), LLM attention on early list entries might not yet have the rule's context. Placing it first primes the disambiguation behavior throughout.

### workflowAmbiguity field fix (issue found in audit)

The `workflowAmbiguity` field was being accessed as `(intent as any).workflowAmbiguity` — a dynamic cast that bypassed TypeScript entirely. This meant:

1. The field was never validated by the type system
2. It was not listed in `DecomposedIntent` (no documentation, no autocompletion)
3. No tests checked whether the parser preserved it

**Fix applied:**

Added to `DecomposedIntent` interface:
```typescript
/** Ambiguity fork point requiring clarification, or null when intent is unambiguous */
workflowAmbiguity?: string | null;
```

Added to `parseIntentResult()` single-intent path:
```typescript
workflowAmbiguity: typeof result.workflowAmbiguity === 'string' ? result.workflowAmbiguity : null,
```

Updated the consumption site:
```typescript
// Before (unsafe cast):
const ambiguity = (intent as any).workflowAmbiguity;
// After (typed):
const ambiguity = intent.workflowAmbiguity;
```

---

## Feature 2 — Use Case 6: Async Session Memory (Phase 1)

### Problem

BioMate uses a 6-turn sliding window. By turn 7+, earlier context (uploaded files, parameter decisions, target definitions) falls out of the model's view. The `accumulatedFacts` mechanism partially compensates, but only captures explicitly-tagged facts, not the broader session understanding.

The root insight from DeerFlow analysis: **memory updates are async, injection is sync**. The main conversation path must never be blocked.

### Architecture

```
Turn N completes
     │
     └──► (async, debounced 30s) SessionMemoryUpdater.queue(sessionId, userMsg, assistantMsg)
                  │
                  ▼
           Haiku call: "given this new turn and current memory, what's the updated memory JSON?"
                  │
                  ▼
           SessionMemory {
             active_task: string,
             key_decisions: string[],
             uploaded_files: string[],
             attempted_workflows: {path, status}[],
             current_parameters: Record<string,any>,
             open_questions: string[],
           }
                  │
                  ▼
           stored in memoryBySession Map (per sessionId)

Turn N+1 starts
     │
     └──► _buildSessionMemoryBlock(sessionId) → <session_memory>...</session_memory>
                  │
                  ▼
           injected into analyzeIntent() and generateResponse() system prompts
```

### Implementation Details

**New class: `SessionMemoryUpdater`** (`galaxy-assistant.ts`, before `GalaxyAssistant` class)

- `queue(sessionId, userMessage, assistantResponse)`: debounced timer per session. If another turn arrives within 30s, the earlier timer is cancelled and replaced — only the latest content is sent for processing (same as DeerFlow's MemoryQueue).
- `get(sessionId)`: returns current memory, updating `lastAccess` for TTL tracking.
- `_update()`: private — calls Haiku, validates JSON structure, stores with timestamp.
- `_evictStale()`: called on every write — removes sessions idle >2 hours. Prevents unbounded memory growth on long-running servers.

**Key design decisions:**

| Decision | Rationale |
|----------|-----------|
| 30s debounce | Matches DeerFlow. Rapid-fire turns within one "thinking pause" are a logical unit; only the last one matters for memory update. |
| Haiku model | Low cost, fast. Memory updates are not on the critical path. |
| max_tokens=600 | Enough for a compact JSON summary. The system prompt instructs conciseness. |
| 2h TTL eviction | Prevents unbounded Map growth. In-memory only (Phase 1) — no DB. |
| Type guards on parse | After JSON.parse, all array/object fields are validated before storage. Malformed LLM output falls back gracefully. |

**Injection points:**

The session memory block is injected into two places per turn:
1. `analyzeIntent()` system prompt — so intent classification sees prior context
2. `generateResponse()` system prompt — so the final response can reference prior decisions

**Wiring in processMessage():**

```typescript
// At start:
const sessionMemoryBlock = this._buildSessionMemoryBlock(context.sessionId);

// Pass to analyzeIntent:
const decomposition = await this.analyzeIntent(message, context, sessionMemoryBlock);

// Pass to generateResponse:
const response = await this.generateResponse(..., sessionMemoryBlock);

// Queue update after turn (non-blocking):
if (context.sessionId) {
  this.sessionMemory.queue(context.sessionId, message, response.message);
}
```

**Format of `<session_memory>` block:**

```
<session_memory>
Current task: designing EGFR inhibitor docking pipeline
Key decisions: using AlphaFold3 for structure; ADMET screen before docking
Files this session: egfr_apo.pdb, library_1000.sdf
Previously attempted: drug_discovery/docking/main.nf (failed)
Parameters set: {"receptor": "egfr_apo.pdb", "exhaustiveness": 16}
Open questions: user hasn't specified the binding pocket residues
</session_memory>
Note: session memory supplements the conversation window — prior turns may have been compressed.
```

**Why this is not rule-based:**

The LLM decides what goes in each field. `key_decisions`, `open_questions`, and `current_parameters` are fully LLM-determined. The schema is the only structure — not keyword matching, not hard-coded categories. The model will naturally:
- Promote the uploaded library from turn 2 to `uploaded_files` even after the window compresses
- Update `active_task` when the user pivots from docking to MD simulation
- Add to `open_questions` when it detects the user hasn't resolved an ambiguity
- Remove resolved items on subsequent updates

---

## Audit Findings and Fixes

An automated subagent audit was run against all new code. It found 4 real issues:

### Issue 3 (High): Memory leak — unbounded Maps

**Finding:** `memoryBySession` and `timers` Maps grew without bounds. Long-running servers with many sessions would accumulate entries indefinitely.

**Fix:** Added `lastAccess` timestamp to each entry. `_evictStale()` removes entries idle >2 hours. Called on every `_update()` (amortized — no dedicated interval timer needed).

```typescript
private memoryBySession: Map<string, { memory: SessionMemory; lastAccess: number }> = new Map();
private static readonly SESSION_TTL_MS = 2 * 60 * 60 * 1000; // 2h

private _evictStale(): void {
  const cutoff = Date.now() - SessionMemoryUpdater.SESSION_TTL_MS;
  for (const [id, entry] of this.memoryBySession) {
    if (entry.lastAccess < cutoff) {
      this.memoryBySession.delete(id);
      const t = this.timers.get(id);
      if (t) { clearTimeout(t); this.timers.delete(id); }
    }
  }
}
```

### Issue 5 (Medium): Malformed SessionMemory JSON crash

**Finding:** If the LLM returned valid JSON with wrong types (e.g., `key_decisions: "string"` instead of an array), `_buildSessionMemoryBlock()` would crash on `.join()` or `.map()`.

**Fix:** Added type guards in `_update()` after JSON.parse, before storing:

```typescript
if (!Array.isArray(updated.key_decisions)) updated.key_decisions = [];
if (!Array.isArray(updated.uploaded_files)) updated.uploaded_files = [];
if (!Array.isArray(updated.attempted_workflows)) updated.attempted_workflows = [];
if (typeof updated.current_parameters !== 'object' || Array.isArray(updated.current_parameters)) updated.current_parameters = {};
if (!Array.isArray(updated.open_questions)) updated.open_questions = [];
```

### Issue 8 (Low): Rule placement — domain profile rule should precede the list

**Finding:** The clarification-guard rule was placed AFTER the 15+ fork-point entries. LLM attention on early list items might not have seen the rule yet.

**Fix:** Moved the rule to the START of `## Ambiguity Detection`, before the fork-point list. Removed the duplicate copy at the end.

### Issue 9+10 (Medium): Missing tests for workflowAmbiguity

**Finding:** No tests verified that `workflowAmbiguity` was extracted from the LLM result. The test helper silently dropped it. No test covered the Use Case 5 scenario.

**Fix:**
1. Added `workflowAmbiguity` extraction to the test helper's `parseIntentResult()`
2. Added describe block `1.7 Use Case 5 — domain profile oncology + vague expression query`:
   - Verifies `workflowAmbiguity='rnaseq_type'` is preserved even with `preferred_domains=['transcriptomics']`
   - Verifies `workflowAmbiguity` is NOT null just because domain is set
3. Added describe block `1.8 workflowAmbiguity=null when query is specific`:
   - Verifies null is correctly passed through when user specifies bulk RNA-seq

---

## Test Results

```
✓ server/analyze-intent-uqu.test.ts  (42 tests) 5ms
Test Files  1 passed (1)
Tests       42 passed (42)
TypeScript: 0 errors
```

Test count went from 36 → 42 (6 new tests for Use Case 5 + workflowAmbiguity propagation).

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | `SessionMemoryUpdater` class; `DecomposedIntent.workflowAmbiguity` field; clarification rule moved to top of ambiguity section; type guards in `_update()`; TTL eviction; injection into `analyzeIntent()` + `generateResponse()`; `processMessage()` + `processMultiIntent()` wiring |
| `frontend/server/analyze-intent-uqu.test.ts` | `workflowAmbiguity` propagation in test helper; 2 new describe blocks (UC5 + null case) |

---

## What Phase 2 Would Add (Deferred)

Phase 1 (implemented here) is in-memory only. Session memory does not survive server restarts.

Phase 2 would add:
- `POST /api/memory/session-state` backend endpoint
- SQLite persistence via `session_memory` table
- Load on first access (not just from in-memory Map)
- Connect `_triggerSessionSummary()` to use the same storage

This is deferred until Phase 1 proves useful in practice.
