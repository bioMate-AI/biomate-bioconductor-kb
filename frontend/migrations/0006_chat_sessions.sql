-- Chat session persistence for cross-machine sync
-- Stores sidebar history + full message content per user account

CREATE TABLE IF NOT EXISTS chat_sessions (
  session_id  TEXT        PRIMARY KEY,
  user_id     TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL DEFAULT 'New Chat',
  status      TEXT        NOT NULL DEFAULT 'active',
  messages    JSONB       NOT NULL DEFAULT '[]',
  workflows   JSONB       NOT NULL DEFAULT '[]',
  datasets    JSONB       NOT NULL DEFAULT '[]',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS chat_sessions_user_id_idx ON chat_sessions (user_id);
CREATE INDEX IF NOT EXISTS chat_sessions_last_activity_idx ON chat_sessions (user_id, last_activity DESC);
