# BioMate LLM Usage Audit
**Date:** 2026-03-31 (updated from 2026-03-30)
**Branch:** `integration/next-phase`
**Purpose:** Pre-release review of every LLM call — prompts, context quality, and capability self-awareness
**Last updated:** 2026-03-31 (v2) — corrected `drug_discovery` classification (domain label, not intent type), corrected S3 (DomainSpecialistPool already exists in backend), removed S2 (confidence score not needed — confirmation required regardless), updated ONE-QUESTION rule, updated suggestions handling, added dataset visualization gap analysis.

---

## Executive Summary

BioMate uses Anthropic Claude models in **14 distinct call sites** across frontend and backend (was 13 — session memory update is new). The system uses a layered architecture: Haiku for fast classification/ranking/clarification/memory, Sonnet for generation and complex response.

Key finding unchanged: **the system does not give the AI a complete inventory of its available workflows** — it uses retrieval (FTS + optional LLM re-ranking) to surface candidates per query. This is intentional (the catalog is too large for a context window) but means the AI's ability to suggest workflows depends entirely on the quality of the search and ranking. The new `key_terms` field from intent analysis (UQU) now compensates for this by narrowing the FTS search space before retrieval.

**Changes since 2026-03-30 audit:**

| Change | Where |
|--------|-------|
| Call Site 14 added: `SessionMemoryUpdater` async Haiku call | `galaxy-assistant.ts` |
| Call Sites 1 + 2: session memory block injected into both system prompts | `galaxy-assistant.ts` |
| Call Site 1: clarification guard moved to start of ambiguity section | `galaxy-assistant.ts` |
| Call Site 1: `admet_scope` new ambiguity type for ADMET queries without SMILES | `galaxy-assistant.ts` |
| Call Site 1: UQU fields (`preferredDomains`, `keyTerms`, `chainHint`, `needsThinking`) routed to search + response | `galaxy-assistant.ts` |
| `workflowAmbiguity` typed in `DecomposedIntent` — removed `(intent as any)` cast | `galaxy-assistant.ts` |

**Overall capability self-awareness grade: B** (up from B-)
The session memory layer substantially improves long-session coherence. The clarification guard prevents domain profile from masking genuine ambiguities. The remaining grade ceiling is the static capability count and the lack of module existence verification in Nextflow composition.

---

## Call Site 1: Intent Analysis
**File:** `frontend/server/galaxy-assistant.ts`, `analyzeIntent()`
**Model:** `claude-haiku-4-5` (fast, cached)
**Usage:** First call on every user message — determines what the AI should do

### System Prompt Structure
The prompt is a large, well-structured document encoding:
- All intent types: `workflow_generation`, `tool_search`, `research_question`, `general_question`, `benchmark_request`, `dataset_search`, `workflow_modification`, `result_comparison`, `troubleshooting`, `experiment_design`, `data_interpretation`, and others — **`drug_discovery` is NOT an intent type** (see note below)
- Multi-intent decomposition rules
- Sequential pipeline detection signal words: "then", "followed by", "next", "pipeline of", "chain:"
- **UQU fields** (new): `preferred_domains`, `key_terms`, `needs_thinking`, `chain_hint` — extracted alongside intent type
- **Clarification guard** (new, at TOP of ambiguity section): "Domain profile and research context do NOT resolve workflow ambiguity. If a query would normally trigger a clarification question, it MUST still trigger that question even when the domain profile suggests a context."
- Ambiguity fork taxonomy: `variant_type`, `rnaseq_type`, `sequencing_type`, `docking_type`, `admet_scope` (new), and others
- Extracted fact schema: `data_type`, `file_reference`, `parameter`, `organism`, `condition`, `comparison`
- JSON output schema with `is_sequential`, `intents[]`, `facts[]`, `workflowAmbiguity`

### Context Injected
- **`<session_memory>` block** (new): async-maintained summary from `SessionMemoryUpdater` — includes active task, key decisions, uploaded files, prior workflow attempts, parameters, open questions. Empty string on first turn.
- User message (current turn)
- `accumulatedFacts` from prior turns in the session (factual supersession enabled)

### Output Use
Routes the entire conversation — determines whether to run workflow generation, tool search, research synthesis, etc. UQU fields (`preferredDomains`, `keyTerms`) are threaded through to the backend FTS query and domain scoring.

### Assessment
**Strong.** The prompt is precise and produces reliable JSON. The fact-extraction mechanism is well-designed. The clarification guard (domain profile ≠ intent resolution) correctly separates search bias from ambiguity resolution.

**Note — `drug_discovery` is a domain classifier, not an intent type.** It is detected by keyword regex (`ADMET`, `docking`, `SMILES`, `hERG`, etc.) and sets the `domain` field used for search bias and response formatting rules. It does not alter intent routing — all drug discovery queries still flow through `workflow_generation`, `research_question`, etc. When the domain is `drug_discovery`, the response prompt injects additional rules: structured sections (workflow phases, decision gates, required inputs), and "at least TWO targeted follow-up questions" when the workflow cannot be generated. This is a response quality enforcement layer, not a separate intent path.

**Remaining gap:** The intent prompt still does not tell the model *which workflows it can generate* — if the user asks for something obscure, the model routes to `workflow_generation` regardless of whether a matching workflow exists. `key_terms` mitigates this (narrows FTS search) but doesn't eliminate it.

---

## Call Site 2: Response Generation
**File:** `frontend/server/galaxy-assistant.ts`, `generateResponse()`
**Model:** `claude-sonnet-4-6` (high quality, cached)
**Usage:** Final user-facing reply — the text the researcher reads

### System Prompt Structure
A cached block containing:
- **Capability statement** (static, manual): "2,177 bioinformatics tools", workflow types, data formats supported
- **DATA-FIRST rule**: Never generate a workflow without knowing what data is available; enumerate accession patterns (SRA, ENA, GEO, ArrayExpress), file uploads, SMILES strings
- **ONE-QUESTION rule**: Maximum one clarifying question per turn — the default prevents form-like interrogation. Exception: when a workflow cannot proceed without two simultaneously missing pieces (e.g., molecule AND endpoint scope for ADMET), the `drug_discovery` domain rules explicitly require "at least TWO targeted follow-up questions". The rule is therefore "one question unless multiple pieces are structurally required to proceed"
- **Drug discovery routing hints** (hand-curated): Named tools and when to use them — AMBER, GROMACS, Schrödinger Glide, MOE, REINVENT4, DiffDock, AutoDock Vina, AiZynthFinder, AlphaFold
- **Response style rules**: Markdown, clinical language, no hallucination warnings

### Context Injected
- **`<session_memory>` block** (new): same memory block as Call Site 1 — Sonnet sees prior decisions and open questions when composing the final response
- **Domain profile prefix**: If user has a saved research domain, prepended as: "User research domains: [domains]. Use this as additional context for workflow search and response generation."
- **Last 6 chat turns** (sliding window — older context dropped)
- Tool ranking results (if tool search ran)
- Workflow diagnostics JSON (if workflow generation ran)
- Dataset search results (if relevant)

### Output Use
The message shown to the user. Suggestions (generated by `generateSuggestions()`) are returned as a separate `suggestions: string[]` array in the JSON response — they must not be embedded in the chat text as inline recommendations. The UI renders them as potential next-step actions that the user can choose to invoke, not as BioMate's advice.

### Assessment
**Partially strong.** The behavioral rules are excellent. The session memory injection closes the long-session coherence gap (information from beyond the 6-turn window is now available). Three capability-statement gaps remain:

1. **Static counts drift**: "2,177 tools" is not computed from the live DB — it will become stale
2. **Drug workflow list is hand-curated**: The response prompt explicitly names AMBER, GROMACS, etc. — if a new tool is added, it won't appear here unless the prompt is manually updated
3. **No general workflow awareness**: The model cannot enumerate all runnable workflows

---

## Call Site 3: Tool Ranking
**File:** `frontend/server/galaxy-assistant.ts`, `rankToolsByRelevance()`
**Model:** `claude-haiku-4-5` (fast, cached)
**Usage:** Ranks a retrieved list of tools/workflows by relevance to the user's query

### System Prompt Structure
- Score each tool 0.0–1.0 based on relevance to the user's stated need
- Return JSON array of `{tool_id, score}` sorted descending
- Considers tool name, category, keywords

### Context Injected
- User query
- Tool list: `{name, id, category, keywords}[]` (typically 5–20 results from Galaxy tool search)
- Optional `userPatternsService.formatContextForPrompt(userContext)` — behavioral patterns from prior sessions

### Assessment
**Good.** Tool-anchored — the model can only rank what it's given, preventing hallucination. The ranking score (0.0–1.0) produced by Haiku is currently discarded before the UI renders. Surfacing it is not necessary — confirmation is required from the user regardless of the score, so adding a percentage would add noise without changing behavior.

---

## Call Site 4: Clarification Generation
**File:** `frontend/server/galaxy-assistant.ts`, `_generateClarificationQuestion()`
**Model:** `claude-haiku-4-5`
**Usage:** When intent is ambiguous, generates the specific clarifying question to ask

### System Prompt Structure
- Expert bioinformatics assistant
- Given `ambiguityType`, generate exactly ONE targeted question
- Examples of ambiguity types: germline vs somatic, bulk vs single-cell, organism not specified, **docking_type** (blind vs site-directed), **admet_scope** (new)

### Context Injected
- User message
- `ambiguityType` string from intent analysis
- Optional recent workflow/session context

### Assessment
**Good.** Narrow and well-specified. The clarification is always derived from a typed ambiguity category, preventing vague questions. `CLARIFICATION_FALLBACKS` provides a deterministic backup for each `ambiguityType` — if Haiku is unavailable, the system still returns a usable question.

**Gap:** The fallback map contains 8 entries. As new ambiguity types are added (e.g., `admet_scope`), the fallback map must be manually updated — there is no automated check that every entry in the system prompt's fork-point list has a corresponding fallback.

---

## Call Site 5: Domain Inference
**File:** `frontend/server/galaxy-assistant.ts`, `_inferDomainWithLLM()`
**Model:** `claude-haiku-4-5`
**Usage:** Infers the research domain when it can't be determined from facts or profile

### System Prompt Structure
- Map user intent to one of: `genomics`, `proteomics`, `metabolomics`, `drug_discovery`, `structural_biology`, `imaging`, `microbiome`, `clinical`, `general`
- JSON output: `{domain_hint, confidence, reasoning}`
- Rules per domain (e.g. drug discovery triggers on SMILES, compound names, docking)

### Context Injected
- User intent text
- Optional current workflow name and recent context

### Assessment
**Good.** The domain rules are clear. **Gap:** The domain taxonomy has 14 entries but this prompt uses ~9 — Bioconductor-specific domains (epigenetics, single-cell trajectory, spatial transcriptomics) may not be caught and will default to `genomics`.

---

## Call Site 6: Session Summary (Context Compression)
**File:** `frontend/server/galaxy-assistant.ts`, `_triggerSessionSummary()`
**Model:** `claude-haiku-4-5`
**Usage:** When conversation overflows the 6-turn window, generates a summary for LTM

### System Prompt
- Compress a dropped message batch into a 2–3 sentence summary
- Preserve: goals, tools mentioned, data types, workflow names, errors

### Context Injected
- Truncated dropped messages (~4000 chars)

### Assessment
**Partially resolved.** The session memory (Call Site 14) now provides a parallel, higher-quality long-session coherence mechanism. The session summary is still generated but is a supplement rather than the primary mechanism.

**Bug still open:** The summary is POSTed to `${GALAXY_URL}/api/memory/session-summary`, but the Galaxy backend defines this route as `/api/ai_assistant/memory/session-summary`. This URL mismatch means summaries don't reach the Python LTM backend. (The Drizzle DB on the frontend Express server does receive them.)

---

## Call Site 7: Prerequisite Validation LLM Analysis
**File:** `frontend/server/workflow-prerequisites-validator.ts`
**Model:** `claude-sonnet-4-5`
**Usage:** Structured analysis of whether workflow requirements are met

### System Prompt Structure
- JSON schema output: `{paramMappings[], missingParams[], suggestions[]}`
- Given workflow requirements and available datasets/parameters, determine what's missing

### Context Injected
- Required inputs and parameters for the workflow
- Available datasets (from Galaxy or uploaded)
- Tool documentation snippets

### Assessment
**Good.** Strongly schema-constrained. **Gap:** "tool documentation snippets" depends on what was retrieved — if the workflow is novel (not in `tool_knowledge` table), documentation may be empty, leading to less precise validation.

---

## Call Site 8: Workflow Search LLM Re-ranking (Pass-0)
**File:** `backend/lib/galaxy/ai/unified_workflow_search.py`, `_browse_catalog_with_llm()`
**Model:** Fast model via `LLMClient` (typically `claude-haiku-3-5`)
**Usage:** When FTS returns too many candidates, LLM re-ranks up to 60 rows

### Prompt Structure
- "You are a bioinformatics workflow recommender"
- Numbered list: `id. workflow_name: description` (descriptions capped at 120 chars)
- Return JSON array of IDs in preference order

### Context Injected
- User query
- Up to 60 FTS candidate rows (name + truncated description)

### Assessment
**Good.** The model can only choose from provided IDs — no hallucination possible. **Gap:** 120-char description truncation may lose important details for distinguishing similar workflows (e.g., multiple ADMET workflows with similar names). Consider 200 chars for drug discovery workflows which often have long, similar names.

---

## Call Site 9: Error Explanation
**File:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`, `explain_workflow_error()`
**Model:** `claude-haiku-4-5` (requires `ANTHROPIC_API_KEY`)
**Usage:** When a workflow fails, generates a human-readable explanation

### System Prompt Structure
- Nextflow debugging assistant
- JSON output: `{error_type, human_summary, suggested_fix, chat_prompt}`
- Error types: `missing_file`, `docker_pull`, `resource_limit`, `missing_parameter`, `process_error`, `configuration`, `unknown`

### Context Injected
- Last 30 lines of the Nextflow log
- Optional `run_id` and `workflow_name`

### Assessment
**Good.** The log-only approach is sensible. **Gap:** 30 lines may not be enough for cascading failures where the root cause appears earlier in the log. DeerFlow uses 50-line windows for diagnostic calls.

---

## Call Site 10: Multi-task Classification
**File:** `backend/lib/galaxy/ai/ai_assistant.py`, `_classify_multi_task_llm()`
**Model:** Fast model (`claude-haiku-3-5`)
**Usage:** Gate deciding whether a query needs multi-step decomposition

### Prompt
- JSON output: `{is_multi_task, task_count, reason}`
- Rules for what constitutes multiple distinct tasks

### Assessment
**Adequate.** Simple binary classification — low risk of over-engineering. The frontend's `analyzeIntent()` now covers this via `is_sequential` + `intents[]`, so this backend call may be partially redundant. Should be reconciled.

---

## Call Site 11: Galaxy Workflow Generation
**File:** `backend/lib/galaxy/ai/galaxy_workflow_generator.py`, `_generate_workflow_structure()`
**Model:** Configured model (typically Sonnet-class via `LLMClient`)
**Usage:** Generates Galaxy `.ga` workflow JSON

### Prompt Structure
- Domain phases (Input → QC → Analysis → Output)
- **AVAILABLE TOOLS** block: exact `tool_id` strings from `tool_knowledge` DB
- Tool priority rules: local tools vs ToolShed
- JSON output schema for workflow steps

### Assessment
**Strong.** Fully tool-grounded — the model can only use tool IDs that were retrieved from the DB. This prevents hallucinating tool names. **Gap:** If FTS misses a relevant tool, the model cannot use it.

---

## Call Site 12: Nextflow Composition
**File:** `backend/lib/galaxy/ai/nextflow_composer.py`
**Model:** Configured model (Sonnet-class via `LLMClient`)
**Usage:** Generates Nextflow DSL2 `main.nf` files

### Prompt Structure
- Expert Nextflow DSL2 engineer persona
- **AVAILABLE TOOLS** block from the catalog
- DSL2 conventions, nf-core style, NF-wrapper vs generate rules
- Output: raw `main.nf` text

### Assessment
**Good.** DSL2 conventions are explicitly stated. **Gap:** Generated NF files may reference processes that don't have matching module definitions in the repo — the generator cannot verify that `SAMTOOLS_SORT` exists in `nf-core-modules`. A post-generation module existence check would catch this before the workflow is shown to the user.

---

## Call Site 13: Workflow Modification Classification
**File:** `backend/lib/galaxy/ai/workflow_modification_classifier.py`
**Model:** `claude-haiku-4-5`
**Usage:** Parses chat messages like "skip adapter trimming" into structured `WorkflowModification` objects

### Prompt Structure
- JSON schema for `WorkflowModification`
- nf-core skip flag examples (e.g., `skip_fastqc: true`)
- Handles: skip steps, change parameters, add steps, enable/disable features

### Assessment
**Strong.** The nf-core flag injection means the model knows the actual parameter names. **Gap:** Custom BioMate workflows may have different parameter names not covered by the nf-core examples.

---

## Call Site 14: Session Memory Update *(NEW — added 2026-03-31)*
**File:** `frontend/server/galaxy-assistant.ts`, `SessionMemoryUpdater._update()`
**Model:** `claude-haiku-4-5-20251001`
**Trigger:** Async, debounced 30s after each turn completes
**Not on the critical path:** the main conversation path is never blocked by this call

### Purpose
Maintains a compact structured summary of the session in the `SessionMemory` struct:
```typescript
{
  active_task: string,            // "designing EGFR inhibitor docking pipeline"
  key_decisions: string[],        // ["using AlphaFold3 for structure; ADMET first"]
  uploaded_files: string[],       // ["egfr_apo.pdb", "library_1000.sdf"]
  attempted_workflows: {path, status}[],  // ["drug_discovery/docking/main.nf → failed"]
  current_parameters: Record<string,any>, // {"receptor": "egfr_apo.pdb", "exhaustiveness": 16}
  open_questions: string[],       // ["user hasn't specified the binding pocket residues"]
}
```

### System Prompt
- "You are maintaining a session memory for a bioinformatics research session"
- Instructions to update incrementally — carry forward what is still relevant, update what has changed
- Schema enforcement: active_task (1 sentence), key_decisions (max 8), uploaded_files (all files mentioned), attempted_workflows (with outcome), current_parameters (concrete values), open_questions (unresolved items)
- `max_tokens=600` — compact by design

### Context Injected
- User message (current turn)
- Assistant response (current turn)
- Current memory state (for incremental update)

### Output Use
Stored in `memoryBySession` Map (per `sessionId`). Retrieved at the start of the **next** turn and injected into Call Sites 1 and 2 as the `<session_memory>` block.

### Reliability Mechanisms
- **30s debounce**: If another turn arrives within 30s, the earlier timer is cancelled — only the latest pair is processed (same as DeerFlow's MemoryQueue pattern)
- **TTL eviction**: Sessions idle >2h are removed from memory (amortized on each write via `_evictStale()`)
- **Type guards after JSON.parse**: All six fields validated before storage; malformed LLM output falls back gracefully rather than crashing
- **Zero-cost on first turn**: `get(sessionId)` returns `null` when no memory exists → empty string injected

### Assessment
**Good (Phase 1 complete).** Memory is updated async and injected sync — main conversation path unblocked. Type guards prevent crash from malformed LLM output. TTL prevents unbounded Map growth.

**Phase 2 deferred:** In-memory only — session memory does not survive server restarts. DB persistence (`POST /api/memory/session-state`, SQLite `session_memory` table) is planned but not yet implemented.

---

## Cross-cutting Capability Assessment

### What BioMate clearly knows
- Its behavioral rules (DATA-FIRST, one-question)
- Domain routing (drug discovery → specific tools)
- nf-core skip flags for workflow modification
- Galaxy tool IDs when generation is running
- How to explain Nextflow errors
- Session-level context for turns 1–6 (sliding window) + prior turns via session memory

### What BioMate does NOT know (by design — retrieval-based)
- The full list of all runnable workflows (2,445+ rows in DB)
- Which workflows are currently passing CI / tested
- Whether a generated Nextflow module actually exists on disk
- Tool count that is live/current (static "2,177" will drift)

---

## Identified Gaps — Updated Status

| Gap | Severity | Status | Fix |
|-----|----------|--------|-----|
| Session summary POST URL mismatch (Call Site 6) | Medium | **Still open** | Align Galaxy route to `/api/memory/session-summary` OR change frontend to POST to `/api/ai_assistant/memory/session-summary` |
| Static capability counts in response prompt | Low | Still open | Replace with DB query at server startup; cache with 1h TTL |
| Drug discovery tool list hand-curated in prompt | Medium | Partially mitigated by `key_terms` routing | Add a DB-backed "featured drug discovery tools" section; regenerate on DB change |
| 30-line log truncation for error explanation | Low | Still open | Increase to 50 lines for cascade failures |
| `user_profile` not passed to `generate_workflow_unified` | Medium | Still open | Thread `preferred_domains` from Call Site 1 through to `unified_workflow_search` backend call |
| Bioconductor domains missing from domain inference | Low | Still open | Add `epigenomics`, `spatial_transcriptomics`, `single_cell_trajectory` to `_inferDomainWithLLM` |
| No fallback-map completeness check for `CLARIFICATION_FALLBACKS` | Low | **New** | Add a TypeScript compile-time check or vitest assertion that every fork-point key has a fallback entry |
| Input dataset visualization not implemented | Medium | **New** | Allow preview of uploaded/referenced datasets before workflow execution; wire to `/api/datasets/:id/preview` |
| Galaxy native visualization tools not connected (Trackster, Charts) | Medium | **New** | Connect `display_apps` for BAM/BigWig track viewing; Galaxy Charts for interactive result plots |
| Large file navigation truncated at 500 rows with no pagination | Medium | **New** | Add server-side cursor pagination or aggregation endpoint for CSV/TSV outputs beyond 500 rows |
| Session memory not persisted across server restarts | Medium | **Phase 2 deferred** | `POST /api/memory/session-state` + SQLite `session_memory` table |
| Call Site 10 multi-task gate may be redundant with `analyzeIntent()` `is_sequential` | Low | **New** | Audit whether backend `_classify_multi_task_llm` is still reachable in the current flow |

---

## Gap Solutions from DeerFlow and Claude Code Harness Analysis

After reading both reference projects in detail (`reference/deer-flow/` and `reference/claude-code/`), the following solutions are recommended for BioMate's open gaps.

---

### S1: ClarificationGate Middleware (from DeerFlow `ClarificationMiddleware`)

**Addresses:** Session-level ambiguity still occasionally bypassed; clarification check is an inline `if` in `processMessage()`.

**DeerFlow's approach** (`clarification_middleware.py`): `ask_clarification` tool calls are intercepted at `wrap_tool_call()` — **before** the tool executes — and a `Command(goto=END)` is returned, halting the entire agent loop. Execution pauses until the user responds. This is not a prompt-based rule — it's a hard interrupt.

**Proposed BioMate solution:**

Extract the inline ambiguity check in `processMessage()` into a discrete `ClarificationGate` function:

```typescript
function clarificationGate(intent: DecomposedIntent, context: ConversationContext): string | null {
  // Returns a clarification question string if one should be asked, null otherwise.
  // NOT the LLM's responsibility — this is a programmatic gate.
  if (intent.workflowAmbiguity) {
    return generateClarificationQuestion(intent.workflowAmbiguity, context);
  }
  if (intent.actions.needsWorkflowGeneration && !hasDataAvailable(context)) {
    return DATA_FIRST_QUESTION;
  }
  return null;
}
```

This makes the gate independently testable, removes it from the LLM's discretion, and prevents the ambiguity check from being accidentally bypassed when `processMessage()` is refactored. The gate becomes a mandatory step in the pipeline — not optional.

**Why this is better than the current approach:** The current implementation is an `if (ambiguity) return clarification` inside a long function. If `processMessage()` is refactored, the check could be moved below the workflow search, meaning a workflow might be returned alongside the clarification (confusing output). A gate function is impossible to bypass accidentally.

---

### S2: Confidence-Gated Memory Injection (from DeerFlow `confidence ≥ 0.7` pattern)

**Addresses:** Call Site 14 memory currently injects all `key_decisions` and `open_questions` unconditionally, including uncertain inferences the Haiku model hedged on.

**DeerFlow's approach** (`memory/updater.py`): Facts below 0.7 confidence are retained in storage but excluded from the injection block. Only high-confidence facts pollute the system prompt. Uncertain facts are preserved for future confirmation but not presented as established context.

**Proposed BioMate solution:**

Add `confidence` scores to `SessionMemory` fact items:

```typescript
export interface SessionMemory {
  active_task: string;
  key_decisions: Array<{ text: string; confidence: number }>;   // was: string[]
  uploaded_files: string[];
  attempted_workflows: Array<{ path: string; status: string }>;
  current_parameters: Record<string, any>;
  open_questions: Array<{ text: string; confidence: number }>;  // was: string[]
}
```

`_buildSessionMemoryBlock()` filters to `confidence ≥ 0.7` for injection. Lower-confidence items stay in storage for the Haiku memory updater to refine on subsequent turns, but don't enter the Sonnet system prompt as if they were established facts.

**Impact:** Prevents the common case where a hedged Haiku inference ("I think the user may be targeting EGFR") gets injected as a stated fact on the next turn, biasing Sonnet toward an incorrect assumption.

---

### S3: Connect Backend DomainSpecialistPool Results to Frontend Response Generation

**Addresses:** Gap — `generateResponse()` (Sonnet, Call Site 2) generates the final user-facing text without domain-specific guidance, even though the backend `DomainSpecialistPool` already ran per-domain specialists.

**What already exists:** `backend/lib/galaxy/ai/agents/domain_specialist.py` implements `DomainSpecialistPool` with per-domain prompts for genomics, transcriptomics, proteomics, metabolomics, single-cell, metagenomics, structural_biology, and pharmacology. Each specialist runs in a `ThreadPoolExecutor` in parallel. The prompts are tailored (e.g., pharmacology: "recommend tools for ADMET prediction, target identification, and safety assessment"). **This is not a gap in the backend** — the backend already has specialized domain reasoning.

**The actual gap:** The domain specialist results are used for tool ranking but are not forwarded to the frontend's `generateResponse()` call. Sonnet generates the final response without seeing what the domain specialist concluded. If the specialist identified that a docking query should use DiffDock (blind) over AutoDock Vina (site-directed) based on the context, that reasoning doesn't reach the response generator.

**Proposed fix:** Thread the domain specialist's output as an additional context block into `generateResponse()`:

```typescript
// In processMessage(), after backend specialist call:
const specialistContext = domainSpecialistResult?.reasoning ?? '';

// In generateResponse() system prompt:
if (specialistContext) {
  systemPrompt += `\n<domain_specialist_analysis>\n${specialistContext}\n</domain_specialist_analysis>`;
}
```

This is a connection fix (plumbing), not building new capability. The specialist already exists and reasons correctly — the response generator just needs to see its output.

---

### S4: Step-by-Step Approval Gate for Sequential Pipelines (from Claude Code phase-gate)

**Addresses:** UC-D5 and B4 sequential pipelines — currently all steps launch in sequence automatically after the user clicks "Run".

**Claude Code harness pattern** (`feature-dev` plugin): Each phase's output is accumulated as input to the next phase. A phase does not start until the previous phase has completed and its output has been reviewed. The agent writes `<promise>DONE</promise>` XML tags to signal completion, which the harness uses as an unambiguous state transition.

**Proposed BioMate solution:**

In `PipelineListView`, show each step's parameters and require confirmation before triggering execution of the next step:

```
Step 1: AlphaFold3 structure prediction  [Parameters: target=EGFR] → ✓ Complete
Step 2: AutoDock Vina docking  [Parameters: receptor=egfr.pdb, library=compounds.sdf]
        → [Review & Confirm] or [Adjust parameters]
Step 3: ADMET screening  (pending step 2 completion)
Step 4: Lead ranking  (pending step 3 completion)
```

This prevents a misconfigured step 3 from running automatically after step 2 completes. For drug discovery pipelines where each step costs real compute, this gate saves money and prevents data loss from propagated errors.

Implementation: `processMultiIntent()` already tracks `dependsOn` for each step. The gate would be: after step N's workflow is displayed, require a user action (confirm/adjust) before `executeStep(N+1)` is called.

---

### S5: Declarative Fallback-Map Completeness Check (from Claude Code rule-based patterns) (from Claude Code rule-based patterns)

**Addresses:** Gap — no automated check that every fork-point ambiguity type has a `CLARIFICATION_FALLBACKS` entry.

**Claude Code's approach** (`rule_engine.py`): Each rule is a typed dataclass with explicit `action` and `event` fields. Invalid configurations fail at load time (missing required fields raise exceptions). The rule system validates itself.

**Proposed BioMate solution:**

Add a vitest assertion that runs at test startup:

```typescript
// In a new describe block in analyze-intent-uqu.test.ts or a dedicated test:
describe('CLARIFICATION_FALLBACKS completeness', () => {
  const FORK_POINTS = [
    'variant_type', 'rnaseq_type', 'sequencing_type', 'docking_type', 'admet_scope',
    'organism_unspecified', 'assembly_version', 'genome_not_specified',
    // ... full list from system prompt
  ] as const;

  it('every fork-point has a fallback entry', () => {
    for (const fp of FORK_POINTS) {
      expect(CLARIFICATION_FALLBACKS).toHaveProperty(fp,
        `Missing fallback for ambiguity type: ${fp}`);
    }
  });
});
```

This makes adding a new ambiguity type to the system prompt automatically require a corresponding test update, preventing silent fallback gaps from shipping.

---

### S6 (implemented): Domain Catalog Injection — generalized pattern

**✅ Implemented 2026-03-31.** See `docs/nextPhase/auditing/20260331_SESSION_IMPLEMENTATION_S1_S2_S5_S6.md` for full details.

**What was built:** `DOMAIN_CATALOGS: Partial<Record<string, string>>` map + `buildDomainCatalogBlock(preferredDomains)` helper in `galaxy-assistant.ts`.

When `preferredDomains` (from the intent classifier + user profile) includes a domain that has a catalog entry, a `<domain_catalog>` XML block is injected into the `generateResponse()` system prompt.

**Design decision — domain signal vs keyword regex:**
The catalog injection uses `preferredDomains` (correct signal), not `isDrugDevelopmentQuery`
keyword regex (wrong signal — fires on message text rather than on user domain intent).

**Design decision — which domains get a catalog:**
Only domains where BioMate has built ≥4 non-obvious proprietary workflows. Currently: `drug_discovery` only. Standard-tool domains (genomics, transcriptomics…) are excluded because Claude already knows GATK, DESeq2, etc. — a catalog adds noise, not signal.

---

## LLM Budget Profile (approximate per query — updated)

| Stage | Model | Tokens ~in | Tokens ~out | When |
|-------|-------|-----------|------------|------|
| Intent analysis | Haiku | 1,200 (+300 session memory) | 300 | Every turn |
| Domain inference | Haiku | 400 | 100 | When ambiguous |
| Clarification | Haiku | 500 | 150 | When ambiguous |
| Tool ranking | Haiku | 1,000 | 200 | When tool search runs |
| Response | Sonnet | 3,000 (+300 session memory) | 600 | Every turn |
| Workflow gen (backend) | Sonnet | 4,000 | 1,500 | When workflow_generation intent |
| Pass-0 re-ranking | Haiku | 2,000 | 200 | Optional |
| Error explanation | Haiku | 1,500 | 300 | On failure |
| **Session memory update** | **Haiku** | **800** | **200** | **Async, debounced 30s, after turn** |

Typical full drug discovery query: ~12,600 input tokens, ~3,000 output tokens (mix of Haiku + Sonnet).
Session memory update: ~1,000 tokens total (async — not on critical path). Amortized across 30s window.

---

## Implementation Priority

| Solution | Effort | Impact | Status |
|----------|--------|--------|--------|
| S5: Fallback-map completeness test | 30 min | Prevents silent regressions | ✅ Done 2026-03-31 |
| S1: ClarificationGate function | 2h | Eliminates accidental bypass risk | ✅ Done 2026-03-31 |
| S2: Confidence-gated memory injection | 3h | Prevents uncertain inferences as stated facts | ✅ Done 2026-03-31 |
| S6: Domain catalog injection (generalized) | 2h | Improves workflow awareness per active domain | ✅ Done 2026-03-31 |
| S3: Connect DomainSpecialistPool → generateResponse() | 2h | Eliminates specialist reasoning dead-end | Next session |
| S4: Step-by-step pipeline approval | 4h | Critical for multi-step safety + cost | Next sprint |
| Input dataset visualization | 3h | Lets users preview data before running workflows | Next sprint |
| Galaxy Trackster / Charts connection | 5h | Unlocks native genomics/proteomics visualization | Future |
| Large file pagination (>500 rows) | 3h | Essential for proteomics/metabolomics results | Next sprint |
| Phase 2 session memory DB persistence | 4h | Cross-restart durability | Defer |

### S6 Design Note — Why only drug_discovery has a catalog entry

`DOMAIN_CATALOGS` in `galaxy-assistant.ts` is a `Partial<Record<string, string>>` map.
The catalog block is injected when `preferredDomains` (from intent classifier + user profile)
contains a domain that has a catalog entry — **not** via keyword regex on the message text.

Only `drug_discovery` is populated today because:
1. BioMate has built 8 proprietary/licensed drug discovery workflows that Claude cannot infer
   from general bioinformatics knowledge (REINVENT4, MOE CovDock, Schrödinger Glide, etc.).
2. Standard domain tools for other domains (GATK, DESeq2, BWA, CryoSPARC…) are well-known
   to Claude — listing them adds no information.

**Rule for adding new entries:** Add to `DOMAIN_CATALOGS` when BioMate has ≥4 workflows for a
domain that use tools/modes the LLM cannot infer from general knowledge. Current candidates:
- `cryo_em` — once SPA + helical + subtomogram workflows are built
- `lab_automation` — once PyLabRobot liquid handling workflows are published
