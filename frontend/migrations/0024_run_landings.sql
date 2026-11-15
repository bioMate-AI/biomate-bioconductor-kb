-- BioMate-native pre-filled run landing links (Wave 4).
-- Distinct from workflow_drafts (/workflow/:id owner-scoped deep links) and
-- from Galaxy workflow_landings. Shareable token → /run/:token claim →
-- chat + panel prefilled, Confirm & Run ready.
-- See docs/20261115_WAVE4_RUN_LANDINGS.md.

CREATE TABLE IF NOT EXISTS run_landings (
  id              TEXT        PRIMARY KEY,
  token           TEXT        NOT NULL UNIQUE,
  created_by      TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  project_id      TEXT,
  workflow_id     TEXT,
  nextflow_path   TEXT,
  workflow_name   TEXT,
  domain          TEXT,
  -- Panel-shaped workflow object (workflow_ga / steps / required_params) when known.
  workflow        JSONB,
  -- Pre-filled parameter map (Confirm & Run inputs).
  params          JSONB       NOT NULL DEFAULT '{}'::jsonb,
  -- Optional dataset references keyed for panel binding (project file ids / S3 URIs).
  dataset_refs    JSONB       NOT NULL DEFAULT '[]'::jsonb,
  -- Optional assistant blurb shown above the workflow card.
  response_text   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ,
  -- First claim audit (links remain reusable until expiry — CRO handoff).
  first_claimed_by TEXT,
  first_claimed_at TIMESTAMPTZ,
  claim_count     INTEGER     NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS run_landings_token_idx ON run_landings (token);
CREATE INDEX IF NOT EXISTS run_landings_created_by_idx ON run_landings (created_by, created_at DESC);
CREATE INDEX IF NOT EXISTS run_landings_expiry_idx ON run_landings (expires_at);
