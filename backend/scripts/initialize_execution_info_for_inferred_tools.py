#!/usr/bin/env python3
"""
Initialize execution_info for inferred tools added from workflow tokens.

This does NOT invent hardware requirements. It only records provenance so
execution_info is structurally present and auditable.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Initialize execution_info for inferred workflow-token tools")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument("--apply", action="store_true", help="Persist updates")
    return parser.parse_args()


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT tool_id, name, execution_info
            FROM tools
            WHERE category='nextflow_token'
              AND (execution_info IS NULL OR TRIM(execution_info) IN ('', '{}', 'null'))
            """
        )
        rows = cur.fetchall()

        updates = []
        now = datetime.now(timezone.utc).isoformat()
        for r in rows:
            updates.append(
                (
                    json.dumps(
                        {
                            "type": "nextflow_token",
                            "install_required": None,
                            "evidence_source": {
                                "type": "workflow_tools_used_token",
                                "initialized_at": now,
                            },
                        }
                    ),
                    r["tool_id"],
                )
            )

        backup = None
        if args.apply and updates:
            backup = backup_db(db_path)
            cur.executemany("UPDATE tools SET execution_info = ? WHERE tool_id = ?", updates)
            conn.commit()

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"candidate_tools: {len(rows)}")
        print(f"updated_tools: {len(updates) if args.apply else 0}")
        if backup:
            print(f"backup_file: {backup}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

