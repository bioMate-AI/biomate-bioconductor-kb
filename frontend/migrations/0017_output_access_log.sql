-- Output Access Log
--
-- Records every output-file access through BioMate's /api/runs/:id/output/:filename
-- endpoint. Required for compliance + chain-of-custody on the Download Report.
-- Per docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (B.2).
--
-- Does NOT log direct S3 access — that path is being revoked atomically with
-- this migration (B.4 bucket policy change deploys alongside).

CREATE TABLE IF NOT EXISTS output_access_log (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL,
  filename TEXT NOT NULL,
  user_id TEXT NOT NULL,
  user_email TEXT,
  project_id TEXT,                      -- nullable for runs not in a project
  ip_address INET,
  user_agent TEXT,
  http_status INTEGER,                  -- 200 / 302 (presigned redirect) / 403 / 404
  file_size_bytes BIGINT,
  accessed_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_output_access_log_run
  ON output_access_log(run_id, accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_output_access_log_user
  ON output_access_log(user_id, accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_output_access_log_project
  ON output_access_log(project_id, accessed_at DESC)
  WHERE project_id IS NOT NULL;
