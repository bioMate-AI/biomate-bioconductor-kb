# Team workspace Phase 1 — immutable project activity ledger

**Date:** 2026-10-03
**Thread:** B (per `docs/20261003_PARALLEL_WORKSTREAM_PLAN.md`)
**Spec:** `docs/20261003_TEAM_WORKSPACE_IMPLEMENTATION_PLAN.md` §Phase 1
**Status:** implemented + locally verified (tsc + vitest). NOT deployed (no `sync_to_dev.sh`, no compute — per workstream guardrails).

## What shipped

An append-only provenance trail for shared projects: who changed what, when. It is the foundation the plan requires before invitations, shared chat, or notifications add more collaboration state. No raw file content, secrets, signed URLs, prompt text, or model/worker logs ever enter the ledger.

### 1. Migration — `frontend/migrations/0022_project_activity.sql`

Next unused number (existing max was `0021`). Idempotent (`CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`), matching the style of the surrounding migrations.

```
project_activity(
  id             UUID PK default gen_random_uuid(),
  project_id     UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  actor_user_id  TEXT REFERENCES users(id) ON DELETE SET NULL,
  event_type     TEXT NOT NULL,
  payload        JSONB NOT NULL default '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL default NOW()
)
```

Indexes:
- `project_activity_project_created_idx (project_id, created_at DESC)` — serves the newest-first feed (the only read path).
- `project_activity_project_idx (project_id)` — existence/CASCADE lookups.

**Type decisions (grounded in the existing schema, not guessed):**
- `actor_user_id` is `TEXT` referencing `users(id)` — matches `project_members.user_id` (TEXT → `users.id`). `project_id` is `UUID` referencing `projects(id)`, matching `project_members`.
- `actor_user_id` is nullable only for future system/automation events and `ON DELETE SET NULL` so an event survives a user-account deletion; it is never taken from client input.

**Retention decision (plan §Phase 1 task 1 asks this explicitly):** rows `ON DELETE CASCADE` with the project, matching `project_members`. When a project is hard-deleted its ledger goes with it. (If legal/audit retention beyond project lifetime is later required, that is a separate change — flagged, not assumed.)

A lazy `ensureProjectActivityTable()` mirrors the existing `project_members`/`project_files`/`project_plans` bootstrap in `project-routes.ts` so the table exists on dev/local even before the migration runner is invoked.

### 2. Helper — `recordProjectActivity(projectId, actorUserId, eventType, payload)`

Exported from `frontend/server/project-routes.ts`. `event_type` is a closed server-side union (`ProjectActivityEvent`): `member_added | member_removed | role_changed | ownership_transferred | file_added | file_removed | plan_created`. Clients never submit `event_type` or `payload`.

**Failure policy (plan §Phase 1 authorization/failure rules):** the helper is called only AFTER the primary mutation has succeeded, and it is **best-effort** — a ledger insert failure is logged, never thrown, so it can never convert a successful membership/file/plan mutation into an unknown state. Phase 1 accepts at-most-once ledger semantics after commit; an outbox/transactional upgrade is a documented follow-up (see below).

### 3. Mutation points wired (all in `project-routes.ts`, which this thread owns)

| Endpoint | Event | Payload (allowlisted) |
|---|---|---|
| `POST /:id/members` | `member_added` | `{ targetUserId, role }` |
| `DELETE /:id/members/:memberId` | `member_removed` | `{ targetUserId }` |
| `DELETE /:id/members/me` (leave) | `member_removed` | `{ targetUserId, self: true }` |
| `PATCH /:id/members/:memberId` | `role_changed` | `{ targetUserId, role }` |
| `PATCH /:id/owner` | `ownership_transferred` | `{ newOwnerId, previousOwnerId }` |
| `POST /:id/files/upload` | `file_added` | `{ fileId, name, source: 'upload' }` |
| `DELETE /:id/files/:fileId` | `file_removed` | `{ fileId }` |
| `POST /:id/plans` | `plan_created` | `{ planId }` |

### 4. Read endpoint — `GET /api/projects/:id/activity`

Owner-or-member only, reusing the existing `_isOwnerOrMember` helper and the **404-not-403** no-disclosure pattern (an outsider cannot even enumerate the feed). Newest-first (`ORDER BY created_at DESC, id DESC`), paginated with `limit` (default 50, capped 100) + `offset`, over-fetching one row to return `hasMore` without a `COUNT`. Left-joins `users` to attach `actor_email`/`actorName` for display.

### 5. Test — `frontend/server/project-activity.test.ts`

Behavioural (not source-grep), modelled on `notes-routes.test.ts`: mounts the real `registerProjectRoutes` on an express app over loopback HTTP, with `./db` faked by a small SQL-dispatching in-memory pool that actually persists `project_activity` rows — so "recorded on mutation → visible in the feed" is a genuine round-trip. 7 tests cover:
- event recorded on a membership add (+ attribution + payload allowlist assertion: no token/password/secret/s3_key/URL);
- event recorded on a role change;
- non-member → 404 (never 403, feed not enumerable);
- unauthenticated → 401;
- owner reads events newest-first after two mutations;
- a non-owner member can also read the feed;
- `limit`/`hasMore` pagination.

## Verification

- `cd frontend && npx tsc --noEmit -p .` → exit 0.
- `npx vitest run` on the new suite + existing project/team suites (`project-routes`, `project-framework-wiring`, `project-file-references`, `chat-sessions-project-scoping`, `notes-routes`) → **59 passed**.
- Updated the one coupled assertion in `project-routes.test.ts` (`authed.length` 25 → 26) for the added endpoint; that contract test still passes.
- No `sync_to_dev.sh`, no compute dispatched. Files committed individually (no `git add -A`).

## Follow-ups (noted, not done — out of this thread's scope)

- **Run launch/terminal events** (`run_requested`/`run_started`/`run_completed`/`run_failed`): the run-lifecycle code path is NOT in `project-routes.ts` (it lives in `nextflow_executor.py` / `routes.ts`). Per the task instruction, recorded here as a follow-up rather than reaching outside the owned file.
- **Share-link create/revoke events**: in-file and cheap, but outside the task's explicit mutation-point list; easy next addition.
- **Transactional/outbox ledger write** for exactly-once semantics under the "primary mutation + event in one transaction" guarantee the plan mentions for a future hardening pass.
- **Activity UI panel** (plan §Phase 1 task 5) — frontend, owned by the UX thread, not this one.
