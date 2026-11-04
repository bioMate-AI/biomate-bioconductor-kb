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

**Status: DEFERRED to a next session (not done).** Each §3 fix is a routing-behavior change in the intent/search path that this plan *requires* be verified on dev before→after. Dev is currently the PR #295 integration candidate (§4.2) and I won't sync to it, so there is no honest before/after to measure against tonight — and these fixes touch `galaxy-assistant.ts`, a MANUAL conflict file in the in-flight merge, so committing unverified routing churn now would worsen that merge for no testable gain. The LLM-switch half of the user's "GLM-5.3 switch, fix routing" request shipped (§2.5); the routing half is held until dev is available for the before/after the plan mandates. First candidate to also re-check once GLM is the backbone: whether the stronger routing recall already fixes CLIN2 / Design-Optimise / Models-Train before any hand-written rule is added.

---

## 4. Deploy discipline for this session
Per the 2026-11-01 flow: commit → push → **open PR (before sync)** → checks → `scripts/sync_to_dev.sh` → test on dev. Pre-sync gate: `tsc --noEmit` + `vitest run` + `py_compile` for any backend `.py`. Verify on dev via a freshly-registered user (fixture Galaxy key 401s). This doc is the living record; results appended as they land.

### 4.1 What shipped (2026-11-03)
- **Commit `5b86c75a2`** — the all-LLM agentic unification (§2.5). Pushed to the feature branch `cursor/tutorial-live-recording-and-report-editing-4ea7`, which is **PR #295's head** (the PR is already OPEN). "PR before sync" satisfied: the change is reviewable on #295.
- Pre-sync gate **green** on the commit: `tsc` 0, `vitest` 2008 passed / 42 skipped / **0 failed**, no backend `.py` touched (steps 3–4 of the checklist N/A).

### 4.2 Dev sync — DEFERRED (not stomped), with a required handoff
`scripts/sync_to_dev.sh` from this worktree **refused the lock**: a concurrent session (worktree `/Users/kky/biomate-merge-295`, pid 3819) was actively syncing and finished **healthy at 00:26:44** deploying commit **`b753455b`** = branch `merge/next-phase-into-dev-20261103` — the PR #295 → `integration/next-phase` **merge candidate** (237 integration commits, 31 conflicts resolved; see `docs/20261103_PR295_MERGE_CONFLICT_TRIAGE.md`).

**Why I did NOT sync my branch:** `b753455b` does **not** contain `5b86c75a2` (the candidate was built before my push), and my feature branch does **not** contain the 237-commit integration merge. Syncing my branch to dev would therefore (a) **regress** the dev-lineage deployment by dropping the integration merge, and (b) **stomp** the concurrent integration mid-flight. Building a *parallel* integration (cherry-pick `5b86c75a2` onto the merge branch + re-sync) would **race** the merge-295 session on the same dev box and its branch. Both violate CLAUDE.md's #1 rule (no workarounds / resolve root cause) and the shared-worktree caution. So dev verification is deferred to the proper lineage rather than forced tonight.

**Required follow-up (handoff sent to `biomate-review-c7`, the likely merge-295 owner):** include `5b86c75a2` when the integration is finalized/re-merged, *before* the next dev sync of `merge/next-phase-into-dev-20261103`. The change is a small, isolated diff (adds `_openrouterAgentic` AsyncLocalStorage OR'd into `isClaudeBackbone`; swaps the `processMessage` OpenRouter branch to `openaiCompatMessagesClient` via `_anthropicOverride`, placed after `runInner`; additive `local-llm.ts` functions + tests; `settings-dialog.tsx` catalog) and should apply cleanly on top of the candidate's `galaxy-assistant.ts` resolution.

### 4.3 Dev smoke test — READY to run once `5b86c75a2` is live on dev
Prereqs confirmed on hand: OpenRouter key (`~/.config/biomate/openrouter.key`), fixture `lifeifei163361@163.com`, dev at `https://dev-public.biomate.ai`. Procedure (opt-in path — dev server has no `OPENROUTER_API_KEY`, confirmed behaviorally since workflows route by default = Gemini backbone):
1. `POST /api/auth/login` (fixture) → JWT.
2. `PATCH /api/user/llm-api-keys` `{provider:'openrouter', key:<OR key>, selected_model:'z-ai/glm-5.3-prime'}` (auth'd) — stores per-user key on the fixture row.
3. `POST /api/chat/stream` (auth'd) with a workflow-eliciting prompt (e.g. nf-core/rnaseq DE). **Pass:** SSE emits a `workflow_ready` / workflow card and/or a `tool_event` (proves the agentic loop fired on GLM — chat-only would emit neither). **Fail:** only text deltas.
4. **Cleanup:** `PATCH /api/user/llm-api-keys` removing the openrouter provider + `selected_model` so the shared fixture isn't left pinned to GLM for other tests.

This cannot run until `5b86c75a2` is deployed to dev (per §4.2). Verifying before then would test code that isn't on the box.

### 4.4 Dev verification — DONE, **PASS** (2026-11-03, later)
Resolution of §4.2: the dev box was taken by a concurrent session (`biomate-review-c7`) that **full-synced the feature-branch head `3e56394e9` to dev (healthy, smoke passed)**. `3e56394e9` is a descendant of `5b86c75a2`/`ee7046f96` and carries `openaiCompatMessagesClient` in both `local-llm.ts` and `galaxy-assistant.ts` — so **my all-LLM code is live on dev** without a separate sync from me. Per the user's "you sync and test": the sync is satisfied (code live + confirmed by commit ancestry and tree grep); I did **not** re-sync because c7 had a chain executing on dev and a re-sync (Galaxy restart + frontend rebuild) would orphan it.

**Smoke test (`scratchpad/openrouter_agentic_smoke.sh`, against `https://dev-public.biomate.ai` as-is):**
- Fixture login OK → set per-user OpenRouter key + `selected_model=z-ai/glm-5.3-prime` → `POST /api/chat/stream` with an nf-core/rnaseq prompt.
- **Stream showed the FULL agentic pipeline**, not a chat-only completion: `progress` stages `intent` (with a correct detailed classification) → `search` → `matched` → `plan`, then a `delta` streaming a structured **nf-core/rnaseq** workflow summary (inputs, STAR/Salmon/FastQC+MultiQC steps, GRCh38 auto-resolved), i.e. a workflow card. Counters: workflow signals 3, tool signals 7. **RESULT: PASS.**
- Cleanup http 200 — fixture LLM settings reset to default so the shared account isn't left pinned to GLM.
- Pre-change, an OpenRouter key routed to `_generateChatWithOpenRouter` = raw completion with **no** intent/search stages and **no** workflow card; the presence of those stages + the card is the proof the agentic path now fires for an OpenRouter-selected model.

**Independent external check (real OpenRouter calls, no BioMate):** `z-ai/glm-5.3-prime`, `moonshotai/kimi-k3`, `deepseek/deepseek-v4-pro` each returned a clean `tool_calls` (`search_literature({"query":"PCSK9 inhibitors"})`) at a realistic token budget — confirming the default model list is function-calling capable (the earlier `finish_reason:length` was only a 200-token probe budget eaten by GLM's reasoning; 3000+ tokens tool-calls cleanly, and the shim uses 4096).

**Net:** the all-LLM agentic unification is implemented, unit-tested, PR'd (#295), live on dev, and verified working on dev with GLM-5.3-prime. The §3 routing fixes remain the open follow-up (need their own dev before/after; see §3), as does folding `5b86c75a2` into the `merge/next-phase-into-dev-20261103` integration (handoff documented; owner = integration owner or user, per c7).

---

## 5. Routing + chat/card naming fixes (2026-11-03, afternoon)

### 5.1 Method — measure with what the UI actually sends
- **Payloads:** all 106 cold-start examples (every module/track/modality + domain shapes) dumped from the UI's own `prepareColdStartExample()` (temporary vitest, `fetch` stubbed), so prompts carry the exact goal rewrite + "Prepared demo context" text. Demo *files* are not uploaded by the probe (text-only) — examples whose answer depends on the uploaded file content ([10], [22]) are probe artifacts, not bugs.
- **Harness:** fixture login once (no `/api/auth/register`), 3 lanes, chat-only (no Batch). Per prompt: final state, `workflow_ready.workflow_name`, tools, response head. Attribution of card swaps from dev frontend logs (Step 6b / 6c-2 lines).
- **Metric:** does the chat text name the *same catalog workflow* as the card — both resolved through `resolve_named_workflow` on the real catalog (display names, snake ids and directory ids of one workflow count as the same).

### 5.2 Baseline findings (before, dev @ 7da46c8b2 lineage)
- 106/106 HTTP 200; 94 workflow cards, 12 chat-only.
- **Text and card named the same workflow in only 10/94 cards.** 51 responses led with no workflow name; 26 with an *invented* name (e.g. "REINVENT4 Scaffold Decoration + ADMET Gate"); 7 with a *different real* workflow.
- **Named "Try sample data" examples misrouted:** [23] "Run perform_chipseq_peak_calling_with_macs2 … built-in demo files" → **nf-core/chipseq** (needs real reads); [18] metaboanalystr → a sibling (`Metaboanalystr Meta`).
- Root causes (code-read + verified): (a) no exact name resolution — only `nf-core/<slug>` had one; (b) post-text card swaps (Steps 6b/6c) built **stripped** cards from `workflow_by_name` and carried the *previous* card's parameters; (c) the response prompt said `Start with "**[workflow name]** —"` but never gave the card's name; (d) the text guardrail (6c) only understood `nf-core/<slug>`.
- **Not changed on purpose:** `parseActions`' `mustGenerateWorkflow` forcing (blocks the documented run_code route for ad-hoc compute, but `aadd82091` added it to stop a real empty-response bug — removing it would regress that).

### 5.3 Fixes (PR #295)
| Commit | Change |
|---|---|
| `190866304` | Backend `resolve_named_workflow` (exact: dir slug / file stem / display-name slug; generic path segments never resolve; duplicate rows break by SOURCE_PRIORITY → real-exec → id). Named-workflow fast path **first** in `generate_workflow_unified` (user's own text only — `[Memory context]` / `[Inline parameters]` excluded; files/param keys/paths skipped; 2+ names → chain routing). `workflow_by_name` resolver fallback. Node: Step 4 call captured (`regenerateWorkflowFor`) so swapped cards are rebuilt complete (own params + session-file bindings) via `_cardForNamedWorkflow`; Step 6b uses it; new Step 6c-2 (text-vs-card for every catalog workflow). Dry run over the 106 prompts: fast path claims exactly the 9 named sample-data examples, 0 false positives. |
| `0639bb7d` | `workflow-display-name.ts` (one name function for the card *and* the prompt); response told the card's exact name. |
| `2d4acaf26` | Measured regression fix: the response may lead only with the **search's other candidates** (listed by exact name), and 6c-2 follows the text only to one of them — the response model re-ranks, it does not retrieve. |

Tests: backend 19 (`backend/tests/test_named_workflow_routing.py`), frontend `server/workflow-name-guardrail.test.ts` (real dev response headers). Gate each commit: tsc 0, vitest 0 failed, py3.9 compile for every backend `.py` in the deploy.

### 5.4 After `0639bb7d` (dev, valid pass)
| | before | after |
|---|---|---|
| text and card = same workflow | 10/94 | **61/95** |
| text names a different real workflow | 7 | 2 |
| text names a non-catalog workflow | 26 | 5 |
| text names no workflow | 51 | 27 |
| named sample-data examples on the named workflow | 8/10 | **10/10** |

Residual: [15]/[88] DE+GO → GEO Data Connector card (the pathway-enrichment override deliberately disables the text guardrails — 2026-07-20 fix — and its own pick is off; pre-existing); 5 non-catalog names = real capability gaps (nanobody humanisation, peptide aggregation, Rosetta design — §3).
**Regression found by attribution (dev logs):** unconstrained 6c-2 moved 5 correct cards to wrong ones (dock top-50 → pocket detection; safety-gate/triage → pharmacophore filtering ×4) and regenerated identical cards when the text used the directory id. Fixed in `2d4acaf26`; re-measurement in §5.6.

### 5.5 Separate pre-existing bug found: per-user Galaxy key rejected for a whole session
The first after-sync pass was **invalid**: from ~18:34–19:00 UTC every workflow request for the fixture got Galaxy `401 {"err_msg":"Provided API key is not valid.","err_code":401001}` (frontend log `[GalaxyAPIProxy] Workflow generation failed`). Timeline (dev logs): 18:31:14 login found the key stale (HTTP 401 after the sync) and **re-provisioned successfully**; 18:32:58–18:33:10 three fixture logins (post-sync E2E + the harness) found Galaxy unresponsive, re-provisioning failed (`fetch failed`); from 18:34 Galaxy rejected the key that had been valid at 18:31, despite no Galaxy container restart (up since Oct 20) and an idempotent provision endpoint (reuses the newest active key). **Established:** the stored key is validated/re-provisioned **only at login** (`auth-service.ts:441-522`); the chat request path has no recovery for a rejected key, so a logged-in user stays broken until they log in again — and the "fall back to shared admin key" log line did not happen on the request path. **Not established:** what invalidated the key on the Galaxy side between 18:31 and 18:34. Proposed (not implemented — security-sensitive, trigger not pinned): on Galaxy `401001` in the per-user proxy, single-flight re-provision per user and retry once; and find the invalidation trigger (sync DB layer vs concurrent logins) before shipping.

### 5.6 Final state on dev (`2d4acaf2`, complete 106-prompt pass)
| chat text vs card | before | after `0639bb7d` | **after `2d4acaf2`** |
|---|---|---|---|
| same catalog workflow | 10/94 | 61/95 | **54/95** |
| a different real workflow | 7 | 2 | **1** |
| a non-catalog (invented) name | 26 | 5 | **3** |
| no workflow name in the text | 51 | 27 | 37 |
| named sample-data examples on the named workflow | 8/10 | 10/10 | **10/10** |
| known wrong swaps (dock→pocket, gate/triage→pharmacophore) | – | 5/5 | **0/5** |

`0639bb7d` had more matches because the text could pull in any catalog workflow — including 5 wrong ones; `2d4acaf2` keeps the text a re-ranker over retrieved candidates (0 hallucinated swaps). Three rows ([83]-[85]) hit a client↔EC2 connection drop (`http -1` together at ~90 s) and succeeded on re-run; merged.

**Open (retrieval, §3 — not naming):** [27] "generate candidates … drug-like properties" and [81] "adapt the generative model" retrieve ADMET prediction (lexical "properties"/"model"), so REINVENT is not a candidate to re-rank to; [12] an IC50-correlation request produced an `nf-core/demo` card; [15]/[88] DE+GO → GEO Data Connector (pathway-enrichment override); 37 responses still lead with no workflow name (e.g. a clarifying question shown next to a card — a separate response-format issue). Next step for these is a rule-first generation-intent hint in retrieval (generate/design/propose + molecules/candidates → generative workflows), measured with this same harness (`scratchpad/route_baseline.py` + `ui_payloads.json`).

---

## 6. Generation-intent routing + Galaxy key revocation (2026-11-03, evening)

### 6.1 Generative requests routed to property prediction
**Symptom (cold-start, dev):** "Generate candidates … drug-like properties", "Optimise this series for potency …", "Adapt the generative model …", and the peptide generate/optimise prompts returned Predict ADMET / Admet Pred.

**Diagnosis — including a correction.** The first fix (`866b78546`) assumed the ADMET fast path caused this; its commit message says so. **That was wrong.** `galaxy.log` for the failing turns shows `[AdmetFastPath] has_admet=False`; the card came from Step 1 *search*, which ranked on the property words that accompany a generative request ("drug-like properties", hERG/MW cut-offs in the demo context). The guard in `866b78546` stays (it is correct for explicit "… with ADMET filtering" phrasing, and is tested) but it did not fix the observed cases, and the REINVENT results seen right after it were run-to-run variance (the rule never fired). Lesson recorded: verify the path a turn actually took (galaxy.log fast-path lines), not the path the code could take.

**Fix (`0b5656bcb`):** `_request_task_text` = the request's own first paragraph (supporting context after a blank line is not the task — matching the whole text flagged 23/106 predict/dock/rank prompts whose demo context says "design exercise"); `_is_generative_task` (generate / design / optimise / adapt-a-generator patterns) → a routing hint for search, modality-aware (peptide → cyclic_peptide_design; antibody → antibody design; small molecule → generative design incl. scaffold hopping).

**Measured on dev — repeated trials, scorer fixed before the after-arm (`scripts/routing_eval/gen_score.py`):**
| | before (3 reps) | **after `0b5656bcb`** (3 reps) |
|---|---|---|
| generative prompts → generative design workflow (14 prompts) | 13/37 (35%) | **42/42 (100%)** |
| controls not turned generative (predict, dock, rank, safety gate, ADMET screen) | 14/14 | **15/15** |
| client-side drops | 6 | 0 |
Before-arm per-prompt: [27]/[30] 2/3, [33] 3/3, [35] 0/3, [36] 3/3, [54]/[55]/[57]/[58] 0/2, [59] 2/2, [60]/[62] 0/3, [81] 0/3, [83] 1/3 (raw rows lost in a scratch-dir wipe; numbers are the scorer's printed output). After-arm raw rows: `evaluation/routing_eval/runs/gen_after_0b5656bcb.jsonl`.
Caveats: [81] "adapt the generative model" → REINVENT4 Lead Design (the Finetune-RL variant would be more precise); [36] nanobody → bispecific/scFv design (no nanobody workflow in the catalog); [39] (control) shifted Predict ADMET → Docking in 2/3 — not generative, arguably better.

### 6.2 Per-user Galaxy key revoked on every Galaxy restart
**Root cause (verified, read-only, on dev):** `_seed_api_key_from_env` (Galaxy boot hook, `fast_factory.py`) assumed Galaxy user 1 is the admin and soft-deleted all of user 1's other API keys on every boot. On dev, user 1 is the first BioMate user ever provisioned — the E2E fixture — so its own key died with each restart (key 269 created 18:31:14, revoked by the 18:33:38 `[boot-seed]`; 250+ revoked keys on that user since September; 8 boots in ~3 h). Chat workflow requests then failed with 401 "Provided API key is not valid." until the next login. `GALAXY_API_KEY` equals `master_api_key`, which Galaxy authenticates as the synthetic BootstrapAdminUser (`master_api_key` is a deprecated alias of `bootstrap_admin_api_key`) — so the seed had nothing legitimate to do, and **admin requests never acted as user 1** (no isolation leak; checked by booleans only, no key values read).

**Fixes:** `2edb4d4a5` + `87c1e5fbe` — the seed is a no-op when the env key is the bootstrap/master key; otherwise only the configured admin user's keys are touched; never user 1 by assumption. Login also stored Galaxy's raw user id ("1") while the drift check compared the encoded id from `/api/users/current`, so every login logged "id drift" and re-provisioned; provisioning now stores the id Galaxy reports for the key.

**Verified on dev:** boot log "GALAXY_API_KEY is the master_api_key — … nothing to seed, no user's keys touched"; the fixture's key 273 (created 21:52 UTC) still active after two later Galaxy boots (00:50, 01:07 UTC); 9 fixture logins since the deploy, **0** "id drift".

**Still open (not addressed):** the chat request path has no recovery for a key Galaxy rejects mid-session (only login re-provisions); the sync DB layer can replace `universe.sqlite` when `galaxy_ai_tools.db` changes (would invalidate all per-user keys — the request-time recovery would cover both).

### 6.3 Harness
Committed in `scripts/routing_eval/` (`aae875b05`) after the scratch copy was wiped by a restart: payload dump from the UI's own code, runner with SSE `final`-event stop + hard deadline (a lost FIN on the client↔EC2 path had stalled a run for 90 min while the server had answered 200), scorer. Fixture password via `E2E_FIXTURE_PASSWORD` (never committed).

---

## 7. Mid-session key recovery, IND pause, forwarder consolidation (2026-11-04)

**Mid-session Galaxy key recovery** (`9503abf5e`, `ed39c9c46`): the per-user Galaxy key was only validated at login; a key Galaxy rejected mid-session (401001 "not valid"/"expired") broke every Galaxy-backed request until re-login. Now every per-user call recovers once: `GalaxyAPIProxy.forUser(key, onKeyRejected)` (all 56 proxy calls) and `fetchGalaxyWithKeyRecovery` / `fetchGalaxyAsUser` (the routes that fetch() the backend directly), both via single-flight `AuthService.recoverGalaxyKey`. Tests run in vitest's Node environment against a local Galaxy-like server (real fetch/FormData; jsdom's FormData can't be sent by Node fetch — `client/src/test/setup.ts` now applies browser mocks only where `window` exists). Deployed; the live revoke-and-retry check (`scripts/verify_galaxy_key_recovery.sh`) writes one row in dev's Galaxy DB and was not permitted to run from the agent — run it with `E2E_FIXTURE_PASSWORD` set.

**Deploy-script hazard — FIXED in `f861d4313` (replacement now needs `BIOMATE_REPLACE_GALAXY_DB=1` and backs up dev's DB first; dry-run verified). Each checkout runs its own copy of the script, so the main checkout (on `fix/resolver-real-nfcore`) stays unguarded until it takes this commit. Original finding:** `scripts/sync_to_dev.sh` `deploy_databases()` copies the local `backend/database/universe.sqlite` over dev's live Galaxy DB whenever the DB layer runs (no comparison/backup). `/Users/kky/biomate` has a July-2 copy: a sync from that checkout would reset dev's Galaxy users/histories/keys to July. Proposed: replace it only behind an explicit opt-in flag.

**IND paused** (`4407cb3c2`): `IND_REPORT_ENABLED` (feature-flags.ts, off unless `VITE_ENABLE_IND_REPORT=true`) gates all four entry points — the sidebar entry, the `/ind-report` route, chat's "Generate IND" chip (was still shown after every ADMET/PBPK run), and chat's roll-into-IND affordance (was calling `/api/ind-report/projects` on every completed workflow). Verified on dev: none of them remain in the deployed client bundle. Backend + forwarders kept for re-enable.

**Forwarders consolidated** (`8ed3da929`): the ind-report / regulatory / grounded / DL forwarders (Node → Python backend; request/response APIs, not workflows — Nextflow doesn't apply) were copy-pasted; now one `backendPassthrough(label)` (−87 lines). Verified on dev, identical before/after: `GET /api/ind-report/projects` 200 `{"projects":[]}`, `GET /api/regulatory/active_adapter` 200; `GET /api/models` 200 (5 models). `/api/grounded/*` has no caller anywhere (Grounded Standards Assistant backend built, not wired into the product) — left in place.

---

## 8. Faithful harness, ad-hoc compute, upload pipeline (2026-11-04, overnight)

**Harness made faithful** (`278643c3e`): `ROUTE_EVAL_WITH_FILES=1` uploads each example's demo files and appends the composer's `[Attached files]/[Uploaded datasets]/[Upload warnings]` blocks exactly as `chat-interface.tsx` does. First result: the "DE + GO → GEO Data Connector" misroute was a **probe artifact** — with the real attachments the GEO fast path's existing "data already attached" guard steps aside and the examples route to nf-core/differentialabundance (5/6). No code change for it.

**Ad-hoc compute → run_code** (`cfb903f4d`): "Summarise this assay table…", "Correlate predicted and measured IC50…", "Reshape this plate readout…" were forced into workflow generation (Assay Ingestion / Run Audit Export / QSAR RF / HTS QC / nf-core/demo). `isAdhocAnalysisOfAttachedData` (attached-dataset block + ad-hoc verb in the request's first paragraph + no pipeline vocabulary) feeds the existing direct-code-execution override (keeps `needsLLMReasoning`, not the `aadd82091` empty-response path). Claims exactly the 3 Ad-hoc compute examples among all 106 payloads (test). With files, 3 reps: run_code **0/9 → 9/9**; controls (DE+GO, MG DE, rank, ADMET screen) unchanged.

**run_code had no inputs** (`686a38fba`): routed correctly, the model still called run_code *without* `input_datasets` and read guessed paths; INPUT_FILES was empty, [12] ended with an empty-directory listing — and the earlier "working" [11] had silently summarised the 20-line `read_file` preview (19 compounds) instead of the 1,513-row table. Fix: stage this turn's attachments when the model lists none; authenticate Galaxy dataset reads; return `staged_inputs`. Verified on dev, 2 reps each (`evaluation/routing_eval/runs/adhoc_answers_after_686a38fb.txt`): [12] Pearson r = 0.383 / Spearman ρ = 0.367 over 1,310 compounds; [11] 1,513 compounds / 691 active; [13] 96-row long table saved. Pattern every run: 1st call guesses a path (exit 1), 2nd uses the staged paths (exit 0).

**Uploads never reached Galaxy** (`dd82da160`): every chat upload logged `Dynamic require of "form-data" is not supported` — `uploadDataset` used `require()` in the ESM bundle and posted to a JSON-only Galaxy endpoint. Fixed on 2026-08-10 on side branches only; never reached this lineage, no test. Ported verbatim + tests + a guard that no server file calls `require()`. Verified on dev: uploads now return a `galaxy_dataset_id`.

**Upload allowlist rejected the examples' own inputs** (`1bd0155f7`): 4 PDB structures + the SMILES actives attached by docking/design/structure/rank examples → HTTP 500. One allowlist module + test over every demo asset; unsupported types return **415** with a message (terminal handler honours 4xx). Verified on dev: `1IEP.pdb`/`.smi` upload (with Galaxy ids); `.exe` → 415.

**Still open:** the first run_code call per turn still guesses a path (recovered on the 2nd via `staged_inputs`) — telling the model the staged paths *before* its first call would save a round; the INTERNAL "MG demo project" examples were not re-measured with project files.
