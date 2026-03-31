# Audit all LLM usage in BioMate
_Exported on 3/30/2026 at 12:31:51 CDT from Cursor (2.4.27)_

---

**Cursor**


Searching the codebase for Anthropic/Claude usage and reading key files to build a complete LLM-call inventory.




Here is a structured audit of **Anthropic Claude usage** in BioMate. The codebase also supports other providers (OpenAI, Gemini, Ollama, Zhipu, etc.) via `LLMClient` and `llm_router.py`; those paths are noted only where they sit beside Claude. **`tool_knowledge_provider.py` does not call an LLM**—it reads SQLite (`galaxy_ai_tools.db`). **`qc_trace_monitor.py` has no LLM usage** (confirmed by search).

---

## 1. Executive summary

| Area | Primary entry | Models (typical) | “Knows” workflows/tools? |
|------|----------------|------------------|----------------------------|
| Chat orchestration | `frontend/server/galaxy-assistant.ts` | Haiku 4.5 (intent/rank/clarify/domain/summary), Sonnet 4.6 (reply) | **Partial**: static capability blurb (e.g. “2,177 tools”); **no full workflow catalog** in the main system prompt. Named workflow hints (AMBER, GROMACS, Schrödinger, REINVENT4, etc.) are **hand-authored** in the response prompt. |
| Backend generation / search | `backend/lib/galaxy/ai/*.py` via `LLMClient` | Config default `claude-sonnet-4-6` (`ai_config.py`); fast path `claude-haiku-3-5` in `ai_assistant.py` (may differ from deployed `llm_model`) | **Yes where constrained**: Galaxy workflow JSON uses **only injected tool lists**; Nextflow composer injects a **tool catalog**; Pass-0 workflow browse injects **up to 60 FTS candidates**. |
| Ops / debugging APIs | `ai_assistant.py` `explain_workflow_error`, `autofix3.py` error-summary | Haiku 4.5 / Haiku 3.5 | Log-focused; **not** a product capability brief. |

**Honest capability assessment (system-level)**  
- **Self-model of capabilities**: The **user-facing** assistant prompt states high-level features (tool search, datasets, workflow generation) and strict behavioral rules (DATA-FIRST, one-question rule, drug-development add-ons). It does **not** expose a complete, versioned inventory of workflows or pipelines.  
- **Workflow awareness**: **Retrieval** (FTS + optional Pass-0 LLM re-ranking) supplies a **small candidate set** per query, not global knowledge. Template-first generation on the backend uses search + tools, not “the model memorized nf-core.”  
- **Tool / Nextflow / nf-core**: Prompts in **NextflowComposer**, **GalaxyWorkflowGenerator**, and **WorkflowModificationClassifier** explicitly anchor the model to **provided tool IDs**, **DSL2 / nf-core-style rules**, or **nf-core skip flag names**.  
- **Context efficiency**: Frontend uses **prompt caching** (intent, tool ranking, response system blocks), **6-turn** history window, and **Haiku** for cheap tasks. Python `LLMClient._generate_anthropic` **prepends** a generic sentence to every user message, which is slightly redundant when the prompt already contains a full system-style spec.

---

## 2. Production / core runtime (direct `messages.create` or dedicated SDK paths)

### 2.1 `frontend/server/galaxy-assistant.ts` — `GalaxyAssistant`

**Client**: `this.claude = new Anthropic({ apiKey })`.

| # | Function | Model | System / prompt structure | Injected context | Output use |
|---|----------|--------|-----------------------------|------------------|------------|
| 1 | `_generateClarificationQuestion` | `claude-haiku-4-5-20251001` | Expert assistant; ambiguity-type → what to ask (germline/somatic, bulk/scRNA, etc.) | User message + `ambiguityType` | One clarifying question for workflow disambiguation |
| 2 | `_inferDomainWithLLM` | Same Haiku snapshot | Single-line domain enum + rules per domain | `userIntent` + optional workflow/recent context | `domain_hint` passed to backend workflow generation |
| 3 | `analyzeIntent` → `messages.create` | `modelConfig.intentModel` (default **`claude-haiku-4-5`**) | Large **cached** system block: intent types, multi-intent/sequential rules, fact extraction, **workflowAmbiguity** fork points, JSON schema | User message; optional **accumulatedFacts** from prior turns | JSON → `IntentDecomposition` → routing (tool search, workflow gen, agents) |
| 4 | `rankToolsByRelevance` | `modelConfig.toolRankingModel` (default **Haiku**) | Cached: rank tools 0–1 + JSON array | User message + **tool list** (name, id, category, keywords) + optional **user patterns** string | Ordered tool recommendations |
| 5 | `generateResponse` | `modelConfig.responseModel` (default **`claude-sonnet-4-6`**) | Cached: BioMate capabilities (static counts), **DATA-FIRST** and **ONE-QUESTION** rules, **named workflow routing hints** (AMBER, GROMACS, Glide, MOE, REINVENT4…), style rules | **Domain profile** prefix if any; last **6** chat turns; user message; tool/dataset lines; workflow diagnostics JSON if failed; research/benchmark JSON slices | Final assistant reply (stream or non-stream); optional thinking |
| 6 | `_triggerSessionSummary` | `claude-haiku-4-5` | User-only summarization request (no separate system in code) | Truncated dropped messages (~4000 chars) | POST to `/api/memory/session-summary` |

**Assessment**: Intent + ranking prompts are **strongly specified** and **cache-friendly**. The **response** prompt mixes **static marketing-style counts** with **strict execution policy**; workflow knowledge for routing is **partial** (curated list of special pipelines, not DB-backed enumeration).

---

### 2.2 `frontend/server/routes.ts`

| Endpoint / area | Model | Prompt | Context | Use |
|-----------------|--------|--------|---------|-----|
| `/api/llm/classify` (approx. lines 8043–8054) | `claude-haiku-4-5` | Implicit: yes/no only | First 2000 chars of `text` + `question` | Boolean classification for tests / gates |

---

### 2.3 `frontend/server/workflow-prerequisites-validator.ts`

| Function | Model | System / user | Context | Use |
|----------|--------|---------------|---------|-----|
| LLM analysis (e.g. ~425) | `claude-sonnet-4-5` | System: JSON schema for mappings/missing params; user: workflow requirements, datasets, tool docs | **Required inputs/params**, **available datasets**, **tool documentation** snippets | Structured prerequisite analysis |
| `generateConversationalResponse` (~594) | Same | Friendly assistant; no JSON in reply | Validation result fields | User-facing message |

---

### 2.4 `frontend/server/iterative-workflow-generator.ts`

| Function | Model | Prompt | Context | Use |
|----------|--------|--------|---------|-----|
| `generateDraft` | `claude-sonnet-4-5` | `buildDraftSystemPrompt(session)` + user: “Generate…” | Session/requirements from prior phases | High-level draft workflow |
| `configureNextStep` | Same | Step-specific system: tool, purpose, configuration bullets | Current draft step | Step configuration text |

---

### 2.5 `frontend/server/context-compressor.ts`

| Function | Model | System | Context | Use |
|----------|--------|--------|---------|-----|
| `generateSummary` | `claude-sonnet-4-5` | Long system: preserve goals, tools, data types, workflows, errors; **prose** not bullets | Full conversation slice to compress | Summary to shrink token usage |

---

### 2.6 `frontend/server/model-test-harness.ts`

Harness comparing Haiku vs Sonnet on intent/response tests—not production routing.

---

## 3. Backend Galaxy AI (`backend/lib/galaxy/ai/`)

### 3.1 Universal HTTP client: `llm_client.py` — `LLMClient`

- **Anthropic path**: `async _generate_anthropic` posts to `/v1/messages` with a **single user message** whose content is:  
  `"You are a helpful bioinformatics assistant. " + prompt`  
  (see ```292:303:backend/lib/galaxy/ai/llm_client.py```).
- **Model**: `self.model` from `AIConfig` (default **`claude-sonnet-4-6`** when provider is Anthropic, per `galaxy/config/ai_config.py`).
- **Sync**: `generate()` wraps `generate_async()` (thread/asyncio handling).

**Any** backend code that calls `llm_client.generate(...)` uses this Anthropic message shape when `llm_provider == anthropic`.

---

### 3.2 `unified_workflow_search.py` — Pass-0 (not direct SDK)

| Function | Model | “System” | Context | Use |
|----------|--------|-----------|---------|-----|
| `_browse_catalog_with_llm` | Whatever `self._llm_client` is (wired from `AIAssistant._call_llm_fast` → **`LLMClient` with fast model**, e.g. **`claude-haiku-3-5`** in `_FAST_CLASSIFICATION_MODELS`) | Inline prompt: “You are a bioinformatics workflow recommender” + user query + **numbered list** `id. name: desc` (up to **60** rows, desc truncated to **120** chars) | FTS-broadened candidates | JSON array of workflow IDs → score boosting |

**Assessment**: Model only chooses among **provided IDs**—good grounding. It does **not** “see” the whole DB.

---

### 3.3 `ai_assistant.py`

| Call site | Model | Prompt summary | Context | Use |
|-----------|--------|----------------|---------|-----|
| `_classify_multi_task_llm` / `_call_llm_fast` | Fast model per provider (`claude-haiku-3-5` for Anthropic in `_FAST_CLASSIFICATION_MODELS`) | Multi-task vs single pipeline; JSON `{is_multi_task, task_count, reason}` | User query | Gate clarification path |
| `workflow_search.set_llm_client` | Same client | N/A | Wires Pass-0 | Side effect |

---

### 3.4 `galaxy_workflow_generator.py`

| Area | Prompt structure | Context | Use |
|------|------------------|---------|-----|
| `_transform_intent_to_fts_query` | FTS5 rules + examples | User intent | Search query string |
| `_generate_workflow_structure` | Large **system** spec: domain phases, **AVAILABLE TOOLS (exact tool_id)**, tool priority local vs ToolShed, parameter hints | `user_intent` + domain phases list | JSON workflow plan |

**Assessment**: Strong **tool-grounding**; aligns with “knows Galaxy tools from catalog,” not from parametric memory.

---

### 3.5 `nextflow_composer.py` — `_build_generation_prompt` / `_call_llm`

- **Model**: `LLMClient` default (Sonnet-class from config).
- **Prompt**: Expert Nextflow DSL2 engineer; **AVAILABLE TOOLS** block; NF-wrapper vs generate rules; DSL2 conventions; output = raw `main.nf`.
- **Use**: Generated Nextflow file on disk.

---

### 3.6 `workflow_modification_classifier.py`

| Function | Model | System | Use |
|----------|--------|--------|-----|
| `_classify_with_llm` | `claude-haiku-4-5-20251001` | `_CLASSIFIER_SYSTEM`: JSON schema; **nf-core skip flag** examples | Parse chat into `WorkflowModification` |

---

### 3.7 `intent_parser.py` — `_llm_parse_intent`

- Prompt lists **ANALYZE/COMPARE/…** intent enums; JSON response.
- Uses `llm_client.generate(prompt)` (configured model).

---

### 3.8 `query_analyzer.py` — `LLMQueryAnalyzer.analyze`

- **`QUERY_ANALYSIS_PROMPT`**: entities, category from **VALID_CATEGORIES**, task_type, expanded_terms, data_types.
- **Use**: Better tool search queries.

---

### 3.9 `tool_discovery.py`, `resource_resolver.py`, `llm_parameter_generator.py`, `propose_validate_*.py`, `agents/*.py`, etc.

All follow the same pattern: **task-specific user prompt** + `llm_client.generate` / `await llm_client.generate` (ResearchAgent uses `await self.llm_client.generate(...)` with a built synthesis prompt including literature/benchmark sections—see `research_agent.py` ~514–524).

---

### 3.10 `workflow_ops/llm_client.py` — `AnthropicProvider.call`

- Direct `self.client.messages.create(**api_params)` with optional **system** extracted from messages.
- Used by **workflow autofix** and similar when `provider='anthropic'`.

---

### 3.11 `workflow_ops/parameter_analyzer.py`

- `messages.create(model="claude-3-5-sonnet-20241022", ...)` with a long **user** prompt (AWS/genome context) and JSON output for parameter recommendations.

---

### 3.12 `workflow_ops/autofix/agent.py`

- `self.llm_client.call(..., provider='anthropic', ...)` for **initial error triage** (investigate vs simple) and **final fix JSON** (Chinese instructions; S3 path discipline; optional parameter recommendations from DB text).
- Model comes from workflow_ops LLM client configuration, not `LLMClient` HTTP wrapper.

---

### 3.13 `workflow_ops/autofix/fixers/llm_first_fixer.py`

- `await self.llm_client.generate(...)` for refinement steps.

---

## 4. Galaxy HTTP API (`backend/lib/galaxy/webapps/galaxy/api/`)

| Location | Model | System / prompt | Use |
|----------|--------|-----------------|-----|
| `ai_assistant.py` → `explain_workflow_error` | `claude-haiku-4-5` | Fixed system: Nextflow debugger → JSON (`error_type`, `human_summary`, `suggested_fix`, `chat_prompt`) | User-facing error explanation when API key present |
| `autofix3.py` → `get_workflow_error_summary` | `claude-haiku-20240307` via `LLMClient.complete(..., provider="anthropic", ...)` | Inline “debugging assistant” + log snippet | Structured error summary from last 200 log lines |

---

## 5. Offline scripts, auto-update, tests, research (representative)

These repeat **`anthropic.messages.create`** or **`LLMClient`** for batch jobs (metadata extraction, compatibility matching, nf-core extraction, E2E tests, etc.). Examples from your grep:  
`backend/scripts/knowledge_based_matcher.py`, `llm_extract_nfcore_workflows.py`, `extract_all_scientific_context.py`, `batch_llm_extract.py`, `web_search_validator.py`, `auto_update/scripts/unified_metadata_extractor.py`, `backend/tests/e2e_*.py`, `backend/biomni_workflows/galaxy/tests/*.py`.

They are **not** the interactive BioMate assistant loop but **do** consume Anthropic quota.

---

## 6. Cross-cutting answers to your specific questions

**Does the prompt tell the AI what workflows are available?**  
- **Chat (`galaxy-assistant.ts`)**: No exhaustive list. It gives **policy**, **ambiguous fork points**, and a **short list of named special workflows** for drug/MD/docking routes.  
- **Search (`unified_workflow_search.py`)**: Yes, but only **≤60** candidate rows for Pass-0.  
- **Generators**: **Tool-anchored** (Galaxy/Nextflow), not “all nf-core.”

**Data types?**  
- **Intent** prompt: fact categories include `data_type`, file references, parameters.  
- **Response** prompt: DATA-FIRST rule enumerates accession patterns, uploads, SMILES, etc.  
- **Query analyzer**: explicit `data_types` JSON field.

**Galaxy tools, Nextflow, nf-core?**  
- **Galaxy**: Tool catalog in `GalaxyWorkflowGenerator`; tool ranking in frontend with Galaxy search results.  
- **Nextflow**: `NextflowComposer` prompt; error explainers reference Nextflow.  
- **nf-core**: Skip flags in `WorkflowModificationClassifier`; composer text references nf-core DSL2 style.

**Context window efficiency?**  
- **Good**: Cached system blocks, Haiku for classification/ranking/summary, 6-message window, Pass-0 cap, truncation of logs/research JSON.  
- **Less ideal**: Generic prefix in `_generate_anthropic` on every call; some duplicated instructions across frontend and backend.

**Vague or under-specified?**  
- **`LLMClient` Anthropic**: Wrapping the entire task prompt inside one user message with a **generic** lead-in is weaker than a proper `system` + `user` split.  
- **Static capability counts** in the frontend (“2,177”, “100+ GB”) can drift from reality.  
- **Multi-provider** docs (`ai_config` schema defaults still mention `gpt-4` in places) can confuse operators vs runtime Anthropic defaults.

---

## 7. Files explicitly listed but without LLM in the sense you asked

- **`/home/yzhang/biomate/backend/lib/galaxy/jobs/qc_trace_monitor.py`**: No LLM references.  
- **`tool_knowledge_provider.py`**: SQLite-backed knowledge only.

---

This inventory is based on reading **actual prompt strings** in `galaxy-assistant.ts`, `unified_workflow_search.py`, `llm_client.py` (`_generate_anthropic`), `galaxy_workflow_generator.py`, `nextflow_composer.py`, `workflow_modification_classifier.py`, `ai_assistant.py` (multi-task + fast LLM), `research_agent.py`, `query_analyzer.py`, `intent_parser.py`, `autofix3.py`, API `explain_workflow_error`, and the frontend auxiliary modules listed above. If you want the same pass for **non-Claude** providers (`grep` already shows OpenAI/Gemini/Ollama branches), say so and we can extend the matrix.

