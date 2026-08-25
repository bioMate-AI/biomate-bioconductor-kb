# Unified LLM Selection + Bring-Your-Own-Account (all-task) — Proposal

**Date:** 2026-08-24 · **Status:** proposal (not yet built) · **Owner:** Y. Zhang

Goal: **one unified model list** where a user picks any top model — foreign and Chinese in the
*same* list, not a siloed "Chinese" category — and can drive it with **their own provider account**,
and that model works for **all tasks (chat + workflow generation + tool use)**, not chat-only.

---

## 1. Current state (verified in code, 2026-08-24)

| Surface | Where | Behavior |
|---|---|---|
| Provider selector | `frontend/client/src/components/settings-dialog.tsx:1029-1031` | 3 fixed options: **BioMate Default** (shared Claude Sonnet 4.5), **OpenRouter (BYOK)**, **Anthropic (BYOK)** |
| Model picker | `settings-dialog.tsx:1059` | OpenRouter model is a **free-text slug** ("paste model slug from openrouter.ai/models") — no curated list |
| BYOK accepted providers | `frontend/server/routes.ts:6974` | `VALID_PROVIDERS = ['anthropic','openrouter']` only |
| Storage | `users.llm_api_keys` JSONB (encrypted `anthropic`,`openrouter` + `selected_model`) | per-user keys, encrypted |
| Backend model config | `backend/lib/galaxy/ai/config.py:26-30` | `llm_provider`/`llm_model`/`llm_base_url` — `base_url` exists but **not exposed per-user in UI** |
| Chinese providers | `config.py` `DEEPSEEK_API_KEY`/`ZHIPU_API_KEY`; `llm_router.py` `glm-4.7`; `llm_providers.yml` local `qwen3:32b` | **system-level only**, not user BYOK |
| **Task coverage of BYOK path** | `frontend/server/galaxy-assistant.ts` (OpenRouter branch) | **chat-only** — the BYOK/OpenRouter path does **not** do workflow generation; only the default Claude path does |

### Three gaps
1. **No unified curated list** — user must know exact slugs; top models aren't presented.
2. **Chinese users can't use their own accounts** — only route is OpenRouter (a middleman needing a
   foreign card; endpoint often slow/blocked from mainland China) or the *system's* shared key.
3. **BYOK models can't do the core product** — workflow generation is hard-wired to default Claude,
   so a user on their own key loses BioMate's differentiator.

---

## 2. Proposal

### 2.1 One unified model catalog (single list)
A single curated catalog surfaced in the selector — foreign and Chinese models **interleaved**, ranked
by capability/price, not grouped by nationality. Each entry:
```
{ id, display_name, provider, model_id, api_base, capabilities: [chat, workflow, tools], tier }
```
Seed set (illustrative, one flat list): Claude Sonnet/Opus, GPT-5.x, Gemini 2.5/3.x,
**DeepSeek-V3/R1, Qwen-Max/Plus, Kimi-K2, GLM-4.7**, Llama. Free-text slug stays as an "Advanced /
custom" escape hatch.

### 2.2 Bring-your-own-account for any provider (generic OpenAI-compatible)
All target providers expose **OpenAI-compatible** APIs — the same client the OpenRouter path already
uses. So BYOK generalizes to storing `{ provider, api_base, key, model }` per user and reusing one
OpenAI-compatible client. Native endpoints (so no OpenRouter middleman, RMB billing, China-reachable):

| Provider | api_base | example model |
|---|---|---|
| DeepSeek | `https://api.deepseek.com` | deepseek-chat / deepseek-reasoner |
| Alibaba DashScope (Qwen) | `https://dashscope.aliyun.com/compatible-mode/v1` | qwen-max |
| Moonshot (Kimi) | `https://api.moonshot.cn/v1` | kimi-k2 |
| Zhipu (GLM) | `https://open.bigmodel.cn/api/paas/v4` | glm-4.7 |
| OpenAI / Azure / any | provider base_url | gpt-5.x |

Changes: expand `VALID_PROVIDERS` → a generic `custom`/per-provider set; store `api_base` alongside
the encrypted key; the chat/agent client reads `{api_base, key, model}` from the user record.

### 2.3 The selected model must do ALL tasks (the hard part)
The differentiator is **workflow generation + tool use**, currently pinned to default Claude. To make
any selected model do all tasks:
- Route the **workflow-generation** and **tool-ranking** calls through the *same* user-selected model
  + endpoint (not a hard-wired Claude client).
- Workflow generation depends on **reliable structured/JSON tool-calling**. Models vary here, so the
  catalog marks a `workflow` capability flag per model, and the pipeline **degrades gracefully**: if
  the user's model fails structured workflow gen (schema-invalid output after N retries), fall back to
  the shared default for the *structured* step only, while chat/reasoning stay on the user's model.
- This keeps the promise ("your model does everything") while protecting workflow quality — and the
  hybrid rule+LLM extraction (per CLAUDE.md) already guards structured params, which helps weaker models.

### 2.4 Phasing
- **P1** — unified catalog UI + generic OpenAI-compatible BYOK (`{api_base,key,model}`), **chat**. Lets
  Chinese users use their own DeepSeek/Qwen/Kimi/GLM accounts immediately.
- **P2** — route workflow-gen + tool-ranking through the selected model; capability flags + graceful
  fallback for the structured step.
- **P3** — per-model capability probing / auto-fallback tuning; usage/cost accounting per BYO account.

### 2.5 Risks
- Structured-output/tool-call reliability varies by model → P2 fallback is essential; verify the
  "chat-only" limitation live before designing the workflow re-route.
- Key security: reuse existing encrypted `llm_api_keys` storage; never return keys to the browser.
- Endpoint reachability from the deployment region (not just the user's region).

---

**Next:** build P1 after the benchmark/manuscript work lands. This doc is the design of record; update
it as scope is verified (esp. the workflow-gen re-route in §2.3).
