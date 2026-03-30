#!/usr/bin/env python3
"""
Conservative cleanup for workflows.tools_used tokens.

Only removes obvious non-tool tokens (noise words) from Nextflow workflows.
No semantic mapping/guessing is performed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


NOISE_TOKENS = {
    "including",
    "directly",
    "identified",
    "replaced",
    "csv_files",
    "2d_classification",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Clean obvious non-tool tokens from workflows.tools_used")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument("--apply", action="store_true", help="Persist updates")
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/workflow_tools_used_cleanup_report.json",
        help="JSON report output path",
    )
    return parser.parse_args()


def parse_tools_used(raw: Any) -> list[str]:
    if raw is None:
        return []
    text = str(raw).strip()
    if not text:
        return []
    if text.startswith("["):
        try:
            arr = json.loads(text)
            if isinstance(arr, list):
                return [str(x).strip() for x in arr if str(x).strip()]
        except Exception:
            pass
    return [p.strip().strip("\"'") for p in re.split(r"[,;\n]+", text) if p.strip()]


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        rows = cur.fetchall()

        updates = []
        removed_counter = Counter()

        for row in rows:
            tokens = parse_tools_used(row["tools_used"])
            if not tokens:
                continue
            cleaned = []
            seen = set()
            removed_here = []
            for tok in tokens:
                t = tok.strip()
                if not t:
                    continue
                if t.lower() in NOISE_TOKENS:
                    removed_here.append(t)
                    removed_counter[t.lower()] += 1
                    continue
                if t not in seen:
                    seen.add(t)
                    cleaned.append(t)
            if removed_here:
                updates.append(
                    {
                        "id": row["id"],
                        "name": row["name"],
                        "filename": row["filename"],
                        "old_tokens": tokens,
                        "new_tokens": cleaned,
                        "removed": removed_here,
                    }
                )

        backup_file = None
        if args.apply and updates:
            backup_file = backup_db(db_path)
            for u in updates:
                cur.execute("UPDATE workflows SET tools_used = ? WHERE id = ?", (json.dumps(u["new_tokens"]), u["id"]))
            conn.commit()

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "apply": args.apply,
            "workflows_scanned": len(rows),
            "workflows_updated": len(updates),
            "removed_token_counts": dict(removed_counter),
            "backup_file": str(backup_file) if backup_file else None,
            "sample_updates": updates[:200],
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"workflows_scanned: {len(rows)}")
        print(f"workflows_updated: {len(updates)}")
        print(f"removed_token_counts: {dict(removed_counter)}")
        if backup_file:
            print(f"backup_file: {backup_file}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

