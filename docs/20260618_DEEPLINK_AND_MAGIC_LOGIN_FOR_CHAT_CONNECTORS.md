# Backend work: deep-linkable workflows + URL auto-login for chat connectors

**Date:** 2026-06-18
**Owner:** backend
**Driver:** IM/chat connectors (Telegram, Feishu/Lark, WeChat, Slack) in the
`biomate-connector` repo route natural language through `/api/chat/stream` and
reply with a card + an "Open in BioMate" button. Today that button cannot deep-link
to the generated workflow, and clicking it never lands the user logged-in.

This doc lists exactly what the **main BioMate app** (this repo) must add. The
connectors already consume these the moment they exist — no connector rework
needed beyond filling a URL.

---

## Problem (verified in code, 2026-06-18)

A chat-driven session generates a workflow, but:

1. **No `view_url` in the SSE stream.** `/api/chat/stream` (`frontend/server/routes.ts:5048`)
   emits `workflow_ready` with fields `workflow_name, workflow_id, workflow_type,
   nextflow_path, source, confidence, chain_name, chain_steps`
   (`routes.ts:5612-5626`) and `final` with `response/state/workflow/metadata/…`
   (`routes.ts:5530-5571`). **Neither carries a URL** to view the workflow.

2. **Generated workflows are not URL-addressable.** A generated workflow lives only
   in the client's in-memory chat/panel state. A stable id (`ExecutionRun.id`) is
   created only on execution (`routes.ts:8427-8438`), and even then the frontend has
   **no public page** for it — only the internal `/debug/outputs/:runId` and
   `/debug/viewer/:runId` test routes (`frontend/client/src/App.tsx`).
   The Wouter router has **no** `/chat`, `/workflow/:id`, or similar route; the main
   chat UI is the root route `/` (`App.tsx:332-475`).
   → This is why a connector button pointing at `…/chat` 404s.

3. **No URL auto-login.** There is no magic-link / one-time-token / "exchange API key
   for a session" mechanism. Only email-verification and password-reset tokens exist
   (`?token=`, body-posted, do NOT create a session); JWTs are issued only after
   email+password login (`backend auth.py:130-139`, `auth-service.ts:778-795`).
   An IM user clicking a link opens a fresh browser with no session → login page.

Net: even a correct URL can't show "their" workflow already-logged-in.

---

## What to build (3 pieces)

### 1. Emit `view_url` (and a stable workflow id) in the SSE stream
- When a runnable workflow is generated, persist it (or its draft) with a stable id
  **at generation time**, not only at execution.
- Add `view_url` (absolute, app-origin) and `workflow_id` to the `workflow_ready`
  and `final` events in `routes.ts` (~5612 / ~5530).
- `view_url` should point at piece #2's route.

**Connector side (already done):** `_open_claw_query()` in
`connectors/{telegram,feishu}/*_bot.py` already reads `view_url` from `workflow_ready`
then `final`, and uses it for the button; it falls back to the app root only when
`view_url` is absent. Ship `view_url` → buttons deep-link automatically.

### 2. A public frontend route that loads a workflow by id
- Add a Wouter route, e.g. `/workflow/:id` (or `/w/:id`), that loads the generated
  workflow draft/panel by the id from #1 and renders the existing
  `ChatWithArtifacts` / workflow panel focused on it.
- Authenticated route; if unauthenticated, redirect through #3 then back here.

### 3. Magic-link / token → session auto-login (the secure way)
**Do NOT put the long-lived API key in the URL** (it leaks via history, server logs,
`Referer`, and IM link-preview crawlers). Use a short-lived one-time token:

- **New endpoint** `POST /api/auth/login-token` (auth: Bearer of a BioMate API key):
  given a valid api_key (the kind an IM bot stores via `bind <api_key>`), return a
  single-use, ~5-min-expiry login token bound to that user.
- **New endpoint/route** `GET /api/auth/magic?token=<one-time>&redirect=<path>`:
  validate+consume the token, establish the session (set the JWT cookie the app
  already uses), then 302 to `redirect` (e.g. `/workflow/<id>`). Invalidate the token
  immediately after use.
- Reuse the existing JWT/session machinery (`auth-middleware.ts:17-79`,
  `oauth-service.ts` token issuance) — this is a new *entry path* to the same session,
  not a new session type.

**Connector side (ready to wire):** bots already store each IM user's api_key via
`bind`. Once #3 exists, the bot will: call `/api/auth/login-token` with the bound key
→ build `…/api/auth/magic?token=<ott>&redirect=<view_url path>` → put that on the
button. (Small, isolated change in `send_workflow_card` callers.)

---

## Acceptance
- `/api/chat/stream` `workflow_ready`/`final` include a working `view_url` + stable id.
- Opening `view_url` in a logged-in browser shows that workflow.
- Opening a bot-built magic link in a fresh browser logs the user in and lands on the
  workflow; the token is single-use and expires.
- No long-lived secret ever appears in a URL.

## Out of scope
- Connector code changes beyond filling the button URL (already structured for this).
- Changing the agentic `/api/chat/stream` contract otherwise.

## References (this repo, read 2026-06-18)
- `frontend/server/routes.ts:5048` — `/api/chat/stream` handler
- `frontend/server/routes.ts:5612-5626` — `workflow_ready` event fields (no view_url)
- `frontend/server/routes.ts:5530-5571` — `final` event fields
- `frontend/server/routes.ts:8427-8438` — ExecutionRun id created on execute
- `frontend/client/src/App.tsx:332-475` — Wouter routes (root `/` is the chat; no `/workflow/:id`)
- `frontend/server/auth-middleware.ts:17-79` — Bearer/JWT auth
- `backend auth.py:130-139`, `frontend/server/auth-service.ts:778-795` — JWT issuance (login-only today)
