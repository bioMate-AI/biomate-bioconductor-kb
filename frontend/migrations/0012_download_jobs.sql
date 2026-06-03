-- Async Job Queue subsystem (Phase 0).
--
-- See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §6 for the full data model.
-- Single source of truth for long-running artifact-producing jobs:
-- download_all_zip, methods_report, reproducibility_bundle, findings_analysis,
-- and future kinds (docx_export, etc.).

CREATE TABLE IF NOT EXISTS download_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         TEXT NOT NULL,
  kind            TEXT NOT NULL,
  payload         JSONB NOT NULL,
  dedup_key       TEXT NOT NULL,
  state           TEXT NOT NULL,
  progress        INT  NOT NULL DEFAULT 0,
  eta_seconds     INT,
  artifact_uri    TEXT,
  artifact_bytes  BIGINT,
  error           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at      TIMESTAMPTZ,
  ready_at        TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  cancelled_at    TIMESTAMPTZ
);

-- Dedup lookup: coalesce repeat clicks while a matching job is still useful.
CREATE INDEX IF NOT EXISTS download_jobs_dedup_lookup
  ON download_jobs (dedup_key, state)
  WHERE state IN ('queued', 'running', 'ready');

-- Per-user concurrency cap lookup.
CREATE INDEX IF NOT EXISTS download_jobs_user_active
  ON download_jobs (user_id, state)
  WHERE state IN ('queued', 'running');

-- GC scan over expired ready artifacts.
CREATE INDEX IF NOT EXISTS download_jobs_gc
  ON download_jobs (expires_at)
  WHERE state = 'ready';
