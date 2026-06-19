# Implemented: deep-linkable workflows + magic-link auto-login for chat connectors

**Date:** 2026-06-18
**Spec:** `20260618_DEEPLINK_AND_MAGIC_LOGIN_FOR_CHAT_CONNECTORS.md` (repo root)
**Scope:** main BioMate app (this repo) only. No connector changes — bots already
consume `view_url` and are ready to call the new auth endpoints.

## What was built (all 3 pieces)

### 1. `view_url` + stable id in the SSE stream
- `frontend/server/routes.ts` `/api/chat/stream`: when `responseState ===
  "workflow_ready"` **and the request is authenticated**, the generated workflow
  is persisted to a new `workflow_drafts` row at **generation time** (uuid id,
  30-day expiry), and an absolute `view_url` (`<APP_URL>/workflow/<id>`) is built.
- The draft `payload` stores the **panel-shaped** workflow (`workflow_ga ?? workflow`
  with `inline_parameters` merged) — the same shape the client builds in
  `chat-interface.tsx onSuccess` — plus `response`, `suggestions`,
  `prerequisitesValidation`, `rawWorkflow`.
- `workflow_ready` event now carries `view_url` and `workflow_id` (the stable draft
  id, preferred over the often-empty catalog `ga.id`). `final` payload also gets
  top-level `view_url` + `workflow_id` (some connector flows read it there).
- Anonymous requests get no `view_url` (no owner to scope to) → connector falls back
  to the app root, exactly as before.

### 2. Public `/workflow/:id` frontend route
- `frontend/client/src/pages/WorkflowDeepLink.tsx` (new) + route wired in
  `App.tsx`. Authenticated route. Fetches `GET /api/workflow-draft/:id`
  (cookie auth, `credentials: include`), builds a synthetic single-message
  `ChatSession` whose assistant message has `metadata.type === 'workflow'`, and
  renders `ChatWithArtifacts`. The existing right-panel **auto-open** effect keys
  off that message and focuses the workflow panel — no new panel plumbing.
- Unauthenticated visitors are bounced to `/login?next=/workflow/:id`. `login.tsx`
  now honors a same-origin `next` param after a successful login.

### 3. Magic-link / one-time-token auto-login
- `POST /api/auth/login-token` (`authLimiter` + `authenticateToken`): authenticates
  with the **Bearer credential the bot already binds** (the same JWT it sends to
  `/api/chat/stream`), mints a single-use, 5-min token. Only the **SHA-256 hash** is
  stored (`login_tokens` table) so a DB read can't be replayed. Optional same-origin
  `redirect` can be baked in at mint time. Returns `{ token, expires_in: 300 }`.
- `GET /api/auth/magic?token=<ott>&redirect=<path>`: **atomically** consumes the
  token (`UPDATE … WHERE consumed_at IS NULL AND expires_at > NOW() RETURNING …`,
  genuinely single-use under concurrent clicks / link-preview crawlers), sets the
  standard `biomate_token` session cookie via the existing
  `authService.generateToken`, and 302s to the (sanitized, same-origin) redirect.
  Invalid/expired/used → 302 to `/login?error=…`.
- This is a **new entry path to the same session**, not a new session type — reuses
  the JWT/cookie machinery the app already authenticates with. No long-lived secret
  ever appears in a URL (only the bot holds the bound credential; the URL carries
  only the one-time token).

### DB
- `frontend/migrations/0017_workflow_drafts_and_login_tokens.sql` — applied at boot
  by `server/migrate.ts` (cross-env safe; `sync_to_dev.sh` doesn't need a manual
  `db:push`).

## Design decisions
- **"BioMate api_key" == the bound Bearer JWT.** There is no separate personal-
  access-token subsystem in this repo, and the bot's bound key is already the only
  Bearer the backend understands (it's what makes `/api/chat/stream` attribute the
  call to the user today). `login-token` therefore authenticates via the existing
  `authenticateToken`. A durable bind is a `rememberMe` (30-day) token. If a real
  PAT system is added later, `authenticateToken` (or a wrapper on this one route) is
  the single extension point.
- **Owner-scoped draft fetch returns 404 (not 403)** on cross-user ids — matches the
  project-routes ownership convention so existence can't be probed.

## Verification
- `npx tsc --noEmit -p .` → **0 errors**.
- `npx vitest run` → **818 passed, 4 skipped**. The only 2 failing *suites*
  (`galaxy-assistant-history-*`) fail at import because `DATABASE_URL` is unset in
  the shell (`db.ts:7` guard) — pre-existing env gating, none of the changed files
  are imported by them.

## Not yet done / next steps
- No automated e2e against the live dev stack yet (would need the deploy +
  `sync_to_dev.sh`). Manual acceptance to run on dev:
  1. Authenticated `/api/chat/stream` that yields a workflow → assert `view_url` in
     `workflow_ready` and `final`.
  2. Open `view_url` in a logged-in browser → workflow panel shows.
  3. `POST /api/auth/login-token` with a bound JWT → `magic?token=…&redirect=<path>`
     in a fresh browser → lands logged-in on the workflow; second use of the same
     token 302s to `/login?error=invalid_or_expired`.
- Connector side: wire `send_workflow_card` callers to call `login-token` then build
  the `…/api/auth/magic?token=…&redirect=<view_url path>` button URL (out of scope
  here; the spec marks it "ready to wire").

## Files touched
- `frontend/migrations/0017_workflow_drafts_and_login_tokens.sql` (new)
- `frontend/server/routes.ts` (draft persist + `view_url`; `/api/workflow-draft/:id`;
  `/api/auth/login-token`; `/api/auth/magic`; `randomBytes` import)
- `frontend/client/src/pages/WorkflowDeepLink.tsx` (new)
- `frontend/client/src/App.tsx` (import + `/workflow/:id` route)
- `frontend/client/src/pages/auth/login.tsx` (`?next=` redirect)
