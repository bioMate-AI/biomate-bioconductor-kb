-- Team workspace Phase 1 — immutable project activity ledger.
--
-- Append-only provenance trail for a shared project: who changed what and
-- when. Written by recordProjectActivity() in server/project-routes.ts AFTER a
-- primary mutation (membership add/remove, role change, ownership transfer,
-- project file add/remove, plan create) has succeeded, and read by
-- GET /api/projects/:id/activity (owner-or-member, newest-first, paginated).
--
-- Rows are immutable: no UPDATE/DELETE path exists in application code. The
-- payload carries only allowlisted, server-rendered references (target user id,
-- role, file id, plan id) — never raw file content, secrets, signed URLs,
-- prompt text, or model/worker logs (docs/20261003_TEAM_WORKSPACE_IMPLEMENTATION_PLAN.md §3).
--
-- event_type is a closed server-side set; clients never submit event_type or
-- payload. actor_user_id is nullable only for future system/automation events;
-- it is never taken from client input.
--
-- Retention: rows CASCADE-delete with the project (project_id FK), matching
-- project_members. actor_user_id ON DELETE SET NULL preserves the event when a
-- user account is removed. Idempotent — safe to re-run.

CREATE TABLE IF NOT EXISTS project_activity (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id     UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  actor_user_id  TEXT REFERENCES users(id) ON DELETE SET NULL,
  event_type     TEXT NOT NULL,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Composite index serves the newest-first project feed (the only read path).
CREATE INDEX IF NOT EXISTS project_activity_project_created_idx
  ON project_activity (project_id, created_at DESC);
-- Plain project_id index for CASCADE / existence lookups.
CREATE INDEX IF NOT EXISTS project_activity_project_idx
  ON project_activity (project_id);
