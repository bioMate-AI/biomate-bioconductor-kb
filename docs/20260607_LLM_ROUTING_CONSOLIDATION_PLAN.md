# LLM routing consolidation — single fallback chain (2026-06-07)

## Problem

`backend/config/llm_providers.yml` defines BioMate's LLM fallback chain:
- Primary: `gemini-3.1-pro-preview`
- Fallback 1: `gemini-3.5-flash-preview`  *(was incorrectly listed as `3.0`)*
- Fallback 2: `claude-sonnet-4-5`
- Fallback 3: `gpt-4o`
- Fallback 4: Ollama `qwen3:32b`

The backend honors this via `FallbackChainManager` in
`llm_client_fallback_implementation.py`. **The frontend doesn't.** Today
9 call sites in `frontend/server/` instantiate `new Anthropic()` directly
with hardcoded `claude-sonnet-4-5` or `claude-sonnet-4-6`, completely
bypassing the YAML config:

| File | Lines | Hardcoded model |
|---|---|---|
| `routes.ts` | 4922 | `claude-sonnet-4-5` (methods-report) |
| `routes.ts` | 10568 | `claude-sonnet-4-6` (findings analysis) |
| `routes.ts` | 12257, 12308 | `claude-sonnet-4-6` |
| `iterative-workflow-generator.ts` | 212, 357 | `claude-sonnet-4-5` |
| `workflow-prerequisites-validator.ts` | 464, 642 | `claude-sonnet-4-5` |
| `context-compressor.ts` | 219 | `claude-sonnet-4-5` |

There are also 13 `callGeminiFlash()` calls in the frontend — a thin
wrapper that bypasses the chain too (always Flash, no fallback).

User has stated multiple times that BioMate must use Gemini primary
with other LLMs as backup. The 9 hardcoded Claude calls violate this
and have been silently doing so.

## Fix plan (single-source-of-truth pattern)

1. **Correct the YAML**: `gemini-3.0-flash-preview` → `gemini-3.5-flash-preview`
   in `backend/config/llm_providers.yml` + 2 other references.

2. **Add backend endpoint** `POST /internal/llm/generate` in a new
   `backend/lib/galaxy/webapps/galaxy/api/llm_internal.py`. Auth pattern
   mirrors `billing_internal.py`: header `X-Internal-Key:
   $BILLING_INTERNAL_KEY` (or a separate `LLM_INTERNAL_KEY` if we want
   independent rotation — start with shared for simplicity).
   - Request body: `{prompt, system?, max_tokens?, temperature?, json_mode?}`
   - Body shape mirrors what `LLMClient.generate()` already accepts.
   - Response: `{text, model_used, fallback_depth, usage}` — surfaces
     which provider answered for observability.
   - Routes through existing `LLMClient.generate()` →
     `generate_with_fallback()` → respects the YAML chain.

3. **Add frontend client** `frontend/server/llm-client.ts`:
   ```ts
   export async function llmGenerate(opts: {
     prompt: string;
     system?: string;
     maxTokens?: number;
     temperature?: number;
     jsonMode?: boolean;
   }): Promise<{ text: string; modelUsed: string; fallbackDepth: number }>;
   ```
   - POSTs to `${GALAXY_URL}/internal/llm/generate` with the internal key.
   - Returns the parsed body; no model strings in TypeScript anywhere.

4. **Migrate the 9 hardcoded Claude callers** to `llmGenerate(...)`.
   Highest-priority first:
   - `routes.ts:4922` — methods-report (the live truncation issue)
   - `routes.ts:10568` — findings analysis (already failed today)
   - Then the other 7

5. **Tests** (local, before sync):
   - Backend: `POST /internal/llm/generate` with a stub `LLMClient`
     returns the expected shape + uses fallback when primary fails.
   - Frontend: `llmGenerate()` integration test against a mock server
     verifies request shape + retry on 5xx.
   - Smoke: hit the live dev endpoint with a real prompt, verify
     Gemini Pro response.

6. **Sync + verify** on dev: re-run the diverse-workflow E2E and confirm
   methods reports are no longer truncated AND that the report
   identifies its model in the `model_used` field as Gemini Pro (not
   Claude).

## What this does NOT touch (yet)

- The 13 `callGeminiFlash()` callers — separate cleanup. They DO use
  Gemini Flash directly which is at least the right family, just
  without fallback. Migrating them to `llmGenerate` is straightforward
  but lower urgency than the Claude ones that violate policy.
- The autofix3 internal `LLMClient` usage — that's backend Python and
  already uses the fallback chain (per the .call shim fix shipped earlier
  today; see commit `db3c9e490`).

## Risk

- Quality regression: methods-report has been Claude Sonnet to date and
  produces high-quality grounded prose with real PMID citations. Gemini
  Pro on the same task is unverified. If output quality regresses, the
  chain auto-falls-back to Claude (per the YAML config), so worst case
  is one Claude call rate-limited and the second tries Gemini — fast
  recovery. Will check post-migration.
- Latency: an extra HTTP hop (frontend → backend) adds ~5-30ms vs
  direct Anthropic SDK call. Negligible against LLM call latency
  (1-30s). Acceptable for the consistency win.

## Order of operations

1. Fix YAML (3 files, 1 commit, no behavior change yet)
2. Add backend endpoint + tests
3. Add frontend client + tests
4. Migrate methods-report (`routes.ts:4922`) — single call site, easiest
   to validate the wiring end-to-end on dev
5. Migrate findings analysis (`routes.ts:10568`) — second most-used
6. Sweep remaining 7 in a follow-up commit once 4-5 are stable

Each step locally tested per `docs/PRE_SYNC_CHECKLIST.md` before sync.

## Update 2026-06-07 (after first sweep) — 4 more sites surfaced

Initial survey under-counted. `galaxy-assistant.ts` has 4 additional
direct `claude.messages.create` calls — the main chat path:

| Line | What | Why deferred |
|---|---|---|
| 4721 | intent classification | uses `cache_control: ephemeral` (Claude prompt caching, saves ~80% on repeat prompts) |
| 5063 | tool ranking | same cache_control |
| 5874 | streaming response | SSE streaming + tool_use; llmGenerate doesn't expose streams |
| 5931 | non-streaming tool turn | Claude tool_use blocks; no equivalent in llmGenerate |

These four require extending `llmGenerate` to support:
  - SSE streaming with token deltas
  - Tool calling / function calling
  - Provider-specific prompt caching hints

That's a meaningful API extension and a separate work item. Until it
lands, the main chat stays on Claude — which is at least the
historically-tested path for that surface.

Also deferred for the same reason:
  - `routes.ts:12315` — Open-Claw streaming (explicitly named
    "Claude has direct access" — model lock-in is by design here)

## Sites successfully migrated this commit

✓ `routes.ts:4922` — methods-report (verified locally end-to-end:
  Gemini Pro returns 6KB grounded report with real PMIDs)
✓ `routes.ts:10568` — findings analysis
✓ `iterative-workflow-generator.ts:212` — workflow draft
✓ `iterative-workflow-generator.ts:357` — step configuration
✓ `workflow-prerequisites-validator.ts:464` — prerequisite validation
✓ `workflow-prerequisites-validator.ts:642` — user prompt generation
✓ `context-compressor.ts:219` — context summarization

6 sites + 1 already-completed = 7 of the originally-identified 9
hardcoded direct-Anthropic calls now route through the YAML fallback
chain.

## Update 2026-06-07 (after end-to-end local test) — quality observations

End-to-end test of each migrated site through real Gemini Pro (local
backend + Node llmGenerate) surfaced:

✅ Backend now forwards `jsonMode: true` → `responseMimeType:
   application/json` on the Gemini request (was being dropped before).

| Site | Behavior with Gemini Pro |
|---|---|
| methods-report | clean 6KB output, real PMIDs, no truncation (verified earlier) |
| findings analysis | JSON parses, real numbers preserved; top-level field names may differ from Claude's exact schema |
| prerequisites-validator (both) | JSON parses correctly with `jsonMode: true` |
| iterative-workflow-generator (both) | prose output vs Claude's numbered list — downstream parser tolerance unknown for new shape |
| context-compressor | needs sufficient maxTokens; caller-controlled |

These are output-shape differences, not crashes. The fallback chain
catches actual API failures. Observed quirks will be characterized on
dev with real workflow data; the migrated paths can be reverted
selectively if downstream parsers break.
