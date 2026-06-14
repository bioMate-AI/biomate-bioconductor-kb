-- Migration 0016: Bridge chat-stream sessionId (text) ↔ LTM sessions.id (uuid).
--
-- Context: 2026-06-13 audit found that memory-integration's
-- recordEpisode / project_episodes write path silently fails because
-- chat-stream sends a text sessionId (e.g. "memw-1781314…") and
-- project_episodes.session_id is uuid (FK to sessions.id). The
-- recordEpisode call wraps in try/catch and just logs, so writes were
-- being dropped without any visible error.
--
-- Fix: add a chat_session_id text column to LTM sessions, UNIQUE so we
-- can find-or-create by it. MemoryService.ensureChatLtmSession will
-- look up the LTM session by chat_session_id and return its UUID for
-- chat-stream to pass through as memorySessionId.
--
-- Idempotent (IF NOT EXISTS).

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS chat_session_id text;

CREATE UNIQUE INDEX IF NOT EXISTS sessions_chat_session_id_idx
  ON sessions (chat_session_id);
