# Findings truncation fix + session lessons (2026-06-04 → 06-05)

## Bug summary

`GET /api/workflows/runs/:id/findings` returned populated structure but
empty arrays for every AWS Batch run:

```json
{
  "summary": "{\n  \"summary\": \"The CryoSPARC SPA test workflow...denois",
  "key_results": [],
  "next_steps": [],
  "caveats": []
}
```

The `summary` field carried a string-encoded JSON fragment that cut off
mid-word ("denois") — the rest of the structured payload never reached
the client. **Pre-existed Phase 4**; Phase 4 only surfaced it by exposing
the legacy endpoint's behavior to deeper inspection.

## Root cause — proved locally with hard evidence

Gemini 3.5 Flash uses **thinking tokens** that count against
`maxOutputTokens`. With `maxTokens: 2048`:

```
promptTokenCount: 713
thoughtsTokenCount: 1798   ← invisible to caller, counted against budget
candidatesTokenCount: 234  ← what's left for actual output
finishReason: MAX_TOKENS   ← truncated
```

234 output tokens → 902 chars → cuts off in the middle of `key_results`.
JSON.parse fails. The catch branch dumps `rawText.slice(0, 500)` into
the `summary` field — making the truncation appear as a "we generated
a string summary" instead of "the model ran out of tokens".

With `maxTokens: 8192`:

```
thoughtsTokenCount: 1798   ← same
candidatesTokenCount: 523  ← enough headroom
finishReason: STOP         ← completed
length: 1955, ends with `}`
```

JSON.parse succeeds. `key_results` populates with 3 entries, all numbers
(20 micrographs, 27,627 picks, 24,880 extracted) traceable to the S3
source files.

## Local reproducer

`/tmp/findings_repro/repro.mjs` — standalone Node script that:
1. Reads the same 4 S3 cryo-EM report JSONs the production endpoint
   would assemble.
2. Builds the identical `fileContext + SYSTEM` prompt.
3. Calls Gemini Flash at both `maxTokens=2048` and `maxTokens=8192`.
4. Logs `finishReason` + `usageMetadata` + first/last 200 chars of the
   response.

Run from `/home/yzhang/biomate/frontend/` so dotenv finds `.env`:
```
cp /tmp/findings_repro/repro.mjs _repro.mjs && node _repro.mjs && rm _repro.mjs
```

## What shipped

| Commit | What |
|---|---|
| `b2bada8ae` | (corrections) drop brittle length<100 guard; add finishReason logging in gemini-flash.ts |
| (final) | maxTokens 2048→8192 in routes.ts findings call; input-prep diagnostic logging; rawText length/preview/tail logging |

The verbose diagnostic logs stay in for now — when the next "no
findings" report comes in, the answer will be one log read away instead
of two days of guessing.

## Session lessons (for me — flagged by user, recorded as feedback)

1. **Test locally before syncing.** I synced a brittle `length < 100`
   guard without running it; a local repro caught that it would reject
   valid small responses (the no-data-found branch's
   `{"summary":"OK","key_results":[]}`). The CLAUDE.md pre-sync
   checklist exists exactly to prevent this; I bypassed it twice in
   one session.

2. **Don't guess root causes — capture evidence first.** I asserted
   "Flash doesn't have thinking" based on vague recall, walked back the
   correct thinking-tokens diagnosis, then re-discovered it via the
   actual API response (`thoughtsTokenCount: 1798`). One 30-second
   `repro.mjs` call would have settled it the first time.

3. **Don't ship a fake fix that hides the real one.** The earlier
   "improve catch message to say AI synthesis unavailable" change was
   not a fix — it just dressed up the failure. The user called this
   out: a clean error message is still no findings. The actual fix is
   making the model not truncate.

4. **Check input quality before swapping the model.** When I proposed
   switching to Claude Sonnet, the user pushed back: "why don't you
   check if the input is already crashed so no llm can give good
   output". The local repro proved the input was fine (761 bytes of
   well-formed JSON) and the truncation was on the output side. Sonnet
   would have masked but not explained.

## Open follow-ups

- **Methods-report uses Sonnet** — the same kind of synthesis task,
  larger output, no truncation. If the findings endpoint ever needs
  output bigger than ~6KB the cheap move is to switch it to Sonnet
  too (~1c per call vs Flash's ~0.1c, but reliable).
- **Other Flash callers** that ask for structured JSON output should
  audit their `maxTokens` setting against expected output size + the
  ~1800-token thinking floor.
- **Async-job-queue subsystem** is fully shipped (Phase 0/1/Gap B/2/4)
  and tested on dev. Phase 3 (`reproducibility_bundle`) deferred per
  product call.
