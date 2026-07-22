# PDF tool-call leak fix + PDF tech-detail loss + ad-hoc image vision

Date: 2026-07-22
Branch: integration/next-phase

## Summary

Two user-reported problems, one shared root architecture gap: **non-text
uploads (PDFs, images) were forced through a text-only chat pipeline.**

1. **"Leaking tech details when reading PDF files."** When the model read an
   uploaded PDF and answered a methods/protocol question, its raw tool-call
   internals leaked into the user-visible chat: literal `<function_calls>` /
   `<invoke name="read_file">` XML and ad-hoc `import PyPDF2` / `print(text[:5000])`
   code, followed by the real answer in the same message. (Screenshot:
   `~/Desktop/business/bioconductor_screenshot/pdfleasing.jpg`.)

2. **Ad-hoc image uploads for a biomedical opinion were unsupported** — and
   failed the *same* way. Images weren't in the chat upload allowlist, and even
   if attached, the message builder only ever sent `text`/`tool_use` blocks to
   Claude (never `type:'image'`), so the model couldn't see the image and fell
   back to `read_file`/`run_code` on the binary → the same leak.

Also fixed en route: PDF **tech-detail loss** from table-dropping extraction and
overly-aggressive truncation.

## Root causes

- **Leak:** The model sometimes *narrates* a tool call as prose text instead of
  emitting a structured `tool_use` block (a model-behavior artifact, most common
  when reading a PDF and "thinking out loud" about extraction). That text was
  captured at `rawResponse += text`, streamed via `onResponseDelta`, and
  persisted to `chat_sessions.messages` — making it **self-reinforcing** across
  turns (replayed history teaches the next turn to repeat the pattern). Trace
  confirmed there is **no** `<function_calls>` XML history-serializer; the
  Claude/Gemini loops use structured content blocks. The leak is the raw text of
  one completion.
- **Table loss:** All three PDF read paths funnel through `page.extract_text()`,
  which silently drops tables — where scientific PDFs put most hard numeric data.
- **Truncation cascade:** 40K extract → 50K concat → 45K LLM injection quietly
  discarded most of a long (100k+ char) paper.
- **`read_file` PDF path:** extracted only `n_lines*200` chars then sliced to the
  first `n_lines` (≈20) lines → returned only the top of page 1.
- **No vision path:** no `type:'image'` block anywhere; image types not accepted.

## Changes

### Leak (frontend/server/galaxy-assistant.ts)
- `stripNarratedToolCalls(text)` — strips balanced `<function_calls>…</function_calls>`
  and `<invoke>…</invoke>` blocks, unclosed openers, and stray tags from complete
  text. Applied to `rawResponse` before parse/quality-enforce/return/persist, and
  to the non-streamed / single-shot emits.
- `StreamToolCallFilter` — streaming counterpart; suppresses narrated tool-call
  XML from the live token stream (handles tags split across chunks; never
  fabricates text). Wired into the first-turn streaming loop with a `flush()` at
  stream end.
- System-prompt **TOOL-USE OUTPUT RULE** (research/compute branch): use real
  tools, never write `<function_calls>`/`<invoke>` XML or extraction code as
  prose; attached file content is already in-context — read it directly.

### PDF tech-detail (frontend + backend)
- Table extraction added to both pdfplumber copies (embedded subprocess script in
  `galaxy-assistant.ts` + Galaxy endpoint `ai_assistant.py`): each page's
  `extract_tables()` is rendered as pipe-delimited `[Table N]` blocks appended to
  the page text. Verified on a real 2-page PDF (`[Table` markers now present).
- Truncation ceilings raised & made consistent: per-file extract 40K→**120K**;
  multi-paper concat 50K→**150K**; `research_agent.py` injection 45K→**150K**;
  `extract_pdf_text` default 50K→**120K**.
- `read_file` PDF path now extracts the whole document up to a generous budget
  (`min(max(n_lines*200, 20000), 120000)`) and returns all lines, not the first
  `n_lines`.

### Image vision (frontend)
- `routes.ts`: added `.png/.jpg/.jpeg/.gif/.webp` to the chat upload allowlist.
- `_buildImageContentBlocks(message, resolveFile?)` — parses image chips (new +
  legacy formats), resolves to local files, and returns Anthropic base64 `image`
  content blocks. Size-gates at 3.75MB (5MB base64 hard limit; no downscaler),
  skips tiff/bmp/svg (not vision-supported) with a note, dedups, caps at 8/turn.
  Resolver is **dependency-injected** (default = routes registry) so it's
  decoupled from the side-effect-heavy routes module and unit-testable.
- Claude user message becomes `[{type:'text'}, ...imageBlocks]` when images are
  present, with a biomedical-read instruction and an explicit **non-diagnostic /
  confirm-with-experts** caution frame. Guarded to the Claude backbone only
  (other providers use the text-only `plainMessages` path).

## Tests (all green: tsc clean, 953 passed / 6 skipped)
- `server/pdf-toolcall-leak.test.ts` (14): sanitizer + streaming filter, incl.
  fragmented streams (1/3/7/50-char chunks), bare `<` prose safety, multi-block,
  interleaved answers, and a 3-round history-cleanliness check (self-reinforcement
  loop stays clean).
- `server/image-vision-blocks.test.ts` (6): multi-file attach, size-gate,
  unsupported-type skip, non-image ignore, webp media type, dedup, legacy chip
  format, 8-image cap with overflow reported.

## Live dev E2E (the fix that mattered)

`frontend/e2e/multiround-pdf-image-vision.e2e.ts` — login (fixture) → upload PDF
(methods + IC50 table) + a generated PNG → 3 rounds (read PDF protocol →
biomedical read of the image → cross-file follow-up), asserting no tool-call
leak on every round.

- **First dev run FAILED** and was invaluable: the leak still reached the client.
  Root cause — the response streams through non-Claude model paths (Gemini/
  OpenAI/Ollama) that `return` before `generateResponse`'s sanitizer. My first
  fix only covered the Claude tool loop.
- **Real fix (commit af609192):** sanitize at `safeSend` in the `/api/chat/stream`
  handler (`routes.ts`) — the single funnel EVERY model path emits through.
  Delta text is filtered live; the `final` response is stripped. Covers all
  paths, including those that never reach the LLM-side stripper.
- **Second dev run PASSED** — R1/R2/R3 all leak-free; PDF methods/IC50 content
  preserved; image not hard-refused (vision active).

## Known limitations / next steps
- **Multi-round dataset memory is ALREADY handled — do not rebuild it.** The R3
  "please re-attach the table/gel" response was a TEST-HARNESS ARTIFACT, not a
  product gap: the E2E used a throwaway sessionId, uploaded files that were never
  associated with that session, and sent `context: {}`, so `sessionDatasets` was
  empty. In the real product the chat/stream route rehydrates
  `chat_sessions.datasets` ∪ `req.session.uploadedDatasets` into
  `context.sessionDatasets` (routes.ts ~5883), and `sessionDatasetsBlock`
  (galaxy-assistant.ts ~7808) injects the dataset list into the system prompt on
  EVERY turn — precisely the fix for "bot keeps asking to re-upload" (docs
  20260610 / 20260612 / 20260613). On a follow-up the model sees `<session_datasets>`
  and reads the PDF by id (getting the table-extracted text).
- **Image re-vision on a follow-up — NOW FIXED (view-by-id).** Previously `read_file`
  on an image id returned utf8 garbage, so the model couldn't re-SEE a stored image
  on a later turn. Now `read_file(id)` on png/jpg/jpeg/gif/webp returns the actual
  pixels as an Anthropic image content block in the tool_result (`toolResultContent`
  wraps `{__imageBlocks}` into `[{text},{image}]`). Because files are durably tracked
  by id and `sessionDatasetsBlock` surfaces the ids every turn, the model can view any
  stored image on demand, on any turn, with no re-upload and without re-sending images
  every turn. Proven live: E2E R4 gives only the id in prose (no chip) → model calls
  read_file → describes the PNG's red/green/blue bands (would be impossible on garbage).
- **E2E follow-up:** to exercise the real multi-round path, the E2E should populate
  `context.sessionDatasets` (or associate uploads with the sessionId) rather than
  sending `context: {}`. The current harness still correctly proves the leak fix,
  PDF extraction, and single-turn image vision.
- On a follow-up turn, an image analyzed in turn 1 is **not** re-sent (history is
  string-only) — the model relies on its turn-1 analysis text. Acceptable for v1.
- Non-Claude providers (Gemini) get no vision path yet (different image format).
- **Not yet synced to dev.** A live multi-round, multi-file E2E (PDF + image in
  one conversation) on `dev-public.biomate.ai` with the fixture account should
  run *after* `scripts/sync_to_dev.sh`. The pre-sync checklist (tsc + vitest) is
  green; the Galaxy `ai_assistant.py` change is import-safe (added `_fmt_table`
  using already-imported `Any`, no PEP 604 unions).

## Note during session
`galaxy-assistant.ts`, `ai_assistant.py`, and `research_agent.py` were reverted
on disk mid-session (early PDF edits lost, later leak/image edits survived); all
lost edits were re-applied and re-verified.
