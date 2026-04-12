-- Instrument Events table
-- Records new-data notifications from physical instrument connectors:
-- flow cytometer (FCS), plate reader (CSV/XLSX), qPCR (.pcrd/.eds), LC-MS (.raw/.mzML),
-- cryo-EM (movie directories). Each row represents a connector-detected run that BioMate
-- can automatically launch a workflow for.

CREATE TABLE IF NOT EXISTS instrument_events (
  id              VARCHAR        PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source connector
  source          TEXT           NOT NULL,        -- e.g. "flow_cytometer_watcher"
  vendor          TEXT,                           -- e.g. "biorad_cfx", "bmg", "thermo"
  directory       TEXT,                           -- watched directory path

  -- Experiment classification
  experiment_type TEXT           NOT NULL,         -- e.g. "rt_qpcr_expression", "immunophenotyping"
  assay_type      TEXT,                            -- plate reader sub-type
  workflow_id     TEXT           NOT NULL,         -- BioMate workflow to launch

  -- Data location
  file_path       TEXT,                            -- single file (qPCR, plate reader)
  fcs_dir         TEXT,                            -- flow cytometry directory
  file_count      INTEGER,                         -- flow cytometry tube count
  param_key       TEXT,                            -- e.g. "qpcr_data_file", "fcs_dir"

  -- Run metadata
  run_name        TEXT,
  targets         TEXT,                            -- JSON array of gene/target names
  sample_count    INTEGER,
  channels        TEXT,                            -- JSON array of FCS channel names

  -- Analysis hint
  analysis_function TEXT,                          -- e.g. "cell_biology.analyze_flow_cytometry_immunophenotyping"

  -- Human-readable
  description     TEXT           NOT NULL,
  message         TEXT           NOT NULL,

  -- Lifecycle
  status          TEXT           NOT NULL DEFAULT 'pending',
  -- 'pending'   = received, not yet acted on
  -- 'launched'  = BioMate workflow execution started
  -- 'dismissed' = user dismissed without launching

  user_id         TEXT,                            -- set when user acts on the notification
  timestamp       TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_instrument_events_status    ON instrument_events (status);
CREATE INDEX IF NOT EXISTS idx_instrument_events_timestamp ON instrument_events (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_instrument_events_source    ON instrument_events (source);
