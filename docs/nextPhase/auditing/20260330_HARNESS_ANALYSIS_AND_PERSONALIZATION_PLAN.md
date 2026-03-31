# Harness Framework Analysis & Personalization Plan
**Date:** 2026-03-30
**Branch:** `integration/next-phase`
**Inputs:** `deer-flow` (ByteDance), `claude-code` harness (Anthropic), `20260330_PERSONALIZATION_AUDIT.md`

---

## 1. Use Case 5 — Vague Query + Domain Profile (Should Clarify, Not Assume)

**The problem:**
User has saved profile: `oncology`. They ask "analyze my expression data" (vague).
Current behavior: the domain profile prefix biases the LLM toward oncology-specific response without asking.
Expected behavior: BioMate should still clarify, even when a domain profile exists.

**Why the current approach is wrong:**

The domain profile prefix says:
```
User research domains: oncology, drug_discovery.
Use this as additional context — current conversation takes priority.
```

But the intent analysis LLM sees this and treats "oncology" as a sufficient disambiguator. It does not ask whether "expression data" means RNA-seq, proteomics, ATAC-seq, single-cell, or something else. The profile collapses the clarification that should happen.

**The correct model:**

Domain profile = search bias. It is NOT a substitute for conversation-level intent resolution.

```
Clarification resolves WHAT the user wants to do.
Domain profile biases HOW the system searches for tools.
These are independent — a domain profile does not answer the question "what kind of analysis?"
```

**Concrete fix in `analyzeIntent()` system prompt:**

Add a rule under the Ambiguity Detection section:

```
IMPORTANT: Domain profile and research context do NOT resolve workflow ambiguity.
If a user's query would normally trigger a clarification question, it should still
trigger that question even when their domain profile suggests a context.

Examples:
- User profile: oncology. Query: "analyze my expression data" → STILL ask: is this
  bulk RNA-seq (differential expression) or single-cell RNA-seq (cell clustering)?
  The profile tells us WHICH tools to rank higher after we know the answer — not
  WHAT the user wants.

- User profile: drug_discovery. Query: "run a docking analysis" → STILL ask: blind
  docking (binding site unknown, DiffDock) or site-directed (known pocket, AutoDock Vina)?

The rule: set workflowAmbiguity when the query is genuinely ambiguous at the technical
level, regardless of what the user's profile says. The profile informs preferred_domains
(search ranking) but never resolves workflowAmbiguity.
```

This is a prompt-level fix — no code changes needed. The domain profile continues to provide the +2.0 search bias for whichever workflow is ultimately generated.

---

## 2. Use Case 6 — Long-Session Coherence (LLM-Based, No Hard-Coded Rules)

### Problem statement

BioMate has a 6-turn sliding window. By turn 7+, earlier context (uploaded files, target definitions, parameter decisions) is dropped from the model's view. The `accumulatedFacts` mechanism partially compensates but only captures explicitly-extracted facts — not the broader session understanding (what has been tried, what failed, what was decided).

The existing session summary trigger (`_triggerSessionSummary()`) saves a summary but **never reinjects it**. This is the missing connection.

### What DeerFlow does (the right model)

DeerFlow's `MemoryMiddleware` + `MemoryQueue`:
1. After every agent turn, conversations are **queued** for background processing (debounced 30s)
2. A Haiku call extracts and updates structured memory: `workContext`, `personalContext`, `topOfMind`, and `facts` (confidence-scored)
3. Top 15 facts + context are **injected into every system prompt** via `<memory>` tags
4. The model itself decides what is important — no hand-coded rules about what to remember

**Key insight:** Memory is updated async and injected sync. The main conversation path is not blocked.

### What Claude Code harness does (complementary pattern)

The `feature-dev` plugin uses **phase accumulation**: each phase's output is carried forward as context for the next phase. Nothing is dropped. The final synthesis phase has access to everything discovered in phase 1.

The `ralph-wiggum` stop-hook uses **completion promises**: the agent writes explicit XML tags when done (`<promise>DONE</promise>`), making state transitions unambiguous.

### Proposed solution for BioMate: Async Session Memory

**Architecture:**

```
Turn N completes
       │
       ├──► (sync) accumulatedFacts — existing fact extraction continues
       │
       └──► (async, debounced 30s) SessionMemoryUpdater.queue(turnN)
                    │
                    ▼
             Haiku call: "Given this new turn and current memory, what should
                          the updated session memory contain?"
                    │
                    ▼
             SessionMemory {
               active_task: string,           // "designing EGFR inhibitor pipeline"
               key_decisions: string[],        // ["using AlphaFold3 for structure", "ADMET first"]
               uploaded_files: string[],       // ["egfr_apo.pdb", "library_1000.sdf"]
               attempted_workflows: {path, status}[], // ["drug_discovery/docking/main.nf → failed"]
               current_parameters: Record<string,any>, // {"genome": "hg38", "strandedness": "auto"}
               open_questions: string[],       // ["user hasn't specified the pocket residue"]
             }
                    │
                    ▼
             Stored in DB + in-memory cache (per session_id)
```

**Injection:**

At the start of each `processMessage()` call, if session memory exists for the session_id:

```typescript
// In analyzeIntent() and generateResponse() system prompts, prepend:
const sessionMemoryBlock = sessionMemory ? `
<session_memory>
Current task: ${sessionMemory.active_task}
Key decisions made: ${sessionMemory.key_decisions.join('; ')}
Files uploaded this session: ${sessionMemory.uploaded_files.join(', ')}
Previously attempted: ${sessionMemory.attempted_workflows.map(w => `${w.path} (${w.status})`).join(', ')}
Parameters established: ${JSON.stringify(sessionMemory.current_parameters)}
Open questions: ${sessionMemory.open_questions.join('; ')}
</session_memory>

Note: This session memory supplements the conversation window. Prior turns may have been compressed.
` : '';
```

**Why this is not rule-based:**

The LLM decides what goes in `key_decisions`, `open_questions`, `current_parameters`. The schema is the only structure — the content is entirely LLM-determined. The model will naturally:
- Promote the compound library from turn 2 to `uploaded_files` even though turn 2 is out of the window
- Update `active_task` when the user pivots from "docking" to "MD simulation"
- Add to `open_questions` when it detects the user hasn't resolved an ambiguity
- Remove items when they become irrelevant or resolved

**Haiku prompt for memory update (concise):**

```
You are maintaining a session memory for a bioinformatics research session.
Given the new conversation turn below and the current memory, produce an updated memory JSON.

Rules:
- active_task: what is the user currently trying to accomplish (1 sentence)
- key_decisions: list of specific technical decisions made (max 8)
- uploaded_files: all files the user has uploaded or mentioned this session
- attempted_workflows: workflows that were generated or run, with outcome
- current_parameters: concrete parameter values established (genome, strandedness, etc)
- open_questions: things that remain ambiguous or unresolved

Update incrementally — carry forward what is still relevant, update what has changed.
Only include items you are confident about. If nothing has changed for a field, keep it as-is.

Return JSON only.
```

**Implementation plan (phased):**

| Phase | Change | Where |
|-------|--------|-------|
| 1 | Add `SessionMemoryUpdater` class with debounced Haiku call | `galaxy-assistant.ts` (new class) |
| 2 | Call updater after each `processMessage()` completes (non-blocking) | `galaxy-assistant.ts` processMessage() |
| 3 | Load session memory at start of `processMessage()`, inject into prompts | `galaxy-assistant.ts` |
| 4 | Persist memory to DB via `/api/memory/session-state` endpoint | `routes.ts` + SQLite |
| 5 | Connect existing `_triggerSessionSummary()` to use the same storage | Refactor, not new code |

**Phase 1 alone** (in-memory only, no DB) already fixes the core use case — memory survives within a server session. DB persistence (Phase 4) adds cross-restart durability.

---

## 3. Synthesis: What to Learn from DeerFlow and Claude Code

### From DeerFlow

| Pattern | BioMate Application |
|---------|---------------------|
| **CLARIFY → PLAN → ACT** enforced by middleware | Add a `ClarificationGate` in the intent path: if `workflowAmbiguity` is set, block workflow generation even if `needsWorkflowGeneration=true` (middleware, not LLM discretion) |
| **Async debounced memory** extraction | `SessionMemoryUpdater` — updates session memory in background after each turn |
| **Confidence-scored facts** (0.0–1.0) | `ExtractedFact.confidence` already exists — use it to gate which facts get injected (only ≥ 0.7) |
| **Deferred tool discovery** | Workflow catalog is ~2400 entries — too large for system prompt. This is exactly what our UQU `key_terms` approach solves: LLM narrows the search space first |
| **Configuration-driven capability assembly** | `_FAST_CLASSIFICATION_MODELS` + skill YAML already does this; could generalize to domain-specific agent configs |
| **Middleware for cross-cutting concerns** | BioMate currently handles ambiguity, ADMET fast path, doom loop in the main pipeline function. Moving these to discrete middleware makes them easier to test and modify |

### From Claude Code Harness

| Pattern | BioMate Application |
|---------|---------------------|
| **Phase-based workflows** (clarify → design → execute) | Multi-step pipeline execution (B4 sequential pipeline) should gate each step: show step N's configuration and wait for approval before launching step N+1 |
| **Confidence-based filtering** (0–100, report ≥80) | `unified_workflow_search.py` `_classify_match()` uses tier thresholds. Could replace with confidence scores that are shown to user ("87% confident this is the right workflow") |
| **Specialized micro-agents** | BioMate's `processSubIntent` fan-out is this pattern. The gap: sub-agents don't have specialized prompts. A "metagenomics specialist agent" would know QIIME2/DADA2 deeply, while a "genomics specialist" knows GATK deeply. |
| **Completion promise pattern** | Sequential pipeline execution (B4): step N should produce `<step_complete>` with outputs before step N+1 starts. Currently status-based polling — completion promises would be cleaner |
| **Stop hooks for autonomous loops** | Error recovery (D4): after a workflow fails, the "fix & retry" path could use a stop hook pattern — automatically re-run the corrected workflow rather than requiring a manual click |
| **Trigger examples over rules** | Agent routing via examples in system prompt already used in BioMate (the ambiguity section). Extend to workflow chain matching — provide 5 examples of queries that trigger each chain |

---

## 4. Priority Recommendations

### Implement now (low effort, high value)

**R1: Fix Use Case 5 — clarification not blocked by domain profile**
Edit: add one paragraph to `analyzeIntent()` system prompt (30 min)

**R2: Wire session memory injection for Use Case 6 — Phase 1 (in-memory)**
New class `SessionMemoryUpdater` + inject into prompts. No DB needed yet. (~4h)

**R3: Use confidence scores from `_classify_match()` in response text**
When showing a workflow recommendation, say "I found a strong match (87% confidence): nf-core/rnaseq". Currently shows as plain text.

### Implement in next session

**R4: ClarificationGate middleware (DeerFlow lesson)**
Extract ambiguity blocking from inline if-statement into a discrete gate function that can be tested independently.

**R5: Specialized sub-agent prompts (Claude Code lesson)**
For each of the 13 taxonomy domains, create a short domain-expert prompt snippet that gets injected when `preferredDomains` contains that domain. The metagenomics variant of `generateWorkflow()` knows to check QIIME2/Kraken2 first.

**R6: Step-by-step approval for sequential pipelines (Claude Code phase-gate)**
In `PipelineListView`, show each step's parameters and require user confirmation before triggering the next step's execution. Currently all steps launch in sequence automatically.

### Defer

**R7: DB-backed session memory persistence** (Phase 4 above)
**R8: DeerFlow-style middleware chain refactor** — significant architectural change, do after other features stabilize
**R9: Chain matching via examples instead of Jaccard** (deferred D9 equivalent)
