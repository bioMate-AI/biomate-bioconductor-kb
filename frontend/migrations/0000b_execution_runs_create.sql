-- Create the execution_runs table if it does not yet exist.
--
-- Fresh installs (on-prem) have no pre-existing postgres schema, so the later
-- migrations (0007, 0010) that assume execution_runs already exists will fail
-- with "relation does not exist".  This migration runs first (lexicographically
-- between 0000_ and 0001_) and creates the full baseline table so all
-- subsequent ALTER TABLE ... IF NOT EXISTS migrations are safe to run.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS execution_runs (
  id                   varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_run_id        varchar,
  run_sequence         text DEFAULT '1',

  -- Ownership
  user_id              text,
  project_id           text,
  chat_session_id      text,

  -- Mode & Workflow
  mode                 text DEFAULT 'sandbox',
  workflow_name        text NOT NULL,
  workflow_definition  text,
  data_scope           text,
  parameters           text,

  -- Galaxy integration
  galaxy_invocation_id text,
  galaxy_history_id    text,
  galaxy_workflow_id   text,

  -- Execution state
  status               text DEFAULT 'configuring',
  started_at           timestamptz,
  completed_at         timestamptz,
  paused_at            timestamptz,
  pause_reason         text,
  error_message        text,

  -- Progress
  total_steps          text DEFAULT '0',
  completed_steps      text DEFAULT '0',
  current_step_index   text,
  current_step_name    text,
  percent_complete     text DEFAULT '0',

  -- JSON blobs
  steps                text,
  metrics              text,
  interactions         text,
  recommendations      text,
  comparison           text,
  execution_json       text,
  nextflow_run_id      text,
  nextflow_output_dir  text,

  -- Timestamps
  created_at           timestamptz DEFAULT now(),
  updated_at           timestamptz DEFAULT now()
);
