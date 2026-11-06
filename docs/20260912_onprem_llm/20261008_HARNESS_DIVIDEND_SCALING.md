# Harness dividend vs model size — the scaling curve (RealBio, via OpenRouter)

**Date:** 2026-10-08
**Author:** Yaoyun Zhang (xiaoni5122@gmail.com)
**Status:** IN PROGRESS — results appended per model as they land (see run log at bottom).

## Question

Does BioMate's harness (the retrieval/catalog + schema layer) contribute a *dividend*
(LLM+harness − bare LLM) that is **largest for the smallest models** and stays
**~flat-high across model size** on routing — while a harness-independent knowledge control
(LitQA2, bare) **rises with size**? If so, the harness substitutes for raw model capacity on
the system-carried tasks: a small on-prem model + harness ≈ a frontier model + harness.

This is a Paper-B figure. It extends the single-model comparison in
`20261004_REALBIO_LLM_VS_HARNESS.md` (which showed routing bare 0.18 → catalog 0.815 on a 9B,
and 0.615 → 0.960 on Opus-5) into a *size sweep*.

## Method

- **Runner:** `evaluation/datasets/public_export/run_baseline.py` + `score.py` (the shared,
  no-LLM-judge objective scorer). Endpoint: OpenRouter (`--base-url https://openrouter.ai/api/v1
  --key-env OPENROUTER_KEY`). Key: `~/.config/biomate/openrouter.key`.
- **Tasks / conditions (same n per cell, all models):**
  - `cross_domain_routing` **bare** (`--mode bare`, n=200) — LLM from its own knowledge, no candidate list.
  - `cross_domain_routing` **+harness** (`--mode catalog --catalog-style described --wf-db
    backend/database/galaxy_ai_tools.db`, n=200) — the production retrieval layer: each candidate
    workflow annotated with its one-line DB description (faithful to `UnifiedWorkflowSearch`).
  - `param_prefill` **bare** (`--mode bare`, n=170) — extract params from the request with **no**
    candidate param names.
  - `param_prefill` **+harness** (`--mode catalog`, default, n=170) — given the candidate param
    names (the harness's schema layer). *Note: a bare LLM cannot know a workflow's exact param keys,
    so bare F1 is a structural floor; the +harness number is the shipped condition.*
  - `litqa2` **bare** (n=199) — the harness-independent KNOWLEDGE control (parametric MCQ, no retrieval).
- Scored with `score.py`: routing = exact-match accuracy (acceptable_alts credited);
  param_prefill = key+value F1; litqa2 = accuracy (correct/all).

## Model ladder (what OpenRouter actually serves)

**Qwen dense ladder (one family, one generation — Qwen3 base, instruct):**
`qwen/qwen3-8b` (8B) → `qwen/qwen3-14b` (14B) → `qwen/qwen3-32b` (32B).
These are the dense (non-MoE) instruct models of the Qwen3 base generation, giving a clean
total-parameter x-axis. 32B marginally exceeds the ≤27B soft cap but is the natural top of this
dense family and is still single-GPU on-prem-servable; it keeps the ladder in one generation
rather than confounding size with generation.

**Explicitly NOT available on OpenRouter (do not fake):** the small dense Qwen3.5 sizes
(0.8B / 2B / 4B) that were hoped for are **not** served by OpenRouter (verified against live
`GET /v1/models`, 468 models, 2026-10-08). The smallest dense Qwen on OpenRouter is 7–8B
(`qwen-2.5-7b-instruct`, `qwen3-8b`). `qwen/qwen3.5-9b` exists but is a different generation.
So the ladder floor is 8B, not sub-1B.

**Frontier anchor (ties to existing leaderboard data):** `anthropic/claude-opus-5` — reusing the
existing full-n `results/anthropic_claude-opus-5/` cells (bare routing, catalog-described routing,
litqa2, param_prefill), which are the same runner/metric and are the leaderboard's 0.615 routing row.

## Results

### Deployable Qwen3.5 / 3.8 set — the ≤27B models actually served (2026-10-08)

**Correction to the ladder note above.** The models run here are the three **deployable
(≤27B) Qwen3.5/3.8** endpoints OpenRouter serves, verified live via
`GET /v1/models/<id>/endpoints` (none 404'd):

- `qwen/qwen3.5-9b` — "Qwen3.5-9B" (9B dense)
- `qwen/qwen3.5-27b` — "Qwen3.5-27B" (27B dense)
- `qwen/qwen3.8-27b` — "Qwen3.8 27B" (27B dense, newest generation)

These are the correct target family for the on-prem ≤27B question; the earlier `qwen3-8b/14b/32b`
rows are the OLD Qwen3 base generation and are **not** substitutes for this comparison.
Only **two distinct sizes** are served on the API (9B and 27B), so this is a **2-point size
comparison** (9B → 27B) plus a **same-size generation cross-check** (3.8-27B vs 3.5-27B). The
sub-5B dense sizes (0.8/2/4B) are **not served** and would need self-hosting for a full curve —
not faked here.

**Decoding config (important, applies to this block only).** All three are *thinking* models:
with the harness's default 2000-token budget and reasoning **on**, routine routing spends
~1–8k reasoning tokens and the answer is frequently truncated (an artifact, not capability) and
the $ cost is ~10–30× higher. To measure capability within budget and remove the truncation
artifact, these runs use **reasoning disabled** (`{"reasoning":{"enabled":false}}`,
`OR_MAX_TOKENS=2500`), applied **identically** to all three models. The within-block
comparisons (9B vs 27B; 3.8 vs 3.5) are therefore clean; these rows are **not** directly
comparable to the reasoning-on `qwen3-*`/frontier rows and must not be merged into one ladder.
(`run_baseline.py` gained an env-gated passthrough — `OR_REASONING_DISABLE`, `OR_MAX_TOKENS` —
defaulting OFF, so all prior/other runs are unchanged.)

| Model | Size | routing bare | routing +harness | **routing dividend** | param bare F1 | param +harness F1 | **param dividend** | litqa2 bare (acc / prec / cov) | n (rt/pf/lq) | est. $ (EVAL1) |
|-------|-----:|-------------:|-----------------:|---------------------:|--------------:|------------------:|-------------------:|:--:|:---:|---:|
| qwen/qwen3.5-9b  | 9B  | 0.120 | 0.815 | **+0.695** | 0.043 | 0.556 | **+0.513** | 0.191 / 0.342 / 0.558 | 200/170/199 | ~0.055 |
| qwen/qwen3.5-27b | 27B | 0.240 | 0.930 | **+0.690** | 0.059 | 0.675 | **+0.616** | 0.286 / 0.416 / 0.688 | 200/170/199 | ~0.130 |
| qwen/qwen3.8-27b | 27B | 0.175 | 0.865 | **+0.690** | 0.058 | 0.625 | **+0.567** | 0.246 / 0.350 / 0.704 | 200/170/199 | ~0.066 |

*(routing/litqa2 = accuracy; param = key+value F1. `must_not_fill` violations on the +harness
param cell: 60 / 62 / 49 respectively — reported separately as a hard penalty, see score.py.
param cells had some empty extractions — 30/18/27 (catalog), 31/17/25 (bare) — scored as recall
misses, real behaviour not truncation. EVAL1 $ is estimated from the per-cell token sidecars ×
representative provider price; the exact session total is in the run log.)*

**Reading the dividend.**
- **Routing harness dividend is enormous and size-robust: +0.69 for all three.** Bare (model
  names the workflow from parametric memory) is 0.12–0.24; giving the in-context described
  catalog (what `UnifiedWorkflowSearch` actually shows the LLM) lifts routing to **0.82–0.93**.
  The harness contributes far more than model size does — the 9B *with* harness (0.815) beats
  any of the three *without* it. This is the core "harness-dividend" result.
- **Param-extraction dividend is also large (+0.51 → +0.62):** a bare LLM cannot guess a
  workflow's exact parameter keys (bare F1 ≈ 0.04–0.06, a floor by construction); giving the
  candidate param schema (the harness layer) lifts F1 to 0.56–0.68.
- **Size vs generation:** 9B → 27B helps bare routing (0.12 → 0.24) and param/litqa2, but the
  +harness routing ceiling is similar across sizes (0.82–0.93). **Same-size cross-check:** the
  newer **3.8-27B does *not* beat 3.5-27B** here — 3.5-27B is higher on every cell
  (routing +harness 0.93 vs 0.865, param +harness 0.675 vs 0.625, litqa2 0.286 vs 0.246). The
  newer generation's gains (longer-context/agentic/multimodal) don't show on these short
  routing/extraction tasks with thinking disabled.

## Run log

**2026-10-08 — Qwen3.5/3.8 deployable set (reasoning disabled).** Ran `run_baseline.py` + `score.py`
for `qwen/qwen3.5-9b`, `qwen/qwen3.5-27b`, `qwen/qwen3.8-27b` on `cross_domain_routing`
(`--mode bare` and `--mode catalog --catalog-style described --wf-db backend/database/galaxy_ai_tools.db`),
`param_prefill` (`--mode catalog` and `--mode bare`), and `litqa2` (bare). Full n per cell
(routing 200, param 170, litqa2 199). **0 empty predictions on routing/litqa2; 0 API errors.**
Output dirs: `results/qwen_qwen3.5-9b/`, `results/qwen_qwen3.5-27b/`, `results/qwen_qwen3.8-27b/`.
Config: `OR_REASONING_DISABLE=1`, `OR_MAX_TOKENS=2500`, base-url `https://openrouter.ai/api/v1`,
`--key-env OPENROUTER_KEY`.
- **Why reasoning-off:** confirmed live that these models emit 1–8k reasoning tokens for routine
  items; at the default 2000-token cap the decomposition/answer truncates (`finish_reason=length`,
  empty/partial content → artificial zeros) and cost is ~10–30× higher. Disabling reasoning gave
  clean completions, uniform config, and ~$0.25 total EVAL1 cost across all three models.
- **Cost (OpenRouter credit delta for the whole session, both EVALs + the aborted reasoning-on
  probe + token-budget diagnostics):** total_usage 309.085 → 311.292 = **$2.207**. Of which the
  clean reasoning-off runs were ~$0.25 (EVAL1) + $0.33 (EVAL2); the remainder (~$1.6) was the
  reasoning-ON partial run and the budget diagnostics done *before* switching to reasoning-off.
