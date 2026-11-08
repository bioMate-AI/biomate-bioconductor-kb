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

**Mid-session Galaxy key recovery** (`9503abf5e`, `ed39c9c46`): the per-user Galaxy key was only validated at login; a key Galaxy rejected mid-session (401001 "not valid"/"expired") broke every Galaxy-backed request until re-login. Now every per-user call recovers once: `GalaxyAPIProxy.forUser(key, onKeyRejected)` (all 56 proxy calls) and `fetchGalaxyWithKeyRecovery` / `fetchGalaxyAsUser` (the routes that fetch() the backend directly), both via single-flight `AuthService.recoverGalaxyKey`. Tests run in vitest's Node environment against a local Galaxy-like server (real fetch/FormData; jsdom's FormData can't be sent by Node fetch — `client/src/test/setup.ts` now applies browser mocks only where `window` exists). **Verified live on dev (2026-11-04):** `scripts/verify_galaxy_key_recovery.sh` logs in, deletes the fixture's Galaxy key through Galaxy's admin API (`DELETE /api/users/{id}/api_key`, HTTP 204), and sends a workflow request on the same session → `workflow_ready`, with the log lines `Galaxy rejected …'s API key mid-session — re-provisioning` and `per-user Galaxy key was rejected mid-session — re-provisioned, retrying once`. PASS. The script reads the fixture password from `~/.config/biomate/e2e_fixture_password` (local, chmod 600) and is allowed by a narrow permission rule, so it runs without manual steps.

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

**Wasted run_code rounds** (`1644f4eec`, `fedc000a4`): two causes of extra calls, fixed one at a time and each re-measured on dev with the same 6 runs ([12], [11], [13] × 2, real uploads):

| Build | run_code calls (6 runs) | First call exit 0 | Answers |
|---|---|---|---|
| `686a38fba` (auto-staging only) | 12 | 0/6 | correct |
| `1644f4eec` (+ staged paths in the prompt before the 1st call) | 13 | 5/6 | correct |
| `fedc000a4` (+ "each call is a FRESH process" in the tool description) | 8 | 5/6 | correct (r = 0.383 over 1,310; 1,513 / 691 active; 96-row long table) |
| `1b9f74f81` (+ first 3 lines of each attached text table in the prompt) | 16 | 3/6 | correct — exposed a staging race (below) |
| `7a1bbf7e` (+ Galaxy dataset state checked before reading) | 13 | 6/6 | correct |
| `97fdd300a` (+ guarded `np`/`pd`/`plt`/`sns` imports) | 15 | 5/6 | correct |
| `11869f75f` (+ uploads read from the local copy; Python cells keep state within a reply) | 12 | **6/6** | correct — **0 failed calls of 12** |

`1644f4eec` fixed path guessing but exposed a second cause: in [13] the model split the work across calls and the second call raised `NameError: plate_layout` (it assumed variables persist). `fedc000a4` states that every call is a new process, and [12]/[11] now finish in a single call. Raw output: `evaluation/routing_eval/runs/adhoc_answers_after_{686a38fb,1644f4ee,fedc000a}.txt`. Then, with stderr captured from the stream (`adhoc13_stderr_5eede051.txt`), each remaining failure was traced and fixed at its cause:
- **Guessed column names** (`KeyError: 'index'` — `plate_layout.csv`'s first column is `row`): the model had never seen the header. The inputs note now carries the first 3 lines of each attached csv/tsv/txt/smi file (`1b9f74f81`).
- **Empty staged files** (`EmptyDataError`): measured on dev, Galaxy reports `state=running` for ~19 s after an upload while `/api/datasets/{id}/display` answers HTTP 200 with 0 bytes, then a partial body. `run_code` staged that whenever a question followed the upload immediately — what real users do. `7a1bbf7e` checked the state first; under 3 parallel chats the check itself could fail and fall through, so `11869f75f` reads an upload from BioMate's local copy (the bytes the user sent) and never from Galaxy; Galaxy, state-checked, waiting up to 60 s and failing loudly, is only for datasets that exist nowhere else.
- **State assumed between calls** (`NameError` for `np`, `plt`, `df`): stating "each call is a FRESH process" did not change the model's behaviour; code-interpreter tools are conventionally stateful. `97fdd300a` added guarded imports for the conventional aliases; `11869f75f` makes Python calls within one reply behave like notebook cells (earlier successful cells of the turn are re-run silently first; R/bash unchanged) and the description says so.

Remaining calls beyond one per answer are deliberate steps (inspect → compute → save), not retries. Raw output: `evaluation/routing_eval/runs/adhoc_answers_after_*.txt`.

**Still open:** the INTERNAL "MG demo project" examples were not re-measured with project files.

---

## 9. Real nf-core pipelines were missing from dev's Galaxy container (2026-11-04)

**Trigger:** an external user's "integrate bulk RNA-seq and proteomics" session (`chat-1793740002652-uci2ce46i`, 2026-11-03/04): 6 runs of `nf-core/diaproteomics`, all `failed` with 0 steps; `execution_json.error` = `Could not resolve Nextflow script 'nfcore/diaproteomics/main.nf'` (the run's `error_message` column was empty).

**Cause:** `backend/nf-core-workflows/` (the downloaded pipelines) and `backend/nf-core-modules/` (the nf-core library) are git-ignored apart from BioMate's own files, belong to no layer of `scripts/sync_to_dev.sh`, and the running Galaxy image is a `docker commit` chain (2026-10-01 → 10-14) of containers that did not contain them. They existed only on the dev host in `/opt/biomate/galaxy_build/` (137 pipelines downloaded 2025-10-30; 93 subworkflows; 1,651 module files). In the container: 0 real pipelines (15 display-only stubs), 0 subworkflows.

**Fix:** restored into the running container (additive) and verified: **all 230 catalog `nf-core/*` entries resolve** (137 pipelines + 93 subworkflows). **Correction (2026-11-05):** "resolve" meant `main.nf` exists — not that the pipeline runs. 125 of the 137 host copies held only top-level files (no `conf/`, `modules/`, `subworkflows/`, `workflows/`), so their runs failed at config parse; found by `-profile test` validation and fixed in §15.3 (complete copies cloned from github.com/nf-core). `ensure_nfcore_pipelines` (`e57f19269`, `46430217b`) now restores any missing ones from the host copy on every sync (~5 s no-op when complete). Backup: `s3://biomate-nextflow-work/nf-core-library/nf-core-library-20261104.tar.gz` (the dev deploy role cannot write to that bucket; uploaded from the workstation).

**Still open for that user:** `nf-core/diaproteomics` processes raw DIA spectra (mzML); the user has processed tables (counts/CPM + DIA-NN `report.pg_matrix.tsv` + DIA-Analyst designs), so it was the wrong pipeline even when resolvable. The catalog has building blocks (`mixomics_spls_regression` ok, `omicade4` ok, `multigsea` unvalidated, `mofa2` fixture_failed) but no end-to-end processed-table RNA + proteomics integration workflow. Failed-run reasons are not copied to `execution_runs.error_message`.

---

## 10. Orchestration audit for multi-layer requests, and the main-branch merge (2026-11-04)

**Question (from the bulk RNA-seq + proteomics report, §9):** why did orchestration not split "integrate bulk RNA-seq with DIA proteomics (lysate + secretome)" into existing workflows? Replayed on dev with the user's own wording (chat only): the classifier (`gemini-3.8-flash`, every message; the Pro tier is disabled in `pickGeminiIntentModel` because it hung without a timeout) returned 2 intents (`workflow_generation`, `data_interpretation`), `is_sequential=false`, `chain_hint=multi_omics_mofa_chain`; the turn ended on a single `nf-core/differentialabundance` card.

**Code-verified state (corrects an earlier statement made from Oct 8–12 notes):**
| Piece | Code | State |
|---|---|---|
| Linear chain execution (handoff, type checks, resume, reconcile) | `workflow_chain.py::_run_chain` | live |
| Parallel DAG execution (`depends_on`, `max_parallel`) | `_run_dag_chain`, `galaxy.chain.dag.run_plan`; Node `/api/workflows/chain` passes `depends_on` | built, API-reachable; chat never emits a DAG |
| Curated chain lookup by `chain_hint` | `galaxy-assistant.ts::processSequentialPipeline` | live, sequential requests only |
| DAG plan builder with typed connections | `decomposed_dag.build_dag_plan` (fire 4.4%→38.2%, 2026-10-21) | flag `BIOMATE_MULTITASK_DAG_ENABLED`, only caller `route_and_handle` has no callers |
| Harness-owned decider (parallel by default; handoff → edge; fan-in → mixed; `validate_plan`) | `grounded-prototype/research/decompose.py` (18/18 tests, 2026-10-19) | offline |
| Live wiring spec | `docs/20261019_DECOMP_ORCHESTRATION_AND_FEEDBACK_DESIGN.md` Part A "A-live" | written, not implemented |
| Pattern router PARALLEL_FANOUT, system-wide task decomposer | `feat/orch-retrieval-s2-20261008`, `feature/decomposer-diffusion-target-discovery` | other branches, not merged |
| Multi-agent orchestrator | `generate_workflow_multi_agent` | no callers |

**Where this request broke:** (1) the decomposition did not split by data layer; (2) `chain_hint` is consumed only on the sequential path, and a fork/join request is correctly non-sequential, so the hint was dropped and each sub-intent routed alone; (3) the sequential path forces curated chain steps into a line (`dependsOn: [previous]`); (4) `multi_omics_mofa_chain` is a `proposed_chains/` template whose steps name chains or workflows that are not in the catalog (`rnaseq_deseq2_de`, `mofa_plus_integration`) and always include metabolomics.

**Benchmarks for decomposition:** the valid set is `evaluation/datasets/orchestration_benchmark` (417 items: `decomposition_real` 68, `composer_orchestration` 9, `reverse_decomp` 300, `lane_arbitration` 40; bare vs +harness; execution-grounded credit). `decomposition_v2` (165) was retracted for same-generator leakage (0.73 vs ≈0.016 on real). Never run as a roster sweep. The cross-model RealBio sweep (`public_export/run_openrouter_sweep.sh`, task list fixed 2026-08-28) never included `task_decomposition`/`intent_interpretation` (added 2026-09-20) — the production decomposition model has no decomposition score.

**Plan agreed with the user (BioMate first, benchmark after):** wire the live multi-intent path to the existing decider + `build_dag_plan` → one pipeline card with `depends_on` → the existing DAG executor (first slice: independent branches + type-checked fan-in; otherwise today's behaviour); a separate decomposition call only for multi-step requests, with a timeout, plan validation and a fallback chain (stronger model → second provider → Flash → single-workflow), logging latency/cost/refusals (Opus-class refusals); then the `orchestration_benchmark` roster sweep, bare vs +harness, with a cost estimate before paid calls.

**Main-branch merge — recorded as `e0209774e`:** merged `origin/merge/next-phase-into-dev-20261103` (244 commits: `integration/next-phase` work incl. the Oct 6–Nov 3 chain fixes — orphaned-chain reconciler, chain-name binding, S3 artifact transforms). One conflict, `galaxy-assistant.ts` `processMessage` provider branch: kept this branch's OpenRouter → full agentic pipeline (shim) and the merged branch's custom OpenAI-compatible providers (`context.openaiBaseUrl`, DashScope/vLLM) → full pipeline via `_openrouterClientStorage`. The merged `routes.ts` adds server-wide fallbacks (`OPENROUTER_API_KEY`, `LLM_API_URL`/`LLM_API_KEY`) that would route every keyless user through that provider; none of them is set on dev (checked), so dev's default path is unchanged. Gate: tsc 0; vitest 2,082 passed / 0 failed; all 10 merged `api/` modules import under the dev container's python3.9 (checked against a copy of `/app/lib` with the merged files; the copy needs `client/` beside it because `galaxy/navigation/navigation.yml` is a relative symlink into `/app/client`). 4 failures are pre-existing and also fail on the live library: `unified_galaxy_nextflow_converter` (imports a missing `dual_llm_converter_system`) and three test modules that assume a different `sys.path`. **Note:** another session committed in this shared worktree while the merge was staged, so git recorded the merge (parents `63facd9cb` + `c0491a00d`, 210 files) under that session's message "feat(billing): dead-letter reconciliation consumer". The content and the conflict resolution are correct; the message is not. History was not rewritten (shared branch).

---

## 11. External-user audit and replay (2026-11-04)

**Collected** (dev Postgres; internal/test accounts excluded — fixture, owner, `@biomate.*`, `@biomate-verify.dev`, `@example.com`, `*.local`, placeholder gmail ids, demo/probe accounts; two sequential qq.com accounts kept but flagged as possibly internal): **33 users, 110 sessions, 250 user turns, 29 runs (15 failed), 0 UX-feedback rows**. Users include academic labs (pediatric cancer centre, two Chinese institutes, Hong Kong, Philippines, Canada, Russia, Harvard College, a US hospital) and biotech. Raw extract kept only in the session scratchpad (contains user data; not committed).

**Issue classes in the original sessions:** (1) ad-hoc analysis of the user's own data narrated instead of executed (tool-call markup printed as text; "run_code now, no Nextflow" ignored 4×); (2) unrelated workflow cards on non-workflow turns (lab-automation test script for a cell-viability comparison, HTML test, scaffold hopping for a patent question); (3) a cryptocurrency-miner request turned into a runnable card and run twice; (4) "why is my run failing?" answered from literature, not from the run's error (3×); support/UI questions likewise; (5) an invented GEO accession (user caught it) and off-topic citations; (6) a 5-turn clarification loop; (7) large-file ingestion: 30 GB upload failures, contradictory answers about Drive links, no cloud import guidance (~40 turns, "not user friendly"); (8) June–July outages (`no such table: workflows`, sandbox image pull, connection refused); (9) runs launched without required inputs (`nf-core/mag` single METABAT2 task, `tfbstools` on "sample") whose user-facing error was "Caused by:"; diaproteomics 404 ×6 (§9, fixed).

**Replay** (`scripts/routing_eval/replay_sessions.py`, 33 scenarios / 41 turns from the users' own wording, synthetic stand-in files where they used private data, chat only; dev at `bedcc0b5`) + `verify_citations.py` (NCBI/Crossref):
| Status | Scenarios |
|---|---|
| **Resolved** | ChIP-seq from GEO (no db error); bulk RNA-seq from GSM ids; scRNA on GSE157703 (card, not "run it locally"); WGS germline; PBPK apigenin; chai1 test; crypto-miner **refused**; clarification loop (one question, then asks for data); fibroadenoma (honest "scarce", no invented ids); **all 52 cited GEO/PMID/DOI identifiers exist**; Chinese beginner guidance; Italian reply language |
| **Still broken — literature agent answers non-literature questions** | public-dataset search (sepsis scRNA: "the provided literature does not identify datasets" though `query_database` was called); patent ownership ("scaffold" matched AI/tissue-engineering papers); "workflow QC not opening" and "failure to attach files" (support questions answered with microelectronics/legal papers); imatinib ADMET ("not detailed in the provided literature"); multi-omics "explain each step and cite a real example" (ultra-processed food and Bayesian priors) |
| **Still broken — ad-hoc compute on the user's data** | fold-change on an attached CSV (Chinese request): workflow card + a reply that *claims* to run code (no `run_code` call); cell-viability CSV: card instead of the requested direct result; DESeq2 / scRNA clustering on inline tables: pipeline cards that need file inputs. `isAdhocAnalysisOfAttachedData` is English-only and ignores inline tables |
| **Fixed this session** | inline scRNA table → `nf-core/proteinfold` (cell barcodes read as protein; `9620583b6`); peptide design → proteinfold (`bedcc0b5`) |
| **Other** | premature cards while clarifying (CAR-T graph, SLC7 purification → `nf-core/proteinfamilies`); URL import exists (`/api/datasets/import-url`) but the assistant says links cannot be used; textbook request answered "did you mean a design workflow?"; Italian abstract drafted with an invented cohort; bulk RNA + proteomics integration (orchestration, §10) |

**Dev outage during this work:** 18:00–18:06 CST. Two gunicorn processes started outside supervisord (parent PID 1, 17:31/17:34, absent from gunicorn.log) held :8080, so the supervised gunicorn crash-looped on "Connection in use". Cleared by hand; `restart_galaxy` now removes such strays before and after the restart (`6c826c9e2`).

### 11.1 Fixes and re-replays (same scenarios, dev)

| Commit | Root cause fixed |
|---|---|
| `8ec3fbb1e` | Ad-hoc compute on the user's data: the classifier now states `execution: direct_compute \| pipeline` (language-independent); honoured only with data in the conversation (dataset blocks or a pasted table), so the July `parseActions` protection still applies otherwise. Agent-loop guard: a reply presenting Python/R analysis code while `run_code` never ran is sent back once to execute it. |
| `87ce3ad79` | Literature-only non-answers: research synthesis states `EVIDENCE: addresses\|insufficient` (→ `evidence_answers_question`); an uncited chat answer is kept (with a note, no off-topic bibliography) when the papers do not address the question. Run-failure questions get the runs with each failed run's recorded error (failed process + specific line), on any turn. |
| `47dbececa` | **Chat context user id was `Number(uuid)` = NaN** (falsy) → every per-user feature (recent runs/errors, cross-session/episode/correction memory, domain profile) was silently skipped for all users. Off-topic research context no longer hands the model papers to cite. Empty-reply placeholder never kept. Reply language fixed to the user's own words. Composed workflows never named "Generated Workflow". |
| `9c1596a6c` | `list_history` returns each failed run's error; a missing error is reported as missing (task-log pointer), not guessed. Composed workflows without a description are named after their steps. |

Results (round 1 → round 3): fold change on an attached CSV (zh) card → computed table in Chinese; cell viability card → means, t-test, PNG + 2 CSVs, in Chinese; pasted scRNA table proteinfold card → Seurat clusters + UMAP PNG; pasted VCF → computed; sepsis public scRNA search "literature does not contain" → named studies with PMIDs (4/4 exist); fish co-evolution non-answer → honest database + literature result; imatinib ADMET non-answer → full profile; Chinese beginner chromatography citation → Chinese guidance; patent question → asks for the scaffold; "QC not opening" / "attach failing" literature → support answers; "why is the run failing?" "not enough context" → finds the user's failed run. Controls unchanged (ChIP-seq from GEO, WGS germline, PBPK, chai1, crypto-miner refusal). Round 4 (`9c1596a6c`): "why is the run failing?" now states the run has no recorded error and points to its task log (still appends a short list of general causes). Still open: the GSE157703 scRNA card is named "Custom workflow" because `_build_workflow_ga_from_generated` receives a workflow with **no steps and no description** — the steps in the reply come from the chat model, not the workflow; the composer path that produces it needs its own investigation (naming is not the fix); pasted-table DESeq2 request still gets a pipeline card; bulk RNA + proteomics integration (orchestration, §10); premature cards while clarifying (CAR-T graph); "did you mean a design workflow?" for a textbook request; URL import not offered for large files.

---

## 12. Orchestration: fork/join requests now produce one DAG plan (2026-11-04)

Wiring per the docs/20261019 Part A spec (the live caller that was never built):
- `POST /api/ai_assistant/plan_dag` (`5b72d8d7`; pure core `decomposed_dag.plan_dag_from_tasks`): sub-tasks + 1-based `depends_on` → existing pipeline-card shape (`execution_mode: dag`, `depends_on`, `connections`, `max_parallel`). Unresolved task → refused with the reason. Typed handoffs via `type_satisfies`; when catalog types cannot wire a dependent step, an **order-only** plan (no connections — `chain.dag.validate_plan` accepts it) with every dependency reported as unmapped (`9e7af9cd`). Nothing is fabricated.
- Node: non-sequential multi-intent turns with ≥2 workflow intents (not ad-hoc compute) call it **after** the per-intent routing and pass each branch's routed workflow (a bare catalog search had resolved an RNA-seq DE branch to a CLIP-seq workflow); otherwise the existing path continues.
- Classifier: branch-and-integrate guidance (one intent per layer, `dependsOn: []`; an integration intent depending on all; `is_sequential: false`).

Replay on dev (`1df25dbd`): the external user's bulk RNA-seq + lysate/secretome proteomics request → **one 4-step DAG card** (3 parallel branches → integration "uses the results of steps 1, 2, 3"); two independent requests → one 2-step parallel DAG card; the sequential QC → alignment → DE request → unchanged curated chain card; ChIP-seq / WGS controls unchanged.

**Open — branch-level routing quality:** branch workflows were RNA DE → `nf-core/differentialabundance` (ok), lysate proteomics DE → `bindingsitefinder/differential_binding_analysis` (wrong), secretome → `lc_ms_proteomics_metabolomics` (plausible), integration → `nf-core/differentialabundance` (wrong). Not a catalog gap: validated candidates exist — proteomics DE on processed matrices `proda` (ok), `msqrob2` (ok_warnings), `proteomm`; integration `mixomics_spls_regression` (ok), `omicade4` (ok). `proda`, `msqrob2`, `proteomm`, `dep` are **mis-tagged `transcriptomics`**, and each branch is routed by keyword search on its sub-query without a branch-level domain signal.

### 12.1 LLM decomposition (user direction: LLM + prompts/examples, no keyword rules)

`2b5d6cda7`: every workflow branch carries an LLM-written `task_spec` (method + data type + input format + expected output, no experimental-design labels) and `domain`; the prompt defines both with good/bad examples, a worked fork/join JSON example and the other shapes (independent, screening fan-out, strict chain). Branches are routed on `task_spec` with their own domain first. `4a991d0c8` logs each decomposed intent (the raw log is cut at 1,500 chars).

**Model trial** (real `analyzeIntent`, production prompt ≈80k chars, intent model pointed at each candidate via OpenRouter; 5 fork/join requests; results `evaluation/routing_eval/runs/decomp_model_trial_20261104.json`): structure (expected roots + join edges, not sequential) — Gemini 3.8 Flash 5/5, Gemini 3.1 Pro 5/5, Claude Sonnet 5.5 5/5, Claude Opus 5.5 4/5 (returned no intents for the docking + ADMET request in 2 s). Specs clean of design labels for all four once two scorer false positives are excluded ("duplicate marking" is a method step; "case vs control" is the comparison type). Latency per call: Flash 12–18 s, Pro 20–32 s, Sonnet 9–15 s, Opus 12–23 s. **Caveat:** the bulk RNA + proteomics request is the prompt's own worked example (contaminated); the other four are out-of-example. **Decision:** keep Flash; Sonnet 5.5 is the preferred fallback. The lysate branch's CLIP-seq selection on dev is therefore routing/catalog (mis-tagged proteomics tools, raw-spectra pipeline ranking first), not decomposition. The out-of-generator `orchestration_benchmark` comparison (≈$15–30) is pending approval.

### 12.2 Held-out decomposition benchmark — cheapest model at near-best quality

Set: the 24 workflow-level rows of `decomposition_real` (17 `real_workflow_chain` + 7 `real_nfcore_subworkflow`; the 44 GTN-tutorial rows are tool-level steps with some inverted gold edges and non-bioinformatics topics — excluded). Each of 12 models ran BioMate's real `analyzeIntent` (production prompt ≈21k input tokens) via OpenRouter (`scripts/routing_eval/decomp_model_bench.ts`); an LLM judge (Claude Sonnet 5.5) aligned predicted to gold nodes one-to-one from the request + node lists only, and node/edge F1 + structure were computed from that alignment (`scripts/routing_eval/decomp_judge.py`). Raw rows: `evaluation/routing_eval/runs/decomp_bench_20261104*.jsonl`.

**Run integrity:** the first pass scored `analyzeIntent`'s silent non-LLM fallback for 240 calls (providers throttled concurrent ≈21k-token requests; the classifier swallows the error) — that pass is kept as `…_judged_INVALID_fallbacks.jsonl` and not used. The bench now records a call without real model usage as a failure, retries with back-off and interleaves models. Final: 277/288 real responses (Opus 5.5 16/24 — 8 empty non-answers; DeepSeek, Terra, GLM-5.3 one miss each).

| Model | node F1 | edge F1 | structure | $/decomposition | median s | fail |
|---|---|---|---|---|---|---|
| GLM-5.2 | 0.586 | 0.357 | 0.42 | 0.013 | 9.5 | 4 |
| Kimi K3 | 0.585 | 0.335 | 0.42 | 0.033 | 13.8 | 3 |
| GPT-5.6 Terra | 0.578 | 0.369 | 0.38 | 0.053 | 10.1 | 4 |
| Claude Haiku 4.5 | 0.545 | 0.284 | 0.29 | 0.032 | 8.9 | 3 |
| GPT-5.6 Luna | 0.519 | 0.249 | 0.33 | 0.005 | 9.4 | 4 |
| Gemini 3.1 Pro | 0.495 | 0.309 | 0.25 | 0.068 | 18.8 | 3 |
| Claude Sonnet 5.5 | 0.527 | 0.267 | 0.25 | 0.079 | 6.4 | 4 |
| DeepSeek V4 Pro | 0.478 | 0.278 | 0.21 | 0.038 | 16.6 | 5 |
| **Gemini 3.8 Flash (production)** | 0.503 | 0.232 | 0.21 | 0.024 | 13.7 | 4 |
| Claude Opus 5.5 | 0.345 | 0.232 | 0.17 | 0.163 | 14.3 | 10 |
| Qwen 3.8-27B | 0.357 | 0.142 | 0.00 | 0.008 | 43.1 | 6 |
| GLM-5.3-Prime | 0.212 | 0.125 | 0.00 | 0.088 | 25.9 | 12 |

Paired bootstrap vs Flash (composite = mean of node F1, edge F1, structure; 5,000 resamples): GLM-5.2 +0.139 [+0.003, +0.280] (7 wins / 2 losses / 15 ties); Kimi K3 +0.131 [+0.030, +0.249] (5/1/18); GPT-5.6 Terra +0.126 [−0.001, +0.264]; Haiku, Luna, Sonnet CIs include 0. **Not yet a switching decision:** one run per model on 24 rows (most rows tie), single judge. Product finding: in production a failed decomposition call also falls back to the heuristic silently.

**Stability (3 runs, 2026-11-05)** — composite per run: GLM-5.2 0.453 / 0.382 / 0.367 (0.401 ± 0.037), Kimi K3 0.445 / 0.384 / 0.389 (0.406 ± 0.028), Gemini 3.8 Flash 0.315 / 0.330 / 0.336 (0.327 ± 0.009). Paired bootstrap on 3-run row means vs Flash: GLM-5.2 +0.074 [−0.026, +0.194] (rows 6 better / 7 worse / 11 tied); Kimi K3 +0.079 [+0.002, +0.175] (5 / 3 / 16). The single-run lead was optimistic for both. **Decision:** keep Gemini 3.8 Flash for decomposition — the most stable, called directly (no OpenRouter dependency), and no candidate is robustly better by a meaningful margin; Kimi K3 is marginally better at ≈1.3× cost, GLM-5.2 equal at ≈half cost. All candidates score low in absolute terms (composite ≈0.33–0.41), so the larger lever is the decomposition prompt (production collapses a complex single task into one intent; the held-out chains expect workflow-level steps), with this harness as its regression test. `d222c1b83` (OpenRouter model option + LLM fallback chain + degraded marking) stays off by default.

### 12.3 Corrected harness: real curated-chain names, chain_hint scored; prompt v2 not shipped (2026-11-05)

**Harness defect fixed.** The bench gave `analyzeIntent` an empty curated-chain list, while production passes the live names (`GET /api/workflow-chains?intent_hint=true`, `source != 'bioc_reactive'`, 64 names). The bench now loads them (`DECOMP_CHAIN_NAMES_FILE`), records `chain_hint`, and the judge scores it against the gold chain for `real_workflow_chain` rows (`chain_hint_acc`). Earlier composites (§12.2) were measured without chain names; the comparison below is the valid one. `decreal_sequential_66` is excluded — its "query" is the catalog placeholder "Retired workflow. No longer functional…", so zero nodes is the correct answer (benchmark design error).

**Prompt v2** (replace "a single complex task is ONE intent" with "one intent only when a single standard pipeline does every step; otherwise one intent per stage", with three out-of-set examples). Gemini 3.8 Flash × 3 runs each, 23 rows (`evaluation/routing_eval/runs/decomp_chains_{old,new}_rep{1,2,3}*.jsonl`):

| Prompt | composite (3-run mean ± sd) | chain_hint accuracy (17 chain rows) | failed |
|---|---|---|---|
| production (old) | 0.355 ± 0.009 | 0.63 | 1 per run (`decreal_parallel_5` → target-ID path, no workflow node) |
| v2 | 0.352 ± 0.005 | 0.67 | same, plus `decreal_sequential_63` once (run 2, zero workflow nodes) |

Paired bootstrap on row means (24 rows incl. the excluded one, 5,000 resamples): Δ = −0.003 [−0.034, +0.029]. **Decision: v2 not shipped** (neutral; the real fork/join request already decomposes correctly with the production prompt, §12). The patch is kept out of the tree.

**chain_hint misses are mostly by design.** Of the 6 chain rows ever missed: `bioc_methylation_dm_v2` is a `bioc_reactive` chain (not offered to the classifier; it picked `methylation_450k_array_analysis`); three ("Run RNA-seq analysis and differential expression", "Find and rank drug targets…", "test compound effect over time…") are left null by the prompt's explicit rule (no chain for a single analysis type; null when in doubt) and go through normal Tier-1 search.

**Product fix: chain_hint on single-intent requests** (`eee894a7f`). A named end-to-end pipeline ("run the full target-to-lead pipeline") is often decomposed as ONE intent with `chain_hint` set; the curated-chain lookup (Tier 2) ran only inside `processSequentialPipeline`, so the hint was ignored. Tier 2 is now `_curatedChainResponse` and is also called for single-intent `workflow_generation` turns, with the same guard (the current message must reference a chain/pipeline or a token of the hint, so a hint inherited from earlier turns is dropped). Tests: `server/curated-chain-single-intent.test.ts`.

## 13. Catalog metadata: domain re-tag, stale FTS index, and the routing A/B (2026-11-05)

**Why.** The external bulk + proteomics request's lysate branch routed to an unrelated workflow, and processed protein tables routed to raw-spectra pipelines. Catalog check: the processed-table proteomics packages were tagged `transcriptomics` (`dep`, `msqrob2`, `proda`, `proteomm`, `deqms`, `msqrob2_dia_precursor_workflow`), so the router's ±4 domain term (`unified_workflow_search.py`, step 6) worked against them.

**Method (LLM, two models, closed list).** `domain_reclassifier --all-domains --canonical` audits every executable workflow (4,168) against its current tag. The closed list is the router's own vocabulary — `domain_registry.CANONICAL_DOMAINS` (the only values `preferred_domains` can take) + `general` + the row's current tag (so "keep" stays expressible). A first pass over the catalog's full 42-tag list was discarded: it moved many workflows into routing-only tags (`biostatistics`, `genetics`, `pharmacology` — the registry says "drug_discovery, NOT pharmacology"), which would silently remove their domain match. Gemini 3.8 Flash proposed 1,164 changes (0 failed calls; a failed call keeps the tag — no keyword fallback in audit mode). Moves into `general` were not applied (they only remove signal). Claude Sonnet 5.5 re-classified each remaining change ≥0.8 confidence independently with the same prompt: **938 / 1,056 agreed** and were applied as guarded `UPDATE … WHERE name=? AND domain=<old>` (`evaluation/routing_eval/domain_retag/retag_updates_20261105.sql`; proposals + verdicts alongside). Largest groups: transcriptomics→single_cell 264, genomics→epigenomics 97, transcriptomics→genomics 85, transcriptomics→epigenomics 59, transcriptomics→systems_biology 43, transcriptomics→proteomics 34, flow-cytometry packages imaging→single_cell 28, CAMERA/XCMS epigenomics→metabolomics 19. Cost ≈ $3.5 (Flash, ×2 passes) + ≈ $2.4 (Sonnet).

**Pre-existing defect found: the FTS index was stale.** `workflows_fts` (external-content FTS5) failed `integrity-check` on the live DB (identical MD5 locally and on dev): rows had been edited without the triggers (likely the `annotation_v2` enrichment), so the index held old text — `MATCH 'dep'` returned 2 documents vs 8 after a rebuild — and the `workflows_au` trigger's `'delete'` failed with "database disk image is malformed" on the first UPDATE attempt (the partial write was restored from the pre-change backup). Fix: `INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')` before the UPDATEs; integrity-check and `quick_check` pass afterwards.

**Deploy.** Via `scripts/sync_to_dev.sh` (a direct SQL write on the dev host was denied by the auto-mode classifier; the user chose the sync path). Arm R = FTS rebuild only; arm RT = rebuild + re-tag (dev MD5 `ce6fc6d6…`; embeddings re-encoded 512 s, gunicorn restarted after). Note: `_ensure_workflow_embeddings` checks staleness once per process, so a DB change takes effect for dense search only after the Galaxy restart the sync performs.

**Routing A/B** (`evaluation/routing_eval/domain_retag/`, 20 queries × 2 reps on dev; 6 target the mis-tagged packages, 14 controls across domains; criteria fixed before the after-arms — the strict proteomics criterion was added after the before-arm, before any after-arm, because the loose regex counted raw-spectra `nf-core/proteomicslfq` as correct for processed tables):

| Arm | target (loose) | processed protein tables (strict, pre-registered) | controls |
|---|---|---|---|
| before | 12/12 | 4/8 | 27/28 |
| R — FTS rebuild (+ single-intent chain hook, see below) | 10/12 | 4/8 | 25/28 |
| RT — rebuild + re-tag, hook removed | 12/12 | 4/8 | 27/28 |

Row-level: the label-free protein-table query (row 3) moved from `nf-core/proteomicslfq` (raw spectra) to `Deqms Psm Table Isobaric` (processed tables) in both reps — the anchored strict regex does not credit it, and the isobaric (TMT) variant is not the label-free one, so it counts as a partial improvement only. The MaxQuant `proteinGroups.txt` query (row 0) still routes to `proteomicslfq`. Controls unchanged within noise. **Conclusion:** the re-tag and the FTS rebuild are correct and cause no regression, but they do not fix processed-table routing by themselves. The remaining cause is input metadata: 106 of 221 nf-core pipelines have placeholder `input_types` (`["input"]`, `["fasta"]` for the IDAT-based methylarray), and the input-type term (step 8) has no proteomics raw/processed types, so "raw spectra pipeline for a processed table" is never penalised. Next step.

**Regression found and reverted: single-intent `chain_hint` hook** (`eee894a7f` → removed in `577ea27d8`). Arm R showed it replacing correct single-pipeline cards (`nf-core/mag`, `nf-core/methylarray`) with curated chains in 4/4 cases. One intent = the classifier judged one workflow covers the request; TIER 2 stays behind TIER 1 (single covering workflow) in the sequential path only. Same commit: curated-chain cards had reached the client **unnamed** (TIER 2 set `name`; `routes.ts` reads `chain_display_name` and mapped string `chain_steps` as objects) — fixed; `route_eval.py` now falls back to `final.response` (chain replies arrive without deltas).

**Run hygiene.** A concurrent sync from the shared worktree restarted the dev frontend mid-way through the first arm-R run (08:17:54Z) — that run is kept as `…_CONTAMINATED_frontend_restart.jsonl` and was repeated; every later arm records container + gunicorn start times before/after and is valid only if unchanged.

### 13.1 input_kinds, the FTS-dominance finding, and the real cause of the proteomicslfq pick (2026-11-05)

**input_kinds** (`339ef76b9`): closed-vocabulary input kinds per workflow (`workflows.input_kinds`, LLM-labelled by `chain_composer/input_kinds_classifier.py`; Gemini 3.8 Flash, 4,167/4,168; Claude Sonnet 5.5 agreed on the raw-vs-processed class for 144/150 random rows), read only by the step-8a score term (+3 kind match; −4 processed-only user vs raw-only workflow and the reverse; never penalises a workflow accepting both). `input_types` is untouched. On dev (`b14797e0…`, synced 2026-11-05). The dev A/B run for this arm is **invalid** (gunicorn restarted mid-run); repeat pending.

**Offline search-only harness** (`scripts/routing_eval/search_offline_eval.py`): `cross_domain_routing` (200, scored 1/0.5/0 as `run_routing.py`), `bioc_method_selection` (24), the 20 domain-retag queries — against the local DB (identical to dev), without Pass-0/dense (absolute numbers differ from dev; A/B of a scorer change on identical inputs is valid). Results in `evaluation/routing_eval/domain_retag/offline_*.json`:

| Arm | routing (200) | bioc (24) | retag loose (20) | processed-table strict (4) |
|---|---|---|---|---|
| input_kinds off | 0.877 | 0.475 | 0.85 | 1/4 |
| **input_kinds on (deployed)** | **0.882** | **0.500** | 0.85 | 1/4 |
| + FTS term normalised to [0,15] | 0.735 | 0.325 | 0.80 | 3/4 |

**FTS dominance.** For the MaxQuant `proteinGroups.txt` query the FTS term (`abs(bm25) × 1.5`, commented "~30% weight") is 62 of `proteomicslfq`'s 74 points vs 42 of `proda`'s 57 — the domain (±4), input-kind (+3/−4) and Pass-0 (+3) terms cannot overturn a 17-point FTS gap. Bounding the FTS term fixes the strict rows but costs −0.15 on routing and −0.18 on bioc: FTS carries most of the useful signal. **Rejected and reverted** (not shipped).

**Real cause: inaccurate enriched annotation.** `proteomicslfq`'s `annotation_v2` keyword list includes "MaxQuant output processing proteinGroups isobaric labeling TMT iTRAQ phosphoproteomics…" — false for this pipeline (OpenMS from mzML; no MaxQuant input; not isobaric). FTS rightly dominates ranking, so keyword claims a workflow does not satisfy pull it onto other workflows' queries. Next: an LLM audit of `annotation_v2` keyword claims against each workflow's description and input kinds (drop claims the workflow does not perform or accept), measured with the offline harness before any deploy.

### 13.2 Root cause: per-query catalog patches; catalog-wide false-claim audit (2026-11-05)

**Correction to §13.1:** the false keywords are in `workflows.annotation` (the FTS-indexed keyword bag nf-core rows carry), not `annotation_v2` (empty for `proteomicslfq`; a multi-column concatenation query misattributed it). **Provenance:** `docs/20260719_ROUTING_BENCHMARK_R9_197_FIXES.md` — to make benchmark row prot_004 (then "MaxQuant output processing and statistical analysis for isobaric labeling experiments") route to `nf-core/proteomicslfq`, the query's words were appended to that pipeline's annotation. The gold was wrong (proteomicslfq is OpenMS label-free from mzML) and prot_004 was later rewritten, but the keywords stayed — real MaxQuant / TMT requests have been pulled onto a raw-spectra pipeline since. The catalog is not under version control, so the number of such per-row patches is unknown; the fix must be catalog-wide, not another hand edit.

**Audit** (`chain_composer/annotation_claim_audit.py`, `7aee147d2`): removal-only. Gemini 3.8 Flash lists VERBATIM annotation phrases claiming an analysis/input/technology/tool the workflow does not perform or accept (given description + input kinds); Claude Sonnet 5.5 confirms each, judging against the real tool because our descriptions are incomplete (the pilot rejected false removals "RSEM" from nf-core/rnaseq and "UMI consensus calling" from nf-core/sarek); applied only if verbatim, both agree, and the row is unchanged since the audit. 2,628 rows: 98 with proposals, 30 confirmed (3 calls still failing, untouched). **Scope applied: BioMate-authored annotations only (19 rows)** — on Bioconductor rows the annotation is the upstream package description, and the spot check found wrong confirmations there (e.g. DSS's own DML/DMR sentence, MassArray's description); upstream prose is not altered. Applied removals include proteomicslfq (MaxQuant output processing, proteinGroups, isobaric labeling, TMT, iTRAQ), methylseq (DMR / differential methylation), methylarray (epigenetic clock), rnavar (somatic), metapep (metaproteomics, mass spectrometry), BAM-only subworkflows ("sam"). Verified against the real nf-core sources on dev (`/opt/biomate/galaxy_build/nf-core-workflows`): methylseq README = preprocessing, alignment, methylation extraction, QC (no DMR); methylarray has no epigenetic-clock code or docs.

**Offline** (`evaluation/routing_eval/domain_retag/offline_claims_*.json`): processed-table strict 1/4 → 2/4 (MaxQuant proteinGroups query now → msstatsconvert); bioc 0.500 → 0.500; cross_domain_routing 0.882 → 0.873 — the drop is exactly two rows whose **gold depends on the removed false claims**: epi_011 (DMR from bisulfite-seq, gold nf-core/methylseq) and epi_012 (450K epigenetic clock, gold nf-core/methylarray). These are benchmark gold errors by the pipelines' own docs; `cross_domain_routing` feeds the RealBio manuscript, so it is reported here, not edited. No other row changed outcome.

### 13.3 Dev result of the claim audit; the remaining lexical lead; input-kind mismatch made disqualifying (2026-11-05)

**Dev A/B, claim-audited DB** (`8807d7e1…`, guarded run valid): target 12/12, strict 4/8, controls **28/28** (`armC_claim_audit_merged.jsonl`; six rep-2 rows that failed client-side with http −1 after 0 s — never reached the server — were re-run and are marked `rerun_reason`). No regression; the MaxQuant `proteinGroups.txt` request still → `nf-core/proteomicslfq` on dev while offline it had moved.

**Why dev differs from offline.** Production passes the intent model's `key_terms` into the FTS query (dev intent model: `gemini-3.8-flash`, as §12 measured — an earlier version of this line said 3.5 Flash, which was wrong: the env var reads 3.5 but every logged intent call uses 3.8). For this request they were `proteinGroups.txt, MaxQuant, differential abundance, LFQ, DEP, MSstats, proteomics`; reproduced locally with the identical DB, `LFQ` alone lifts proteomicslfq from 82.6 to 106.6 (a rare token that truthfully occurs in its description, "label-free quantification (LFQ)"). This is not false text: the pipeline does LFQ — from raw spectra. The deciding fact is runnability: the user's data is an explicit processed table and the workflow accepts only raw spectra.

**Change:** the step-8a mismatch penalty is a named constant, `_INPUT_KIND_MISMATCH_PENALTY`, raised from 4 to **25** — larger than the 17–24-point lexical leads measured, so an explicitly incompatible workflow is disqualified in practice (penalty, not filter: kind labels carry ~4% inter-model disagreement). Offline (`offline_mismatch_{4,25}.json`): cross_domain_routing 0.873 → 0.873, bioc 0.500 → 0.500; two rows change, both to the input-compatible workflow — EPIC beta values: nf-core/methylarray (IDAT only) → coMethDMR (beta values); Cell Ranger output: nf-core/scrnaseq (FASTQ) → nf-core/scdownstream (processed). The loose retag regexes do not credit those two names (pre-registered criterion flaw; scored as-is: 0.85 → 0.75).

**Dev A/B, mismatch penalty 25** (`armP_mismatch25.jsonl`; sync `76ac575c` healthy, no restart during the run, DB `8807d7e1`): pre-registered scores target 12/12, strict 4/8, controls 25/28. By substance: **all 8 processed-table proteomics runs now route to table-input methods** — the MaxQuant `proteinGroups.txt` request → `deqms_maxquant_lfq` in both reps (proteomicslfq in every earlier arm), DIA-NN report → msqrob2 DIA precursor, TMT peptides → msstatstmt, label-free protein table → DEqMS; the anchored strict regex (`^deqms$`) does not credit the `Deqms Maxquant Lfq` name. Controls: Cell Ranger output → nf-core/scdownstream ×2 (correct: scrnaseq needs FASTQ; not credited by the regex); shotgun "taxonomic profiling and genome binning" → nf-core/taxprofiler once (genuine partial miss — profiling without binning; was nf-core/mag in all other runs). Scores are kept as pre-registered; the regex flaws (anchoring, missing scdownstream/coMethDMR) should be fixed in a new version of the set before it is reused, not retroactively.

**Open items from §13:** (1) `nf-core/proteomicslfq` fails the executability check yet is kept as the routing result ("execution layer must adapt") — separate defect; (2) cross_domain_routing gold errors epi_011 / epi_012 (owner: RealBio); (3) 3 claim-audit calls still failing (sarek, ctrap, tapseq); (4) Bioconductor annotations excluded from the audit — needs a verifier that judges wrapper vs package scope before it can be applied there.

### 13.4 Runnability check uses the executor's resolver; text-driven card swaps respect input compatibility (2026-11-05)

**Executability** (`f008ecc19`): `_is_executable_nextflow_match` judged the file `_find_nf_file` returns — the biomni_workflows/ param stub (no `workflow {}`) — while the executor runs the real downloaded nf-core pipeline (`_resolve_nextflow_path`, real-first since 2026-08-24). Every nf-core pipeline was "non-executable" at routing time ("proteomicslfq failed executability check … keeping as routing result") and `_pick_best_executable_nextflow_match` skipped them, although `_is_runnable_nextflow_match` treated them runnable. Now the check resolves via the executor (falls back to `_find_nf_file`). 128/131 catalog nf-core entries have a real copy on dev; stub-only: bam_stringtie_merge, bcl_demultiplex, dia_proteomics_analysis (still rejected here; the webapps search copy of the check does not read files and accepts them — open). Dev A/B (`armE_exec_resolver.jsonl`, valid): 0 "failed executability check" warnings; one MaxQuant run regressed to proteomicslfq — next item.

**Card swap guard** (`ddd8dcd7c`): in that run Galaxy chose `dep` (verified by `_llm_verify_routing`), then Node Step 6c moved the card to `nf-core/proteomicslfq` because the chat reply (wrongly) recommended it "for MaxQuant proteinGroups.txt". Step 6c followed the first `nf-core/…` name anywhere in the reply, unconstrained — the precedence "text is the more authoritative signal" overrode the backend's runnability evidence. Fix: one predicate `UnifiedWorkflowSearch._kinds_mismatch` (step-8a score) also served as `input_compatible` by `GET /api/ai_assistant/workflow_by_name?name=…&query=…`; `_cardForNamedWorkflow` (Steps 6b, 6c-2) and Step 6c refuse an incompatible target; Step 6c now follows only search candidates, as 6c-2 already did. Tests: `backend/tests/test_input_kinds_scoring.py::test_input_compatible_for_card_swap_guard`, `frontend/server/card-swap-input-guard.test.ts`.

**Dev A/B** (`armG_swap_guard.jsonl`; `ddd8dcd7` backend + frontend verified in the containers; no restart during the run): pre-registered target 10/12, strict 5/8, controls 25/28. MaxQuant proteinGroups → `dep` / `deqms_maxquant_lfq` (both table methods); label-free protein table → `deqms_maxquant_lfq` ×2. Row 4 (MWAS on EPIC **beta values**, continuous phenotype): rep 1 asked for the data without a card; rep 2 → `perform_mwas_cyp2c19_metabolizer_status` — input-compatible (beta values + phenotype file + covariates) but specific to a categorical CYP2C19 phenotype; the better catalog fit is `coMethDMR` (beta values, continuous phenotypes; offline top-1). Earlier arms routed this to nf-core/methylarray, which needs IDAT files.

**Open:** (1) row-4 specificity — a generic beta-value EWAS is out-ranked by a phenotype-specific one on the "MWAS" token; (2) the pre-registered regexes of this set under-credit correct names (anchored `^deqms$`; scdownstream, coMethDMR) — publish a v2 set before reuse; (3) items from §13.3.

## 14. External review by an LLM committee (2026-11-05)

Work since §5 packaged for review with a test manual: `docs/20261105_ROUTING_ORCHESTRATION_CATALOG_REVIEW_PACKET.md`. Reviewed independently by
Claude Opus 5.5, GPT-5.6 Terra, Gemini 4 Argon, Kimi K3 and DeepSeek V4 Pro (same packet + 15 commits' code diffs; `scripts/review/llm_committee_review.py`;
$2.31). 58 findings; every one checked against the code or data before acting: **29 adopted, 9 partial, 13 deferred, 7 rejected** —
`docs/reviews/20261105_committee/TRIAGE.md` (per-finding verdict and evidence; raw outputs alongside).

Most consequential, confirmed: (1) a **data bug on dev** — the claim-audit cleaner removed "sam" from inside "samtools" in two nf-core annotations
(repaired with a token-bounded cleaner + guarded repair); (2) DAG plans **discarded** the non-workflow parts of a request; (3) a combining step
emitted before its branches **lost its dependencies**; (4) the unexecuted-code guard **kept possibly fabricated pre-execution text** in the final
message. Fixed in `ffe84a8d3` with tests. Seven rejections were contradicted by code the reviewers had not been shown (call sites outside the
diff, a later commit) — the next packet should include call sites of changed functions.

Deferred, as proposals: LLM-extracted user data kinds in place of the regex (T-LLMKINDS); which "other" kinds count as processed (T-REGIMES);
a v2 evaluation set with pre-fixed acceptable-workflow lists and ≥3 reps (T-EVALV2) — the committee is right that, on the pre-registered criteria,
the deployed arm is not better than baseline on loose/controls; re-benchmark the decomposition models with the fixed harness (T-DECOMP; 3.8 Flash, GLM-5.2, Kimi K3 × 3 runs). The deployed model is gemini-3.8-flash — the §13.3/§14 statement that dev runs 3.5 Flash was wrong (owner correction).

## 15. Committee follow-ups: T-DECOMP, T-REGIMES, T-EVALV2, T-LLMKINDS (2026-11-05)

**Correction (owner):** the deployed intent model is `gemini-3.8-flash`. `BIOMATE_INTENT_MODEL=gemini-3.5-flash` is set in the
containers, but `pickGeminiIntentModel` resolves it; every logged intent call on dev uses 3.8 Flash. My §13.3/§14 and the
review packet said 3.5 — wrong, corrected in all three documents (`cb16c9c2d`).

**T-DECOMP — decomposition models, fixed harness** (real curated-chain names; 23 held-out rows × 3 runs; `runs/decomp_models_v2_rep*`):
Gemini 3.8 Flash 0.322 ± 0.025; **GLM-5.2 0.430 ± 0.023**, paired Δ **+0.108 [+0.004, +0.227]** (rows 8 better / 5 worse / 10 tied),
≈40% of Flash's cost per call, fewer failed calls; Kimi K3 0.370 ± 0.049, Δ +0.047 [−0.030, +0.142]. Direction matches the earlier
(defective-harness) stability run. **Not switched:** the bound is near zero, n = 23, and the metric is decomposition structure, not
routing outcome. Proposed: a routing A/B of GLM-5.2 vs Flash on input_regime_v2 (needs the dev frontend's BIOMATE_INTENT_MODEL +
a dedicated OpenRouter key — owner decision).

**T-REGIMES — count vcf / peaks / gene_list as processed:** offline (`offline_regimes_{base,vcf}.json`) **no prediction changed** on any
of the three gold sets (the regex detects only vcf among the three). Null result → not changed; revisit with T-LLMKINDS kinds.

**T-EVALV2 — new evaluation set** (`evaluation/routing_eval/input_regime_v2/`): 40 queries in 19 input-regime groups (processed vs raw
for the same task, negation, both-regime, controls). Per query a list of acceptable workflows — must perform the task AND accept the
stated input — chosen from broad keyword pools of the catalog (not from input_kinds) and **fixed before any run** (`6cbde4ea3`).
Independent check of the lists by GPT-5.6 Terra (`acceptable_review_gpt56terra.txt`): 42 flags, each judged — accepted when our
wrapper's description is narrower than the task (e.g. minfi/enmix/watermelon/sesame for differential methylation), rejected when the
declared input is a known catalog placeholder (methylarray `fasta`, mhcquant empty, sesame `count_data`); four queries reworded so a
qualifying workflow exists. Scorer compares slugs (`score.py`). Catalog issue found: `nf-core/chipseq` and `nf-core/atacseq` are
`executable=0` although deployed and routed to (open; to investigate catalog-wide, not patched).
**Baseline on dev** (`v2_baseline.jsonl`, dev `2e7b0b33`, 3 reps, no restart, no connection errors): **91/120 = 0.758**. Weakest
groups: proteomics processed 6/15, methylation processed 0/6, metabolomics raw 0/3, docking from SDF 0/3, somatic from BAM 0/3.

**T-LLMKINDS — the classifier states the user's input kinds** (`b0fc95fb9`): new `input_kinds` field (closed vocabulary = data the user
HAS; not outputs wanted; not data said to be missing; per intent in multi-intent turns), threaded Node → proxy → `generate_workflow_unified`
→ `search` → score step 8a and `workflow_by_name(input_kinds)`. Absent → the text regex as fallback; `[]` → no input data stated (regex not
consulted). A unit test showed the regex flaw concretely: "I don't have the raw files, only proteinGroups.txt" gave the raw-spectra
pipeline **+3**; with the classifier's kinds it takes −25. Dev arm on input_regime_v2: pending (§15.1).

### 15.1 T-LLMKINDS result on input_regime_v2 (dev `b0fc95fb`, 3 reps)
First run: 37/120 rows failed client-side (`http -1`, network between this machine and dev; no container restart) — re-run
those rows only (`v2_llmkinds_rerun.jsonl`, no restart, none still failing) and merged with `rerun_reason`
(`v2_llmkinds_merged.jsonl`). **93/120 = 0.775 vs baseline 91/120 = 0.758 — neutral** (within run-to-run noise). My prediction
(gains on processed proteomics and methylation) **did not hold**: proteomics processed 6/15 → 6/15, methylation processed 0/6 → 1/6.

**Why:** the remaining misses are not raw-vs-processed mismatches — they are choices *within* the right regime at a finer grain:
DIA-NN protein matrix → a precursor-level workflow; peptide/Spectronaut tables → PSM-level TMT tools; array beta values → the
bisulfite-sequencing DMRcate variant; SDF ligands → a SMILES-only docking workflow; raw LC-MS → a joint proteomics+metabolomics
workflow; beta values + continuous phenotype → no catalog match (composed "Custom workflow"); and a **catalog contradiction**:
`Detect And Annotate Somatic Mutations` declares tumour/normal BAM inputs but its description says it starts from a VCF.
**Decision:** keep T-LLMKINDS (principled, tested, fixes the demonstrated negation flaw, neutral on this set). The next lever is
finer-grained input matching (sub-formats: protein vs precursor vs PSM tables, array vs sequencing methylation, SMILES vs SDF) and
catalog metadata consistency (declared inputs vs description) — not more weight on the raw/processed term.

### 15.2 Catalog consistency: disabled nf-core pipelines; code-grounded description audit (2026-11-05)

**Disabled nf-core pipelines.** 9 `nf-core/*` rows are `executable=0` although their real pipeline is deployed on dev (chipseq, atacseq,
eager, mnaseseq, moleculardynamics, spatialxe, genephylo, hackathon, testpipeline). Cause (`docs/20261001_NONEXECUTABLE_STUB_AUDIT.md`):
on 2026-10-01 the file that would run was the display stub (invented tool flags, 0 outputs). Since then the real pipelines are restored
(§9) and the executor resolves real-first. **Not flipped:** re-enabling claims they run — needs a Batch run of each pipeline's test
profile first (pending). They are routed to regardless (input_regime_v2 chip/ATAC cards).

**False description found by its code.** `Detect And Annotate Somatic Mutations` runs GATK Mutect2 from tumour/normal BAM (its main.nf);
its description said it "starts from a pre-existing VCF — it does NOT perform … variant calling" (a past per-row text patch). The
input_regime_v2 list had excluded it on a reviewer flag based on that description — restored, both arms re-scored alike (94 vs 96 /120).

**Audit** (`chain_composer/description_code_audit.py`, `d1cfcbe7f`): Flash lists VERBATIM description clauses contradicting the workflow's
own `.nf` (inputs taken, steps performed), with the code line; Sonnet confirms against the code. 3,717 rows with local code (nf-core display
stubs skipped) → **50 rows confirmed**. Triage (`evaluation/routing_eval/domain_retag/description_code_audit_*`):
- **Applied-ready (21 rows):** 16 non-Bioconductor "Inputs: csv/vcf/…" boilerplate lines that the code contradicts, and 5 factual
  clauses whose removal leaves a sound description (Aizynthfinder "mock_mode default true" — code default false; LC-MS joint workflow
  "not for single-modality" — code has `mode = proteomics|metabolomics|both`; GROMACS `pdb2gmx` — code uses tleap; OpenFE "SepTop" —
  code uses RelativeHybridTopology; P0 PKPD "Cmax within 30% of 15 nM" — code reference 30 nM). **Held until the GLM arm finishes**
  (a changed DB would reach dev on any sync).
- **Rewrite, not removal (3):** the false clause is the core sentence — somatic mutations (calls from BAM), CYP450 (claims "QSAR ML
  models"; code is "a clearly-labelled HEURISTIC"), Search Gene (claims NCBI search; code does pattern search in a sequence).
- **Code refuses / stub (3):** Isolate-Purify Immune Cells and Bacterial CFU exit with "wet-lab procedure with no compute equivalent";
  Advanced Web Search returns empty results. A routability decision (should they be routable at all?) — owner.
- **Bioconductor (excluded):** package DESCRIPTION text vs our narrower wrapper (same rule as §13.2). Several wrappers look broken
  (e.g. tidysbml's code imports `regions.bed`) — separate wrapper-quality finding.

**GLM-5.2 decomposition arm:** dev `/opt/biomate/.env` set to `BIOMATE_INTENT_MODEL=openrouter:z-ai/glm-5.2` + dedicated
`BIOMATE_DECOMP_OPENROUTER_KEY` (owner-approved; backup `.env.bak_pre_glm_*`; `OPENROUTER_API_KEY` not set). The first sync refused
(2 uncommitted source files of another session in the shared worktree) and the frontend stayed on Flash — the arm was stopped before it
could be mislabelled. It runs once the worktree is clean, after verifying the frontend env and the intent log.

### 15.3 Which LLM decomposes best (fixed harness, 2026-11-05)
Screen (1 run, 23 held-out rows, real curated-chain names, Sonnet 5.5 judge; `runs/decomp_screen_v2_rep1*`) of the newest models, then
3 runs for the top two (`decomp_screen_v2_rep{2,3}*`), compared with GLM-5.2 / Gemini 3.8 Flash (`decomp_models_v2_*`):

| Model | composite | failed calls | $/call |
|---|---|---|---|
| **GPT-5.6 Terra** | **0.472 ± 0.003** (3 runs) | 1/1/2 | 0.055 |
| GLM-5.2 | 0.430 ± 0.023 (3 runs) | 0/0/2 | ~0.010 |
| GPT-6.1 Terra | 0.414 ± 0.004 (3 runs) | 3/3/3 | 0.026 |
| GPT-6.1 Sol | 0.401 (1 run) | 3 | 0.052 |
| Gemini 3.1 Pro | 0.378 (1 run) | 1 | 0.068 |
| Claude Sonnet 5.5 | 0.355 (1 run) | 0 | 0.081 |
| Gemini 4 Argon | 0.335 (1 run) | 0 | 0.052 |
| Claude Haiku 5.5 | 0.334 (1 run) | 4 | 0.004 |
| Gemini 3.8 Flash | 0.322 ± 0.025 (3 runs) | 3/2/2 | 0.026 |
| DeepSeek V4 Pro | 0.228 (1 run) | 5 | 0.025 |

Paired (3-run row means): GPT-5.6 Terra − GLM-5.2 **+0.042 [−0.050, +0.136]** (8/6/9) — not distinguishable; GPT-5.6 Terra − Flash
**+0.150 [+0.064, +0.238]** (11/1/11); GPT-6.1 Terra − GLM-5.2 −0.016 [−0.129, +0.092]. Not tested (owner: no premium): Claude Fable 5.1,
GPT-6 Astra. Routing outcome on input_regime_v2, one clean rep: GLM-5.2 30/40 vs Flash 31/40 (the two other GLM reps were invalidated by
restarts from concurrent syncs). **Dev runs GLM-5.2** (`/opt/biomate/.env`, owner-approved; Flash is the automatic fallback).

## 16. Making the non-runnable nf-core pipelines run (2026-11-06)

### 16.1 Per-pipeline Nextflow framework (`256453a3c`)
Two groups of catalog nf-core pipelines could not run on dev's Nextflow 25.10.5 at their catalog-pinned releases:
- **DSL1 pipelines.** Nextflow 22.12 removed DSL1. The 10 affected are cageseq, clipseq, diaproteomics, dualrnaseq, eager, imcyto, mnaseseq, proteogenomicsdb, proteomicslfq and slamseq.
- **Pipelines whose manifest requires `!>=26.04.6`.** These are createpanelrefs, diseasemodulediscovery, scdownstream and stableexpression.

`nextflow_executor._pipeline_nextflow_version` now picks the framework per pipeline. It applies only to paths under `/nf-core-workflows/`; everything else keeps the hard pin.
- **DSL1 pipelines** (detected from `nextflow.enable.dsl=1`, or from having no `workflow {}`/`include {}`) run on `NXF_VER=22.10.8` with `-dsl1`.
- **Pipelines requiring a newer framework** get the smallest supported version that meets the requirement (`_SUPPORTED_NXF_VERSIONS`).
- **Plugin pin:** the override config pins the nf-amazon release built for that framework (22.10.8 → 1.11.5, 26.04.6 → 3.9.2). nf-amazon 3.x does not load on 22.10.
- **Pre-fetch:** `sync_to_dev.sh` pre-fetches each framework and its plugin into the runtime `NXF_HOME` (/opt/nextflow). It reads the version→plugin map from the executor, so there is one source of truth.

Applied to the 137 deployed pipelines, the classifier gives 123 default, 10 on 22.10.8 with `-dsl1`, and 4 on 26.04.6. These are exactly the groups found by validation run 2. pairgenomealign, phageannotator and moleculardynamics are DSL2 at their pinned releases.

### 16.2 Validation run 3 (test profiles via the product execute path, 15 pipelines in parallel)
Every DSL1 and 26.04 pipeline now parses, launches, and runs tasks on AWS Batch (logs show `NXF_VER=22.10.8 -dsl1` and `NXF_VER=26.04.6`). The remaining failures do not come from the framework:

| Cause | Pipelines | Kind |
|---|---|---|
| `no space left on device` on the Batch host (image pull or container create) | eager, clipseq, diaproteomics, diseasemodulediscovery (also likely the cause for createpanelrefs, scdownstream, imcyto, mnaseseq, slamseq; re-run needed) | infra: launch template lt-099eb24c4fe1b477e v16 boots a **30 GB** root volume shared by every image and task; 15 concurrent nf-core runs filled it |
| Test data removed upstream (`chr_sub.fasta`/`.gtf` return 404 on nf-core/test-datasets) | cageseq | upstream test data; the pipeline itself launched |
| Ensembl REST API returned 503 | proteogenomicsdb | upstream, transient |
| `$baseDir/bin/…` called by absolute path, which does not exist on the Batch host | dualrnaseq | pipeline assumes a shared filesystem → not runnable on Batch as released |
| `Cannot invoke method into() on null object` (DSL1 `into` inside a DSL2 module) | moleculardynamics (unreleased dev snapshot) | the pipeline's own code is broken → executable=0 |
| Blocked by the required-param gate (stub over-required 4 params) | proteomicslfq | fixed by §16.3 |

### 16.3 Required params from the executed pipeline's schema (`65b59be6a`)
nf-core rows resolve to a `biomni_workflows/nfcore/<name>` display stub, and the stub parser marked every null-default param as required. The executor, however, runs the real pipeline, and Nextflow validates against *its* `nextflow_schema.json`.

`galaxy/ai/executed_schema.py` now provides the required set (minus `outdir`, which the executor sets). Both param builders use it: the chat path `_get_workflow_params` and `/api/workflows/search`. Stub entries stay for display and are demoted to optional when the pipeline's schema does not require them.

Live on dev, the required params now match each schema exactly:

| Pipeline | Required params now |
|---|---|
| chipseq | input, fasta |
| atacseq, scrnaseq, mag, eager, rnaseq | input |
| ampliseq | none (its schema has `input` inside an anyOf) |
| proteomicslfq | input, database |

Before the fix, the gate asked for genome, macs_gsize, host_genome and primers instead.

### 16.4 Failed runs record why (`65b59be6a`)
The run's errorMessage used to be the last log line, for example `-[nf-core/x] Pipeline completed with errors-`. Galaxy now adds `error_summary` to a failed status, built from the run's `nextflow.log`. It picks the first match from:
1. the first failed process, with its cause and the last two lines of its command error;
2. a launch-time `ERROR ~` message, with the script and line;
3. the inputs reported missing.

Node stores `error_summary` as errorMessage. It handles both the 22.10/25.10 log format and the 26.04 format (`ERROR ~ Error executing process`). Unit tests use the real dev failure shapes.

### 16.5 Sync churn
Seven pipelines with dev-snapshot pins (`1.0dev`, …) were re-cloned on every sync, because no fetchable version matches such a pin. Sync now records the fetched version as the pin (`26e3803d1`).

### 16.6 Defects found by running the test profiles (all fixed, 2026-11-06)
Each was found from a failed or suspicious validation run. Each fix applies to every pipeline in its class, never to a single catalog row.

| Commit | Defect | Evidence | Fix |
|---|---|---|---|
| `2a0e60c7` | List/map params were sent to nf-core pipelines as JSON strings. BioMate's own `.nf` files parse those with `json.loads`, but nf-core pipelines read real Groovy lists. | proteomicslfq 1.0.0 received its 6 mzML inputs as one string and aborted: "EITHER spectra data OR an SDRF needs to be provided". | Collections for `/nf-core-workflows/` pipelines go through `-params-file` as native JSON. |
| `2fe9ce1a` | Fixed per-label resource tiers overrode each pipeline's own `check_max(params.max_cpus)` caps. | mnaseseq's test profile caps CPUs at 2, but process_high was forced to 12. TrimGalore then ran `--cores 4`, which its Python 2 cutadapt rejects. | Pipelines that have `conf/base.config` size their own labels; only the process_high queue routing is kept. |
| `f8cc10fb` | Display-stub defaults were sent as CLI params, overriding the pipeline's config and its `-profile`. Stub-only param names also reached the pipeline. | proteomicslfq got `add_decoys=true` on a database that already has decoys (PeptideIndexer abort), `max_cpus 8`, and the nonexistent `enable_umi`. proteogenomicsdb skipped its decoy and clean steps. | Param builders now show only params the executed pipeline declares, with its own defaults (config value, else schema value). The executor also drops undeclared params for every caller. The validator sends only the profile plus the required values. |
| `0b8fe587` | Failed runs ended up with `errorMessage = null`. | Every failed validation run. | `updateExecutionRunStatus(id, 'failed')` no longer erases an already-recorded error. Runs finalized elsewhere get the error filled in from Galaxy's `error_summary`. |
| `694d3a9c` | The completion poller marked live runs **succeeded mid-pipeline**. With the Nextflow head still alive, "every Batch job submitted so far is terminal" was read as "the run is done". | rnaseq, mnaseseq and slamseq were marked succeeded at 38/76/29 tasks while their heads were still running. proteomicslfq's later failure was hidden. | While a head for the run is alive, the poller waits for `.nextflow.log` to say `Execution complete -- Goodbye`, then lets the finalizer read the run's trace/log. A FAILED Batch job whose retry succeeded does not fail the run. |

Validation results are therefore judged from each run's `workflow-trace.txt` plus its Nextflow log end line, not from the reported status. Run-4 results recorded before `f8cc10fb` (eager, diaproteomics, clipseq, proteogenomicsdb) are being re-run as run 6, because stub defaults may have overridden their test profiles.

**Final status by pipeline.** Each verdict is judged from `workflow-trace.txt` plus Nextflow's own "Pipeline completed …" line.

| Pipeline | Framework | Result | Evidence |
|---|---|---|---|
| eager | 22.10.8 -dsl1 | **pass** | 26/26 tasks, "completed successfully". Re-run after all fixes (run 7): finalized 2 s after Nextflow's Goodbye, not mid-pipeline. |
| mnaseseq | 22.10.8 -dsl1 | **pass** | 81 tasks (after the label-sizing fix) |
| slamseq | 22.10.8 -dsl1 | **pass** | 67 tasks (run 5; run 4 had hit disk-full) |
| clipseq | 22.10.8 -dsl1 | **pass** | 22 tasks (run 6, test-profile params only) |
| proteogenomicsdb | 22.10.8 -dsl1 | **pass** | 8 tasks incl. decoy/clean (run 6); earlier failure was an Ensembl 503 |
| createpanelrefs | 26.04.6 | **pass** | completed successfully |
| rnaseq (regression check) | 25.10.5 | analysis pass | 208/209 tasks; only MultiQC failed: `CannotPullContainerError … no space left on device` |
| diaproteomics | 22.10.8 -dsl1 | infra | passed in run 4 (18 tasks); run 6 failed at `dia_spectral_library_search` with `[Errno 28] No space left on device` |
| proteomicslfq | 22.10.8 -dsl1 | **pass** (run 15: 47/47) | Earlier failure reproduced in its container: "No proteins left after FDR filtering". BioMate had sent the pipeline's general defaults (comet, FDR 0.05), which override the test profile (msgf, FDR 1.0); fixed by `6da61ae01`. Old note: | 44/45 tasks; the final ProteomicsLFQ (OpenMS) step exits 8 = INCOMPATIBLE_INPUT_DATA on its own test data, with only the test-profile params set. Raw-proteomics support is planned via nf-core/quantms. |
| moleculardynamics | 25.10.5 | not runnable as released (kept executable=0) | dev snapshot: DSL1 `into` inside a DSL2 module (`pre_pos_clean_pdb.nf:27`) |
| dualrnaseq | 22.10.8 -dsl1 | **pass** (run 14: 59/59) after patch `infra/nfcore-patches/dualrnaseq/1.0.0.patch` | Was: | calls `$baseDir/bin/*.sh` by absolute path, absent on the Batch host |
| imcyto | 22.10.8 -dsl1 | **pass** (run 12: 7/7) on compat image `cellprofiler-3.1.9-noentry` | Was: | the CellProfiler image's ENTRYPOINT runs `cellprofiler` instead of the task script ("You must specify a pipeline filename") |
| diseasemodulediscovery | 26.04.6 | **pass** (run 13: 70/70, BIOPAX_VALIDATOR ok) on compat image `biopax-validator-6.0.0-SNAPSHOT-glibc` | Was: | BIOPAX_VALIDATOR: "cannot execute: required file not found" |
| scdownstream | 26.04.6 | **pass** (run 17: 148/148) with `ambient_correction=decontx`, as nf-core's own CI (tests/default.nf.test) runs it | Was: | SoupX "No plausible marker genes" on its test data (dev snapshot) |
| cageseq | 22.10.8 -dsl1 | **pass** | 26/26 tasks. Its test data moved upstream into `reference/v1/` and `testdata/v1/` (the old paths 404); the validator supplies the new URLs. |

**Batch disk (fixed, `3ab18e793`, applied 2026-11-06 by the owner).** Batch autoscaling adds instances, never disk. Every host booted with the AMI's 30 GB root, shared by every pulled image and all task scratch, and stopped-task containers were kept ~3 h. `scripts/batch_lt_storage.sh` created launch template `lt-099eb24c4fe1b477e` **v17**: a 200 GB gp3 encrypted root, plus ECS cleanup (stopped tasks after 15 min, image pruning every 10 min). ce-v2, hpc-v1 and ce-spot are pinned to v17. New hosts were verified with 200 GB gp3 encrypted volumes.

Run 8 re-ran the four disk-failed pipelines on v17, one at a time; all passed with zero failed tasks:

| Pipeline | Tasks | Time |
|---|---|---|
| rnaseq | 209/209 | 27 min |
| diaproteomics | 33/33 | 11 min |
| slamseq | 67/67 | 13 min |
| eager | 26/26 | 8 min |

Open design question from the owner: "we should not run multiple workflows in one machine". Batch packs jobs by resources, not by workflow. The options (per-run compute environment, single VM per run, per-tenant compute environment) are pending the owner's reason (disk vs data isolation).

### 16.6b Run-record state: stuck, lost and never-launched runs (2026-11-06)
Validating cageseq exposed that BioMate's run record lags or never reaches a terminal state. Galaxy finished cageseq at 16:01; the record flipped at 17:22.

| Commit | Defect | Fix |
|---|---|---|
| `6da61ae01` / `133a1f10d` / `4cad9185f` | Params that equal a pipeline default were re-sent and tripped the input-path check (cageseq `input='data/*R1.fastq.gz'` → 422). The moved filter then referenced `run_id` before it was assigned (UnboundLocalError on every nf-core launch that dropped a param). The filter also dropped `params.input_paths`, which cageseq's code reads. | Params are sent only when they differ from the pipeline's default, and the filter runs before the input check. Logs are labelled by pipeline. "Known" params include every `params.X` the pipeline's code or configs read. |
| `49e071207` | The stale-run reaper self-called the auth-protected status route with no credentials. Every call got a 401, yet the log said "reconciled N/N". | It calls the route as the run's owner and counts real outcomes. |
| `075b900df` | The reaper saw only the newest 200 runs (dev: 52 running + 16 configuring in the DB; it saw 7–9). Never-launched runs (the Node process died mid-launch at a deploy) could never resolve. | It queries non-terminal runs directly. Runs still configuring/queued with no Galaxy id 6 h after creation are closed as failed. |
| `bcd4144d0` → `291580abd` | Galaxy answers 404 "Run not found" forever for runs lost in container rebuilds. The first check read `err.response.status`, but the proxy rethrows `{status_code, detail}`, so nothing closed. | A tested helper, `isNextflowRunNotFound`, matches both error shapes. A run Galaxy no longer knows, more than 24 h after start, is closed as failed with an honest message. |
| `d94fc53b9` | 3 lost runs had no owner account, so the user-scoped route couldn't be called for them. | The reaper asks Galaxy directly and applies the same rule. |

Result on dev: 16 never-launched runs and 51 lost runs (Sept 28 – Oct 14) were closed; **0 non-terminal runs remain**. Run 11, after all param fixes: mnaseseq 81/81 and rnaseq 209/209, "completed successfully". The validator now polls the UI's status route (`9a350a884`).

### 16.6c Making the remaining pipelines run (2026-11-06)
Two BioMate mechanisms were added. Both are reproducible, versioned, and cite their evidence; neither edits a pipeline by hand.

- **Compat images** (`fba08bf57`). `galaxy/ai/nfcore_compat_images.py` lists the source image, the fix, the ECR tag, the processes that use it, and the evidence. `scripts/build_nfcore_compat_images.sh` builds and pushes them on the deploy-test host. The executor emits `withName` overrides for matching nf-core pipelines.
  - *alpine-glibc*: Alpine/musl images cannot run Batch's host-mounted glibc AWS CLI ("cannot execute: required file not found"). gcompat is not enough (it lacks `dladdr1`). glibc 2.35 plus a glibc libz under `/usr/glibc-compat` runs the CLI while the image's musl programs keep working. These processes get `containerOptions=''`: the default host-libz `LD_LIBRARY_PATH` made musl Java load glibc libz and fail relocation.
  - *clear-entrypoint*: images whose ENTRYPOINT is a tool (cellprofiler `["/init","cellprofiler"]`) run that tool instead of the task script.
- **Pipeline patches** (`176dac7a5`). `infra/nfcore-patches/<pipeline>/<version>.patch` is applied by sync to the host source when the pinned version matches. `.biomate_patches` records the applied patch hashes, and the container copy is replaced when its patch set differs. First patch: dualrnaseq calls its bin scripts by name, not by `$workflow.projectDir/bin/` (absent on Batch). It is a mechanical rule covering 91 lines.
- **Validator test-harness fixes**: cageseq's test data moved to `v1/` upstream; scdownstream uses `decontx` like nf-core's CI.
- **Build host**: deploy-test was at 100% disk. With owner approval, `docker image prune -a` reclaimed 34 GB, removing only images no container used.

**Result:** all test profiles pass except moleculardynamics (unreleased dev code, kept executable=0).

### 16.7 Open
- **Batch root volume:** done. The owner applied launch-template v17 (200 GB gp3 plus ECS image/task cleanup) to ce-v2, hpc-v1 and ce-spot (§16.6, run 8).
- **One workflow per machine:** the owner's decision ("previously AWS Batch put multiple workflows on the same machine without thinking, always mistakes"). Not yet implemented.
- **executable=0 with evidence:** moleculardynamics (broken upstream code) and dualrnaseq (absolute-path bin calls). Re-enable spatialxe and genephylo, then turn on `BIOMATE_ENFORCE_EXECUTABLE`.
- **Not started yet:** nf-core/quantms for raw proteomics.

## 17. Molecular dynamics workflows: making them run (2026-11-08)

**Why.** The owner's group uses MD routinely, yet no MD workflow had ever completed through the product. nf-core/moleculardynamics does not fill the gap. It runs apo-protein GROMACS only and strips HETATM records, so it has no ligand, no drug modality and no binding energy. BioMate's own MD workflows (GROMACS protein–ligand + MM-GBSA, AMBER pmemd + MM-GBSA, AMBER peptide MM-GBSA, pmx FEP, MLIP MD) were each audited by running them.

**Test system.** T4 lysozyme L99A with benzene (PDB 181L): the receptor PDB, plus the ligand with hydrogens added and its crystal pose kept (12 atoms). The inputs are in `s3://biomate-nextflow-work/test-inputs/md/181l/`. Runs used 5,000 steps (10 ps), a smoke test only.

### 17.1 Defects and fixes

| Commit | Workflow | Defect | Fix |
|---|---|---|---|
| (earlier, §16) | amber_pmemd_md, moe_covalent_docking, schrodinger_glide_docking, alphagenome_track_prediction, polymorph_stability_screening | Groovy parse errors: script delimiters not restored, nested triple quotes, unescaped `$'` / `\(` | Delimiters and escapes repaired. MOE's body is still truncated (from `c6fceb828`); MOE and Schrödinger are licensed tools. |
| `5e812ef429` | all (launch gate); GROMACS, pmx FEP | A null-default param was treated as required even when the code handles its absence (`?:`, `!= null`, `if (params.X)`). GROMACS and pmx FEP were refused at launch. | `galaxy/ai/nf_param_requirement.py`: a null param is required only when the code enforces it. |
| `5e812ef429` | gromacs_protein_md, amber_pmemd_md | An SDF/MOL ligand without hydrogens fails parameterisation | RDKit `AddHs(addCoords=True)`; the pose is kept |
| `2e20a2b7a8` | mlip_md_simulation | Its image `biomate/mlip-md` had never been built, so every run failed `CannotPullImageManifestError` | `infra/docker/mlip-md/Dockerfile` (OpenMM 8 + openmm-ml + openmm-torch + mace-torch + AIMNet2). The final build step is an energy smoke test for both potentials. |
| `ff3be8e3c3`, `a1e643ba5e` | mlip_md_simulation | Labelled `process_high` (CPU hpc queue) although the script prefers OpenMM's CUDA platform; the image was a CPU-only PyTorch build | Label `process_gpu` → `biomate-gpu-spot-queue`, accelerator 1. PyTorch is the CUDA 12.4 build (`CONDA_OVERRIDE_CUDA`, because the build host has no GPU; it runs on any driver ≥ 525). The image is pinned as `cuda12.4-x86` (sha256:5cbb9949…, 7.9 GB). |
| `0b1ac50d0a` | gromacs_protein_md | **False success.** The run reported COMPLETED, but MM_GBSA had failed: `start frame (10) > total frames (2)`. The window was fixed at 10..100 every 5 regardless of trajectory length; gmx_MMPBSA ran under `|| true`; the parser wrote "calculation failed" with ΔG = None and exited 0. | Frames are counted with `gmx check`. When the requested start is past the end, the first ~20% are skipped, the end is capped at the last frame, and the interval shrinks to keep ≥ ~10 frames. The window used and the requested one are both recorded in `binding_summary.json`. No DELTA TOTAL means the step fails with the gmx_MMPBSA log tail. `is None` replaces truthiness (a ΔG of 0.0 read as failed). |

### 17.2 Results (wave 2, dev, 2026-11-08)

| Workflow | Status shown | Actual |
|---|---|---|
| GROMACS Protein-Ligand MD + MM-GBSA | completed (48.8 min) | LIGAND_PREP → RECEPTOR_TRIM → SYSTEM_SETUP → EM → NVT → NPT on the CPU queue, then PRODUCTION_MD on the GPU queue at **48.5 ns/day**, then trajectory analysis (162 residues, 2 frames): all succeeded. **MM-GBSA failed silently** (the defect above, fixed in `0b1ac50d0a`, not yet deployed). |
| AMBER pmemd GPU MD | failed | EQUILIBRATION: `/opt/amber24/amber.sh: No such file` and `pmemd.cuda: command not found`. See §17.3. |

### 17.3 AMBER cannot run as written: a licence decision

`amber_pmemd_md` (EQUILIBRATION and PRODUCTION_MD) calls `pmemd.cuda`. `amber_peptide_mmgbsa` sources `/opt/amber24`. On AWS both use `biomate/ambertools-gromacs-nf` (conda AmberTools 23 + GROMACS 2024). The local-only `amber24-cuda` image does not exist in ECR. `pmemd` and `pmemd.cuda` are not part of free AmberTools, including AmberTools25; they need an AMBER licence. Also, no AMBER process carries a GPU label, so the "GPU" steps went to the CPU queue.

Options for the owner:
1. Buy an AMBER24 licence, then build `amber24-cuda` and label EQUILIBRATION/PRODUCTION_MD `process_gpu`.
2. Keep AMBER force fields and preparation (tleap, ff19SB, GAFF2) and run the dynamics in OpenMM on the GPU. This is free; OpenMM reads prmtop/inpcrd natively.

Both AMBER MM-GBSA steps also share the GROMACS defects: a fixed start frame (500), and an "N/A" ΔG exits 0. The fix pattern of §17.1 applies, but it cannot be validated until the engine question is settled.

### 17.4 Build infrastructure

The deploy-test host (t3.medium, 4 GB RAM) became unreachable while building the MLIP CPU image (SSM ConnectionLost; history of OOM kills and full disk). `scripts/build_mlip_md_image.sh` now defaults to a one-shot **c6i.2xlarge spot builder** (100 GB gp3, about $0.13/h; terminates itself; hard stop at 120 min). Success requires a receipt tag `build-<instance-id>` whose digest equals the target tag's. The serial console proved unreliable as a log channel. `BUILD_MODE=host` keeps the old path. The CUDA build took about 20 min, for an estimated cost of about $0.05.

Residual risk: the stale CPU build on deploy-test can push `biomate/mlip-md:x86` if the host recovers. The workflow pins `cuda12.4-x86`, so it is unaffected.

### 17.5 Open
- Deploy `0b1ac50d0a` / `a1e643ba5e` / `5e812ef429` to dev. Then re-run GROMACS (MM-GBSA must report a ΔG), run MLIP MD on the GPU queue (the summary must report `platform: CUDA`), and run the pmx FEP smoke.
- GPU sizing (catalog-wide): `process_gpu` asks for 8 vCPU / 32 GB, more than a g4dn/g6.2xlarge offers once ECS takes its share, so jobs land on 4xlarge (about 2× the cost).
- AMBER engine decision (§17.3).
- Fixture password committed in three tracked e2e/recording files (pre-existing). Move it to `E2E_FIXTURE_PASSWORD` and rotate it.

