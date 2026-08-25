# LLM Configuration Fragmentation — Audit & Fix Plan

**Date:** 2026-08-24 · **Status:** finding (verified) + proposed fix · **Trigger:** "is there a config file to switch BioMate's LLM, or can the config not control the entire system?"

## Finding: there is no single source of truth for BioMate's LLM

The config (`backend/lib/galaxy/ai/config.py:28`) sets only a **default** (`llm_model = 'claude-sonnet-4-5'`). It does **not** control the whole system. The active model is chosen independently in ~23 backend modules and the frontend, most by **hardcoded literal**, several **stale**.

### Hardcoded call sites (bypass the config)
| File:line | Hardcoded model | Note |
|---|---|---|
| `llm_router.py:75,85` | `claude-sonnet-4-5`, `gemini-2.0-flash-exp` | router table literals |
| `enhanced_process_converter.py:190` | `claude-sonnet-4.5` | |
| `dual_llm_converter_system.py:407,503` | `gemini-2.0-flash-exp`, `claude-sonnet-4.5` | |
| `drug_discovery/regulatory_auditor.py:382` | `claude-haiku-4-5-20251001` | |
| `cryo_em_knowledge/rag_index.py:146` | `gemini-3.5-flash` | |
| `workflow_ops/log_analyzer.py:401` | `claude-3-haiku-20240307` | **stale**; comment 统一使用 Haiku |
| `workflow_ops/auto_healer.py:548` | `gemini-3.5-flash` | |
| `workflow_ops/query_agent.py:81` | `gemini-3.5-flash` | |
| `workflow_ops/parameter_analyzer.py:162` | `claude-3-5-sonnet-20241022` | **stale** |
| `workflow_ops/autofix/agent_fixer.py:185,406` | `claude-sonnet-4-20250514` | **stale** |
| `frontend/server/galaxy-assistant.ts:319-329` | `gemini-3.5-flash` (intent), `gpt-5.6-luna` (response), `claude-haiku-4` (tool-rank), `gemini-3.1-pro-preview` | frontend chat path, independent of backend config |

(23 backend files total carry a model literal; the above are the confirmed call-site literals.)

### There are also *three* competing config surfaces
1. `config.py` — `llm_provider`/`llm_model`/`llm_base_url` default (some paths read it).
2. `config/llm_providers.yml` — a routing/fallback table (a different path reads it; a known Mac-hardcoded config-path bug means it silently no-ops on Linux, falling back to hardcoded defaults).
3. `evaluation/config.yaml` — the eval harness's own model (for scoring/judge, not BioMate's generation).

## Why this is a problem (three consequences)

1. **BioMate×LLM matrix is not centrally runnable.** Switching the backend model requires editing ~23 files, not one config value — so the model-invariance sweep (flagship Suppl. Table S5.4) cannot be executed by configuration. The engine-free invariance result (S5.2) is unaffected (those paths make no model call), but the D3 cross-model sweep is blocked at the architecture level, not just dev-access.
2. **Blocks BYOK / unified-LLM.** The unified-selection proposal ([[20260824_LLM_CONFIG_UNIFIED_BYOK_PROPOSAL]] §2.3) requires the *selected* model to serve all tasks. It cannot, because each module pins its own model. A user's own DeepSeek/Qwen/GLM account would drive only the paths that happen to read config — not autofix, converters, auditors, cryo-EM RAG, etc.
3. **Silent quality/cost drift.** Several paths run stale or cheap models (`claude-3-5-sonnet-20241022`, `claude-3-haiku-20240307`, `gemini-2.0-flash-exp`, `claude-sonnet-4-20250514`) with no central visibility. Upgrades require hunting literals; costs are non-uniform and unaudited.

## Fix: one model resolver, read by every path

Introduce a single **`resolve_model(role, config, user_overrides)`** as the *only* way any module obtains a model, replacing all literals:
- **Roles** (not hardcoded models): `intent`, `tool_rank`, `response`, `convert`, `autofix`, `audit`, `rag`, `judge`. Each maps to a model *via config*, with sensible defaults.
- **Precedence:** per-user BYOK override (→ enables the unified-LLM feature) → per-role config → global default. One place to change; one place to audit.
- **Backend + frontend share it** (frontend calls a `/api/llm/resolve` or reads the same role→model map), eliminating the frontend's independent hardcodes.
- **Migration:** replace the 23 literals with `resolve_model(<role>)`; delete the redundant config surfaces (keep one); fix the Mac-hardcoded `llm_providers.yml` path bug.

**Payoff:** (a) the BioMate×LLM matrix becomes a one-value sweep (unblocks S5.4); (b) BYOK "all-tasks" becomes real (unblocks the unified-LLM feature for Chinese-provider users); (c) stale models are fixed once and audited centrally.

This is the same fragmentation pattern already flagged for data sources ([[data_source_fragmentation]]) — three siloed registries where one belongs — now for LLM selection. The fix is the same: one registry/resolver all surfaces read.
