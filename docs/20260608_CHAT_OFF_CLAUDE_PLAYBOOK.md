# Chat off Claude — playbook (2026-06-08)

Per user's repeated note that Claude has frequent rate limits, this doc
captures exactly what env vars flip each of the 4 main chat call sites
in `frontend/server/galaxy-assistant.ts` over to Gemini.

**TL;DR — the chat-via-Gemini machinery has been in the codebase for
months.** The reason it wasn't actually being used:

1. `gemini-3-flash-preview` (the default Gemini model name baked into
   3 places in galaxy-assistant.ts + 1 in routes.ts) returns HTTP 404
   on Google's API — that model ID never existed publicly. Verified
   2026-06-07 by direct API probe.
2. No one had set `BIOMATE_RESPONSE_MODEL` / `BIOMATE_INTENT_MODEL` /
   `BIOMATE_TOOL_RANKING_MODEL` on the production container.

Both blockers are now removed: commit `<latest>` renames the broken
default to `gemini-2.5-flash` (verified working) in all 4 sites.

## The 4 chat sites and how each routes today

| Site | What | Default model | Gemini-aware? |
|---|---|---|---|
| `galaxy-assistant.ts:4721` | intent classification | `gemini-2.5-flash` | ✓ — `_generateWithGemini` / two-tier flash↔pro routing |
| `galaxy-assistant.ts:5063` | tool ranking | `claude-haiku-4-5` | flag-gated — set `BIOMATE_CHAT_VIA_CHAIN=true` to route through llmGenerate (YAML chain) |
| `galaxy-assistant.ts:5874` | response stream | `claude-sonnet-4-6` | ✓ — `_generateWithGemini` with `responseModel.startsWith('gemini-')` gate |
| `galaxy-assistant.ts:5931` | tool-use turn | `claude-sonnet-4-6` | ✓ — same `_generateWithGemini` agentic loop (`MAX_TOOL_TURNS=12`) |

## To move everything off Claude (dev or prod)

Set ALL four env vars on the Galaxy container:

```bash
# Use the YAML fallback chain for tool ranking (Gemini Pro → Flash → Claude → ...)
BIOMATE_CHAT_VIA_CHAIN=true

# Pin each model to a verified-working Gemini name
BIOMATE_INTENT_MODEL=gemini-2.5-flash          # default, leave as-is
BIOMATE_TOOL_RANKING_MODEL=gemini-2.5-flash    # only used if CHAT_VIA_CHAIN=false
BIOMATE_RESPONSE_MODEL=gemini-2.5-pro          # response + tool-use turn (the expensive ones)
```

Verified model names (probed against Google's API 2026-06-07):
  - ✓ `gemini-3.1-pro-preview` (HTTP 200 — Anthropic-quality on long-form scientific writing per E2E)
  - ✓ `gemini-2.5-pro` (HTTP 200 — stable, no preview suffix)
  - ✓ `gemini-2.5-flash` (HTTP 200 — fast, no preview suffix)
  - ✓ `gemini-3.5-flash` (HTTP 200 — newer flash variant)
  - ✗ `gemini-3.5-flash-preview` (HTTP 404 — bogus name; previously in YAML)
  - ✗ `gemini-3-flash-preview` (HTTP 404 — bogus name; previously hardcoded everywhere)
  - ✗ `gemini-3-pro-preview` (HTTP 404)
  - ✗ `gemini-2.0-flash` (HTTP 404)

## To apply on dev container (without recreating)

Env vars on a running container can't be changed without a recreate.
Use the existing `scripts/enable_autofix3_on_dev.sh`-style pattern, or
just edit `/opt/biomate/.env` on the EC2 host and let the next sync
container-rebuild pick it up via `--env-file`.

For a one-off persistent flip, mirror what we did for autofix3 — capture
current env from the running container, merge in the new vars, recreate
with `--env <K>=<V>`. See `scripts/enable_autofix3_on_dev.sh` lines
80-100 as a template.

## What the migration does NOT touch (by design)

- **Open-Claw mode** at `routes.ts:12315` — explicitly named "Claude has
  direct access" with Claude-only `tools` block. Model lock-in is the
  feature.
- **Prompt caching** (`cache_control: ephemeral`) — Claude-specific
  performance optimization (~80% cost reduction on repeat prompts).
  When `BIOMATE_RESPONSE_MODEL=gemini-*` is active, caching no longer
  applies to that route. If cost matters more than rate-limit
  reduction, only enable for tool-ranking + intent (already Gemini)
  and keep response + tool-use on Claude.

## Verification

Pre-flip: tail Galaxy logs for `[GalaxyAssistant] Response API request:`
lines — they show `model: claude-sonnet-4-6` today.

Post-flip: same log line should show `model: gemini-2.5-pro` and
`[GalaxyAssistant] _generateWithGemini` should appear in the trace.

If the chain falls back (e.g. Gemini quota exhausted), the existing
fallback in `_generateWithGemini`'s exception handler emits "I
encountered an error generating a response: ..." — that path is
explicit, not silent.

## Local repro

Tested 2026-06-07 with real Gemini Pro through the chain:
  - Tool ranking: 8s, correct top-2 tools, irrelevant excluded
  - Methods-report-shape long-form: 6.2 KB clean output with real
    PMID citations
  - JSON-mode (`responseMimeType: application/json`): clean parseable
    JSON returned

The Gemini-via-`_generateWithGemini` path uses **batched** response
(`sendMessage`, not `sendMessageStream`) — users wait for the full
response before seeing it. A future task could swap to
`sendMessageStream` for true token-by-token streaming UX.

## Why this wasn't already enabled

Two silent-config issues compounded:
1. The broken `gemini-3-flash-preview` default would 404 → fall through
   to Claude on every call. No one noticed because the user saw
   responses (just from Claude not Gemini).
2. `BIOMATE_RESPONSE_MODEL` wasn't being set in production's
   `/opt/biomate/.env`, so the default Claude path stayed active.

Both fall under "configured but never actually exercised" — a class of
issue that's invisible without explicit observability.
