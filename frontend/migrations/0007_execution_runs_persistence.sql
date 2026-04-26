-- Add execution_json column to store full execution state
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS execution_json text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS nextflow_run_id text;
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS nextflow_output_dir text;

-- Apply migration
