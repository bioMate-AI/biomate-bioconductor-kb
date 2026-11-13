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

## Galaxy (Python) side — routed per request

Galaxy's own LLM calls for a China user (workflow search / re-rank, parameter extraction, research,
findings, autofix, target ID, IND narratives, workflow generation …) follow the same policy.

**How the policy reaches Galaxy (Node, `server/galaxy-llm-policy-header.ts`).** Every request Node
sends to Galaxy while serving a user carries

```
X-BioMate-LLM-Policy: region=cn; model=<the resolved Chinese model>   # China user
X-BioMate-LLM-Policy: region=intl                                     # everyone else
```

It is set in the two ways Node reaches Galaxy:
- `installGalaxyFetchPolicy()` (in `index.ts`) wraps the global `fetch` once and adds the header to
  every request whose origin is Galaxy's (`GALAXY_URL` / `GALAXY_INTERNAL_URL` /
  `localhost:8081`). That covers `fetchGalaxyAsUser`, `backendPassthrough` and the ~120 direct
  `fetch(`${GALAXY_URL}/…`)` calls in `routes.ts`, `galaxy-assistant.ts` and the services,
  including ones added later. A wrapper was chosen over editing each call site so that new
  Galaxy calls are covered by construction.
- `GalaxyAPIProxy`'s axios client adds it in a request interceptor (the only axios client that
  talks to Galaxy).

The user's own OpenRouter key is never sent; Galaxy uses the deployment's credential.

**Trust (deliberate choice).** The header can only RESTRICT a request to Chinese models: with no
header, or with `region=intl`, Galaxy uses its ordinary chain, so a forged header can never lift
the restriction. A forged `region=cn` only restricts the forger (and spends the deployment's
Chinese-model key, which that user could equally do through the chat). `model=` is honoured only
when it names a Chinese model; anything else becomes the Chinese default. So no shared secret is
needed. As hygiene, Node also strips any browser-sent copy of the header
(`stripInboundLlmPolicyHeader`, the first middleware) and its own value always overrides.

**Galaxy (`galaxy/ai/llm_region.py`).**
- `LlmPolicyMiddleware` (pure ASGI, added in `fast_app.initialize_fast_app`) puts the parsed
  header in a `ContextVar` for the whole request: FastAPI routes, their background tasks, the
  threadpool sync endpoints run in, and the WSGI-mounted legacy app (a2wsgi copies the context).
- `cn_route()` is the single question every chokepoint asks: `None` outside the region, else the
  Chinese route, else `ChineseModelUnavailable` (fail closed). Credentials: `OPENROUTER_ZH_API_KEY`
  → `OPENROUTER_API_KEY` → an on-prem `LLM_API_URL` whose `LLM_MODEL` is Chinese.
- A FastAPI exception handler turns `ChineseModelUnavailable` into **503
  `{"code": "cn_model_unavailable"}`**.
- **Threads.** Python 3.9 starts every thread with an empty context, so a request's policy was lost
  the moment a handler handed work to a thread (research fan-out, the run launch / monitor thread,
  parallel re-rankers …). `install_thread_context_propagation()` fixes that boundary once:
  `ThreadPoolExecutor.submit` (also `map` and `loop.run_in_executor`) and `Thread.start` run the
  work in a copy of the submitter's context. Threads started at boot (pollers) copy the boot
  context, which has no policy.
- **Runs.** The run record stores `llm_policy` at launch (pre-record, full record, auto-reroute).
  The run's own launch / monitor threads inherit the request context. The completion poller /
  orphan finalizer runs in any worker's poller thread, outside the request: `finalize_orphaned_run`
  re-enters the recorded policy (`run_policy_scope`), so a China-region run's QC, autoloop and
  findings LLM calls stay on a Chinese model. Runs launched before this change have no
  `llm_policy` and keep the ordinary chain.

**Chokepoints covered:**

| Chokepoint | China-region behaviour | Callers |
|---|---|---|
| `LLMClient.generate_async` (and `generate`, whose worker thread now carries the context) | Chinese model via `cn_generate` | every `LLMClient` user: ai_assistant search / arbiter / extract_params / re-rank, research_agent, findings (`ai/ai_assistant.py`), workflow generation, llm_router, target ID, autofix3, `/internal/llm/generate` |
| `generate_with_fallback` | Chinese model (never the Gemini → Claude → GPT chain) | the chain itself, for any direct caller |
| `gemini_flash.call_gemini_flash` / `call_gemini_flash_vision` | Chinese model (vision as an image part) | classifiers, research figure reading, IND / audit fallbacks |
| `workflow_ops.UnifiedLLMClient.call` | Chinese model, same return shape as the provider the caller named | auto_healer, log_analyzer, query_agent, autofix agent |
| `/api/ai_assistant/paperqa_synthesize` | litellm `openrouter/<model>` (or the on-prem endpoint) with local sparse embeddings — no paper text to Anthropic / OpenAI | research synthesis over uploaded PDFs |
| `/api/chat` (Galaxy's job-error wizard, OpenAI) | Chinese model | tool-error explanations |
| `/internal/llm/generate` | skips the SFT-gold adapter (not a Chinese-vendor model); `LLMClient` as above | Node `llmGenerate` (China users already go direct on the Node side) |
| `ind_assembly` frontier path (GPT / Claude / Gemini) | Chinese model stands in for the frontier model; then the Qwen-based Modal / vLLM / local paths | IND narratives |
| `regulatory_auditor._call_llm_judge` | Chinese model, no Anthropic / Gemini fallback | IND audit |
| `biological_logic_detector`, `dual_llm_converter_system`, `workflow_ops.parameter_analyzer` | Chinese model | workflow conversion / parameter analysis |
| `cryo_em_knowledge.rag_index._embed_with_anthropic` | no text sent to Anthropic; the deterministic embedding it always returned | cryo RAG index build |

**Not covered (none reachable from a user request):**
- `chain_composer/domain_reclassifier.openrouter_llm` — an offline catalog-audit CLI that reads
  `~/.config/biomate/openrouter.key`.
- `workflow_ops/autofix/fixers/pure_llm_fixer.PureLLMAutoFixer` — exported, never constructed
  (an Anthropic tool-use loop).
- `agents/research_agent._get_anthropic_client` — defined, never called.
- `target_id/bench_targetid_llm*.py`, the evaluation / training CLIs (`auto_retrain`,
  `regulatory_training_jobs_cli`) — offline jobs with no user.
- Celery / cron jobs not tied to a run carry no user region and are unchanged.
- `dual_llm_converter_system` is patched but does not load on dev today (the `google` package is
  not installed in the Galaxy container) — a pre-existing condition.
- Tool-use loops on the China route are text-only: the autofix agent's Anthropic tool calls get a
  plain text answer from the Chinese model (it treats that as the final answer).

## Model set — one Chinese model per role (2026-11-12)

China-region users run each role on its own Chinese model, mirroring the English hybrid
(`CN_MODEL_SET` in `frontend/server/llm-region-policy.ts`; the backend chain is mirrored as
`CN_GALAXY_CHAIN` in `backend/lib/galaxy/ai/llm_region.py`, parity-tested). All are reached through
OpenRouter and were checked on OpenRouter's live `/models` list on 2026-11-12; all support tool
calling.

| Role | English today (dev) | Chinese set | Env override |
|---|---|---|---|
| Intent / task breakdown | GLM 5.2 via OpenRouter (`BIOMATE_INTENT_MODEL`); code default Gemini 3.8 Flash. A Gemini 3.1 Pro tier exists, but `pickGeminiIntentModel` currently always returns Flash. | `z-ai/glm-5.2` | `BIOMATE_CN_INTENT_MODEL` |
| Main reply + agentic tool loop | GPT-5.6 Luna (`BIOMATE_RESPONSE_MODEL`); code default Gemini 3.8 Flash; Claude Sonnet 4.5 fallback | `deepseek/deepseek-v4.1-flash` (tools + images) | `BIOMATE_CN_RESPONSE_MODEL` (older alias `OPENROUTER_ZH_DEFAULT_MODEL`) |
| Hard / long reasoning | Gemini 3.1 Pro / Opus / thinking calls | `deepseek/deepseek-v4-pro` (text only) | `BIOMATE_CN_REASONING_MODEL` |
| Lightweight: tool ranking, titles, session memory, notes, compressor | Claude Haiku 4.5; Gemini Flash (`callGeminiFlash`) | `qwen/qwen3.5-flash-02-23` (tools + images) | `BIOMATE_CN_LIGHT_MODEL` |
| Image reading | the reply model | `deepseek/deepseek-v4.1-flash` | `BIOMATE_CN_VISION_MODEL` |
| Backend chain (`llmGenerate`, Galaxy `LLMClient`) | Gemini Flash → Claude Sonnet → GPT | `deepseek/deepseek-v4.1-flash` → `z-ai/glm-5.2` → `qwen/qwen3.5-plus-20260420`, then fail closed | `BIOMATE_CN_GALAXY_CHAIN` (comma list) |

**Benchmark status.** GLM 5.2 and the DeepSeek models have been measured on BioMate's evals. The
Qwen picks (3.5 Flash, 3.5 Plus) were chosen on capability (tools, images, context) and price. They
need the routing and tool-call benchmarks before being treated as final.

**How each role is reached:**
- **Intent:** the decomposition call uses `route.models.intent` on the user's Chinese route.
- **Reply, tool loop, light, reasoning and images:** these go through Anthropic-SDK calls, served
  by `cnRoleMessagesClient`. That client picks the role from the model the English code asked for:
  - Haiku-class → light;
  - Pro / Opus / a `thinking` call → reasoning;
  - a call carrying images → vision;
  - anything else → response.
  The English side already chooses a model per role, so the Chinese set follows the same split.
  Both the plain `_getClaude()` path and the OpenRouter agentic override use this client for China
  users.
- **`callGeminiFlash`:** the light model.
- **`llmGenerate`:** walks the chain (`cnChainCompletion`). The first model that answers wins, and
  `modelUsed` / `fallbackDepth` report which one did.
- **Galaxy:** tries the model Node names in the header first, then `CN_GALAXY_CHAIN`, in
  `cn_generate` / `cn_generate_sync`. On-prem routes have one model for every role.

**Overrides.** Every override must itself be a Chinese model (`isChineseModel`). A non-Chinese value
is ignored with a warning and the role keeps its default. A chain override with no Chinese entries
left falls back to the default chain.

**User's pick.** A China user's Chinese pick in Settings replaces the response role only. Intent,
light, reasoning, vision and the chain keep the set.

On the English side, `selected_model` with an OpenRouter key drives every Anthropic-SDK call through
the shim (`openaiCompatMessagesClient` with one fixed model), including Haiku-class light calls, but
not intent or `callGeminiFlash`. The Chinese side deliberately keeps light calls on the light model.

**Identity.** The MODEL IDENTITY block names the response model, the one the user talks to. For
China users it adds that background steps may run on other Chinese models from the same set. The
chat label stays the response model.

**Tests:**
- `frontend/server/llm-region-model-set.test.ts` (12);
- the updated `llm-region-policy.test.ts` (25);
- `backend/lib/galaxy/ai/tests/test_llm_region.py` tests 10–12: chain parity with Node, fallthrough
  that never leaves the list, and overrides that stay Chinese.

## Environment needed

| Var | Where | Effect |
|---|---|---|
| `OPENROUTER_ZH_API_KEY` | `/opt/biomate/.env` (read by BOTH the frontend and the Galaxy containers) | Chinese model for China users without their own OpenRouter key. **Without it (and without `OPENROUTER_API_KEY` or an on-prem Chinese `LLM_API_URL`) every China user's LLM call fails closed.** On dev today, that would be every user with a Chinese UI, a Chinese browser, or a CN/HK/MO/TW IP. |
| `OPENROUTER_ZH_DEFAULT_MODEL` (optional) | same | Chinese default model; must be a Chinese vendor, otherwise it is ignored |

## Tests

| Test file | Count | What it covers |
|---|---|---|
| `server/llm-region-policy.test.ts` | 25 | OR logic; CN/HK/MO/TW positives; US/JP/SG negatives; IPv6; the allow-list; identity; fail-closed; `resolveChatLlm` (China user + Anthropic key + Claude pick → Chinese; US user + GLM keeps GLM); the `callGeminiFlash` / `llmGenerate` chokepoints |
| `server/llm-policy-routes.test.ts` | 9 | Real express: `/api/llm/policy`; the 400s for China users; US saves are unchanged |
| `server/galaxy-assistant-model-identity.test.ts` | 5 | The identity block in the built reply prompt and the OpenRouter prompt; `responseModelFor`; under a China user Gemini is `null` and `_getClaude` returns the Chinese shim or throws |
| `client/src/components/settings-dialog.llm-region.test.tsx` | 5 | China picker (no Claude chip, Chinese default, inline rejection, no Anthropic provider); the picker outside the region is unchanged |
| `server/galaxy-llm-policy-header.test.ts` | 5 | The header value (model named, never the key); fetch to Galaxy carries it (and only to Galaxy, overriding a forged one); the inbound strip; GalaxyAPIProxy's axios requests carry it |
| `backend/lib/galaxy/ai/tests/test_llm_region.py` | 8 | Header parsing (no non-Chinese model, junk = ordinary chain); the ASGI middleware; fail-closed; gemini_flash (text + vision) never builds a Gemini client; LLMClient.generate_async / generate (worker thread) / the fallback chain; thread / executor / run_in_executor propagation; the orphan finalizer re-entering the run's recorded policy; allow-list parity with the Node module |

The Galaxy chokepoint, thread and finalizer tests (4–7 of `test_llm_region.py`) fail with the
pre-change chokepoints; the axios-interceptor test fails without the interceptor. Every modified
Galaxy module was loaded in dev's Galaxy Python 3.9 (read-only) — all load, except
`dual_llm_converter_system`, which already could not (no `google` package in the container).

The chokepoint, identity and picker tests failed on the pre-change code.
