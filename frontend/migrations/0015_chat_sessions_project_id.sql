-- Migration 0015: Add project_id to chat_sessions for project-scoped
-- cross-session context recovery.
--
-- Context: 2026-06-12 audit (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md)
-- established the policy that datasets and context flow across sessions
-- ONLY within the same project, never across projects.
--
-- The chat-stream endpoint now resolves a projectId via
-- MemoryService.ensureDefaultProject on every request (commit
-- enabling Q4, 2026-06-12). This column persists that linkage on the
-- chat_sessions row so cold-refresh recovery queries can scope by
-- project. Without it, every session is a project orphan and the
-- recovery query can't trust the dataset list it surfaces.
--
-- Nullable + ON DELETE SET NULL: existing rows pre-dating Q4 stay
-- valid; if a project is later deleted, chat_sessions are kept but
-- detached. The FK targets the LTM `projects.id` (uuid), introduced
-- in 0012_ltm_schema.sql.

ALTER TABLE chat_sessions
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS chat_sessions_project_id_idx ON chat_sessions (project_id);

-- Compound index for the cold-refresh recovery query path
-- (project_id, last_activity DESC) — the planned query reads
-- "datasets from other sessions in the same project, most recent first".
CREATE INDEX IF NOT EXISTS chat_sessions_project_last_activity_idx
  ON chat_sessions (project_id, last_activity DESC);
