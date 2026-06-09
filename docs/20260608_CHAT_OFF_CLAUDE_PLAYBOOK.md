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
default to `gemini-3.5-flash` (verified working) in all 4 sites.

## The 4 chat sites and how each routes today

| Site | What | Default model | Gemini-aware? |
|---|---|---|---|
| `galaxy-assistant.ts:4721` | intent classification | `gemini-3.5-flash` | ✓ — `_generateWithGemini` / two-tier flash↔pro routing |
| `galaxy-assistant.ts:5063` | tool ranking | `claude-haiku-4-5` | flag-gated — set `BIOMATE_CHAT_VIA_CHAIN=true` to route through llmGenerate (YAML chain) |
| `galaxy-assistant.ts:5874` | response stream | `claude-sonnet-4-6` | ✓ — `_generateWithGemini` with `responseModel.startsWith('gemini-')` gate |
| `galaxy-assistant.ts:5931` | tool-use turn | `claude-sonnet-4-6` | ✓ — same `_generateWithGemini` agentic loop (`MAX_TOOL_TURNS=12`) |

## To move everything off Claude (dev or prod)

Set ALL four env vars on the Galaxy container:

```bash
# Use the YAML fallback chain for tool ranking (Gemini Pro → Flash → Claude → ...)
BIOMATE_CHAT_VIA_CHAIN=true

# Pin each model to a verified-working Gemini name
BIOMATE_INTENT_MODEL=gemini-3.5-flash          # newest GA Flash
BIOMATE_TOOL_RANKING_MODEL=gemini-3.5-flash    # only used if CHAT_VIA_CHAIN=false
BIOMATE_RESPONSE_MODEL=gemini-3.1-pro-preview  # response + tool-use turn (the expensive ones)
```

**Model name landscape as of 2026-06-07** (verified by probing
Google's `/v1beta/models` endpoint):

Pro variants:
  - ✓ `gemini-3.1-pro-preview` — newest Pro (preview tier; matches what's
    already configured as primary in `backend/config/llm_providers.yml`)
  - There is **no `gemini-3.5-pro`** (Google has not shipped a 3.5 Pro;
    the Pro line jumps from 2.5-pro GA straight to 3.1-pro-preview)

Flash variants:
  - ✓ `gemini-3.5-flash` — newest GA Flash (use this for intent + tool-ranking)
  - ✓ `gemini-3.1-flash-lite` — even cheaper variant

Specialty (NOT for chat):
  - `gemini-2.5-computer-use-preview`, `*-image`, `*-tts`, `*-customtools` etc.

Bogus names that returned HTTP 404 (avoid):
  - ✗ `gemini-3.5-pro` / `gemini-3.5-pro-preview` (don't exist)
  - ✗ `gemini-3-pro` / `gemini-3.1-pro` (need the `-preview` suffix)
  - ✗ `gemini-3-flash-preview` (this was the bogus default that broke
    chat for months)
  - ✗ `gemini-3.5-flash-preview` (`gemini-3.5-flash` is the right name
    — no `-preview` suffix needed)
  - ✗ `gemini-2.0-flash` (`gemini-3.5-flash` is the closest GA)

## To apply on dev (one canonical flow)

Edit `/opt/biomate/.env` on the EC2 host (`ssh ubuntu@52.42.49.175`,
then `sudo nano /opt/biomate/.env`) — add or change the BIOMATE_*
keys. Then trigger one sync with the env-resync flag:

```bash
BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh
```

That flag tells `sync_to_dev.sh` to recreate the Galaxy container with
`--env-file /opt/biomate/.env` merged in (preserving every existing
env var that was set at original container launch — JWT_SECRET,
DATABASE_URL, API keys, etc.). One-shot; subsequent syncs without the
flag run normally and leave the env alone.

For the **frontend** container, `/opt/biomate/.env` is already loaded
via `--env-file` on every sync (line 178 of `sync_to_dev.sh`), so
frontend env-var changes need no special flag.

The previous one-off `scripts/enable_autofix3_on_dev.sh` has been
deleted in favor of this uniform mechanism.

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

Post-flip: same log line should show `model: gemini-3.1-pro-preview` and
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
