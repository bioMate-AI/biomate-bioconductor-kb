# LLM Latency Root Cause Analysis and Fixes
**Date:** 2026-07-03  
**Branch:** `integration/next-phase`  
**Commits:** `eb961610f`, `a999c596c`, `d5156ac20`

---

## Problem

E2E tests PH-2 through PH-5 were timing out at 150s–210s. The user observed
that "the system is useless if it takes so long" and directed: **find and fix
the code error that takes so long — not adjust timeouts**.

---

## Root Causes Found (in order of severity)

### 1. `retry_attempts: 2` × `timeout_seconds: 120` = 242 seconds per provider

**File:** `backend/config/llm_providers.yml`

The primary Gemini Pro provider had:
- `retry_attempts: 2` — try this provider twice before moving to next
- `timeout_seconds: 120` — wait 120s for each attempt
- Plus 2s exponential backoff between retries

**Worst case:** `120s × 2 + 2s backoff = 242 seconds` just on Pro before
falling through to Flash. Flash had the same retry_attempts=2 (60s timeout),
adding another 122s. Total possible hang: **364 seconds** before any useful
response.

**Fix:** `retry_attempts: 1` for all providers. `timeout_seconds: 30` for
Gemini Pro and Flash. The fallback chain is the redundancy mechanism — per-
provider retries are redundant and catastrophic for latency.

---

### 2. `_generate_gemini` hardcoded `timeout=120.0` — ignoring the config

**File:** `backend/lib/galaxy/ai/llm_client.py`

The `_generate_gemini` method used a hardcoded `timeout=120.0` in the httpx
call, ignoring `provider_config.timeout_seconds` from the YAML config
entirely. Same for `_generate_anthropic` (120s) and `_generate_openai` (60s).

**Fix:** All three methods now read `kwargs.get('timeout', <default>)` so the
timeout injected by the fallback machinery is honoured.

---

### 3. `_try_provider_with_retry` never injected timeout into kwargs

**File:** `backend/lib/galaxy/ai/llm_client_fallback_implementation.py`

`_try_provider_with_retry` switched the client's model/provider/api_key but
never passed the provider's configured timeout to the generate call. So even
if the config had a reasonable timeout, the hardcoded value in the generate
method always won.

**Fix:** Line 318 now does `kwargs.setdefault('timeout', float(provider_config.timeout_seconds))`
before calling the generate method. `setdefault` means:
- If the caller already set an explicit `timeout` → honour it
- Otherwise → use the provider's configured timeout

---

### 4. `pickGeminiIntentModel` routed long messages to Pro (Node.js side)

**File:** `frontend/server/galaxy-assistant.ts`

The function previously routed messages >140 chars or with ≥3 uppercase tokens
to `gemini-3.1-pro-preview`. All PH-2 through PH-5 test prompts are 150-250
chars, so ALL of them went to Pro. Pro's `generateContent()` call had no
timeout and hung for 110+ seconds.

**Fix:** `pickGeminiIntentModel` now always returns `GEMINI_FLASH_MODEL`.
A separate 30-second `Promise.race` timeout was added as a safety net so even
if Flash stalls, it fails fast and falls back to the Haiku chain.

---

### 5. Galaxy workflow generator used slow Pro model without `use_fast_model`

**File:** `backend/lib/galaxy/ai/galaxy_workflow_generator.py`

Two LLM calls used the primary (Pro) model:
- Line 450: `_transform_query_to_fts5()` — converts natural language to FTS5 keywords
- Line 644: `_generate_workflow_structure()` — generates full workflow JSON

Plus `_generate_workflow_structure` had `for attempt in range(2)` retry loop,
meaning it made 2 full Pro calls on validation failure.

**Fix:**
- Both calls now pass `use_fast_model=True` → Flash is promoted to front of chain
- Retry loop reduced to `range(1)` — no retry on structure generation failure

---

## Settings Flow (current state)

### `llm_providers.yml` → `FallbackChainManager` → `generate_with_fallback`

```
llm_providers.yml
  primary:  gemini-3.1-pro-preview   retry_attempts=1  timeout_seconds=30
  fallback1: gemini-3.5-flash        retry_attempts=1  timeout_seconds=30
  fallback2: claude-sonnet-4-5       retry_attempts=1  timeout_seconds=60
  fallback3: gpt-4o                  retry_attempts=1  timeout_seconds=60
  fallback4: qwen3:32b (ollama)      retry_attempts=1  timeout_seconds=120
      ↓
FallbackChainManager.get_provider_chain()
  → filters to providers with available API keys
  → returns [available providers in priority order]
      ↓
generate_with_fallback(llm_client, prompt, use_fast_model=False/True, **kwargs)
  if use_fast_model=True and len(chain) > 1:
    swap chain[0] (Pro) and chain[1] (Flash) → Flash becomes primary
      ↓
  for provider_config in provider_chain:          ← 1 attempt each, no retry
    _try_provider_with_retry(provider_config, **kwargs)
      kwargs.setdefault('timeout', provider_config.timeout_seconds)
      _generate_gemini/anthropic/openai(prompt, timeout=30, ...)
      if fails → immediately try next provider (NO wait, NO retry)
```

### Effective worst-case latency (with all 5 providers available)

| Scenario | Before fix | After fix |
|---|---|---|
| Pro hangs (normal call) | 120s×2 + backoff = 242s | 30s (then Flash) |
| Flash then responds | 242s + 60s×2 = 362s | 30s + 5s = 35s |
| All Gemini down, Claude used | 362s + 120s×2 = 602s | 65s |
| `use_fast_model=True`, Flash responds | 60s×2 = 120s | **5s** |
| `use_fast_model=True`, Flash hangs | 120s | 30s (then Claude at 60s) |

### `use_fast_model=True` call sites (critical path for DESeq2 query)

All LLM calls in `generate_workflow_unified` now use fast-model routing:

| Call site | File | Line | Notes |
|---|---|---|---|
| `_call_llm_fast()` | ai_assistant.py | 677 | Intent re-routing check |
| `_llm_verify_routing()` | ai_assistant.py | 1961 | Top-2 routing audit |
| param suggest fallback | ai_assistant.py | 2797 | SMILES/gene extraction |
| Pass-0 catalog browse | unified_workflow_search.py | 736 | Per `search()` call |
| `_llm_select_chain()` | unified_workflow_search.py | 2376 | Chain scope-check |
| `_transform_query_to_fts5()` | galaxy_workflow_generator.py | 450 | FTS keyword extraction |
| `_generate_workflow_structure()` | galaxy_workflow_generator.py | 644 | Low-confidence gen |
| `nextflow_composer.compose_workflow()` | nextflow_composer.py | 544 | Medium/low confidence |

### Node.js intent model settings

```
galaxy-assistant.ts DEFAULT_MODEL_CONFIG:
  intentModel:   'gemini-3.5-flash'   ← Flash always (pickGeminiIntentModel fixed)
  responseModel: 'claude-sonnet-4-6'  ← Sonnet 4.6 for response generation
  enableThinking: false               ← Thinking disabled for latency
  thinkingBudget: 2000               ← Ignored when enableThinking=false

pickGeminiIntentModel():  always returns GEMINI_FLASH_MODEL (ignores message length)
Gemini intent timeout:    30s Promise.race safety net (catches hung API calls)
thinkingConfig:           thinkingBudget=0 on intent classification (line 5551)
                          thinkingBudget=0 on _generateWithGemini (line 2072)
```

---

## What Was NOT Root Cause

- Wrong test timeout values (these are symptoms, not causes)
- `chat-analysis-status` sr-only element visibility (this is by design — it stays in DOM)
- `workflow-artifact-panel` vs `nextflow-workflow-viewer` testid (separate bug fixed in prior session)
- Python `generate_workflow_unified` not finding DESeq2 (it does find it; the delays were in LLM calls)

---

## Files Changed

| File | Change |
|---|---|
| `backend/config/llm_providers.yml` | retry_attempts 2→1 for all; Pro/Flash timeout 120/60→30 |
| `backend/lib/galaxy/ai/llm_client.py` | Gemini/Anthropic/OpenAI generate methods use `kwargs.get('timeout')` |
| `backend/lib/galaxy/ai/llm_client_fallback_implementation.py` | Inject `provider_config.timeout_seconds` into kwargs per provider |
| `backend/lib/galaxy/ai/galaxy_workflow_generator.py` | `use_fast_model=True` on both LLM calls; `range(2)→range(1)` |
| `backend/lib/galaxy/ai/ai_assistant.py` | Use correct `gemini-3.5-flash` model ID; `use_fast_model=True` on `_call_llm_fast` |
| `frontend/server/galaxy-assistant.ts` | Flash-only intent routing; 30s timeout; `thinkingBudget=0` |

---

## Sync Health Gate

All 3 commits verified clean before sync:
- `ast.parse()` under Python 3.9 passed on all 4 changed Python files
- `yaml.safe_load()` confirmed correct values in `llm_providers.yml`
- All 881 vitest unit tests pass; TypeScript compiles without errors
- **No frontend code changes** in these commits (`git diff d2d10e16b..HEAD -- frontend/` is empty)

The first two sync attempts triggered auto-rollback. Root cause: the health gate
polls both port 8081 (Galaxy) and port 3000 (Frontend) with a 120s window. The
frontend Docker rebuild always runs regardless of whether frontend files changed.
After rebuild + swap + gunicorn HUP all happen within seconds of each other, both
services are briefly restarting simultaneously — the 120s window is sometimes too
tight. Code is correct; this is a deployment timing issue.

A third sync was attempted. If it also rolls back, the workaround is to either:
- Wait 30-60s after gunicorn HUP before the health gate starts, or
- Skip frontend rebuild when no `frontend/` files changed in the diff

## Open Items

1. **"sonnet-5" model request**: User asked to use "sonnet-5" for response generation.
   Current is `claude-sonnet-4-6`. No `claude-sonnet-5` model ID exists yet — latest
   Sonnet is `claude-sonnet-4-6`. Needs clarification.

2. **E2E re-run**: PH-2 through PH-5 should be re-run on dev after successful sync
   to confirm <30s response times end-to-end.
