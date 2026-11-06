#!/usr/bin/env python3
"""
Migration: add annotation_v2 to the workflows_fts FTS5 index + triggers.

The authoritative retriever (unified_workflow_search.py) matched only
name/description/annotation/tags/domain/tools_used. The enriched
`annotation_v2` column (~1300 chars avg: key_parameters, alternatives,
when_to_use, keywords) was populated in the workflows table but NOT indexed,
so well-annotated workflows were under-retrieved.

This migration rebuilds the external-content FTS5 table and its INSERT/UPDATE
triggers to include annotation_v2, then repopulates so existing rows are
indexed. Idempotent: detects whether annotation_v2 is already in the FTS schema.

Usage:
    python3 backend/scripts/migrate_fts_add_annotation_v2.py [path/to/galaxy_ai_tools.db]
"""
import sqlite3
import sys
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parent.parent / "database" / "galaxy_ai_tools.db"


def fts_has_annotation_v2(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='workflows_fts'"
    ).fetchone()
    return bool(row) and "annotation_v2" in (row[0] or "")


def migrate(db_path: Path) -> None:
    conn = sqlite3.connect(str(db_path))
    try:
        if fts_has_annotation_v2(conn):
            print(f"[migrate] annotation_v2 already in workflows_fts — nothing to do ({db_path})")
            return

        print(f"[migrate] rebuilding workflows_fts with annotation_v2 ({db_path})")
        cur = conn.cursor()
        # Drop triggers first (they reference the FTS table).
        cur.execute("DROP TRIGGER IF EXISTS workflows_ai")
        cur.execute("DROP TRIGGER IF EXISTS workflows_au")
        cur.execute("DROP TRIGGER IF EXISTS workflows_ad")
        cur.execute("DROP TABLE IF EXISTS workflows_fts")

        cur.execute("""
            CREATE VIRTUAL TABLE workflows_fts USING fts5(
                name, description, annotation, annotation_v2, tags, domain, tools_used,
                content='workflows',
                content_rowid='id'
            )
        """)
        cur.execute("""
            INSERT INTO workflows_fts(rowid, name, description, annotation, annotation_v2, tags, domain, tools_used)
            SELECT id, name, description, annotation, annotation_v2, tags, domain, tools_used FROM workflows
        """)

        # Recreate external-content sync triggers including annotation_v2.
        cur.execute("""
            CREATE TRIGGER workflows_ai AFTER INSERT ON workflows BEGIN
                INSERT INTO workflows_fts(rowid, name, description, annotation, annotation_v2, tags, domain, tools_used)
                VALUES (new.id, new.name, new.description, new.annotation, new.annotation_v2, new.tags, new.domain, new.tools_used);
            END
        """)
        cur.execute("""
            CREATE TRIGGER workflows_ad AFTER DELETE ON workflows BEGIN
                INSERT INTO workflows_fts(workflows_fts, rowid, name, description, annotation, annotation_v2, tags, domain, tools_used)
                VALUES ('delete', old.id, old.name, old.description, old.annotation, old.annotation_v2, old.tags, old.domain, old.tools_used);
            END
        """)
        cur.execute("""
            CREATE TRIGGER workflows_au AFTER UPDATE ON workflows BEGIN
                INSERT INTO workflows_fts(workflows_fts, rowid, name, description, annotation, annotation_v2, tags, domain, tools_used)
                VALUES ('delete', old.id, old.name, old.description, old.annotation, old.annotation_v2, old.tags, old.domain, old.tools_used);
                INSERT INTO workflows_fts(rowid, name, description, annotation, annotation_v2, tags, domain, tools_used)
                VALUES (new.id, new.name, new.description, new.annotation, new.annotation_v2, new.tags, new.domain, new.tools_used);
            END
        """)
        conn.commit()

        n = conn.execute("SELECT count(*) FROM workflows_fts").fetchone()[0]
        print(f"[migrate] done — workflows_fts repopulated with {n} rows")
    finally:
        conn.close()


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB
    if not path.exists():
        print(f"[migrate] DB not found: {path}", file=sys.stderr)
        sys.exit(1)
    migrate(path)
