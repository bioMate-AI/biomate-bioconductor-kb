# BioMate AI Personalization and User Adaptation Audit
**Date:** 2026-03-30  
**Purpose:** Pre-release assessment of user-adaptation mechanisms, with concrete use cases and gap analysis

---

## Overview

BioMate has **five personalization dimensions**: research domain profile, behavioral patterns (tool usage history), within-session factual memory, long-term memory (LTM) via correction logs and workflow outcomes, and context compression/summary. The mechanisms are partially wired — the infrastructure exists but some critical connections between components are missing.

**Overall personalization grade: C+**  
Good infrastructure, incomplete wiring. A user with a saved domain profile does not reliably get different search results than one without.

---

## Mechanism 1: Research Domain Profile

### What It Is
A user-set declaration of their research domains and specific topics, stored in the database and retrieved per-session.

### Components
- **`domain_taxonomy.py`**: 14 research domains, each with 5–15 example topics
  - Domains: `genomics`, `proteomics`, `metabolomics`, `structural_biology`, `drug_discovery`, `immunology`, `neuroscience`, `oncology`, `microbiome`, `epigenetics`, `single_cell`, `systems_biology`, `bioinformatics_methods`, `clinical_genomics`
- **`POST/GET /api/user/domain-profile`**: Stores domains and topics as a `UserPreference` row in the database
- **`ResearchProfilePanel` in `research-profile.tsx`**: UI for selecting domains; shows workflow recommendation preview
- **In-memory cache**: 5-minute cache per user ID in `galaxy-assistant.ts`

### How It Affects the AI

**Effect 1: System prompt prefix (Frontend)**
```
"User research domains: oncology, drug_discovery.
Topics: EGFR targeting, kinase inhibitors, ADMET profiling.
Use this as additional context — current conversation takes priority."
```
This prefix is added to the response-generation system prompt when the user has set a profile. The LLM sees it and can use it to color its answers.

**Effect 2: Workflow search bias (Backend — PARTIALLY WIRED)**
In `unified_workflow_search.py`, when `search()` is called with `user_profile`, workflows whose DB `domain` matches the user's domains get a `+2` score bonus.

**Critical gap:** `AIAssistant.generate_workflow_unified()` calls `self.workflow_search.search(trial, limit=5)` WITHOUT passing `user_profile`. So the domain profile bias is **not applied** during the main workflow generation path. The +2 bonus only applies when `search()` is called explicitly with the profile argument.

### Use Case (Ideal vs Actual)

**Scenario:** User has set domain profile: `oncology, drug_discovery`. They ask: "help me analyze my expression data."

**Ideal behavior:** System searches for oncology-specific RNA-seq or drug mechanism workflows, boosts results from the pharmacology and drug_discovery domain folders.

**Actual behavior:** The query "analyze expression data" produces the same FTS results regardless of domain profile. The system prompt prefix mentions oncology, so the response text may reference oncology context, but the workflow selected comes from keyword-only scoring.

**Fix needed:** Pass `get_domain_profile(user_id)` result into `generate_workflow_unified()` → `workflow_search.search()`.

---

## Mechanism 2: Behavioral Patterns (Usage History)

### What It Is
An analysis of the user's historical tool usage, compiled into a `UserContext` object and injected into tool ranking.

### Components
- **`user-patterns-service.ts`**: Fetches `/api/user-patterns/insights`, 5-minute cache
  - Returns: `dominantDomain`, `preferredTools[]`, `expertise` level, `usedDataTypes[]`
- **`formatContextForPrompt(userContext)`**: Formats this into a short text block:
  ```
  "User context: Typically works on genomics.
   Has used these tools: STAR, HISAT2, DESeq2.
   Expertise: intermediate."
  ```

### How It Affects the AI

Injected into the **tool ranking system prompt** (`rankToolsByRelevance`). The ranking LLM sees user history and can weight familiar tools higher.

### Use Case

**Scenario:** A user regularly works with single-cell RNA-seq and has used Seurat, Scanpy, and Cell Ranger in prior sessions.

**When they ask:** "what tool should I use for clustering?"

**Behavior:** Tool ranking sees `preferredTools: [seurat, scanpy, cell_ranger]` and can rank Seurat/Scanpy higher than an unfamiliar clustering tool.

**Limitation:** This only affects the text response and tool search rankings — not the workflow generator itself. If the user's workflow is automatically generated, the generator does not see usage history.

---

## Mechanism 3: Within-Session Factual Memory

### What It Is
Structured extraction and persistence of facts from the conversation, with explicit supersession support.

### Components
- **`ExtractedFact`** type: `{id, category, value, confidence, supersedes?}`
- **Fact categories**: `data_type`, `file_reference`, `parameter`, `organism`, `condition`, `comparison`, `timeline`, `constraint`
- **`accumulatedFacts`**: Loaded from `ConversationStateManager` at the start of each turn; passed to intent analysis
- **`supersedes`**: When the user says "actually it's human not mouse," the new fact can supersede the old one

### How It Affects the AI

The intent analysis prompt section "Existing Facts from Prior Turns" shows the model all currently-active facts. This prevents:
- Re-asking questions already answered
- Keeping stale facts after correction
- Treating the same query differently each turn

Facts are persisted to the database via `saveState` after each turn, so they survive page refreshes within the same session.

### Use Case

**Multi-turn EGFR study planning:**

> Turn 1: User: "I want to analyze EGFR signaling in lung cancer cell lines"
> 
> Facts extracted: `{organism: "human", condition: "EGFR signaling", tissue: "lung cancer cell line"}`
>
> Turn 2: User: "I have 6 samples, 3 treated with gefitinib and 3 controls, paired-end 150bp Illumina"
>
> Facts extracted: `{data_type: "RNA-seq", n_samples: 6, comparison: "gefitinib vs control", sequencing: "PE150", platform: "Illumina"}`
>
> Turn 3: User: "run the workflow"
>
> The system has all facts — no re-asking. Generates workflow for human RNA-seq, 6 samples, PE150, gefitinib comparison.

**Assessment: Strong.** This mechanism works well within a session. It is the most reliable personalization layer currently.

---

## Mechanism 4: Long-Term Memory (LTM)

### What It Is
Persistent storage of user interactions, corrections, and workflow outcomes across sessions.

### Components (Python LTM stack)
- **`AgenticMemoryService`**: Main service class
  - `record_interaction(user_id, session_id, ...)`: Stores conversation turns
  - `record_workflow_outcome(user_id, workflow_id, success, ...)`: Records execution results
  - `get_recent_corrections(user_id, limit=10)`: Retrieves correction history
  - `update_domain_profile(user_id, domains, topics)`: Stores domain preferences
- **`CorrectionLog` table**: Stores user-made corrections ("I said mouse but meant human")
- **`ProjectEpisode` table**: Full interaction episodes, searchable

### How It Affects the AI

**Correction injection:** In `AIAssistant.generate_workflow_unified()`:
```python
recent_corrections = memory_svc.get_recent_corrections(user_id, limit=10)
if recent_corrections:
    correction_text = "\n".join([f"- {c.description}" for c in recent_corrections])
    user_intent = f"{user_intent}\n\nUser correction history:\n{correction_text}"
```
This prepends the user's history of corrections to the workflow generation query. If a user repeatedly corrected "mouse" to "human," future generations would see this pattern.

**Workflow outcome learning:** 
- Successful workflows → incremented usage counts
- Failed workflows → `WorkflowLearningService.learn_from_workflow_outcome()`
- Chain usage → `UnifiedWorkflowSearch.record_chain_run()` updates `success_rate`

### Frontend LTM Stack (separate)

A parallel memory system using Drizzle ORM and a frontend DB:
- **`memory-repository.ts`**: Frontend memory operations
- **`processWithMemory()`**: Used when `memorySessionId` AND `projectId` are both set
- **`addMemoryHints()`**: Prepends a synthetic assistant message with memory context

**Key limitation:** Most chat sessions use the standard path, not `processWithMemory`. The memory path is only activated when the request explicitly includes both `memorySessionId` and `projectId`. In practice, the standard UI session may not set these.

### Use Case

**Cross-session personalization:**

> Session 1 (Monday): User runs nf-core/rnaseq, it fails on STAR alignment. They say "the STAR step failed because the genome index is outdated." This is logged as a CorrectionLog.
>
> Session 2 (Thursday): User asks to run RNA-seq again. Their correction history ("STAR genome index outdated") is prepended to the workflow generation query. The system may generate a workflow with `--genome GRCh38 --star_index /path/to/fresh/index` as a suggested parameter.

**Assessment: Partial.** The correction injection works IF `MEMORY_AVAILABLE` and the memory service is properly connected. The frontend memory path (`processWithMemory`) is not reliably triggered. Two memory stacks (Python LTM + frontend Drizzle) create maintenance complexity and may diverge.

---

## Mechanism 5: Context Compression and Session Summary

### What It Is
When a conversation exceeds the 6-turn sliding window, older context is compressed into a summary that can be stored and potentially reloaded.

### How It Works
1. When `conversationHistory.length > CONTEXT_WINDOW (6)`, `_triggerSessionSummary()` is called
2. Haiku generates a 2–3 sentence summary: goals, tools, data types, errors
3. Summary is POSTed to `/api/memory/session-summary`

**Critical gap:** The summary is saved, but it is **not** prepended to the next prompt. The system has a 6-turn window and drops older context. If the summary were loaded and reinjected at the start of the system prompt, long conversations would be coherent. Currently, turn 7+ is lost from the model's context (though facts may still be available via `accumulatedFacts`).

**Additional gap:** The POST URL may not reach the Galaxy backend (see LLM Audit doc). The frontend Express server handles `/api/memory/session-summary` locally.

### Use Case (Limitation)

**Long drug discovery session:**

> Turns 1-6: User defines the target (EGFR), uploads PDB, sets ADMET parameters, reviews results
>
> Turn 7: User: "Based on everything we've discussed, what's the next step?"
>
> **Actual behavior:** The model only sees turns 2-7 (the last 6). Turn 1 (target definition) is dropped. The system may ask for the target again, or give a generic answer, unless the target was captured as a fact.
>
> **Factual memory rescue:** If "EGFR" was captured as an `organism/target` fact in turn 1, it persists. The AI sees "target: EGFR" in the facts section even though the original turn is gone.

---

## Gap Summary and Recommendations

### Critical Gaps

| Gap | Impact | Fix |
|-----|--------|-----|
| Domain profile not passed to `generate_workflow_unified` | Medium — vague queries get wrong workflows | Add `user_profile` arg to search call |
| `buildMemoryContextPrompt` not used in production | Medium — LTM corrections not in chat context | Wire into `processMessage` for memory-enabled sessions |
| Session summary not reinjected into prompt | Medium — long sessions lose coherence | Prepend compressed summary to system prompt when available |
| Session summary POST URL misalignment | Low — summaries may not reach Galaxy LTM | Align route to Galaxy backend API path |
| `topics` from domain profile unused in scoring | Low — domain matching is coarse (domain only) | Use topics as additional keyword signals in `_calculate_score` |

### What Works Well

1. **Within-session factual memory** — robust, DB-backed, with supersession support
2. **Tool ranking with usage history** — users get familiar tools ranked higher
3. **Domain profile in response prompt** — the LLM's text acknowledges the user's research area
4. **Correction log injection** — cross-session corrections do influence workflow generation
5. **Domain inference** — the system makes reasonable guesses about domain when profile is absent

### Concrete Use Cases That Work Today

**Use Case 1: Sequential clarification**
User mentions "mouse EGFR samples" then corrects to "human" in the next turn. The supersession mechanism correctly updates the organism fact. Subsequent workflow generation uses human genome parameters.

**Use Case 2: Domain-aware response**
User has saved domain profile: `drug_discovery, pharmacology`. Their chat response to "what should I run next?" includes ADMET and docking tool suggestions rather than generic bioinformatics tools. The LLM's text is personalized even if workflow ranking is not.

**Use Case 3: Tool preference nudge**
User has historically used Bowtie2 for alignment. When they ask "what aligner should I use for ChIP-seq?", Bowtie2 appears higher in tool rankings than STAR or BWA, matching their established workflow.

**Use Case 4: Cross-session correction**
User ran nf-core/rnaseq twice with wrong strandedness. They corrected it manually both times. On the third session, the correction history includes "RNA-seq strandedness should be 'reverse'" and the system may suggest this parameter proactively.

### Concrete Use Cases That Do NOT Work Yet

**Use Case 5: Domain-biased search**
User with `oncology` profile asks "analyze my expression data" (vague). System should boost cancer-relevant RNA-seq workflows, but currently gives the same results as an anonymous user.

**Use Case 6: Long-session coherence**
A 20-turn drug discovery session. By turn 15, the original target definition, uploaded files, and ADMET results are all out of the 6-turn window. The AI has no recollection of what compound library was uploaded in turn 2.
