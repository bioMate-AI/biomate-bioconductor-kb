-- Provenance: record which exact dataset was bound to each data-input step at
-- launch, so a run record can state its resolved inputs (Phase 1 P0 "real
-- inputs bound before compute"). JSON array of InputBinding[]. Idempotent.
ALTER TABLE execution_runs ADD COLUMN IF NOT EXISTS input_bindings TEXT;
