-- Personal workflow uploads — stores .nf / .ga / .yml workflow files
-- imported by the user via the "Import Workflow" sidebar button.
-- Self-contained in the frontend DB; no Galaxy backend required.

CREATE TABLE IF NOT EXISTS personal_workflows (
  id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id      TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT        NOT NULL,
  description  TEXT        NOT NULL DEFAULT '',
  file_type    TEXT        NOT NULL,
  file_content TEXT        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS personal_workflows_user_idx
  ON personal_workflows (user_id, created_at DESC);
