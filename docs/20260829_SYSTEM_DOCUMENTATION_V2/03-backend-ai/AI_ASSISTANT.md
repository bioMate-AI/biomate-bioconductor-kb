# 03a · Backend AI Assistant & Workflow Generation

**Verified 2026-08-29.** Source: `backend/lib/galaxy/ai/` and `backend/lib/galaxy/webapps/galaxy/api/`.

---

## 1. Orchestration

`backend/lib/galaxy/ai/ai_assistant.py` — **6,859 lines**, single class `AIAssistant` (L150). The API twin `webapps/galaxy/api/ai_assistant.py` (6,268 lines) is the FastAPI router wrapping it.

`__init__` (L153) runs a **lightweight mode**: it eagerly builds only `workflow_search`, `constrained_generator` (`GalaxyWorkflowGenerator`), and `dataset_selector`; everything else (`intent_parser`, `task_decomposer`, `nextflow_composer`, `agent_orchestrator`, `research_agent`, tool search) is **lazy-loaded via `@property`** (L240–385). Bioconductor + cryo-EM chain templates register at startup.

### 1.1 Primary entry — `generate_workflow_unified` (L3956)
Exposed as `POST /api/ai_assistant/generate_workflow` (API L3440). Search-first pipeline:

1. **Feature-flagged early routes** (L3999) — `ml_training`, `multiomics` (both default OFF, inert until flag set).
2. **LTM correction injection** (L4025) — UUID `user_id` + `agentic_memory` prepends recent corrections to the intent.
3. **Fast-path shortcuts** (L4052) — hardcoded routers for codon, docking, virtual-screening, BOIN trial, somatic variant, CryoSPARC SPA, ADMET, GEO scRNA pseudobulk, nf-core.
4. **Fast LLM client init** (L4119) — cheap classification client (`_FAST_CLASSIFICATION_MODELS`, L94: `claude-haiku-4-5`/`gemini-3.5-flash`) injected into search for chain verification.
5. **Chain lookup** (L4133) — if top single-result score ≥ 55.0 (`_SPECIFIC_WORKFLOW_THRESHOLD`) skip chains; else `search_chains(min_score=0.35)`. Returns a `chain` or `clarification` card.
6. **Routing hint injection** (L4221) — microarray→limma, codon/mRNA, AutoDock Vina.
7. **Iterative search trials** (L4271) — `_build_intent_trials` (L2165) yields query rewrites; each `search(limit=5)`; keep best, break on first `high_confidence`.
8. **Disambiguation gate** (L4322) — see §3.4.
9. **LLM routing verification** (L4462) — `_llm_verify_routing` (L1944) at temp 0 for medium confidence or close top-2 (<8pt gap); produces an audit trail. Skips when #1 is an nf-core pipeline leading a bioconductor subworkflow (penalty already applied).
10. **Confidence-tiered strategy** (L4602) — high (≥12)→`template_reuse`; medium (≥6)→`template_adapt`; low→compose from scratch via `NextflowComposer`. Nextflow matches funnel through `_return_nextflow_match` (L3146), which assembles the final dict (rationale, hardware, QC profile, layered param injection).

Legacy `process_request` (L1565, 4-step) and `generate_workflow_multi_agent` (L1303, via `agent_orchestrator`) still exist but are superseded.

## 2. LLM client & the model resolver

Modules: `llm_client.py`, `llm_router.py`, `model_resolver.py`, `config.py`, `llm_client_fallback_implementation.py`, plus the endpoint `webapps/.../llm_internal.py`.

**7 providers** (dispatch `llm_client.py:128–184`): Anthropic (Claude), OpenAI, Gemini/Google, DeepSeek, Ollama (local), Zhipu GLM, generic `local`.

**Defaults (fragmentation is real):**
- Global fallback: **`claude-sonnet-4-5`** (`config.py:28,140`; `model_resolver.py` GLOBAL_DEFAULT L36).
- Per-role (`model_resolver.py:25–36`): `intent`→`gemini-3.5-flash`; `tool_rank`/`audit`/`judge`→`claude-haiku-4-5`; `response`/`convert`/`autofix`/`param`→`claude-sonnet-4-5`; `rag`→`gemini-3.5-flash`.
- **YAML fallback chain** (`config/llm_providers.yml`, **highest runtime priority**): `gemini-3.1-pro-preview` → `gemini-3.5-flash` → `claude-sonnet-4-5` → `gpt-4o` → local `qwen3:32b`.
- Fallback logic (`llm_client_fallback_implementation.py:191`) iterates the chain with per-provider exponential backoff (2s→60s). `HybridLLMRouter` (`llm_router.py:325`) scores providers by task complexity (TRIVIAL…EXPERT) and type (coding→Qwen3/GLM, scientific→Anthropic).

**`model_resolver.py`** is the intended single source of truth. Precedence: user BYOK per-role → user BYOK global → `BIOMATE_MODEL_<ROLE>` env → `BIOMATE_MODEL` env → config map → role default → global. **But only ~15 files reference `resolve_model()`**; ~23 backend modules + the frontend `galaxy-assistant.ts` still hardcode literals (some stale: `claude-3-5-sonnet-20241022`, `claude-3-haiku-20240307`). This is the #1 architectural debt for the upgrade — see `docs/20260824_LLM_CONFIG_FRAGMENTATION_AUDIT.md`.

**Internal relay:** `POST /internal/llm/generate` (`llm_internal.py:47`, gated by `X-Internal-Key = BILLING_INTERNAL_KEY`) reroutes hardcoded frontend calls through the canonical chain; returns `text`, `model_used`, `fallback_depth`. Env keys: `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`/`GEMINI_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `ZHIPU_API_KEY`.

## 3. Intent parsing & routing

### 3.1 Classification (hybrid keyword + LLM)
`classify_intent` (L386) → `UnifiedIntentRouter` (`agents/unified_intent_router.py:56`). Keyword fast path `_keyword_classify` (L232, +0.3/pattern, +0.4/strong keyword); when confidence < 0.6, `_llm_classify` (L344). `UserIntent` enum → handler (WORKFLOW_GENERATION→`agent_orchestrator`, RESEARCH_QUESTION→`research_agent`). Fallbacks: `_simple_intent_classify` (L448), legacy `intent_parser.py:115`.

### 3.2 Multi-task detection
`ai_assistant.py:574`: `_looks_like_multi_task` → cheap-LLM `_classify_multi_task_llm` returns `{is_multi_task, task_count, reason}`, MD5-cached.

### 3.3 Score-driven routing
`unified_workflow_search.py:_calculate_score` (L1710–1865), **additive** across ~10 components: FTS×1.5 + keyword weights + phrase bonus + name overlap/exact-match + `SOURCE_PRIORITY`/15 (nfcore=100) + domain preference (±4) + input-type compat (±4) + preferred/legacy tag (±6) + exec-quality (±2). `_classify_match`: ≥12 high, ≥6 medium, else low.

**The subworkflow-reclassify guardrail (PR #188)** — 283 runnable domain workflows under `nextflow_nfcore/subworkflows/<domain>/` were wrongly flagged as pipeline *components* by `_is_component_subworkflow()` and given an unconditional **−8 penalty**. The bare substring test `if "nfcore/subworkflows/" in fn` matched the `nextflow_nfcore/subworkflows/` path — a silent no-op. Fix anchors the check (L138–177): `fn.startswith("nfcore/subworkflows/")` OR `"nf-core-modules/subworkflows/" in fn` OR `"/subworkflows/bioconductor/" in fn`. Measured **+8.00 uniform lift** (docking 44→52, admet 62→70, chipseq 64→72, cryoem 51→59), zero regression. Explicitly protected from LLM-verify override at `ai_assistant.py:4501–4516`. (Detail: `docs/20260827_RECLASSIFY_SUBWORKFLOW_ROUTING_GUARDRAIL.md`.)

### 3.4 Disambiguation
Two gates return `workflow_type:'disambiguation'` (L4322): **(a)** alt-method enumeration — `_detect_alt_method_enumeration` (L113) fires when ≥2 `_ALT_METHOD_TOKENS` (deseq2/edger/limma…) appear with an alternative marker (or/vs/compare), even at high confidence; **(b)** score-gap — ≥2 candidates (≥6.0) within `_DISAMBIG_GAP_THRESHOLD`=3.0. ADMET has a bypass (promotes `predict_admet_properties` to #1).

### 3.5 Task decomposition
`task_decomposer.py` (L136–378): template-first (RNA-seq / genome-assembly / variant-calling, conf 0.85) then LLM decomposition (3–8 tasks, conf 0.7); builds a dependency graph with parallel-execution optimization.

## 4. Workflow generation (3 generators by confidence tier)

- **`GalaxyWorkflowGenerator`** (`galaxy_workflow_generator.py:42`, `generate_workflow` L105) — builds the Galaxy `.ga` JSON (`_build_galaxy_workflow_json` L942): `a_galaxy_workflow`, `format-version:"0.1"`, `name`, `annotation`, `tags`, `steps` dict. Each step (L854) carries `id`, `tool_id`, `name`, `tool_state` (JSON params from `LLMParameterGenerator`), `inputs`, `position`. Return dict (L270) adds `workflow_ga`, `workflow_structure`, `generated_parameters`, `citations`, `methods_section`, `detected_domain`, `compatibility_validated/warnings`. **`required_params`/`optional_params` are NOT direct `.ga` fields** — they live in each step's `tool_state`.
- **`EnhancedWorkflowGenerator`** (`enhanced_workflow_generator.py:25`) — template/RAG/hybrid, for medium-confidence adaptation.
- **`NextflowComposer`** (`nextflow_composer.py:227`, `compose_workflow` L632) — primary generate-from-scratch path. 4 layers: **L0** cache (`SubworkflowLibrary`, Jaccard ≥ 0.75) → **L1** FTS tool retrieval → **L2** wrapper-path validation (`composable` vs `adhoc`) → **L3** a *single* LLM call emitting DSL2 `.nf` (reference workflow as structural guide) → **L4** syntax validation with one strip-and-retry (max 2 LLM calls). Composes via `include{PROC} from 'path/main.nf'` for wrapped tools, inline `process` (container `biomate/biomni-tools:latest`) otherwise.

Steps are lazily fetched via `/api/nextflow/steps` when `workflow_ga.steps = {}` (see [WORKFLOW_EXECUTION §7](WORKFLOW_EXECUTION.md)).

## 5. Tool & workflow search

Classes: `UnifiedWorkflowSearch` (`unified_workflow_search.py:335`), `UnifiedToolSearch` (`unified_tool_search.py:27`), `VectorToolSearch` (`vector_search.py:82`), `EnhancedToolSearch`.

- **FTS5:** `workflows_fts(name, description, annotation, tags, domain, tools_used, content='workflows')` (L666), `bm25()` scoring.
- **Vector — two 384-dim models:** workflows use **`BAAI/bge-small-en-v1.5`** (L87; +9% recall vs MiniLM, MTEB 62.17), index `backend/database/galaxy_ai_workflow_embeddings.npz` + `tools.embedding` BLOB; chains use **`all-MiniLM-L6-v2`** (L38, min-sim 0.50).
- **Embed server:** a single shared process loads both models once, served over Unix socket `/tmp/biomate_embed.sock` (`embed_server.py:28`, `embed_client.py:21`) — saves ~1.5 GB across workers; thread-safe per-worker singleton, FTS-only fallback.
- **Score fusion:** workflow search = **additive** ~10 components + a 3-pass wrapper (Pass-0 fast-LLM catalog browse graded +3.0…+0.3; Pass-1 BGE dense cosine additive `sim×0.5` cap 0.5 threshold 0.55; Pass-2 FTS/BM25). Tool search = **Reciprocal Rank Fusion** (`unified_tool_search.py:422`, k=60) across 4 stages (entity → vector → FTS-with-category → FTS fallback).

## 6. Parameter extraction (hybrid rule + LLM)

Orchestrated in `_return_nextflow_match` (L3160–3208), layered: parse schema params → rule injectors → hints → explicit → LLM.

- **Rule (deterministic):** `_extract_sra_accession` (L2551, regex SRR/GSE/GSM/E-MTAB/PXD), `_extract_genome_build` (L2556, alias GRCh38→hg38, GRCh37→hg19, GRCm38→mm10, GRCm39→mm39), `_extract_max_spots` (L2584), `_extract_explicit_params_from_query` (L2873): extension→param (`.mrc/.tif`→movies_path, `.fastq`→reads, `.bam`→bam, `.vcf`→vcf, `.pdb`→receptor_pdb, `.sdf`→ligand_sdf), `key=value` parsing, SMILES with paren-nesting validation.
- **LLM:** `_infer_params_from_intent_llm` (L2745, Claude Haiku via `use_fast_model`): ambiguous file types (.csv→matrix vs samplesheet), free-text SMILES/gene/PDB, enum mapping. **Note:** unit conversions ("37°C→310K", "ns→n_steps×500 fs"), `dUTP→reverse`, and negations are **LLM-prompt-embedded, not rule code** (system prompt L2693–2743).
- **Guardrail:** LLM suggestions filtered (L2853) to require the param name in schema `valid_names`, non-null, non-empty. Type/enum coercion in `llm_parameter_generator.py:278–330`. `_build_prereq_validation` (L2626) flags truly-missing required params for the frontend Run gate.
- **API:** `parameter_inference.py` (497 lines): `GET /api/pilot_analysis/analyzers`, `POST /pilot_analysis/run|batch`, `POST /context_gathering/chat`, `POST /parameter_inference/infer`, `GET /parameter_inference/health`.

## 7. Agentic tools / run_code

- **`run_code`** (LLM-callable Python/R/bash) is implemented **frontend-side** (`frontend/server/code-runner.ts`, ephemeral docker sandbox; local socket in dev, `RUN_CODE_BACKEND_URL` in prod). Backend agents use **Claude native `tool_use` blocks** (`workflow_ops/autofix/agent_fixer.py:197`), not a separate run_code registration; the autofix tool set is `bash_command.py`, `read_file.py`, `grep_search.py`, `file_operations.py`.
- **`ai/agents/`:** `agent_orchestrator.py:46` (EnhancedDomainRouter → DomainSpecialistPool → WorkflowAssembler), `research_agent.py` (~2,650 lines, literature-backed Q&A with live PubMed/Ensembl/VEP/GTEx/Open-Targets/GWAS + citation tracking), `context_gatherer.py:19` (progressive clarification, ≤3 questions/turn).
- **Known issue (now fixed)** — "agentic tools don't fire in live chat on some models" was a **frontend intent-classification fallback bug**, not a model or backend limitation: a malformed Gemini classifier response fell back to hardcoded `type:'tool_search'`, so `mustGenerateWorkflow` never fired for inline-omics messages. Fixed by detecting inline data → `type:'workflow_generation'` (`docs/20260702_INLINE_DATA_ARRAY_PRESERVATION.md`). Tool-use loop `MAX_TOOL_TURNS=12` in `galaxy-assistant.ts`. ⚠️ The memory index `project_agentic_tools_gemini.md` still records this as an open bug — it is **stale**; the code fix landed.

- **Expert-skills persona layer** — before generation, `SkillManager` (`ai/skill_manager.py`) trigger-matches the query against 9 domain personas and composes the matched persona's `system_block` into the prompt. See [DOMAIN_MODULES §9](../04-domains/DOMAIN_MODULES.md).

## Key files

| Path | Purpose | ~LOC |
|------|---------|------|
| `ai/ai_assistant.py` | Core orchestrator; `generate_workflow_unified` | 6,859 |
| `webapps/.../ai_assistant.py` | FastAPI router (`/api/ai_assistant/*`) | 6,268 |
| `ai/unified_workflow_search.py` | FTS5 + BGE dense + LLM browse, additive scoring, reclassify | ~3,800 |
| `ai/unified_tool_search.py` | 4-stage RRF tool search | ~510 |
| `ai/vector_search.py` / `embed_server.py` / `embed_client.py` | BGE embeddings + shared socket server | ~700 / ~190 / ~150 |
| `ai/llm_client.py` / `llm_router.py` / `model_resolver.py` | 7-provider client / hybrid router / role resolver | ~700 / ~550 / ~80 |
| `ai/nextflow_composer.py` | 4-layer DSL2 compose | ~810 |
| `ai/galaxy_workflow_generator.py` | Galaxy `.ga` JSON builder | ~1,100 |
| `ai/agents/{unified_intent_router,research_agent,agent_orchestrator,context_gatherer}.py` | Routing + research + multi-agent + clarification | — |
| `webapps/.../parameter_inference.py` | Param-inference / pilot / context endpoints | 497 |
