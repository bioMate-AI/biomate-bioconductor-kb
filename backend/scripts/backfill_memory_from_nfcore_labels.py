#!/usr/bin/env python3
"""
Backfill execution_info.memory for nextflow_token tools using nf-core module labels.

Evidence chain:
- module file label from `backend/nf-core-modules/modules/nf-core/**/main.nf`
- label memory from `backend/nf-core-workflows/*/conf/base.config`
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


LABELS = ["process_single", "process_low", "process_medium", "process_high", "process_high_memory"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill memory from nf-core label defaults")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/execution_info_nfcore_label_memory_report.json",
    )
    return parser.parse_args()


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def parse_label_memory(base_config_text: str, label: str) -> float | None:
    patterns = [
        rf"withLabel:\s*{label}\s*\{{[\s\S]*?memory\s*=\s*\{{\s*check_max\(\s*([0-9]+(?:\.[0-9]+)?)\.GB",
        rf"withLabel:\s*{label}\s*\{{[\s\S]*?memory\s*=\s*\{{\s*([0-9]+(?:\.[0-9]+)?)\.GB",
    ]
    for p in patterns:
        m = re.search(p, base_config_text, flags=re.IGNORECASE)
        if m:
            return float(m.group(1))
    return None


def resolve_label_memory_defaults(repo_root: Path) -> tuple[dict[str, float], list[str]]:
    label_values: dict[str, set[float]] = {k: set() for k in LABELS}
    scanned_files: list[str] = []
    for path in sorted((repo_root / "backend" / "nf-core-workflows").glob("*/conf/base.config")):
        txt = path.read_text(encoding="utf-8", errors="ignore")
        scanned_files.append(str(path.relative_to(repo_root)))
        for label in LABELS:
            v = parse_label_memory(txt, label)
            if v is not None:
                label_values[label].add(v)

    resolved: dict[str, float] = {}
    for label, vals in label_values.items():
        if len(vals) == 1:
            resolved[label] = list(vals)[0]
    return resolved, scanned_files


def normalize_exec(raw: Any) -> dict[str, Any]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return dict(raw)
    text = str(raw).strip()
    if not text or text in ("{}", "null"):
        return {}
    try:
        parsed = json.loads(text)
    except Exception:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def find_module_main(repo_root: Path, token_tool_id: str) -> Path | None:
    parts = [p for p in token_tool_id.split("/") if p]
    if len(parts) < 2:
        return None
    candidate = repo_root / "backend" / "nf-core-modules" / "modules" / "nf-core"
    for p in parts:
        candidate = candidate / p
    main_nf = candidate / "main.nf"
    return main_nf if main_nf.exists() else None


def extract_module_label(main_nf_text: str) -> str | None:
    m = re.search(r"label\s+['\"](process_[a-z_]+)['\"]", main_nf_text)
    return m.group(1) if m else None


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    repo_root = Path(__file__).resolve().parents[2]

    label_defaults, scanned_base_configs = resolve_label_memory_defaults(repo_root)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT tool_id, name, category, execution_info
            FROM tools
            WHERE category='nextflow_token'
            """
        )
        rows = cur.fetchall()

        updates = []
        skipped = []
        now = datetime.now(timezone.utc).isoformat()

        for r in rows:
            tool_id = str(r["tool_id"] or "")
            info = normalize_exec(r["execution_info"])
            if "memory" in info and str(info.get("memory", "")).strip():
                continue

            main_nf = find_module_main(repo_root, tool_id)
            if not main_nf:
                skipped.append({"tool_id": tool_id, "reason": "module_main_not_found"})
                continue

            txt = main_nf.read_text(encoding="utf-8", errors="ignore")
            label = extract_module_label(txt)
            if not label:
                skipped.append({"tool_id": tool_id, "reason": "module_label_missing", "module_main": str(main_nf.relative_to(repo_root))})
                continue

            memory_gb = label_defaults.get(label)
            if memory_gb is None:
                skipped.append({"tool_id": tool_id, "reason": "label_memory_not_consistent", "label": label})
                continue

            new_info = dict(info)
            new_info["memory"] = f"{memory_gb}GB"
            new_info["evidence_source"] = {
                "type": "nfcore_module_label_default",
                "label": label,
                "module_main": str(main_nf.relative_to(repo_root)),
                "base_configs_scanned": scanned_base_configs[:20],
                "resolved_at": now,
            }
            updates.append((json.dumps(new_info), tool_id))

        backup = None
        if args.apply and updates:
            backup = backup_db(db_path)
            cur.executemany("UPDATE tools SET execution_info = ? WHERE tool_id = ?", updates)
            conn.commit()

        report = {
            "timestamp_utc": now,
            "db_path": str(db_path),
            "apply": args.apply,
            "label_defaults": label_defaults,
            "updates": len(updates),
            "skipped": len(skipped),
            "backup_file": str(backup) if backup else None,
            "sample_skipped": skipped[:200],
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"label_defaults: {label_defaults}")
        print(f"updates: {len(updates)}")
        print(f"skipped: {len(skipped)}")
        if backup:
            print(f"backup_file: {backup}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

