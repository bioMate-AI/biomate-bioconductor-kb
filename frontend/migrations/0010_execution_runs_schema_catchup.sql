-- Add the columns the drizzle schema (shared/schema.ts:executionRuns) defines
-- but earlier migrations did not create. Without these, every storage.createExecutionRun
-- silently fails (fire-and-forget .catch in storage.ts), so the execution_runs table
-- accumulates zero rows even on a healthy deploy — users lose all run history
-- whenever the frontend container restarts and MemStorage clears.
--
-- Verified on dev-public 2026-05-18: table had 24 columns vs 35 in the schema.
-- The .catch was logging:
--   column "error_message" of relation "execution_runs" does not exist
--   column "completed_steps" of relation "execution_runs" does not exist
--
-- Idempotent: IF NOT EXISTS on every column.

ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS error_message text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS total_steps text DEFAULT '0';
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS completed_steps text DEFAULT '0';
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS current_step_index text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS current_step_name text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS percent_complete text DEFAULT '0';
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS steps text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS metrics text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS interactions text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS recommendations text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS comparison text;
