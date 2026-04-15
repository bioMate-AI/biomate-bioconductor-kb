"""
Cryo-EM Knowledge DB Schema — adds structured protocol knowledge to galaxy_ai_tools.db.

Three new tables mirroring the tool_knowledge / workflows pattern:

  cryo_em_protocols   — per-sample-type protocol knowledge
  cryo_em_parameters  — flat parameter lookup (MW → pixel_size, etc.)
  cryo_em_tools       — tool inventory with BioMate status per step

Query is SQL only — zero LLM cost.
"""

MIGRATION_NAME = "cryo_em_knowledge_v1"

SCHEMA_SQL = """
-- ─────────────────────────────────────────────────────────────────────────────
-- cryo_em_protocols
-- One row per sample class (saposin_nanodisc, gpcr_complex, liposome_pore, ...)
-- JSON fields keep it compact; FTS index makes it searchable.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cryo_em_protocols (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    sample_class            TEXT NOT NULL UNIQUE,   -- machine key
    display_name            TEXT NOT NULL,           -- human label
    typical_mw_range_kda    TEXT,                    -- e.g. "20-60"
    reconstitution_type     TEXT,                    -- saposin|msp|detergent|liposome|none|endogenous|vesicle

    -- JSON fields (compact, query-friendly)
    collection_params       TEXT NOT NULL,           -- pixel_size, defocus, dose, frame_count, box_size
    reconstitution_params   TEXT,                    -- lipid_mix, molar_ratio, stabilizer, qc_criteria
    qc_gates                TEXT NOT NULL,           -- [{name, criterion, pass, fail_action}]
    picking_strategy        TEXT NOT NULL,           -- {tools, order, box_size_rule, training_needed}
    refinement_strategy     TEXT NOT NULL,           -- {symmetry, masking, local_refine, ctf_refine_depth}
    model_building          TEXT NOT NULL,           -- {template_source, pipeline, ligand_handling}
    use_cases               TEXT NOT NULL,           -- JSON array of scenario strings
    limitations             TEXT NOT NULL,           -- JSON array
    key_principles          TEXT NOT NULL,           -- JSON array — BioMate-learnable rules
    tool_requirements       TEXT NOT NULL,           -- [{tool, version, step, status}]
    reference_papers        TEXT,                    -- [{title, journal, year, doi}]

    created_at              TEXT DEFAULT (datetime('now')),
    updated_at              TEXT DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS cryo_em_protocols_fts USING fts5(
    sample_class, display_name, reconstitution_type,
    use_cases, key_principles, limitations,
    content='cryo_em_protocols',
    content_rowid='id',
    tokenize='porter unicode61'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- cryo_em_parameters
-- Flat key-value lookup: (context, parameter) → value
-- e.g. SELECT value FROM cryo_em_parameters
--      WHERE context='mw_50_100' AND parameter='pixel_size'
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cryo_em_parameters (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    context     TEXT NOT NULL,   -- 'mw_lt50' | 'mw_50_100' | 'saposin_nanodisc' | 'gpcr_complex' | ...
    parameter   TEXT NOT NULL,   -- 'pixel_size' | 'defocus_min' | 'total_dose' | 'box_size_px' | ...
    value       TEXT NOT NULL,   -- the actual value (stored as text, cast in app)
    unit        TEXT,            -- 'angstrom' | 'um' | 'e/A2' | 'pixels' | 'kDa'
    rationale   TEXT,            -- brief reason (<80 chars)
    UNIQUE(context, parameter)
);

CREATE INDEX IF NOT EXISTS idx_cryo_em_params_context ON cryo_em_parameters(context);
CREATE INDEX IF NOT EXISTS idx_cryo_em_params_param   ON cryo_em_parameters(parameter);

-- ─────────────────────────────────────────────────────────────────────────────
-- cryo_em_tools
-- One row per tool used in cryo-EM workflows
-- Mirrors tool_knowledge but cryo-EM specific
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cryo_em_tools (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_name           TEXT NOT NULL UNIQUE,
    tool_category       TEXT NOT NULL,   -- motion_correction|ctf|picking|classify|refine|model_building|visualization|post_processing
    biomate_status      TEXT NOT NULL,   -- 'have'|'partial'|'missing'
    container_image     TEXT,            -- Docker image if available
    version             TEXT,

    use_when            TEXT NOT NULL,   -- JSON array of conditions/scenarios
    key_parameters      TEXT,           -- JSON {param: description}
    alternatives        TEXT,           -- JSON array of alternative tool names
    biomate_gap_notes   TEXT,           -- what's missing if status != 'have'

    created_at          TEXT DEFAULT (datetime('now'))
);
"""

TRIGGERS_SQL = """
-- Keep FTS in sync with cryo_em_protocols
CREATE TRIGGER IF NOT EXISTS cryo_em_protocols_fts_insert
AFTER INSERT ON cryo_em_protocols BEGIN
    INSERT INTO cryo_em_protocols_fts(rowid, sample_class, display_name, reconstitution_type, use_cases, key_principles, limitations)
    VALUES (new.id, new.sample_class, new.display_name, new.reconstitution_type, new.use_cases, new.key_principles, new.limitations);
END;

CREATE TRIGGER IF NOT EXISTS cryo_em_protocols_fts_update
AFTER UPDATE ON cryo_em_protocols BEGIN
    UPDATE cryo_em_protocols_fts SET
        sample_class=new.sample_class, display_name=new.display_name,
        reconstitution_type=new.reconstitution_type, use_cases=new.use_cases,
        key_principles=new.key_principles, limitations=new.limitations
    WHERE rowid=old.id;
END;

CREATE TRIGGER IF NOT EXISTS cryo_em_protocols_fts_delete
AFTER DELETE ON cryo_em_protocols BEGIN
    DELETE FROM cryo_em_protocols_fts WHERE rowid=old.id;
END;
"""


def apply_migration(db_path: str) -> bool:
    import sqlite3
    conn = sqlite3.connect(db_path)
    try:
        # Check if already applied
        cur = conn.execute(
            "SELECT id FROM schema_migrations WHERE migration_name = ?",
            (MIGRATION_NAME,)
        )
        if cur.fetchone():
            print(f"Migration '{MIGRATION_NAME}' already applied.")
            return False

        conn.executescript(SCHEMA_SQL)
        conn.executescript(TRIGGERS_SQL)
        conn.execute(
            "INSERT INTO schema_migrations (migration_name, applied_at, status) VALUES (?, datetime('now'), 'applied')",
            (MIGRATION_NAME,)
        )
        conn.commit()
        print(f"Migration '{MIGRATION_NAME}' applied successfully.")
        return True
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


if __name__ == "__main__":
    import sys
    db = sys.argv[1] if len(sys.argv) > 1 else "/home/yzhang/biomate/backend/galaxy_ai_tools.db"
    apply_migration(db)
