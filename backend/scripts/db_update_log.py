#!/usr/bin/env python3
"""
db_update_log — an explicit audit trail for workflow-DB updates.

Motivation
----------
Until now the ONLY record of DB updates was the per-row timestamp columns
(`created_at`, `indexed_at`, `annotation_v2_at`, `workflow_json_v2_at`,
`real_exec_at`, tools.`scientific_context_v2_at`). That makes "what changed and
when" reconstructable only by aggregating those columns, and it captures nothing
about *why* / *by which script* / bulk operations that don't touch a per-row
timestamp (VACUUM, re-embed, S3 snapshot).

This module adds a first-class `db_update_log` table and a `log_update()` helper
the enrichment/index/verify scripts call, so future DB changes have an explicit,
queryable audit trail — consistent with BioMate's provenance/audit posture.

Usage
-----
    # one-time: create the table and backfill history from existing timestamps
    python3 backend/scripts/db_update_log.py --backfill

    # from another script:
    from db_update_log import log_update
    log_update(conn, action="enrich", target_table="workflows",
               n_rows=153, source="biomni_nextflow",
               detail="annotation_v2 for 2026-09-02 batch", script="enrich_v2.py")

The table is additive and safe (CREATE TABLE IF NOT EXISTS); it never modifies
existing rows.
"""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

DEFAULT_DB = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS db_update_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    ts           TEXT NOT NULL,              -- ISO8601 when the update happened
    action       TEXT NOT NULL,              -- create | index | enrich | verify | embed | vacuum | snapshot
    target_table TEXT,                       -- workflows | tools | (blank for whole-db ops)
    n_rows       INTEGER,                    -- rows affected
    source       TEXT,                       -- biomni_nextflow | nfcore | bioconductor | ...
    detail       TEXT,                       -- free-text specifics
    script       TEXT,                       -- producing script / operator
    recorded_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_db_update_log_ts ON db_update_log(ts);
CREATE INDEX IF NOT EXISTS idx_db_update_log_action ON db_update_log(action);
"""


def ensure_table(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def log_update(conn: sqlite3.Connection, *, action: str, target_table: str = "",
               n_rows: int | None = None, source: str = "", detail: str = "",
               script: str = "", ts: str | None = None) -> None:
    """Append one audit row. `ts` defaults to now (UTC-naive, ISO)."""
    ensure_table(conn)
    if ts is None:
        ts = conn.execute("SELECT datetime('now')").fetchone()[0]
    conn.execute(
        "INSERT INTO db_update_log (ts, action, target_table, n_rows, source, detail, script) "
        "VALUES (?,?,?,?,?,?,?)",
        (ts, action, target_table, n_rows, source, detail, script),
    )
    conn.commit()


def backfill(conn: sqlite3.Connection) -> int:
    """Reconstruct historical log entries from existing per-row timestamps.

    Idempotent: clears prior backfilled rows (script='backfill') before re-inserting,
    so it can be re-run safely without duplicating history.
    """
    ensure_table(conn)
    conn.execute("DELETE FROM db_update_log WHERE script = 'backfill'")

    inserted = 0
    # (timestamp column, table, action, source-filter-note)
    passes = [
        ("workflows", "created_at",           "create",  "workflow created"),
        ("workflows", "indexed_at",            "index",   "workflow indexed"),
        ("workflows", "annotation_v2_at",      "enrich",  "annotation_v2 written"),
        ("workflows", "workflow_json_v2_at",   "enrich",  "workflow_json_v2 written"),
        ("workflows", "real_exec_at",          "verify",  "real-execution verification"),
        ("tools",     "scientific_context_v2_at", "enrich", "tools scientific_context_v2 written"),
    ]
    for table, tscol, action, note in passes:
        try:
            rows = conn.execute(
                f"SELECT substr({tscol},1,10) d, count(*) n "
                f"FROM {table} WHERE {tscol} IS NOT NULL AND {tscol} != '' "
                f"GROUP BY d ORDER BY d"
            ).fetchall()
        except sqlite3.OperationalError:
            continue  # column doesn't exist on this table
        for d, n in rows:
            if not d:
                continue
            conn.execute(
                "INSERT INTO db_update_log (ts, action, target_table, n_rows, source, detail, script) "
                "VALUES (?,?,?,?,?,?,?)",
                (d, action, table, n, "", note, "backfill"),
            )
            inserted += 1
    conn.commit()
    return inserted


def show(conn: sqlite3.Connection, limit: int = 40) -> None:
    ensure_table(conn)
    rows = conn.execute(
        "SELECT ts, action, target_table, n_rows, detail, script "
        "FROM db_update_log ORDER BY ts DESC, id DESC LIMIT ?", (limit,)
    ).fetchall()
    print(f"{'ts':<12} {'action':<8} {'table':<10} {'n':>6}  detail (script)")
    print("-" * 78)
    for ts, action, tbl, n, detail, script in rows:
        print(f"{ts or '':<12} {action:<8} {tbl or '':<10} {str(n or ''):>6}  {detail or ''} ({script or ''})")


def main() -> None:
    ap = argparse.ArgumentParser(description="Workflow-DB update audit log")
    ap.add_argument("--db", default=str(DEFAULT_DB), help="path to galaxy_ai_tools.db")
    ap.add_argument("--backfill", action="store_true", help="create table + backfill history from timestamps")
    ap.add_argument("--show", type=int, nargs="?", const=40, help="print the last N log rows")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    ensure_table(conn)
    if args.backfill:
        n = backfill(conn)
        print(f"[db_update_log] table ensured; backfilled {n} historical entries from timestamps")
    if args.show is not None:
        show(conn, args.show)
    if not args.backfill and args.show is None:
        print("[db_update_log] table ensured. Use --backfill and/or --show.")
    conn.close()


if __name__ == "__main__":
    main()
