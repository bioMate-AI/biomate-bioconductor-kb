# Chat context harness — what it governs, and the CURRENT view scope (from code)

Date 2026-11-06. Written as the foundation for designing a better harness. Part 1 defines what a
"chat context harness" is and the dimensions it must govern. Part 2 maps the CURRENT state onto those
dimensions, with exact constants and `file:line` from the code (verified, not from memory). Part 3 is
what today's harness does NOT define (the levers a better harness would add).

All paths relative to `/Users/kky/biomate-review/frontend/` unless noted.

---

## Part 1 — What the harness is, and what it must DEFINE

The **chat context harness** is everything that decides, on each chat turn, (a) WHAT the model sees
(its "view scope" / universe), (b) WHAT it can reach for, and (c) HOW that is assembled, bounded, and
reported. A complete harness defines these nine dimensions:

1. **Channels (inputs).** The discrete sources that can feed the prompt on a turn (history, project
   context, attached files, memory, runs, …). Each is a named block.
2. **Assembly & structure.** The order and the wrapping (XML-ish tags like `<session_datasets>`,
   `<long_term_memory>`) in which channels are concatenated into the system/user prompt.
3. **Budgets & truncation.** Per-channel and overall size caps, and the truncation policy when a
   channel or the whole context exceeds budget (drop? head/tail clip? summarize?).
4. **Triggers / gates.** The condition under which each channel fires: every turn, first-message-only,
   on-attachment, on-run-problem, etc.
5. **Scope & authorization.** The visibility boundary of each channel — this conversation / this
   project / this user / global — and the ownership check applied.
6. **Tool reach (pull).** The tools the model can call to PULL additional context or act, vs channels
   that passively PUSH context in. This is the active half of the "universe".
7. **Freshness / caching.** Whether a channel reflects live state or a value seeded/cached once, and
   its staleness window.
8. **Failure semantics.** What the model is told when a channel's lookup fails or returns nothing
   (silent empty vs an explicit "searched, found nothing" signal).
9. **Observability / determinism / testability.** Whether the fully-assembled context for a turn can
   be inspected and asserted in a test — i.e. whether the harness is itself testable. **This is the
   dimension the "better harness" most needs**: today the assembly is spread across `routes.ts` and
   `galaxy-assistant.ts` with no single inspectable artifact.

A better harness = one object/function that takes a turn's inputs and returns the assembled context
+ a manifest of which channels fired, their sizes, their scope, and their failure state — so it can
be unit-tested and reasoned about, instead of being emergent from scattered string concatenations.

---

## Part 2 — CURRENT view scope, by channel (from code)

### A. PASSIVE channels (pushed into the prompt; the model does not ask for them)

| # | Channel | What it contains | Budget / limit | Trigger (gate) | Scope | Freshness | file:line |
|---|---|---|---|---|---|---|---|
| A1 | Conversation history | Prior messages of THIS chat | last **6** messages; **16 KB** total, **1200 chars**/msg (head75%/tail15% clip); dataset-attach msgs kept verbatim | every turn | this conversation | client-sent or rehydrated from `chat_sessions.messages` | `chat-history-selector.ts:49-51`; `galaxy-assistant.ts:9747-9750` |
| A2 | History compression summary | 2–3 sentence summary of messages dropped beyond the window | input cut to 4000 chars | when > 6 messages | this conversation | background; **NOT fed back into the same chat** | `galaxy-assistant.ts:9757-9760, 11398` |
| A3 | Project context | `Project / Description / Research goal / Background instructions` | full text, no cap | every turn in a project | this project | live DB read | `routes.ts:6887-6890` |
| A4 | Standing instructions | Promoted `project_instruction` knowledge rows | **≤8 rows, 300 chars each** | every turn in a project | this project | live (not ranked vs question) | `routes.ts:6903-6925` |
| A5 | Composer instructions | Request-scoped chat-specific instructions + enabled output requirements | server trim **24 000 chars** | every turn when set | this chat | per-request | `chat-context.ts:8,13`; `routes.ts:6928` |
| A6 | Session datasets | Attached files / chips (`<session_datasets>`), ids + preview handles | capped list | every turn when files attached | this chat (resolved to project files by exact id) | per-turn (chips cleared after send) | `galaxy-assistant.ts:9347-9398` |
| A7 | Cross-session recall | Top-5 of the user's last **20** session SUMMARIES by token-overlap, 150-char each | 5 lines | **first message only** + userId | user (last 20 sessions) | lexical only; no embeddings | `galaxy-assistant.ts:3832-3871`, gate `4563` |
| A8 | Episode memory (P1) | Last **10** project episodes, top-5 by keyword overlap | 5 lines | **first message only** | user | lexical | `galaxy-assistant.ts:3879-3925` |
| A9 | Corrections (P2) | Last **5** user corrections as routing constraints | 5 lines | **first message only** | user | — | `galaxy-assistant.ts:3936-3955` |
| A10 | Recent runs | Last ~5–6 workflow runs (name/status) | 5–6 lines | first message, or a run-problem question | user | live | `galaxy-assistant.ts:11214-11260`, gate `4553-4562` |
| A11 | Skill packs | Expert-pack instruction blocks the user switched on | per selection | every turn when selected | user-owned + shared | — | `/api/skills/block`; `skillPackIds` |

All passive memory blocks (A7–A10) are wrapped as `<long_term_memory>` (`galaxy-assistant.ts:3201`).

### B. ACTIVE reach (tools the model can call to PULL context / act)

`BIOMATE_TOOLS` (`galaxy-assistant.ts:95-383`): `run_code`, `read_file`, `query_domain_knowledge`,
`list_history`, `search_literature`, `query_database`, `search_my_data`, `list_data_sources`,
`search_workflows`, `request_new_tool`, `identify_targets`, `write_review`.

- **read_file** — reads an attached project file's first ≤500 lines (256 KB prefix) as text, only if
  it's in this turn's `sessionDatasets` with an `s3_key` (`galaxy-assistant.ts:10616-10650`).
- **run_code** — Python/R on Galaxy/session uploads; **cannot** open project files
  (`galaxy-assistant.ts:9409, 10554-10600`).
- **search_my_data** — `ILIKE` over `project_files` scoped to the **user across all projects** (not the
  active project); returns metadata, not content; ids not openable by read_file/run_code
  (`galaxy-assistant.ts:10829-10870`).
- **list_history** — lists ≤50 recent **runs** (name/status/param-key names), not datasets, not chat,
  not findings (`galaxy-assistant.ts:11161-11212`).
- `recall_memory`, `get_run`, `list_runs` exist ONLY on the connector/MCP surface, **not** in-chat
  (`routes.ts:19635, 994, 19595`).

### C. Failure semantics (current)
Every passive builder returns `''` on error or no-match (`catch { return '' }`) — the model gets **no
signal** that a lookup happened and found nothing, so it can answer from an unrelated line or from
nothing. There is no "searched, found nothing" channel.

---

## Part 3 — What the harness does NOT define today (levers for a better one)

- **No single assembly point / manifest.** Context is concatenated across `routes.ts` (A3–A6) and
  `galaxy-assistant.ts` (A1–A2, A7–A11) with no object that reports "these channels fired, these
  sizes, this scope." → **not inspectable, hard to test** (dimension 9). The better harness should
  centralize assembly and emit a per-turn manifest.
- **No cross-conversation search** (only A7, first-message, lexical, last-20 summaries).
- **No findings/param-value search** over past runs (A10/list_history are name/status only).
- **No real compute on project files** (read_file preview only; run_code can't reach them).
- **Project file list not in ambient context** — the chat is blind to the project's files until one is
  attached; and `search_my_data` is user-wide, contradicting a "project universe".
- **No semantic retrieval** anywhere in the memory path (all token-overlap / ILIKE).
- **Silent failures** (Part 2.C) instead of an explicit empty-result signal.
- **Freshness gaps** — some values seed once (composer instructions seeded from the project; the
  instructions-chip count now refetches on `biomate:projects-updated`).

### Testability target (the harness the user wants)
A function like `assembleChatContext(turnInputs) -> { prompt, manifest }` where `manifest` lists each
channel: `{ name, fired: bool, bytes, scope, truncated, failureSignalled }`. Then a harness test seeds
a conversation/project/runs and asserts the manifest (e.g. "A7 fired, scoped to user, 5 lines" or
"cross-conversation search returned an explicit empty note"). Today none of A1–A11 is assertable as a
unit because the assembly is emergent string work inside the two request handlers.

---

## Part 4 — What a harness ALSO does (beyond the 9 base dimensions)

Dimensions 1–9 (Part 1) are the view-scope mechanics. A mature harness also owns these — most are
NOT in BioMate today and are candidates, not commitments:

10. **Global-budget eviction priority.** When the sum of channels exceeds the model's real limit,
    WHICH channels shed first (e.g. keep attached files + recent history; drop old episodes). Today
    each channel self-caps; there is no cross-channel priority — the prompt can overflow unmanaged.
11. **Relevance ranking within a channel.** Which items of a channel to include, by relevance to the
    question — not just recency/token-overlap. Today A7–A10 are lexical/recency only.
12. **Cross-channel dedup.** The same fact must not appear in two channels (we already hit this:
    research_goal was injected as both project context and composer instructions — fixed `502b83e6`).
13. **Provenance / attribution.** Tag each context item with its source so the model can attribute
    claims and the UI/audit can cite them. Today context is anonymous text.
14. **Token-accurate accounting.** Budget by real model tokens, not bytes (current budgets are byte/
    char approximations).
15. **Multi-turn entity persistence.** Carry resolved entities (an attached file, a chosen run) across
    turns so "now filter that file" works. Today chips clear after send (`chat-input.tsx:389`).
16. **Tool-result folding.** How a tool's output (read_file, a search) re-enters context on the next
    step of the agentic loop, under budget — the loop's own context management, not just turn 1.
17. **Instruction precedence / conflict resolution.** When composer instructions, project standing
    rules, and a stored correction conflict, which wins and in what order they're stated.
18. **Redaction / safety / instruction-source boundary.** Strip secrets/PII before text enters the
    prompt, and mark retrieved content as DATA (not instructions) so a file/search result can't
    hijack the agent.
19. **Determinism / replay.** Same inputs → same assembled context, so turns can be replayed for eval.

## Part 5 — Prioritized plan (build order; not all now)

**P0 — Foundation — ✅ DONE + live-verified.** The inspectable manifest core
(`server/chat-context-harness.ts` + 10 tests) AND the SHADOW wiring (`galaxy-assistant.ts`, logs one
`manifestSummary` line per turn at the provider-independent assembly point). Live on dev: a projectless
first-message turn logged `[ctx] cross_session(user,1.2KB) total=1.2KB msgs=0 firstMsg=true` — the
manifest is observable on real traffic, zero behavior change. Known P0 imprecision: blocks are merged
at the shadow point (the LTM aggregate A7–A10 is logged under `cross_session`); per-channel attribution
arrives when the live assembly is migrated onto the builder. (dimensions 1,2,3,9)

**P1 — Highest user value (anchored on the three worries + trust).**
- **P1a. `run_code`/`read_file` reach into project-file OUTPUTS.** Unlocks "analyze/summarize my run
  output file" — the single biggest functional gap (run outputs live in project files; today only a
  ≤500-line preview). (tool reach, dimension 6)
- **P1b. Honest failure signalling.** Replace the silent `''` on a memory/search miss with an explicit
  "searched, found nothing" channel (the harness's `failureSignalled`). Cheap, high trust — stops the
  model answering from nothing. (dimension 8)

**P2 — Cross-history search tool — ✅ DONE (PR #338).** `search_chat_history` tool over
`chat_sessions.messages`, scoped to the authenticated user, EXCLUDING the current session, AND-matched
case-insensitive `ILIKE`, `ORDER BY last_activity DESC` (indexed), `LIMIT 8`, returning `{session_id,
title, status, last_activity, snippet}` per hit. An empty result is returned honestly ("nothing found
— do not invent a recollection"). Pure `extractChatSnippet()` helper is unit-tested (6 tests). The
`biomate-universe` skill's "you cannot search past conversations" boundary was flipped to describe the
new scoped keyword search and its real limits (own chats only, literal word match, no semantic recall).
Findings-text search was NOT added (findings live per-run in `_findingsCache`/outputs, not a single
searchable column) — `list_history` + `search_my_data` already cover run lookup. (channels + tool reach)

**P3 — Chat → report edit — NOT backend-only; needs the client (deferred).** The store side is
already done: `reportVersionStore.append` (v0-fork protection) + `POST /api/runs/:anyId/report/versions`
+ the report-editor save flow. The blocker for a chat `edit_report(runId, instruction)` tool is that
**the authoritative "current report" is composed client-side** (`buildFullReportMarkdown` in the
after-run Results view) and POSTed as `currentMarkdown` on save — the server cannot reconstruct exactly
what the user is looking at (`GET …/findings/report` only renders from the disk file or
`_findingsCache`, an approximation; routes.ts:13887 confirms v0 is seeded "from the report markdown the
client currently shows"). So a correct P3 requires the CLIENT to (a) pass the current composed markdown
into the chat turn, (b) host the propose-diff / accept UI, and (c) call the existing append route on
accept. A server-only `edit_report` that edits a server-reconstructed approximation would silently
diverge from the real report — a workaround we do not ship. P3 stays deferred until it can be built
AND verified through the UI. The `biomate-universe` skill's "you cannot edit a saved report through
chat" boundary therefore remains accurate and is left unchanged.

**P4 — Defer until P0 data says they're worth it.** Semantic retrieval (11), global-budget eviction
(10), multi-turn entity persistence (15), provenance (13), token-accurate budgeting (14).

**Recommendation:** P0 now (it's mostly done), then P1a + P1b together (they're the highest
value-to-effort and directly address the "refer to a file / act" and trust gaps). Decide P2/P3 after
the P0 shadow shows how the real context actually looks on live turns.
