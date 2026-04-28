-- Audit log table for regulatory compliance and auditability
-- Supports SOC 2, HIPAA §164.312, and FDA 21 CFR Part 11 requirements

CREATE TABLE IF NOT EXISTS audit_logs (
  id              VARCHAR       PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Who
  user_id         TEXT,                          -- NULL for unauthenticated actions
  session_id      TEXT,

  -- What
  action          TEXT          NOT NULL,        -- e.g. "workflow.execute", "auth.login"
  resource_type   TEXT,                          -- e.g. "workflow", "dataset", "project"
  resource_id     TEXT,

  -- Details
  details         TEXT,                          -- JSON-stringified additional context
  reasoning       TEXT,                          -- AI decision reasoning (workflow generation)

  -- When
  timestamp       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- Context
  ip_address      TEXT,
  user_agent      TEXT,

  -- Result
  status          TEXT          DEFAULT 'success', -- 'success' | 'failure' | 'error'
  error_message   TEXT,

  -- Duration tracking
  duration_ms     TEXT
);

-- Fast lookup by user for compliance exports
CREATE INDEX IF NOT EXISTS audit_logs_user_id_idx       ON audit_logs (user_id);

-- Time-range queries (HIPAA requires ordered access to audit trails)
CREATE INDEX IF NOT EXISTS audit_logs_timestamp_idx     ON audit_logs (timestamp DESC);

-- Action-type filtering (e.g. "give me all auth.login events")
CREATE INDEX IF NOT EXISTS audit_logs_action_idx        ON audit_logs (action);

-- Resource-level tracing
CREATE INDEX IF NOT EXISTS audit_logs_resource_idx      ON audit_logs (resource_type, resource_id);
