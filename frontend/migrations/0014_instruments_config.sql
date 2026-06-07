-- Migration 0014: instrument configurations table
-- Stores user-registered lab instruments (network devices + cloud services).
-- Companion to instrument_events (0005): events are inbound from daemons;
-- this table holds the user-configured connection registry.

CREATE TABLE IF NOT EXISTS instruments (
  id             VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        TEXT NOT NULL,

  -- Identity
  name           TEXT NOT NULL,
  type           TEXT NOT NULL,         -- see INSTRUMENT_TYPES in schema.ts

  -- Network connection
  host           TEXT,
  port           INTEGER,

  -- Auth
  api_key        TEXT,
  oauth_token    TEXT,
  oauth_refresh_token TEXT,

  -- Type-specific config (JSON)
  config         TEXT,

  -- Health status
  status         TEXT NOT NULL DEFAULT 'unknown',
  last_seen_at   TIMESTAMP,
  last_error     TEXT,

  created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_instruments_user_id ON instruments(user_id);
CREATE INDEX IF NOT EXISTS idx_instruments_type    ON instruments(type);
