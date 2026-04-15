-- Feature flags table: runtime-togglable feature gates
-- Replaces scattered ENABLE_X environment variable checks.
-- Backwards-compatible: seedDefaultFlags() reads env vars for initial values.

CREATE TABLE IF NOT EXISTS feature_flags (
  flag_name   VARCHAR(128) PRIMARY KEY,
  enabled     BOOLEAN      NOT NULL DEFAULT FALSE,
  rollout_pct INTEGER      NOT NULL DEFAULT 100,
  user_overrides TEXT      DEFAULT '{}',
  description TEXT,
  updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Seed known flags (idempotent via ON CONFLICT DO NOTHING)
INSERT INTO feature_flags (flag_name, enabled, rollout_pct, description) VALUES
  ('ux_feedback',     TRUE,  100, 'UX feedback collection panel (thumbs up/down + free-text)'),
  ('thinking_mode',   FALSE, 100, 'Enable extended thinking (claude-3-7-sonnet thinking budget)'),
  ('nextflow_aws',    FALSE, 100, 'Run Nextflow workflows on AWS Batch instead of local Docker'),
  ('ltm_injection',   TRUE,  100, 'Inject long-term memory into LLM system prompt'),
  ('mcp_server',      TRUE,  100, 'BioMate MCP server enabled for Claude Code CLI integration'),
  ('domain_guidance', TRUE,  100, 'S3 domain specialist guidance in generateResponse()'),
  ('step_control',    TRUE,  100, 'Step-level Run/Resume buttons in workflow viewer (GC-8)')
ON CONFLICT (flag_name) DO NOTHING;
