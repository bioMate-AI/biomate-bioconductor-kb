-- Catalog label translations (server/label-translation.ts). Backend-sourced
-- English labels (phase / step / parameter names) translated for the zh UI.
-- Keyed by prompt_version so a changed prompt never serves old translations.
CREATE TABLE IF NOT EXISTS label_translations (
  prompt_version integer     NOT NULL,
  lang           text        NOT NULL,
  src            text        NOT NULL,
  translation    text        NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (prompt_version, lang, src)
);
