# DeepAgents / AgentHarness — BioMate Optimization Analysis

**Date:** 2026-03-21
**Branch:** connection_formal
**Status:** Draft — open for editing

---

## 1. What Is DeepAgents?

DeepAgents is a production-ready agent framework from LangChain built on top of LangGraph. It provides a "batteries-included" harness that wraps any LLM into an autonomous agent capable of planning, delegating subtasks, and persisting knowledge.

Core identity: **Agent = Model + Harness**

The *harness* supplies everything the model lacks natively:
- Planning & task decomposition
- Filesystem / state management
- Subagent spawning and delegation
- Context summarization
- Human-in-the-loop interrupts
- Persistent long-term memory

**Key repositories:**
- Python SDK: `github.com/langchain-ai/deepagents`
- JavaScript SDK: `github.com/langchain-ai/deepagentsjs`
- UI component: `github.com/langchain-ai/deep-agents-ui`
- Docs: `docs.langchain.com/oss/python/deepagents/overview`

---

## 2. AgentHarness Architecture

### 2.1 Primary Entry Point

```python
from deepagents import create_deep_agent
from langchain.chat_models import init_chat_model

agent = create_deep_agent(
    model=init_chat_model("anthropic:claude-sonnet-4-6"),
    tools=[custom_tool_1, custom_tool_2],
    system_prompt="Custom instructions..."
)
# Returns CompiledStateGraph (LangGraph)
result = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
```

### 2.2 Middleware Stack (Modular Extensibility)

Each middleware component defines state schemas, provides tools, and modifies system prompts:

| Middleware | Purpose |
|---|---|
| `PlanningMiddleware` | `write_todos` — task decomposition + progress tracking |
| `FilesystemMiddleware` | `read_file`, `write_file`, `edit_file`, `ls`, `glob`, `grep` |
| `SubAgentMiddleware` | `task` tool — spawn isolated subagents for delegation |
| `SummarizationMiddleware` | Auto-compress long contexts |
| `AnthropicPromptCachingMiddleware` | Reduce API costs (optional) |
| `LocalContextMiddleware` | Discover `cwd` and available tools at agent start |
| `PreCompletionChecklistMiddleware` | Verify outputs before agent exits |
| `LoopDetectionMiddleware` | Prevent infinite edit loops |

### 2.3 Multi-Agent Coordination Patterns

Four patterns supported:

1. **Subagents** — Supervisor spawns specialized agents with context isolation
2. **Skills** — Load domain-specific prompts/knowledge on-demand
3. **Handoffs / Routers** — Agents transfer control via tool calls
4. **Filesystems** — Natural collaboration surface (agents write files; others read)

### 2.4 Filesystem Backends (Pluggable)

| Backend | Use Case |
|---|---|
| `StateBackend` | Ephemeral in-memory (dev/test) |
| `FilesystemBackend` | Persist to disk |
| `StoreBackend` | Persist via LangGraph Store (cross-session) |
| `LocalShellBackend` | Real filesystem + shell execution |
| `CompositeBackend` | Route different paths to different backends |

### 2.5 LangGraph Runtime (Production Features)

DeepAgents returns a `CompiledStateGraph`, giving access to:
- **Streaming** — Token/event streaming
- **Checkpoints** — Save and resume graph state
- **Studio** — LangSmith visualization + debugging
- **Human-in-the-loop** — Interrupt → human review → resume
- **State rollback** — Deterministic execution with undo

---

## 3. BioMate Current Agent Architecture (Summary)

### 3.1 What Exists Today

| Component | File | Status |
|---|---|---|
| `UnifiedIntentRouter` | `agents/unified_intent_router.py` | ✅ Active — every request |
| `ResearchAgent` | `agents/research_agent.py` | ✅ Active — triggered only for `research_question` intent |
| `SkillLoader` | `agents/skill_loader.py` | ✅ Active — loads from 24+ SKILL.md files in `research_repos/claude-scientific-skills-biomate/`; called via ResearchAgent |
| `ToolKnowledgeProvider` | `tool_knowledge_provider.py` | ✅ Active — 12,274 tools, citations + param recommendations injected into every workflow |
| `AutoFix3Orchestrator` | `workflow_ops/autofix/autofix3_orchestrator.py` | ✅ Active — triggered on workflow failure |
| `AgentSystem` (15 capability types) | `workflow_ops/agent_system.py` | ✅ Implemented |
| `AgentOrchestrator` | `agents/agent_orchestrator.py` | ❌ Dead code — fully implemented (554 lines) but never called; endpoint exists but no frontend path invokes it |
| `DomainSpecialists (×8)` | `agents/domain_specialist.py` | ❌ Dead code — only reachable via AgentOrchestrator which is never called |
| `WorkflowAssembler` | `agents/workflow_assembler.py` | ❌ Dead code — same as above |
| `BenchmarkKnowledgeDB` | `benchmark_knowledge.py` | ✅ Active — 334 tools have benchmark papers in `galaxy_ai_tools.db` via `tool_knowledge_provider.py`; the benchmark evidence / scientific rationale surface in the workflow generation response already covers this aspect. `benchmark_knowledge.db` (advanced semantic query DB) intentionally unpopulated — not needed, scientific_rationale handles that use case. |
| LangGraph StateGraph | — | ⚠️ Foundation only (v1.1.2 installed, not wired) |
| Agentic Memory (LTM) | `memory/agentic_memory.py` | ⚠️ Schema complete, PostgreSQL tables exist, not fully wired into request path |

### 3.2 Current Orchestration Flow (Actual Production Path)

```
User Query
  → UnifiedIntentRouter (Haiku, classify 9 intents)
  → if research_question: ResearchAgent → SkillLoader (SKILL.md prompts) → literature search
  → else: UnifiedWorkflowSearch (2,285 workflows, SQLite FTS5)
       — 1,818 bioconductor_nf + 465 nextflow (nfcore/biomni) + 2 galaxy
  → ToolKnowledgeProvider (12,274 tools, citations + param recommendations)
  → GalaxyWorkflowGenerator / NextflowComposer
  → Execution (AWS Batch / Galaxy / CryoSPARC)
  → AutoFix3 (on failure, 10 specialized tools)

NEVER CALLED (dead code):
  AgentOrchestrator → DomainSpecialists × 8 → WorkflowAssembler
  (endpoint exists at /api/ai_assistant/generate_workflow_multi_agent but no frontend code invokes it)
```

### 3.3 Key Gaps in Current Design

1. **No formal state machine** — direct Python method calls, hard to observe/resume
2. **LangGraph not yet wired** — foundation laid (`pending_tasks` table, v1.1.2 installed) but StateGraph not implemented
3. **Memory feedback loop missing** — correction logs exist, not used for improvement
4. **benchmark_knowledge.db unpopulated** — not a gap; scientific_rationale in workflow generation already covers benchmark evidence presentation. `benchmark_knowledge.db` advanced semantic queries are not needed.
5. **No tool/workflow search caching** — every query re-runs SQLite + embeddings
6. **Autofix not proactively scheduled** — only triggered on error, not on QC warnings
7. **AgentOrchestrator is dead code** — if multi-agent approach becomes desirable again, this can be activated; or DeepAgents subagent pattern can replace it
8. **nf-core index stale** — only 100/405 pipelines indexed, last reindexed 2026-02-19

---

## 4. Can DeepAgents Optimize BioMate?

### 4.1 Direct Integration (Drop-in)

**Verdict: Partial fit — useful for specific subsystems, not the full stack.**

BioMate is a domain-specialized platform (bioinformatics workflows, cryo-EM, drug discovery). DeepAgents is a general-purpose coding/task agent. The overlap is strongest in:

- **AutoFix 3.0** — DeepAgents' `LocalShellBackend + execute tool` pattern is nearly identical to what AutoFix3Orchestrator does manually. Migrating AutoFix to a DeepAgents subagent would give it planning (`write_todos`), loop detection, and LangSmith observability for free.
- **ResearchAgent** — DeepAgents' `SubAgentMiddleware` + `SkillLoader` pattern maps directly to BioMate's literature search + skills concept. The `CompositeBackend` could route `/memories/` to the existing PostgreSQL LTM.
- **Workflow generation** — The `FilesystemMiddleware` context management (large outputs saved to files, not context) would reduce prompt bloat in multi-step workflow generation.

### 4.2 Architectural Patterns Worth Adopting

These patterns from DeepAgents are directly applicable regardless of whether we import the package:

#### Pattern A — Middleware Architecture for BioMate Agents

Replace the ad-hoc agent activation logic with a declared middleware stack:

```python
# Proposed BioMate middleware stack
class BioMateIntentMiddleware:      # Classify 9 intent types
class BioMateWorkflowMiddleware:    # FTS search + generation
class BioMateResearchMiddleware:    # Literature + citations
class BioMateExecutionMiddleware:   # Batch/Galaxy/CryoSPARC dispatch
class BioMateQCMiddleware:          # QC gate + threshold checks
class BioMateAutoFixMiddleware:     # Error recovery with write_todos
class BioMateMemoryMiddleware:      # LTM read/write
```

Each middleware is self-contained: owns its state schema, tools, and system prompt fragment.

#### Pattern B — LangGraph StateGraph for Full Pipeline

Replace direct method calls with a formal state machine:

```python
workflow = StateGraph(BioMateQueryState)
workflow.add_node("classify",   classify_intent)       # Haiku
workflow.add_node("clarify",    clarify_if_ambiguous)  # conditional
workflow.add_node("search",     search_workflows)      # FTS
workflow.add_node("specialize", run_domain_specialists) # parallel
workflow.add_node("assemble",   assemble_workflow)
workflow.add_node("execute",    dispatch_execution)
workflow.add_node("monitor",    monitor_with_qc)
workflow.add_node("fix",        autofix_on_failure)    # conditional
workflow.add_conditional_edges("classify", route_intent)
workflow.add_conditional_edges("execute",  route_on_error)
```

Benefits: observable progress (LangSmith), resumable on error, human-in-the-loop for QC gates.

#### Pattern C — SubAgent Delegation for Specialists

Replace the parallel domain specialist pool with DeepAgents subagents:

```python
# Domain specialists as isolated subagents
main_agent = create_deep_agent(
    model=haiku,
    subagents={
        "genomics":        GenomicsSpecialistAgent(...),
        "transcriptomics": TranscriptomicsAgent(...),
        "drug_discovery":  DrugDiscoveryAgent(...),
        "cryo_em":         CryoEMAgent(...),
    }
)
```

Benefits: true context isolation, specialist agents can be upgraded independently, parallel execution maintained.

#### Pattern D — CompositeBackend for Memory

Wire the existing PostgreSQL LTM to a CompositeBackend:

```python
backend = CompositeBackend({
    "/memories/user":    PostgresLTMBackend(table="ltm_user"),
    "/memories/project": PostgresLTMBackend(table="project_knowledge"),
    "/workspace":        StateBackend(),   # ephemeral per-session
    "/corrections":      PostgresLTMBackend(table="correction_log"),
})
```

This would activate the dormant `agentic_memory.py` schema in a structured way.

---

## 5. Recommended Integration Plan

### Phase 1 — LangGraph StateGraph (Highest Value, ~2 weeks)

Wire existing agents into a formal StateGraph. No new agents, just formal edges.

- Define `BioMateQueryState` TypedDict
- Add nodes: classify → (clarify?) → search → specialize → assemble → execute → (fix?)
- Add conditional edges for ambiguity and error paths
- Enable LangSmith tracing for observability
- Checkpoint/resume for long Nextflow runs (Batch jobs)

**Files to change:** `ai_assistant.py`, `agents/agent_orchestrator.py`

### Phase 2 — AutoFix as DeepAgents Subagent (~1 week)

Replace `AutoFix3Orchestrator` direct calls with a DeepAgents agent:

- `LocalShellBackend` replaces manual bash execution
- `PlanningMiddleware` replaces manual `write_todos` equivalent
- `LoopDetectionMiddleware` prevents infinite fix loops (already a known risk)
- LangSmith gives full trace of every fix attempt

**Files to change:** `workflow_ops/autofix/autofix3_orchestrator.py`

### Phase 3 — Memory Middleware (~1 week)

Activate the dormant LTM system via CompositeBackend:

- Route `/memories/` paths to PostgreSQL LTM backend
- Wire correction logs into model improvement loop
- Add pre-completion checklist for research agent (cite sources, verify tool exists)

**Files to change:** `memory/agentic_memory.py`, `agents/research_agent.py`

### Phase 4 — Tool/Workflow Search Caching (~2 days)

Add Redis caching layer (already wired for billing):

- Cache workflow search results (TTL: 10 min)
- Cache tool embeddings (TTL: 1 hour)
- Cache LLM intent classifications by query hash (already partially done in `unified_workflow_search.py`)

---

## 6. Risk / Trade-offs

| Option | Benefit | Risk |
|---|---|---|
| Import `deepagents` package | Fast middleware, built-in tools | External dependency, API surface churn |
| Adopt patterns only (no import) | Full control, no dep | More implementation work |
| LangGraph StateGraph only | Observability + resilience | Refactor cost (~200 lines changed) |
| Full DeepAgents migration | Cohesive harness | Major refactor, unknown bio-domain fit |

**Recommendation:** Adopt patterns A + B (LangGraph StateGraph + middleware architecture) without importing `deepagents` directly. Import only `langgraph` (already installed v1.1.2). Phase 2 (AutoFix subagent) is the best candidate for a direct `deepagents` package trial since it is isolated.

---

## 7. User Domain Profile — Starting Context Design

### Concept

At registration and in user settings, let users pre-select their working domains and topics. This becomes their **starting context prior** for intent routing and workflow search — eliminating the cold-start LLM guessing on early queries, without adding keyword-first shortcuts.

### Two-Tier Selection

**Tier 1 — Domain** (broad, ~15 options):
`genomics` · `transcriptomics` · `single_cell` · `epigenomics` · `proteomics` · `metabolomics` · `metagenomics` · `structural_biology` · `drug_discovery` · `cryo_em` · `pharmacology` · `systems_biology` · `synthetic_biology` · `bioimaging` · `other`

**Tier 2 — Topics** (domain-specific subtopics, shown after Tier 1 selection):
- Example: genomics → `variant calling` / `WGS` / `WES` / `copy number` / `SV` / `population genetics`
- Example: transcriptomics → `bulk RNA-seq` / `single-cell` / `spatial` / `long-read` / `ATAC-seq`
- Topics narrow preferred_domains and key_terms injected into `_classify_intent_with_llm()`

### Where It Plugs In

```
User profile (domains + topics) stored in LTM (ltm_user table)
  ↓
Loaded at session start by UnifiedIntentRouter
  ↓
Injected as preferred_domains + key_terms bias into:
  — unified_workflow_search.py: _classify_intent_with_llm()
  — galaxy-assistant.ts: system prompt prefix
  ↓
Current conversation context progressively overrides profile weight
  (as session accumulates evidence, profile prior diminishes naturally)
```

### Override Behavior (Future Work — deferred)

The interaction between profile prior and session context is intentionally not implemented now. Current behavior: profile is always injected as a static bias; LLM naturally prioritises current conversation context. Three options for future consideration:
- Option A: Hard override — once session has N turns, profile is ignored entirely
- Option B: Soft blend — profile weight decays per turn (e.g., weight = 1/(1+turns))
- Option C: User-controlled — explicit "Apply my profile" toggle in UI

### UI Touchpoints

1. **Registration flow** — after email/password, step 2: "What do you work on?" (Tier 1 + Tier 2 multi-select, skippable)
2. **Settings → My Research Profile** — same selector, editable any time; note: "BioMate uses this as your starting context for workflow search"
3. **No-selection fallback** — users who skip or have no selection: use no prior (current behavior, cold start)

### What This Does NOT Change

- LLM is still called for every intent classification — no keyword-first shortcuts
- The profile is injected as structured context into the LLM prompt, not as a rule override
- Users whose interests evolve simply update their profile in settings

---

## 8. Open Questions for Editing

- [ ] Should Phase 1 (LangGraph StateGraph) block the next public beta release?
- [ ] Is LangSmith monitoring acceptable (data leaves BioMate infrastructure)?
- [ ] For Phase 2 AutoFix: use `deepagents` package OR implement matching pattern manually?
- [ ] Priority order: LangGraph (observability) vs Domain Profile (user stickiness) vs Caching (latency)?
- [ ] LangSmith tracing: acceptable to have trace data leave BioMate infrastructure?
- **Decided:** Tier 2 topic lists are static curated lists — not dynamically generated.
- **Deferred:** Domain profile override threshold — see Future Work section in implementation plan.

---

## 8. References

- LangChain DeepAgents overview: `docs.langchain.com/oss/python/deepagents/overview`
- Anatomy of an Agent Harness: `blog.langchain.com/the-anatomy-of-an-agent-harness/`
- DeepAgents GitHub: `github.com/langchain-ai/deepagents`
- BioMate LangGraph foundation: `backend/lib/galaxy/ai/` (LangGraph v1.1.2 installed, `pending_tasks` table)
- BioMate AutoFix: `backend/lib/galaxy/ai/workflow_ops/autofix/autofix3_orchestrator.py`
- BioMate LTM schema: `backend/lib/galaxy/ai/memory/agentic_memory.py`
- Current session doc: `docs/nextPhase/20260321_DEEPAGENTS_AGENTHARNESS_ANALYSIS.md`
