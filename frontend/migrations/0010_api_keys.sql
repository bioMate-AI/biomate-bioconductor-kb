-- Per-user API keys for headless / connector access (biomate-connector).
--
-- A user generates a key in Settings → API Keys. The plaintext key
-- (prefix `bm_live_`) is shown ONCE at creation and never stored — only its
-- SHA-256 hash is persisted, so a DB leak cannot reveal usable keys.
--
-- Connector requests send `Authorization: Bearer bm_live_…` (or `X-API-Key`).
-- The auth middleware hashes the presented key, looks it up here, and resolves
-- the owning user — so connector traffic runs as that user (their own runs,
-- quota, and history), unlike the single shared service account.

CREATE TABLE IF NOT EXISTS api_keys (
  id            VARCHAR       PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id       VARCHAR       NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- SHA-256 hex of the full plaintext key. Unique so a presented key maps to
  -- at most one row.
  key_hash      TEXT          NOT NULL UNIQUE,

  -- Display-only fingerprint: `bm_live_` + first 4 + last 4 of the random body.
  -- Lets the UI show "bm_live_ab…wxyz" without ever storing the secret.
  key_prefix    TEXT          NOT NULL,

  -- User-supplied label, e.g. "Feishu bot", "Slack prod".
  name          TEXT,

  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  last_used_at  TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ                          -- NULL = active
);

-- Hot path: middleware looks up by key_hash on every connector request.
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_keys_key_hash ON api_keys (key_hash);

-- Settings UI lists a user's keys.
CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON api_keys (user_id);
