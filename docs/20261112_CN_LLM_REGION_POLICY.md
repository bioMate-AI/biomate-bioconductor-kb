# Chinese-LLM region policy (2026-11-12)

## Why

The founder's requirement: users in the Chinese region may use only Chinese large models (国产大模型). BioMate must switch to one correctly, and it must say plainly which model the user is on.

What was found on dev on 2026-11-12:

- **The model guessed its own identity.** A user asked "which llm you are using right now" and BioMate answered "I'm Claude, made by Anthropic". In fact the intent step ran on GLM (`z-ai/glm-5.2`, the deployment's decomposition model) and the reply ran on Gemini (`gemini-3.8-flash`). Nothing told the model what it was.
- **Chinese routing was unreliable:**
  - `isChineseBrowser` let the UI language override everything, so an English UI on a Chinese browser or IP was not routed;
  - the IP was never consulted, because dev receives no CDN geo header;
  - a stored Anthropic key or a non-Chinese Settings pick always won;
  - dev has no OpenRouter or Chinese-model key, so the Chinese path never activated at all.

## Policy

**A China user** has ANY of these signals (an OR, not a precedence order):

| Signal | Source |
|---|---|
| (a) UI / Settings language is Chinese | chat `context.uiLanguage`; on every other request, the `biomate_ui_lang` cookie set by `client/src/lib/i18n.ts` from the Settings language |
| (b) The browser's **primary** Accept-Language is `zh*` | `zh`, `zh-CN`, `zh-TW`, `zh-HK`, … (a `zh` that is only a fallback preference does not count) |
| (c) The client IP geolocates to `CN_REGION_COUNTRIES` = CN, HK, MO, TW | `req.ip` (Express `trust proxy` 1) against `server/data/cn-region-ip-ranges.json`; a CDN country header with one of the same four codes also counts |

**Chinese model** = an OpenRouter vendor prefix in `CHINESE_MODEL_VENDORS`:
`deepseek`, `qwen`, `z-ai`, `moonshotai`, `minimax`, `baidu`, `tencent`, `bytedance`, `bytedance-seed`, `stepfun`, `inclusionai`, `meituan`, `xiaomi`, `thudm`, `01-ai`. These were verified against `openrouter.ai/api/v1/models` on 2026-11-12. Bare provider-native names such as `qwen-max`, `glm-*` and `deepseek-*` also count, which covers the on-prem `LLM_MODEL`.

**One direction only.** Only China users are restricted. Everyone else keeps today's behaviour: every model (open and proprietary, Chinese included), their own Anthropic and OpenRouter keys, free-text slugs, and the existing defaults (the GLM Settings default, `OPENROUTER_DEFAULT_MODEL`).

## Decision table (chat turn — `resolveChatLlm`, re-run on every request)

| User | Stored keys / pick | Result |
|---|---|---|
| China | Own OpenRouter key + Chinese pick (e.g. `moonshotai/kimi-k3`) | That pick, own key |
| China | Own OpenRouter key + non-Chinese pick (e.g. Claude) | Chinese default (`zhDefaultModel()`, default `deepseek/deepseek-v4.1-flash`), own key |
| China | Own Anthropic key only | Anthropic key dropped; Chinese default through `OPENROUTER_ZH_API_KEY` → `OPENROUTER_API_KEY` → on-prem Chinese `LLM_API_URL` |
| China | Nothing, and no Chinese credential in the deployment | **Fail closed:** SSE `error` with `code: cn_model_unavailable`, "Chinese model unavailable — contact the administrator. 国产大模型暂不可用，请联系管理员。" Never a silent Claude/Gemini answer |
| Outside | Own OpenRouter key + GLM | GLM (unchanged) |
| Outside | Own Anthropic key | Unchanged |
| Outside | Nothing | Unchanged: `OPENROUTER_API_KEY` + `OPENROUTER_DEFAULT_MODEL`, else on-prem `LLM_API_*`, else built-in Gemini/Claude |

A non-Chinese `OPENROUTER_ZH_DEFAULT_MODEL` override is ignored for China users.

## Enforcement — where (Node)

**Per-request state.** `llmPolicyStorage` (an AsyncLocalStorage) carries `{region, reasons, cnRoute}`. It is set in two places:

- by `llmRegionMiddleware` for EVERY request, mounted in `index.ts` after body, session and auth parsing; this uses the deployment's keys;
- again by the chat stream with the user's own key (`routes.ts`, around `processMessage`).

**Chokepoints that read it.** For a China user, each one goes to the Chinese model, or throws `ChineseModelUnavailableError`:

| Chokepoint | China-user behaviour | Callers covered |
|---|---|---|
| `callGeminiFlash` (`gemini-flash.ts`) | `cnCompletion` on the Chinese route | session memory, inline-data extraction, domain classification, chat title / summary, notes, evidence, routes.ts findings helpers |
| `llmGenerate` (`llm-client.ts`) | `cnCompletion` (the backend `/internal/llm/generate` chain is not called) | intent fallback, UQU, context compressor, iterative workflow generator, prerequisites validator, routes.ts report helpers |
| `GalaxyAssistant._getClaude()` | No per-request client → `policyMessagesClient` (the OpenAI-compatible Messages shim on the Chinese model) | every `messages.create`: response, agentic tool loop, run_code repair, inline data, intent Claude fallback |
| `GalaxyAssistant.gemini` (now a getter) | `null`, so every Gemini branch falls through to the clients above | intent Gemini path, the Gemini response path, billing/after-run Gemini helpers |
| Intent model (`openrouter:<slug>` decomposition) | Kept if the configured model is Chinese; otherwise the user's Chinese route (on-prem via `cnCompletion`) | intent classification and decomposition |
| Chat response | Through the existing OpenRouter agentic shim (`_anthropicOverride` + `_openrouterAgentic`) with the Chinese model; the user's Anthropic key is ignored in `processMessage` | the reply, tools, workflows, run_code |

**Not covered on the Node side:**
- `dataset-validator.ts` and `routes.ts` use OpenAI SDK clients (`OPENAI_API_KEY`, embeddings / validation). They are unset on dev, but they do not consult the policy.
- `localOnly()` deployments (`BIOMATE_LOCAL_ONLY=1`) run their own local model. The policy does not apply there, since the data and the model are local.

**Settings (Node routes, `llm-policy-routes.ts`):**
- `GET /api/llm/policy` returns `{region, reasons, regionCountries, allowedVendors ('all' for others), defaultModel, anthropicKeyAllowed, chineseModelAvailable}`.
- `PATCH /api/user/llm-api-keys` rejects, for China users only:
  - a non-Chinese `selected_model`: **400 `model_not_allowed_in_region`**;
  - an Anthropic key: **400 `provider_not_allowed_in_region`**.
  Removing a key is always allowed.

**Client:**
- `lib/llm-region.ts` provides `useLlmPolicy`, the picker groups and `modelLabel`.
- **China users in the Settings picker** get Chinese chips only, the Chinese default (a stored non-Chinese pick is replaced) and no Anthropic provider option. They see a region note, and a typed non-Chinese slug is rejected inline in en and zh.
- **Everyone else** sees the picker unchanged.
- **Chat label (`chat-model-label`):**
  - it comes from the server's new `model` SSE event, i.e. the policy-resolved model that actually answers, not the stored pick;
  - it reads "Model: DeepSeek V4.1 Flash (DeepSeek · Chinese model)" or "模型：DeepSeek V4.1 Flash（深度求索 · 国产大模型）";
  - a user outside the region on GLM sees "Model: GLM 5.3 Prime (Zhipu AI · Chinese model)".

## Identity — what BioMate says about itself

The chat stream resolves the answering model (`GalaxyAssistant.responseModelFor`) and sends it in the `model` event. It also puts a **MODEL IDENTITY** block (`modelIdentityDirective`) into the main reply system prompt and the OpenRouter chat prompt. The block:
- names the exact model, its slug and its vendor;
- for China users, says the reply runs on a Chinese large model (国产大模型) and gives the wording to use;
- tells the model to answer "which model / LLM are you" exactly from the block, and never to claim to be Claude, GPT, Gemini or any other model.

It applies to every user.

## IP data

- **File:** `frontend/server/data/cn-region-ip-ranges.json` (~1.1 MB; 17,259 IPv4 + 9,551 IPv6 merged ranges for CN/HK/MO/TW). It is inlined into the server bundle by esbuild.
- **Regeneration:** run `python3 scripts/gen_cn_region_ip_ranges.py` monthly.
- **Source:** DB-IP "IP to Country Lite", 2026-11 (CC BY 4.0, "IP Geolocation by DB-IP").
- **Why not APNIC:** I chose a geolocation database rather than APNIC's delegated allocation file. APNIC records registrations, not locations, and misses blocks registered elsewhere but used in the region. The dev visitor `47.242.215.11` (Alibaba Cloud Hong Kong, an ARIN registration) is not in APNIC's HK data but is HK in DB-IP. The coordinator's message suggested APNIC; this is a deliberate deviation for that reason.

## Python (Galaxy) side — NOT yet routed per request

Galaxy's `LLMClient` uses the deployment provider (`GALAXY_AI_LLM_PROVIDER` / `llm_providers.yml`: Gemini → Claude → GPT …) for every caller. There are about 45 modules that call an LLM. A China user's chat can trigger these Galaxy LLM calls:

| Endpoint (called by Node during chat / after a run) | LLM call |
|---|---|
| `POST /api/ai_assistant/search_nextflow_workflow` | `webapps/galaxy/api/ai_assistant.py:2511` (arbiter), `:2851` (param extraction) |
| `POST /api/ai_assistant/extract_params` | `ai_assistant.py:3107`, `:3186` (workflow search re-rank) |
| `POST /api/ai_assistant/research_query` | `ai_assistant.py:5724`; `ai/agents/research_agent.py:1373` |
| `POST /api/nextflow/analyze-outputs` (findings) | `webapps/galaxy/api/nextflow_executor.py:3307` and the findings path; `ai/ai_assistant.py:3371` |
| Autofix after a failed run | `webapps/galaxy/api/autofix3.py:211`, `:535`, `:702` |
| Target ID | `webapps/galaxy/api/target_id_api.py:107` |
| Workflow generation (`ai/ai_assistant.py`) | `:791`, `:1502`, `:5258`; `ai/llm_router.py:174` |

**Proposed fix (not implemented here):**
- Node adds `X-BioMate-LLM-Region: cn` and `X-BioMate-LLM-Model: <slug>` in `fetchGalaxyAsUser` / `userProxy` from `llmPolicyStorage`.
- A Galaxy middleware sets a `contextvar`. `LLMClient.generate*` honours it by calling the OpenAI-compatible endpoint (OpenRouter with `OPENROUTER_ZH_API_KEY`) with that model, or raising for a China user with no key.
- Caveat: `LLMClient.generate()` runs `asyncio.run` in a `ThreadPoolExecutor`, and `contextvars` do not cross that boundary unless they are copied (`contextvars.copy_context().run`).
- This needs a decision and a Galaxy deploy. Until then, the Galaxy-side calls above still use the deployment's chain for China users.

## Environment needed

| Var | Where | Effect |
|---|---|---|
| `OPENROUTER_ZH_API_KEY` | `/opt/biomate/.env` (frontend container) | Chinese model for China users without their own OpenRouter key. **Without it (and without `OPENROUTER_API_KEY` or an on-prem Chinese `LLM_API_URL`) every China user's LLM call fails closed.** On dev today, that would be every user with a Chinese UI, a Chinese browser, or a CN/HK/MO/TW IP. |
| `OPENROUTER_ZH_DEFAULT_MODEL` (optional) | same | Chinese default model; must be a Chinese vendor, otherwise it is ignored |

## Tests

| Test file | Count | What it covers |
|---|---|---|
| `server/llm-region-policy.test.ts` | 25 | OR logic; CN/HK/MO/TW positives; US/JP/SG negatives; IPv6; the allow-list; identity; fail-closed; `resolveChatLlm` (China user + Anthropic key + Claude pick → Chinese; US user + GLM keeps GLM); the `callGeminiFlash` / `llmGenerate` chokepoints |
| `server/llm-policy-routes.test.ts` | 9 | Real express: `/api/llm/policy`; the 400s for China users; US saves are unchanged |
| `server/galaxy-assistant-model-identity.test.ts` | 5 | The identity block in the built reply prompt and the OpenRouter prompt; `responseModelFor`; under a China user Gemini is `null` and `_getClaude` returns the Chinese shim or throws |
| `client/src/components/settings-dialog.llm-region.test.tsx` | 5 | China picker (no Claude chip, Chinese default, inline rejection, no Anthropic provider); the picker outside the region is unchanged |

The chokepoint, identity and picker tests failed on the pre-change code.
