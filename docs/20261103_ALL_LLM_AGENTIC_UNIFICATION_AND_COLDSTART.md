# All-LLM agentic unification + cold-start example verification/fixes

**Date:** 2026-11-03 · **Status:** in progress (autonomous session; PR before dev sync)
**Scope:** (1) verify every cold-start example works for real + fix what's broken; (2) make BioMate's LLM backbone pluggable across closed/open/on-prem/OpenRouter *with full agentic parity* (tools + workflow generation + run_code), with the UI model catalog refreshed; (3) fix the routing mismatches the verification surfaced.

---

## 1. Cold-start example verification (done)

Every cold-start example was checked for real (routing on dev via a fresh registered user, routing-only — no Batch launches). Two layers:
- **Client routing contract** (`cold-start-dashboard.test.tsx`, 94 tests): every example (all tabs + per-modality + domain seeds) routes to a lane via `readIntent()` — green. No example is dead in the UI.
- **Backend reality** (51 distinct checks across 21 module seeds + 10 PREPARED sample-data + 2 internal + 18 per-tab `ex`/`exBy`):

| Result | Count | Notes |
|---|---|---|
| ✅ works (routes to the right runnable workflow / correct cited chat answer) | ~37 | incl. all Search tabs (chat_only = correct), GEN-pep→Cyclic Peptide Design, GEN-ab→Bispecific Antibody Design, PRED-ab→Antibody Developability, PRED-fep→OpenFE RBFE, all 10 sample-data workflows (exist in catalog, 5 have historical Batch exit-0) |
| ❌ broken → FIXED | 1 | P6 Cox-PH demo data not served (see §1.1) |
| ⚠️ mismatch (routes to a real but wrong/suboptimal workflow) | see §3 | the residual routing work |

**No hard failures** — the two earlier `workflow_failed`s (Design Optimise pep/ab) were **transient dev-backend blips** (`ECONNREFUSED 172.19.0.2:8080`); they route when the backend is healthy. The dev backend intermittently refuses on :8080 — a separate reliability issue worth a look.

**`run_code` is NOT broken** (stale belief corrected): a live probe ran Python end-to-end (`Mean 4.4000, Std 2.1726`, exit 0, 772 ms). Tool turns are force-routed to Claude Haiku (`galaxy-assistant.ts:9026`) and the Gemini backbone also has a tool loop (`_generateWithGemini` + `BIOMATE_TOOLS`, `:9052`). The cold-start I2 "summarize CSV" failure was a test-context artifact (the bare test didn't set up the MG demo project files that `ensureInternalDemoProject` uploads in the real UI).

### 1.1 Fixes shipped
- **P6 Cox-PH demo data** (`d5904b6bf`): `patient_clinical_data.csv` lived only in `frontend/public/` (unserved — Vite serves `frontend/client/public/`), so the example fetched the SPA `index.html` and broke before sending. Copied into the served dir; added a demo-catalog test guard for `/demo/mg_demo/` assets.
- **STR3 reword** (`e1f5c3a48`): "compare model vs map / list discrepancies" had no backing workflow (it routed to DeepEMhancer, a map-sharpening tool). Reworded to "Sharpen and post-process this cryo-EM density map, then re-estimate the local resolution" to match the real capability. Router self-test still green.

---

## 2. LLM backbone: current state + the all-LLM agentic plan

### 2.1 Which model to switch Gemini → (if desired)
BioMate's own routing/workflow-gen benchmark (`evaluation/datasets/public_export/results/_wfgenB_summary.json`, B_acc / mean_recall):
GLM-5.3-prime 0.95/0.80 · Kimi-K3 0.95/0.78 · gpt-5.6-luna 0.85/0.73 · Gemini-3.1-pro 0.80/0.66 · DeepSeek-V4-pro 0.80/0.67 · Qwen3.8-max-prime 0.65/0.53.
**GLM-5.3-prime is cheapest ($1.40/$4.40 per 1M vs Kimi $3/$15) and tied-best-open** — the recommended default open backbone. OpenRouter slug `z-ai/glm-5.3-prime`.

### 2.2 Current LLM-sourcing matrix (verified in code)
| Source | Selection | Agentic (tools + workflows + run_code) | Mechanism |
|---|---|---|---|
| Anthropic / Gemini (cloud) | yes | ✅ | `_processMessageInner` (Claude) / `_generateWithGemini` tool loop |
| **On-prem / customer's own API** (vLLM/Ollama/their endpoint) | env | ✅ | `local-llm.ts` `localMessagesClient()` — Anthropic↔OpenAI tool-calling shim; `BIOMATE_LOCAL_ONLY=1` + `BIOMATE_LOCAL_LLM_URL`/`_MODEL`/`_KEY`/`_ORIGIN` (SSRF allowlist)/`_TIMEOUT_MS`; `BIOMATE_OFFLINE=1` for air-gap. vLLM runbook: `docs/20260528_VLLM_DEPLOY_RUNBOOK.md` |
| OpenRouter (GLM/Kimi/DeepSeek/GPT…) | yes (UI selector `settings-dialog.tsx:1075`) | ❌ **chat-only today** | `_generateChatWithOpenRouter` (`:2876`) = plain `chat.completions` stream, no tools/workflow-gen |

### 2.3 The key realization
The **OpenAI-format agentic tool loop already exists** — it's `local-llm.ts` `localMessagesClient()` (used for on-prem). The OpenRouter path is chat-only only because it was wired to the simple shortcut (`processMessage:4022`) instead of that shim. **So "make OpenRouter first-class agentic" = generalize the on-prem shim to any OpenAI-compatible base_url, not a from-scratch tool loop.**

### 2.4 Implementation plan (the all-LLM unification)
1. **`local-llm.ts` → add a config-parameterized OpenAI-compatible agentic shim.** Extract `openaiCompatCompletion(cfg, body)` + `openaiCompatMessagesClient(cfg)` where `cfg = {url, model, key?, timeout?}`. `localCompletion`/`localMessagesClient` become thin wrappers that pass `localConfig()` (preserving the `BIOMATE_LOCAL_*` env + origin allowlist for the local path untouched). The translation (`localMessages`, `validateToolInput`, `events`, tool_use↔tool_calls) is reused verbatim. +unit tests mirroring the existing ones with an injected cfg + a fake fetch.
2. **`galaxy-assistant.ts` processMessage OpenRouter branch (`:4022`):** instead of `_generateChatWithOpenRouter`, build `cfg = {url:'https://openrouter.ai/api/v1', model: context.selectedModel || 'z-ai/glm-5.3-prime', key: openrouterKey}` and run the **full agentic pipeline** — mirror the proven `localOnly` wiring: override `_getClaude()` to `openaiCompatMessagesClient(cfg)` (via the existing `_anthropicOverride` storage) AND set this turn's `intentModel`/`responseModel` to the selected model so the intent classifier takes the non-Gemini (`_getClaude`) branch. Graceful fallback to the chat-only path (or Gemini) on error so prod can't regress. Keep tool turns working (they already run via `_getClaude`/the shim).
3. **Refresh the UI model catalog** (`settings-dialog.tsx`) to current closed+open models: `z-ai/glm-5.3-prime`, `moonshotai/kimi-k3`, `deepseek/deepseek-v4-pro`, `qwen/qwen3.8-max`, `anthropic/claude-opus-5.5`, `openai/gpt-6.1-sol-pro`, `google/gemini-3.1-pro-preview` (+ keep a cheap default). Slugs verified in `evaluation/datasets/public_export/models.yaml`.
4. **Blast radius:** on dev the default backbone is Gemini (server `OPENROUTER_API_KEY` not set → the OpenRouter branch only fires for users who explicitly select an OpenRouter model), so this change does not alter the default dev experience; it upgrades the OpenRouter-model experience from chat-only to agentic.

### 2.5 Implementation — LANDED (2026-11-03)
All three parts shipped; pre-sync gate green (`tsc` 0, `vitest` 2008 passed / 42 skipped / **0 failed**, no backend `.py` touched).

1. **`local-llm.ts` — config-parameterized OpenAI-compatible agentic shim.** Added `openaiCompatCompletion(cfg, body)` + `openaiCompatMessagesClient(cfg)` (`cfg = {url, model, key?, timeout?}`), reusing the exact translation helpers (`localMessages`, `validateToolInput`, `events`, `jsonObjectText`) and the same transport discipline as `localCompletion` (`redirect:'error'`, explicit `AbortSignal.timeout`, strict `finish_reason`, strict JSON). **Deliberately did NOT refactor `localCompletion`/`localMessagesClient`/`localConfig` into wrappers** — the on-prem path is security-sensitive (SSRF origin allowlist, no-fallback, air-gap) with a 7-test file + 9 importers; touching it to DRY-up buys nothing and risks a regression there. The new functions are additive and take an explicit `cfg` from a *trusted* caller instead of the `BIOMATE_LOCAL_*` env, so the two paths are independent (proven by a test that deletes all `BIOMATE_LOCAL_*` env and still routes). +3 unit tests (endpoint/auth/model/redirect + no-env-dependency; validated tool loop with ID preservation + trailing-slash normalization + unknown-tool reject; schema-guardrail reject) → the file is now **12 tests green**.
2. **`galaxy-assistant.ts` — OpenRouter branch routes the full agentic pipeline.** The branch (now placed after `runInner`) builds `openaiCompatMessagesClient({url:'https://openrouter.ai/api/v1', model: context.selectedModel || 'z-ai/glm-5.3-prime', key: openrouterKey})` and runs `_anthropicOverride.run(shim, () => _openrouterAgentic.run(true, runInner))`.
   - **Mechanism (two edits, isolated):** (a) `_getClaude()` already returns `_anthropicOverride.getStore() ?? this.claude`, so storing the shim there makes every response/tool/intent `_getClaude()` call hit the selected model. (b) a new `_openrouterAgentic` AsyncLocalStorage<boolean> is OR'd into `isClaudeBackbone` (`:9015`) so the response path takes the agentic tool loop (and the model isn't force-overridden to Haiku). The shim ignores the `model` arg passed by the loop (it uses `cfg.model`), so `apiOptions.model` is irrelevant.
   - **Deviation from the §2.4 plan — did NOT mutate `modelConfig.intentModel`/`responseModel` per-request.** `GalaxyAssistant` is a shared instance; mutating its config per-request would race across concurrent users. Not needed anyway: with a Gemini key present (dev) the intent classifier stays on Gemini (cheap, good at intent) while response+tools run on the selected model; on a **pure-OpenRouter deploy** (no Gemini key) the intent classifier's `isGemini && this.gemini` guard is false → it falls to the `_getClaude()` branch → the shim, so intent *also* runs on the selected model. Both work with zero shared-state mutation.
   - **Deviation — no silent chat-only fallback.** The §2.4 note floated a graceful fallback, but CLAUDE.md's #1 rule (resolve root causes, never mask) + the double-streaming hazard (the pipeline may have already streamed tokens before a mid-turn error) make a catch-all wrong here. The branch is **opt-in** (fires only when a user supplies an OpenRouter key AND selects a model; dev default = Gemini, server has no OpenRouter key), so running it straight cannot regress the default path. A tool-incapable model surfaces an honest error; `_generateChatWithOpenRouter` is retained for a *future explicit* route for models known to lack tool support (not an error-masking fallback).
3. **UI model catalog refreshed** (`settings-dialog.tsx`): quick-pick + default (`useState`) now `z-ai/glm-5.3-prime` (recommended open default), `moonshotai/kimi-k3`, `deepseek/deepseek-v4-pro`, `anthropic/claude-opus-5.5`, `openai/gpt-6.1-sol-pro`, `google/gemini-3.1-pro-preview`. **Corrected from the §2.4 list:** dropped `qwen/qwen3.8-max` — the roster (`models.yaml`) marks `qwen/qwen3-max` **UNVERIFIED_SLUG**; only `verified` / `verified_by_results` slugs are offered so no quick-pick is a dead id. All six are function-calling capable → full agentic pipeline.

**Still to verify on dev (post-sync):** send a chat with an OpenRouter key + `z-ai/glm-5.3-prime` selected and confirm a workflow card + a `run_code`/search tool event fire (not just a chat stream). Dev server has no `OPENROUTER_API_KEY`, so this needs a per-user key via the settings dialog (the `context.openrouterKey` path), exercised through the real UI or an API call that passes the key.

---

## 3. Routing mismatches to fix (from the per-tab verification)
Each routes to a real but wrong/suboptimal workflow; fix with routing rules + re-verify on dev before/after:
- **CLIN2** "biomarker panel + cross-validated risk model" → MetaboAnalystR Biomarker (metabolomics) on a generic clinical cohort. Target: a generic classifier/risk workflow (`mlinterfaces_multi_classifier_evaluation`, `icare_absolute_risk_model_validation`, `sampleclassifier_*` all exist). The word "biomarker" pulls it to metabolomics.
- **Design Optimise** (sm/pep/ab) → REINVENT4 *Generative* Lead Design — an "optimise an existing series" intent landing on a *generation* workflow.
- **Models Train/Adapt** → REINVENT4 generative/finetune — "train/fine-tune a predictor" landing on generative design (the ML-training routing override at `galaxy-assistant.ts:4285` isn't catching these).
- **Modality**: PRED-pep → small-molecule ADMET (unstable; one try gave the correct peptide-binding wf); GEN-protvar (enzyme variants) → Bispecific Antibody; RANK-pep → just permeability; RANK-ab → Bispecific design.
- **ADHOC** "summarise + plot" → a workflow instead of `run_code`.

Sequencing: the all-LLM/GLM work (better routing recall) may resolve several; then add targeted routing rules for the residual, each with a dev before/after check.

---

## 4. Deploy discipline for this session
Per the 2026-11-01 flow: commit → push → **open PR (before sync)** → checks → `scripts/sync_to_dev.sh` → test on dev. Pre-sync gate: `tsc --noEmit` + `vitest run` + `py_compile` for any backend `.py`. Verify on dev via a freshly-registered user (fixture Galaxy key 401s). This doc is the living record; results appended as they land.
