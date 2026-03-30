#!/usr/bin/env python3
"""
Initialize missing execution_info for Nextflow-referenced tools listed in gap report.

Sets only structural metadata from existing DB evidence:
- type inferred from tool_id pattern (`toolshed` vs `galaxy_tool`)
- install_required inferred from availability_status
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Initialize missing execution_info for nextflow-referenced tools")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument(
        "--gap-report",
        default="backend/database/tmp/execution_info_gap_report.json",
        help="Gap report JSON path",
    )
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
    report_path = Path(args.gap_report).resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    missing_ids = list(report.get("missing_execution_info_tool_ids", []))

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        updates = []
        now = datetime.now(timezone.utc).isoformat()
        for tool_id in missing_ids:
            cur.execute(
                "SELECT tool_id, availability_status FROM tools WHERE tool_id = ?",
                (tool_id,),
            )
            row = cur.fetchone()
            if not row:
                continue
            inferred_type = "toolshed" if str(tool_id).startswith("toolshed.g2.bx.psu.edu/") else "galaxy_tool"
            availability = str(row["availability_status"] or "").lower()
            install_required = True if availability in ("installable", "needs_install") else None
            execution_info = {
                "type": inferred_type,
                "install_required": install_required,
                "evidence_source": {
                    "type": "db_metadata_inference",
                    "initialized_at": now,
                    "source_fields": ["tool_id", "availability_status"],
                },
            }
            updates.append((json.dumps(execution_info), tool_id))

        backup = None
        if args.apply and updates:
            backup = backup_db(db_path)
            cur.executemany("UPDATE tools SET execution_info = ? WHERE tool_id = ?", updates)
            conn.commit()

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"missing_ids_from_report: {len(missing_ids)}")
        print(f"updated_tools: {len(updates) if args.apply else 0}")
        if backup:
            print(f"backup_file: {backup}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

