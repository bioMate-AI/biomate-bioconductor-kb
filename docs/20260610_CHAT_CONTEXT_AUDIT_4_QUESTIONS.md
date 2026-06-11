# Chat-context audit — four user-raised questions (2026-06-10)

Triggered by review of the wjunlin@HKU fix-set
(`docs/20260610_REAL_USER_FULL_CHAT_LOGS.md`). The user raised four
sharp questions that the previous patch did not address. This document
captures the actual state of the code and the proposed correction.

---

## 1. Is the context compression code working? Will it strip datasets / outside context?

**Status: PARTIALLY WORKING — manual, lossy on dataset IDs, bypassed by chat-stream.**

### What exists
- `frontend/server/context-compressor.ts` (344 LOC) — `ContextCompressor`
  class that uses Claude to summarize older messages and keep the
  most recent N.
- HTTP endpoint: `POST /api/compress-session` (`routes.ts:5523`).
- Client trigger: `CompressionDialog` (`chat-interface.tsx:599-607`)
  shown at **70%** of 200K tokens (warning) and **80%** (critical).

### What it does NOT do
- **Not automatic.** Compression only runs when the user clicks
  "Compress" in the dialog. Many users dismiss / ignore the dialog
  and keep sending — uncapped — into `/api/chat/stream`.
- **Lossy on dataset identity.** The summarizer is an LLM. Given
  `[Galaxy dataset: clinical_gse22055.csv (id: 5cf7a795-565d-487e-bdb6-47a9859ff02d)]`,
  it will paraphrase to "user attached clinical metadata file" and
  **drop the UUID**. Downstream tools (`run_code`, workflow
  parameters that consume `$DATA_DIR/<id>/<file>`) lose the handle.
- **Not in the chat-stream path.** The wjunlin/Archia fix I shipped
  bloats `context.previousMessages` server-side; the compressor
  doesn't intercept that payload. Compression and chat-stream are
  disjoint paths today.
- **Compressed state is client-only.** Nothing writes the summary
  back to `chat_sessions.messages`, so a refresh re-loads the
  un-compressed jsonb and triggers the 70% dialog again.

### Fix needed
1. **Compression must preserve dataset blocks verbatim.** Pre-process:
   extract every `[Galaxy dataset: …]` / `[Uploaded datasets: …]` /
   `[Attached files: …]` line, summarize the rest, then re-attach the
   verbatim blocks at the top of the summary. Lock this in a test
   against the actual UUID round-trip.
2. **Persist the summary back to `chat_sessions.messages`** under a
   `{role:"system", isSummary:true}` marker so refresh doesn't undo it.
3. **Server-side token cap on the chat-stream history payload**
   regardless of compression state (see Q3).

---

## 2. Should we suggest starting a new chat when the context is too long?

**Recommendation: YES, but as a second option next to compression.**

- The current `CompressionDialog` only offers "Compress." At very
  high token usage, compression has diminishing returns (the
  summary itself eats tokens; the conversation has accumulated so
  much state the user is probably better off starting fresh).
- Add a "Start a new chat" CTA in the dialog at ≥85%, alongside
  Compress. New-chat would: (a) create a fresh `chat_sessions` row,
  (b) carry over only the user's **attached datasets** and any
  project memory, (c) leave the old session intact for reference.
- Wording matters: "Your conversation has grown large. Start a new
  chat to keep things responsive — your attached datasets will
  carry over."

---

## 3. The previous fix risks blowing up context (user's third concern — VALID)

**Status: confirmed real problem with my prior commit.**

### Risk model
The shipped fix bumped the client from `slice(-4)` to:
- `slice(-20)` of recent messages, AND
- every earlier message containing a dataset-attachment block

The server then backfills up to 40 messages from `chat_sessions`
when the client payload is empty.

For a wjunlin-style session (25 messages, average BioMate
assistant reply ~5–15 KB of markdown):

| Configuration | Approx history tokens |
|---|---|
| Previous (slice -4) | ≤ 6K |
| **My prior fix (slice -20 + attachments)** | **~25-50K** |
| Server backfill (up to 40 msgs) | ~50-100K |
| Claude's 200K window | (need room for system prompt + tools + new reply) |

A single chat-stream call could now eat **50%** of the context
window on history alone. That's exactly the bloat the user flagged.

### Replacement strategy (token-budget aware)
1. **Hard byte cap** on the assembled `previousMessages` payload
   (~16 KB of text — roughly 4K tokens). Two-pass selection:
   a. **Always keep, verbatim:** every message containing a
      dataset-attachment block (these are load-bearing pointers).
   b. **Recency window:** as many of the most recent N messages as
      fit under the cap.
   c. **Heavy truncation of long assistant messages:** prefer keeping
      the first ~600 chars of each old assistant reply (where intent
      lives) + "[…truncated for context budget…]" — assistant
      messages are the bloat.
2. **Server enforces the same cap** after backfill, so a malicious
   or stale client payload can't bypass it.
3. **Unit-test the cap** with the wjunlin transcript — assert
   payload stays under 16 KB and dataset UUIDs survive.

---

## 4. Is the project framework working? (User says it's commented out.)

**Status: WIRED IN MEMORY, NOT EXPOSED VIA CHAT UI.**

### Backend status (alive)
- `frontend/server/memory-integration.ts` — `context.projectId`,
  `projectMemory`, `loadProjectContext`, `findMatchingProcedures`,
  `getSimilarEpisodes` — all gate on `context.projectId`.
- `memory-repository.ts` has `ProjectMemoryRepository` /
  `loadProjectContext` etc.

### Client status (effectively disabled for chat)
- The chat-stream call body in `chat-interface.tsx:679-691` does
  **not** send `projectId`. So memory-integration's `projectId`
  branches never execute — project memory is dark, project
  procedures don't match, project episodes don't retrieve.
- The only place where projects show up in the UI is
  `chat-message.tsx:406` — IND-report "Roll into IND project"
  card. That's a narrow IND flow, not general-purpose project
  scoping.

### Why this matters (user is right that this is important)
- A real user like wjunlin@HKU is doing **one** scientific
  project: GSE22055 colorectal cancer DEG. Without a project
  boundary, every `/api/chat/stream` call rebuilds context from
  arbitrary chat-session memory.
- Project scoping would give us:
  - **Natural context boundary** — only this project's datasets,
    procedures, episodes get loaded.
  - **Cleaner team workflow** — multiple users can join a project
    (e.g. PI + postdoc); chat + run history scoped to it.
  - **Per-project compression** — summary covers project-scoped
    work, not random earlier chats.
  - **Better billing/quota story** — costs roll up by project,
    matches how PIs think about budgets.

### Proposed re-enablement (separate, scoped work)
1. Add a project selector / "active project" context to the
   client; pass `projectId` in chat-stream body.
2. Auto-create a default project per user on first chat (so users
   don't have to think about it on day 1).
3. When user attaches a dataset, register it against the active
   project (`projects.datasets` table or jsonb on `projects`).
4. Memory-integration is already wired — no backend work needed
   to start consuming `projectId`.

This is bigger than the current fix-set — propose tracking it as a
separate PR.

---

## Action plan from this audit

| # | Action | Status |
|---|---|---|
| Q3 | Replace the naive client/server expansion with a token-budget-aware selector (≤16 KB cap, dataset blocks always retained verbatim, assistant messages truncated) | **doing now** |
| Q1 | Lock in dataset-block preservation across compression (test against UUID round-trip) | follow-up |
| Q1 | Persist compression summary back to `chat_sessions.messages` | follow-up |
| Q2 | Add "Start a new chat" CTA to `CompressionDialog` at ≥85% | follow-up |
| Q4 | Re-enable project framework: client-side selector + `projectId` plumbing | separate PR |
