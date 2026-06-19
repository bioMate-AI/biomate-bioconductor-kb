-- Deep-linkable workflow drafts + one-time magic-login tokens.
-- Backs the IM/chat-connector "Open in BioMate" deep link:
--   1. workflow_drafts — a generated workflow persisted at generation time
--      (not only at execution) so it has a stable, URL-addressable id. The
--      /workflow/:id frontend route loads it via GET /api/workflow-draft/:id.
--   2. login_tokens — short-lived, single-use tokens minted from a bound
--      BioMate credential (POST /api/auth/login-token) and consumed by
--      GET /api/auth/magic to establish a session without putting any
--      long-lived secret in the URL.
-- See docs/20260618_DEEPLINK_AND_MAGIC_LOGIN_FOR_CHAT_CONNECTORS.md.

CREATE TABLE IF NOT EXISTS workflow_drafts (
  id            TEXT        PRIMARY KEY,
  user_id       TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  workflow_name TEXT,
  payload       JSONB       NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS workflow_drafts_user_idx ON workflow_drafts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS workflow_drafts_expiry_idx ON workflow_drafts (expires_at);

CREATE TABLE IF NOT EXISTS login_tokens (
  -- Only the SHA-256 hash of the one-time token is stored, so a DB read
  -- can't be replayed to mint a session.
  token_hash  TEXT        PRIMARY KEY,
  user_id     TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  redirect    TEXT,
  expires_at  TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS login_tokens_expiry_idx ON login_tokens (expires_at);
