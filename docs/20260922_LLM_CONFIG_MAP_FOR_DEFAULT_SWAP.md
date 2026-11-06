# LLM config map — for the (held) default-model swap to OpenAI gpt-6-luna

**Date:** 2026-09-22
**Status:** INVESTIGATION ONLY — the LLM default swap is **on hold** (user wants to examine model performance first). This doc preserves the map so we don't re-investigate.

## The single source of truth (frontend)
`frontend/server/galaxy-assistant.ts`
- **`ModelConfig` interface** — lines 268–279 (`intentModel`, `toolRankingModel`, `responseModel`, `enableThinking`, `thinkingBudget`).
- **`DEFAULT_MODEL_CONFIG`** — lines 322–328:
  - `intentModel: 'gemini-3.5-flash'`, `toolRankingModel: 'claude-haiku-4-5'`, `responseModel: 'gemini-3.5-flash'`.
- **Env overrides** — lines 332–333 (`BIOMATE_INTENT_MODEL_FLASH`, `BIOMATE_INTENT_MODEL_PRO`).
- **Resolution at construction** — lines 2608–2633 (merges `options.modelConfig`, then key-availability fallback).

## Provider selection = **model-id prefix** (the critical gap)
`generateResponse()` lines ~8645–8707:
- `responseModel.startsWith('gemini-')` → Gemini
- `responseModel.startsWith('claude-')` → Claude
- **else → fallback chain** (Gemini → Claude → OpenAI → Ollama), where the OpenAI fn reads `OPENAI_MODEL` env, **NOT `responseModel`**.

> **⚠️ Blocker for the swap:** setting `responseModel='gpt-6-luna'` will NOT route to OpenAI with that model — there is **no `gpt-*`/openai branch**. To make gpt-6-luna the default we must add an explicit OpenAI provider branch that honors `responseModel` (mirroring the gemini/claude branches), OR route via the OpenRouter path with `openai/gpt-6-luna`.

## Backend fallback chain
`backend/config/llm_providers.yml`: `gemini-3.1-pro-preview` → `gemini-3.5-flash` → `claude-sonnet-4-5` → `gpt-4o` → `qwen3:32b`. No gpt-6-luna. `frontend/server/llm-client.ts` delegates to `/internal/llm/generate` (this YAML), hardcodes no model.

## User BYOK / self-config (keep intact)
- UI: `settings-dialog.tsx` (LLM provider section ~1029–1198): Default / OpenRouter (BYOK) / Anthropic BYOK; model input for OpenRouter.
- Storage: `routes.ts` `GET`/`PATCH /api/user/llm-api-keys` → encrypted `users.llm_api_keys` jsonb (`{anthropic?, openrouter?, selected_model?}`).
- Chat turn: `routes.ts` ~6133–6156 decrypts per-request → `enrichedContext.{userAnthropicApiKey, openrouterKey, selectedModel}` → `processMessage`.
- OpenRouter path: `galaxy-assistant.ts` ~3789 (`new OpenAI({baseURL:'https://openrouter.ai/api/v1', apiKey})`), model = `context.selectedModel || 'deepseek/deepseek-chat'` (~2680–2705). **A user override always wins over the system default.**

## gpt-6-luna today
Only in archived eval results (`evaluation/datasets/public_export/results/openai_gpt-5.6-luna/…`) and the eval matrix runner — **not wired** to any live provider.

## Minimal-risk plan when we resume
1. Add an **OpenAI provider branch** in `generateResponse()` keyed on `responseModel.startsWith('gpt-')` → call OpenAI SDK with `responseModel` (base URL + `OPENAI_API_KEY`, reuse the OpenAI-SDK pattern already used for OpenRouter). Confirm the gpt-6-luna endpoint/base-url + key env.
2. Set `DEFAULT_MODEL_CONFIG.responseModel = 'gpt-6-luna'` (+ intent/ranking as desired) — single-line default change once the branch exists.
3. Prefer an env override (`BIOMATE_RESPONSE_MODEL`) so future swaps need no code change.
4. Leave BYOK/OpenRouter override path untouched (user selection already wins).
5. Verify on dev; then compare performance.
