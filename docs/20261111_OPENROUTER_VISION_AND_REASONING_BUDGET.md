# OpenRouter: image input for vision models, and the reasoning-budget truncation bug

Date: 2026-11-11 · Branch: `fix/images-and-reroute-20261111` (PR #378) · Status: vision adapter
shipped in PR #378; **reasoning-budget bug documented, fix deferred** (per user: "skip it now and
document it").

## 1. Image input on the OpenRouter / OpenAI-compatible path (shipped)

**Problem.** OpenRouter runs BioMate's full agentic loop through the Anthropic↔OpenAI shim
(`frontend/server/local-llm.ts`, `openaiCompatMessagesClient`). That shim was text-only: an image
block (a `run_code` plot, an attached image) threw and aborted the turn. After f3e1903101 it became a
text note — no crash, but no model on OpenRouter could see a plot.

**Fix (b5de468f55).**
- `localMessages(params, { vision })`: with `vision`, image blocks become OpenAI `image_url` parts
  (data URI). The OpenAI `tool` role carries text only, so a tool result's images are sent as one
  `user` message *after* the turn's contiguous tool messages, prefixed "Image output of tool call
  <id>:". Without `vision`, each image stays a text note.
- `modelAcceptsImages(cfg)`: reads the provider's `/models` listing
  (`architecture.input_modalities` includes `image`), cached per model; looked up only on turns that
  carry an image. Unreachable listing → text note (not cached, retried next time).
- On-prem `localMessagesClient` stays text-only (a local model's vision support is unknown).
- Tests: `server/image-bytes-model.test.ts` (10), `server/__tests__/local-llm.test.ts` (stale
  "image throws" test replaced).

**Which picker models see plots** (`settings-dialog.tsx` roster vs the live OpenRouter listing,
2026-11-11):

| Model | Image input |
|---|---|
| anthropic/claude-opus-5.5, anthropic/claude-sonnet-5.5 | yes |
| openai/gpt-6.1-sol-pro, google/gemini-3.1-pro-preview, x-ai/grok-4.7 | yes |
| moonshotai/kimi-k3, mistralai/mistral-large-4-0, meta-llama/llama-4-maverick | yes |
| **z-ai/glm-5.3-prime (default)**, deepseek/deepseek-v4-pro, qwen/qwen3-235b-a22b-2507 | **no** |

Live check of the three "no" models: sending an `image_url` directly returns HTTP 404 "No endpoints
found that support image input" from every provider (1 / 13 / 4 providers); the control
(claude-sonnet-5.5) answered "Red" for a red-square PNG. So the text-note fallback is required —
sending them an image would fail the whole request.

Vision siblings in the same families: `z-ai/glm-5v-turbo`, `z-ai/glm-5.3-flash`,
`z-ai/glm-5.3-flashx`; `qwen/qwen3-vl-235b-a22b-instruct`, qwen3.6–3.8 lines;
`deepseek/deepseek-v4.1-flash`, `deepseek/deepseek-v4-flash-vision-exp`.

**Plot-reading check through the product path** (run_code tool_result + image block → shim →
OpenRouter; 4 plots with exact answers: volcano up/down majority, PCA cluster count, QC failing
sample, dose-response IC50 below/above 1 µM):

| Model | Correct | Input $/M |
|---|---|---|
| z-ai/glm-5.3-prime | 0/4 (2× "can't see the image", 2× empty) | 2.80 |
| z-ai/glm-5v-turbo | 4/4 | 1.20 |
| z-ai/glm-5.3-flashx | 4/4 | 0.37 |
| z-ai/glm-5.3-flash | 4/4 | 0.04 |
| anthropic/claude-sonnet-5.5 (control) | 4/4 | — |

Four plots establish the capability (sees and reads a plot), not a ranking among vision models.

## 2. Reasoning-budget truncation on reasoning models (bug — fix deferred)

**Found while** comparing the GLM models on the decomposition benchmark
(`scripts/routing_eval/decomp_model_bench.ts` + `decomp_judge.py`, 23 held-out workflow-level rows of
`decomposition_real`, no chain-name hints, same condition for all models):

| Model | fail | node_F1 | edge_F1 | struct | $/call | med s |
|---|---|---|---|---|---|---|
| z-ai/glm-5v-turbo | 2 | 0.549 | 0.327 | 0.26 | 0.0328 | 26.6 |
| z-ai/glm-5.3-flashx | 3 | 0.480 | 0.232 | 0.13 | 0.0120 | 18.3 |
| z-ai/glm-5.3-flash | 4 | 0.450 | 0.159 | 0.17 | 0.0011 | 20.9 |
| z-ai/glm-5.3-prime | 15 | 0.164 | 0.130 | 0.00 | 0.0936 | 21.7 |

**This table is NOT a valid model comparison.** 20 of the 24 failed rows recorded exactly 4,096
output tokens (prime 15/15, flash 3/4, flashx 2/3) — the request cap.

**Root cause (reproduced in isolation, raw provider response captured):** `analyzeIntent` sends
`max_tokens: 4096` through `openaiCompatCompletion`. For reasoning models, OpenRouter counts hidden
reasoning tokens against `max_tokens`. On `decreal_mixed_1` and `decreal_mixed_4`, glm-5.3-prime
used `reasoning_tokens: 4094`, returned `finish_reason: "length"` with `content: ""` (2 chars). The
shim accepts `length` as a valid finish, the empty/partial JSON fails to parse, and `analyzeIntent`
**silently** falls back to one generic intent. On rows where reasoning stayed smaller
(`decreal_mixed_0`: 3,287; `decreal_parallel_5`: 884) the plan came back normally.

**Impact.** Any OpenRouter reasoning model — including the default glm-5.3-prime — on a complex
request can return a degraded single-intent plan with no error shown. Same class as the earlier
Gemini thinking-tokens incident (`docs/PRE_SYNC_CHECKLIST.md`).

**Proposed fix (not implemented):**
1. Budget the answer separately from reasoning in `openaiCompatCompletion` /
   `openaiCompatMessagesClient`: cap reasoning with OpenRouter's `reasoning: { max_tokens: R }`
   (all candidate models list `reasoning` in `supported_parameters`) and send
   `max_tokens = answer budget + R`, so the caller's 4,096 stays an answer budget.
2. No silent skip: `finish_reason: "length"` with empty content (or with reasoning consuming the
   budget) should raise a named error ("model spent its output budget on reasoning"), logged, rather
   than flowing into the parse fallback.
3. Unit test with a stubbed provider response (`finish_reason: length`, empty content,
   `reasoning_tokens ≈ max_tokens`).
4. Then re-run the four-model decomposition benchmark; only that run can decide whether a vision GLM
   (glm-5v-turbo / glm-5.3-flash) should replace glm-5.3-prime as the OpenRouter default.

**Where this applies on dev (checked 2026-11-11, dev container env + code):**
- Dev has **no** system `OPENROUTER_API_KEY`, so keyless users never use the OpenRouter agentic shim.
  glm-5.3-prime is only the managed default for China-origin requests *when* that key is set
  (`routes.ts` ~7319); it is not dev's default.
- Dev's intent/decomposition model is `BIOMATE_INTENT_MODEL=openrouter:z-ai/glm-5.2`, called by
  `decomposeViaOpenRouter` (`galaxy-assistant.ts` ~2914) with the same `max_tokens: 4096`. There an
  empty reply throws, is retried once, then falls back to Gemini Flash with a logged warning — not
  silent, but a reasoning-exhausted reply can cost two 45 s timeouts. Last 72 h of dev logs: 2
  OpenRouter intent calls, both OK (too few to judge). The budget fix should cover this call too.
- Dev's tool turns (run_code etc.) run on the Claude agentic loop with claude-haiku-4-5 (response
  model `gpt-5.6-luna` has no tool loop; ANTHROPIC_API_KEY is set) — plots reach it as image blocks.

## 3. Open items
- Gemini tool loop (`_generateWithGemini`) still passes tool output as text: plots render in the UI
  but the model does not see them. It runs (a) as the fallback when Anthropic credit is exhausted
  (`galaxy-assistant.ts` ~10917, incl. dev) and (b) as the primary loop on Gemini-configured /
  no-Anthropic-key deployments (code default `gemini-3.8-flash`). Not dev's normal path. Fix: send
  the image as a separate `inlineData` part alongside the function response.
- Default-model decision waits on §2 fix + re-benchmark.

Artifacts (scratchpad, not committed): `glmvision_bench.jsonl`, `glmvision_judged.jsonl`,
`plot_read_bench.ts`, `plots/truth.json`, `prime_probe.ts` + `probe_*.log`.
