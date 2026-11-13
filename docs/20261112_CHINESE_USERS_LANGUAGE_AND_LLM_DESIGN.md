# Chinese Users: LLM Region Policy, Chinese Model Set, and the Language Boundary

**Date:** 2026-11-12
**Status:** policy and model set implemented on branches, not yet deployed (see §8); language-boundary work proposed, not started.
**Related:** `docs/20261112_CN_LLM_REGION_POLICY.md` (implementation detail of the region policy),
`docs/20261111_OPENROUTER_VISION_AND_REASONING_BUDGET.md` (why DeepSeek V4.1 Flash is the Chinese reply model).

---

## 1. Background

BioMate serves two user populations from one deployment:

- users outside Greater China, who may use any model;
- users in Greater China, or using BioMate in Chinese, who must be served **only by Chinese large models (国产大模型)**.

Two problems triggered this work on 2026-11-12:

1. A dev user asked "which llm you are using right now" and BioMate answered "I'm Claude, made by Anthropic".
   This was false. The user had GLM selected in Settings, the intent step ran on `z-ai/glm-5.2`, and the reply
   was logged as `gemini-3.8-flash`. Nothing told the model which model it was, so it guessed.
2. Chinese users were not reliably served by Chinese models:
   - the user's own model selection or own Anthropic key always overrode the Chinese route;
   - the three region signals were not combined (UI language overrode everything; IP was consulted only when
     the browser sent no language);
   - the IP check relied on CDN geo headers that dev never receives;
   - dev had no Chinese-model credential at all, so the Chinese route never activated.

This document records the policy decided with the founder, the model sets, and the open language-boundary risk:
the platform's databases, catalogues and skills are English, while part of the users will now chat in Chinese.

---

## 2. Region policy (decided)

### 2.1 Who is a "China-region user"

A user is China-region if **any one** of these holds (logical OR), evaluated on every request:

| Signal | Source |
|---|---|
| (a) Chinese selected in BioMate Settings / UI language is Chinese | chat request `uiLanguage`; the `biomate_ui_lang` cookie set by the client |
| (b) Browser primary language is Chinese | first tag of `Accept-Language` is `zh` or `zh-*` (zh-CN, zh-TW, zh-HK …) |
| (c) Client IP is in mainland China, Hong Kong, Macau or Taiwan | IP range table (CN, HK, MO, TW), plus CDN country headers with those codes when present |

The four region codes are kept in one constant (`CN_REGION_COUNTRIES = ['CN','HK','MO','TW']`) so the scope can
be changed in one place. The founder decided the scope in three steps on 2026-11-12: mainland China → plus Hong Kong
→ plus Macau and Taiwan.

**IP data source.** DB-IP "IP to Country Lite" (monthly, CC BY 4.0; attribution required: "IP Geolocation by DB-IP"),
compiled into `frontend/server/data/cn-region-ip-ranges.json` (≈1.1 MB) by `scripts/gen_cn_region_ip_ranges.py`,
to be refreshed monthly. APNIC's delegated file was rejected: it records where address blocks are *registered*,
not where they are *used* — it missed the Hong Kong test address `47.242.215.11` (an Alibaba Cloud block registered
with ARIN). The attribution should also appear on a public credits page if BioMate has one.

### 2.2 What the policy enforces

| User | Allowed models | User's own pick / key |
|---|---|---|
| China-region | Chinese models only (vendor allow-list: deepseek, qwen, z-ai/GLM, moonshotai/Kimi, minimax, baidu, tencent, bytedance, stepfun, 01-ai, thudm; plus an on-prem Chinese `LLM_API_URL` model) | A Chinese pick is honoured; a non-Chinese pick and the user's Anthropic key are ignored for that request |
| Everyone else | Any model, including Chinese models | Unchanged: any pick, own Anthropic key, free-text model slug |

The restriction is **one-directional**: everyone else may still choose a Chinese model. (An earlier reading that
also banned Chinese models for everyone else was withdrawn by the founder.)

**Fail closed.** If a China-region request finds no Chinese-model credential, it returns a clear error
(`cn_model_unavailable`, bilingual message) instead of silently falling back to Claude, Gemini or GPT.

**Re-checked on every request,** because the region can change mid-session (a VPN, a language switch).

### 2.3 Settings model picker

`frontend/client/src/components/settings-dialog.tsx` lets the user choose a provider (Anthropic key or OpenRouter
key) and a model (free text plus quick-pick chips). For China-region users:

- only Chinese-model chips are shown, and the default is the Chinese default;
- a typed non-Chinese model is rejected inline (en/zh);
- the Anthropic provider option is hidden, with the reason shown;
- the server enforces the same rule: `PATCH /api/user/llm-api-keys` returns 400 `model_not_allowed_in_region` or
  `provider_not_allowed_in_region`. Removing a key is always allowed.

`GET /api/llm/policy` returns the user's region, the reasons, the allowed vendors and the default model, so the
picker and the server use the same decision. Other users see the picker unchanged.

### 2.4 Model identity (all users)

- Every system prompt built for a user contains a **MODEL IDENTITY** block naming the exact model and vendor.
  For China-region users it states that the reply runs on a Chinese large model (国产大模型) and names it.
  It instructs the model to answer "which model / LLM are you" from this block and never to claim to be Claude,
  GPT, Gemini or any model other than the one named.
- The chat shows a label with the model that actually answered, sent by the server in a `model` stream event —
  e.g. "模型：DeepSeek V4.1 Flash（深度求索 · 国产大模型）" or "Model: GLM 5.3 Prime (Zhipu AI · Chinese model)".

### 2.5 Coverage

**Node (frontend/server).** Every LLM call made for a chat user follows the per-request policy: intent and
decomposition, the reply and tool loop, run_code, image reading, session memory, titles and summaries, notes,
evidence, the context compressor, the prerequisites validator and the workflow generator. Chokepoints:
`callGeminiFlash`, `llmGenerate`, `GalaxyAssistant._getClaude()`, the Gemini client, the intent model, `processMessage`.

**Galaxy (Python).** Node adds `X-BioMate-LLM-Policy: region=cn; model=<Chinese model>` (or `region=intl`) to every
request it sends to Galaxy. Galaxy's ASGI middleware puts it in a ContextVar for the request; LLM chokepoints
(`LLMClient.generate_async` / `generate`, `generate_with_fallback`, `gemini_flash`, `workflow_ops.UnifiedLLMClient`)
route a China-region request to a Chinese model. This covers workflow search and re-rank, parameter extraction,
research and PaperQA synthesis, findings, workflow generation, `llm_router`, target ID, autofix3, the IND narratives
and the job-error wizard.

- **Trust:** the header can only *restrict* a request to Chinese models; a missing header or `region=intl` means the
  normal chain, so a forged header cannot lift the restriction. Node strips any browser-sent copy.
- **Threads:** Python 3.9 starts threads with an empty context. A one-time patch carries **only the LLM policy**
  into `ThreadPoolExecutor.submit` and `Thread.start`. (The first version copied the whole context; review found
  this would share Galaxy's request-scoped SQLAlchemy session — keyed by the `REQUEST_ID` ContextVar in
  `galaxy/model/base.py` — across threads. Fixed in `151c910d30`, with a regression test.)
- **Background runs:** each run records its `llm_policy` at launch; findings, QC and the autoloop after the run
  re-enter it.
- **Galaxy is not publicly reachable:** port 8081 is bound on the dev host, but requests from outside time out
  (checked 2026-11-12 from one external address), so a user cannot bypass Node's region check by calling Galaxy
  directly. Confirming the AWS security group allows 8081 only internally would make this certain.

**Known limits.**

- On the Chinese route, the autofix agent receives plain-text replies only (no tool calls).
- Not covered because no user request reaches them: an offline domain reclassifier, an unused autofixer class,
  an unused research-agent Anthropic client, benchmark and training CLIs, cron jobs not tied to a run.
- `localOnly` deployments and the OpenAI-SDK clients in `dataset-validator.ts` / `routes.ts` (`OPENAI_API_KEY`,
  unset on dev) do not consult the policy.

---

## 3. Model sets

BioMate uses a different model for each job ("hybrid"). Several roles are set by environment variables on dev,
overriding the code defaults.

| Role | English side today (dev) | Chinese set (approved 2026-11-12) | Override env var |
|---|---|---|---|
| Intent / task breakdown | GLM 5.2 via OpenRouter (`BIOMATE_INTENT_MODEL=openrouter:z-ai/glm-5.2`); code default Gemini 3.8 Flash, Gemini 3.1 Pro for complex queries | `z-ai/glm-5.2` | `BIOMATE_CN_INTENT_MODEL` |
| Main reply + tool loop | GPT-5.6 Luna (`BIOMATE_RESPONSE_MODEL`); code default Gemini 3.8 Flash, Claude Sonnet 4.5 fallback | `deepseek/deepseek-v4.1-flash` (tools + images) | `BIOMATE_CN_RESPONSE_MODEL` |
| Hard / long reasoning | Gemini 3.1 Pro tier | `deepseek/deepseek-v4-pro` (text only) | `BIOMATE_CN_REASONING_MODEL` |
| Lightweight (tool ranking, titles, session memory, notes, compressor) | Claude Haiku 4.5 | `qwen/qwen3.5-flash-02-23` (tools + images) | `BIOMATE_CN_LIGHT_MODEL` |
| Image reading | the reply model | `deepseek/deepseek-v4.1-flash` | `BIOMATE_CN_VISION_MODEL` |
| Galaxy (search, parameters, findings, research) | Gemini Flash → Claude Sonnet → GPT | `deepseek/deepseek-v4.1-flash` → `z-ai/glm-5.2` → `qwen/qwen3.5-plus-20260420`, then fail closed | `BIOMATE_CN_GALAXY_CHAIN` |

Notes:

- All Chinese-set slugs were checked against OpenRouter's live `/models` list on 2026-11-12 and support tool calling.
  Prices per 1M tokens (in/out): DeepSeek V4.1 Flash $0.30/$1.20, DeepSeek V4 Pro $0.89/$1.78,
  Qwen 3.5 Flash $0.07/$0.26.
- An override must still be a Chinese model; a non-Chinese value is rejected with a warning.
- A China-region user's own Chinese pick in Settings replaces only the **reply** role; the other roles keep the set.
- **Benchmark status:** only GLM 5.2 and the DeepSeek models have been measured on BioMate's evaluations.
  The Qwen picks were chosen on capability and price and need the routing and tool-call benchmarks before they
  are treated as final.
- The English side already uses a Chinese model (GLM 5.2) for every user's intent step; that is permitted.
- Credential: `OPENROUTER_ZH_API_KEY` in `/opt/biomate/.env` on the dev host (added 2026-11-12 with the founder's
  approval; this is the shared OpenRouter key, so Chinese users' usage on dev bills to it). Both the frontend and
  Galaxy containers read it when they are recreated.

---

## 4. The language boundary: risks of Chinese chat over English data

All of BioMate's databases, catalogues and skills are in English: the workflow catalogue (≈4,223 workflows), the
tool index (≈12,312 tools), skill descriptions, parameter schemas, and retrieved literature. Part of the users will
now chat in Chinese. Later, users may also add **Chinese** skills, connector resources and imported workflows.

### 4.1 What is not affected

| Component | Why it is safe |
|---|---|
| Skill selection | Operation skills are chosen by the LLM reading each skill's English "when to use" description (`frontend/server/operation-skills.ts`: "Selection is inference over each skill's `whenToUse` description"). A bilingual model reads English descriptions against a Chinese request correctly. |
| Execution identifiers | Workflow names, parameter names and values, file paths, SMILES and accession IDs stay unchanged; `responseLanguageDirective` (`frontend/server/response-language.ts`) requires this. Only explanatory prose follows the user's language. |
| Reply language | `replyLanguageNote` (`galaxy-assistant.ts` ~2825) fixes the reply language to the user's own words, not to the English blocks around them. |
| Catalogue labels shown in the UI | Already localised through `/api/i18n/labels` and `useLocalizedLabels`. |
| Reading English sources | All models in both sets are bilingual; reading English papers, tool docs or workflow descriptions and answering in Chinese works. |

### 4.2 What is affected

**1. Workflow and tool search (high impact).**

- **Lexical search dominates.** The workflow index is an SQLite FTS5 table (`workflows_fts`, created in
  `backend/lib/galaxy/ai/unified_workflow_search.py` ~837) using FTS5's default tokenizer. A code comment there
  (~215) states that the FTS term is 85–90% of a long chat query's score. FTS5's default tokenizer does not split
  Chinese into words, so a Chinese query matches almost nothing in an English index.
- **Embeddings are English-only.** The vector layers use `BAAI/bge-small-en-v1.5` (`vector_search.py` ~104,
  `unified_workflow_search.py` ~88) and `all-MiniLM-L6-v2` (`unified_workflow_search.py` ~39, chain search).
  Chinese text embedded with these models lands far from the English entries it means.
- **Chinese text reaches the search query.** The search query is the intent step's `subQuery` with the user's
  original message appended (`galaxy-assistant.ts` ~5705). The intent prompt's examples are English, but no rule
  says `subQuery` or `task_spec` must be written in English, and a Chinese model given a Chinese request will often
  write them in Chinese.
- **Consequence:** routing quality for Chinese users is very likely lower than for English. It has not been
  measured.

**2. Rule-based parameter extraction (medium impact).** BioMate's rule: rules first, LLM as fallback (unit
conversion, "single-end → single_end=true", "human → GRCh38", negations). The rules are written for English
phrasing (`backend/lib/galaxy/ai/ai_assistant.py`, `pattern_router.py`, `agents/context_extractor.py`).
"双端测序" or "人类" will miss them and fall to the LLM, which is less reliable for exactly these deterministic values.

**3. Mixed-language content added later (grows over time).** Chinese skills, connector resources and imported
workflows would make the index mixed-language. With English-only embeddings and FTS, Chinese entries would be hard
to find from English requests and vice versa.

**4. Evaluation blind spot.** The routing, param_prefill and other benchmarks are English. Nothing measures the
system for Chinese users, so regressions would go unnoticed.

---

## 5. Plan

### Step 1 — Measure (first, cheap)

Translate the existing `routing` and `param_prefill` benchmark questions (`evaluation/datasets/…`) into natural
Chinese, run both language versions through the live system with the Chinese model set, and compare per item.
Run after the region policy is on dev so the measurement uses the models real Chinese users get. The gap decides
how urgent Step 2 is.

### Step 2 — English as the internal search language

- The intent step always writes `subQuery` and `task_spec` in English, whatever the user's language, defined in the
  prompt as the canonical retrieval form. The user still gets replies in their language.
- The raw user message is no longer appended to the embedding / FTS query when it is not English; only identifiers
  extracted from it (SMILES, accession numbers, gene and drug names, file names) are carried over.
- Parameter rules gain Chinese aliases where wording matters (人类 → GRCh38, 小鼠 → GRCm39, 双端 → paired-end,
  单端 → single-end, 链特异性/反向 → reverse, 纳秒 → n_steps …), keeping "rules first, LLM fallback".
- Verify with the Step-1 benchmark: Chinese scores should approach English.

### Step 3 — Two layers for imported content

When a user adds a skill, imports a workflow, or a connector brings in a resource:

- keep the original text (shown to the user in their language);
- generate and store an English canonical description, with a language tag;
- index the English layer for search; the user-facing views show the original.

Skill selection already works across languages (§4.1); the English layer keeps search consistent.

### Step 4 — Multilingual retrieval (later, if Chinese content grows)

Switch the embedding layer to a multilingual model (e.g. `BAAI/bge-m3`), add a CJK-aware FTS tokenizer
(e.g. trigram or a segmenting tokenizer), and re-index the catalogue (≈4,200 workflows, ≈12,300 tools).
This is a larger, separate change. Step 3 makes it easier but does not require it.

---

## 6. Decisions recorded

| Date | Decision | By |
|---|---|---|
| 2026-11-12 | China-region users may use only Chinese models; everyone else keeps full choice (one-directional) | Founder |
| 2026-11-12 | Region = Chinese UI/Settings language OR Chinese browser language OR IP in CN/HK/MO/TW | Founder |
| 2026-11-12 | Use OpenRouter (shared key) as the Chinese-model credential on dev | Founder |
| 2026-11-12 | Approve the per-role Chinese model set in §3 | Founder |
| 2026-11-12 | Fail closed when no Chinese model is available | Engineering (spec) |
| 2026-11-12 | DB-IP instead of APNIC for IP regions | Engineering (accuracy) |

---

## 7. Open items

1. Run the Step-1 Chinese benchmark after deploy.
2. Benchmark the Qwen picks (light role, Galaxy chain third tier) on routing and tool calls.
3. Autofix on the Chinese route has no tool calls.
4. Confirm the AWS security group keeps Galaxy's port 8081 internal-only.
5. Add the DB-IP attribution to a public credits page, if one exists.
6. Refresh the IP range file monthly (`scripts/gen_cn_region_ip_ranges.py`).
7. `localOnly` deployments and the OpenAI-SDK clients do not consult the region policy.

---

## 8. Status (verified 2026-11-12 evening)

| Item | Branch / commit | State |
|---|---|---|
| Region policy, Node side (detection, enforcement, Settings, identity, label) | `feat/cn-llm-region-policy-20261112` @ `28017770a2` | built, tested, pushed (ancestor of model-set branch) |
| Galaxy per-request routing + thread-context fix | `feat/cn-llm-galaxy-routing-20261112` @ `151c910d30` | built, tested, pushed (ancestor of model-set branch) |
| Per-role Chinese model set (§3) | `feat/cn-llm-model-set-20261112` @ `1e58083519` | committed and pushed; unit tests not re-verified in this session; doc update unfinished at the weekly usage limit |
| Round-9 dataset-panel / run_code fixes | `devline/ds-audit-20261112` @ `c8b1032b75` | **not on dev**. Dev tip is `3182a6ab45` (`origin/deploy/models-abc-20261112` / fix/f9-turn-busy). `f18133ea32` is not an ancestor of that tip. Needs re-merge + gate + deploy. |
| Last recorded sync commit in deploy worktree | `.last_dev_sync_commit` = `2554e05cb0` | older than both round-9 and current models-abc tip |
| `OPENROUTER_ZH_API_KEY` on dev | `/opt/biomate/.env` | added (prior session; not re-checked tonight) |
| Deploy Chinese-model rule to dev | — | blocked on: (1) round-9 re-merge/deploy, (2) model-set gate, (3) warn other sessions about Galaxy restart |
| This document | recovered from Claude scratchpad into `docs/` | was only in `/private/tmp/claude-501/.../scratchpad/`; scratchpad empty as of tonight |
| Language boundary (§4–5) | — | proposed; Step 1 Chinese benchmark after Chinese models are on the same path real users get |

### Worktree map (2026-11-12 evening)

| Worktree | Branch | What's there |
|---|---|---|
| `/Users/kky/biomate-review` | `fix/images-and-reroute-20261111` | older image/reroute work; local dirty files; not touched for CN/round-9 |
| `/Users/kky/biomate-deploy-images-20261111` | `devline/ds-audit-20261112` @ `c8b1032b75` | round-9 fixes + merges of earlier deployed tips; clean |
| `/Users/kky/biomate-cn-set` | `feat/cn-llm-model-set-20261112` @ `1e58083519` | per-role Chinese model set (`CN_MODEL_SET` + env overrides); clean, tracking origin |

### Env overrides for the Chinese set

| Role | Chinese default | Override |
|---|---|---|
| Intent | GLM 5.2 | `BIOMATE_CN_INTENT_MODEL` |
| Reply, tool loop and images | DeepSeek V4.1 Flash | `BIOMATE_CN_RESPONSE_MODEL` |
| Hard reasoning | DeepSeek V4 Pro | `BIOMATE_CN_REASONING_MODEL` |
| Titles, session memory, tool ranking | Qwen 3.5 Flash | `BIOMATE_CN_LIGHT_MODEL` |
| Galaxy | DeepSeek V4.1 Flash → GLM 5.2 → Qwen 3.5 Plus | `BIOMATE_CN_GALAXY_CHAIN` |

Non-Chinese override values are rejected. A Chinese Settings pick replaces only the reply model; other roles keep the set. The chat model label shows the reply model.
