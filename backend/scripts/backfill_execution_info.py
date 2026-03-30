#!/usr/bin/env python3
"""
Backfill tools.execution_info for workflow-referenced tools.

This script normalizes execution_info so runtime hints are always explicit:
  - gpu: boolean
  - memory: "<N>GB" string
  - install_required: boolean
  - type: runtime type string

By default, this runs in dry-run mode and only prints/report changes.
Use --apply to persist updates.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class ToolRecord:
    tool_id: str
    name: str
    execution_info_raw: Any
    requirements_raw: Any
    container_info_raw: Any


@dataclass
class UpdateRow:
    tool_id: str
    name: str
    old_info: dict[str, Any] | None
    new_info: dict[str, Any]
    reason: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill tools.execution_info hints.")
    parser.add_argument(
        "--db",
        default="backend/database/galaxy_ai_tools.db",
        help="Path to galaxy_ai_tools.db",
    )
    parser.add_argument(
        "--scope",
        choices=["nextflow", "all_workflows"],
        default="nextflow",
        help="Choose which workflow set drives tool selection.",
    )
    parser.add_argument(
        "--strategy",
        choices=["evidence_only", "heuristic"],
        default="evidence_only",
        help="evidence_only fills from explicit evidence only; heuristic allows defaults.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist updates to DB (default is dry-run).",
    )
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/execution_info_backfill_report.json",
        help="Where to write the JSON report.",
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
            value = json.loads(text)
            if isinstance(value, list):
                return [str(v).strip() for v in value if str(v).strip()]
        except Exception:
            pass
    parts = re.split(r"[,;\n]+", text)
    return [p.strip().strip("\"'") for p in parts if p.strip()]


def normalize_json(raw: Any) -> dict[str, Any] | None:
    if raw is None:
        return None
    if isinstance(raw, dict):
        return dict(raw)
    text = str(raw).strip()
    if not text or text.lower() == "null":
        return None
    try:
        parsed = json.loads(text)
    except Exception:
        return None
    if isinstance(parsed, dict):
        return parsed
    return None


def parse_memory_to_gb(text: str) -> int | None:
    if not text:
        return None
    lower = text.lower()
    # Match values like 16gb, 32768mb, 4 g, 8192 m
    match = re.search(r"(\d+(?:\.\d+)?)\s*(gb|gib|g|mb|mib|m)\b", lower)
    if not match:
        return None
    value = float(match.group(1))
    unit = match.group(2)
    if unit in ("gb", "gib", "g"):
        return max(1, int(round(value)))
    return max(1, int(round(value / 1024.0)))


def extract_evidence(record: ToolRecord, current: dict[str, Any]) -> tuple[bool | None, int | None]:
    gpu_evidence: bool | None = None
    memory_evidence_gb: int | None = None

    if isinstance(current.get("gpu"), bool):
        gpu_evidence = current["gpu"]

    if isinstance(current.get("memory"), (str, int, float)):
        parsed = parse_memory_to_gb(str(current["memory"]))
        if parsed is not None:
            memory_evidence_gb = parsed

    corpus = " ".join(
        [
            str(record.container_info_raw or ""),
            str(record.requirements_raw or ""),
            str(current.get("image", "") or ""),
            str(current.get("runtime_type", "") or ""),
        ]
    ).lower()

    if gpu_evidence is None and any(tok in corpus for tok in ("cuda", "nvidia", "gpu", "cudnn")):
        gpu_evidence = True

    if memory_evidence_gb is None:
        parsed = parse_memory_to_gb(corpus)
        if parsed is not None:
            memory_evidence_gb = parsed

    return gpu_evidence, memory_evidence_gb


def normalize_execution_info(record: ToolRecord, strategy: str) -> UpdateRow | None:
    current = normalize_json(record.execution_info_raw) or {}
    gpu_evidence, memory_evidence_gb = extract_evidence(record, current)

    new_info = dict(current)
    changed_reasons: list[str] = []

    if "gpu" not in new_info:
        if gpu_evidence is not None:
            new_info["gpu"] = gpu_evidence
            changed_reasons.append("set_gpu_from_evidence")
        elif strategy == "heuristic":
            new_info["gpu"] = False
            changed_reasons.append("set_gpu_heuristic_default")

    memory_missing = "memory" not in new_info or not str(new_info.get("memory", "")).strip()
    if memory_missing:
        if memory_evidence_gb is not None:
            new_info["memory"] = f"{memory_evidence_gb}GB"
            changed_reasons.append("set_memory_from_evidence")
        elif strategy == "heuristic":
            new_info["memory"] = "8GB"
            changed_reasons.append("set_memory_heuristic_default")

    if not changed_reasons:
        return None

    return UpdateRow(
        tool_id=record.tool_id,
        name=record.name,
        old_info=current if current else None,
        new_info=new_info,
        reason=",".join(changed_reasons),
    )


def load_workflow_tool_refs(conn: sqlite3.Connection, scope: str) -> list[str]:
    cur = conn.cursor()
    if scope == "nextflow":
        cur.execute("SELECT tools_used FROM workflows WHERE LOWER(format)='nextflow'")
    else:
        cur.execute("SELECT tools_used FROM workflows")
    refs: list[str] = []
    for (tools_used,) in cur.fetchall():
        refs.extend(parse_tools_used(tools_used))
    return refs


def resolve_tool_rows(conn: sqlite3.Connection, refs: list[str]) -> tuple[list[ToolRecord], list[str]]:
    cur = conn.cursor()
    cur.execute("SELECT tool_id, name, execution_info, requirements, container_info FROM tools")
    rows = cur.fetchall()

    by_tool_id = {str(r[0]).lower(): r for r in rows if r[0]}
    by_name = {str(r[1]).lower(): r for r in rows if r[1]}

    resolved: dict[str, ToolRecord] = {}
    unmatched: list[str] = []

    for ref in refs:
        candidates = [ref]
        if "/" in ref:
            candidates.append(ref.split("/")[-1])
        found = None
        for cand in candidates:
            found = by_tool_id.get(cand.lower()) or by_name.get(cand.lower())
            if found:
                break
        if not found:
            pattern = ref.lower()
            for row in rows:
                tool_id = str(row[0] or "").lower()
                name = str(row[1] or "").lower()
                if pattern and (pattern in tool_id or pattern in name):
                    found = row
                    break

        if not found:
            unmatched.append(ref)
            continue

        tool_id = str(found[0] or "").strip()
        if not tool_id:
            unmatched.append(ref)
            continue

        resolved[tool_id] = ToolRecord(
            tool_id=tool_id,
            name=str(found[1] or tool_id),
            execution_info_raw=found[2],
            requirements_raw=found[3],
            container_info_raw=found[4],
        )

    return list(resolved.values()), unmatched


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def apply_updates(conn: sqlite3.Connection, updates: list[UpdateRow]) -> None:
    cur = conn.cursor()
    for row in updates:
        cur.execute(
            "UPDATE tools SET execution_info = ? WHERE tool_id = ?",
            (json.dumps(row.new_info, ensure_ascii=True), row.tool_id),
        )
    conn.commit()


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        raise FileNotFoundError(f"DB not found: {db_path}")

    conn = sqlite3.connect(str(db_path))
    try:
        refs = load_workflow_tool_refs(conn, args.scope)
        tool_rows, unmatched = resolve_tool_rows(conn, refs)

        updates: list[UpdateRow] = []
        for record in tool_rows:
            maybe = normalize_execution_info(record, args.strategy)
            if maybe:
                updates.append(maybe)

        reason_counts = Counter()
        for row in updates:
            for reason in row.reason.split(","):
                reason_counts[reason] += 1

        backup_file = None
        if args.apply and updates:
            backup_file = backup_db(db_path)
            apply_updates(conn, updates)

        report = {
            "db_path": str(db_path),
            "scope": args.scope,
            "strategy": args.strategy,
            "apply": args.apply,
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "workflow_tool_refs_scanned": len(refs),
            "workflow_tool_refs_unmatched": len(unmatched),
            "resolved_unique_tools": len(tool_rows),
            "updated_tools": len(updates),
            "reason_counts": dict(reason_counts),
            "backup_file": str(backup_file) if backup_file else None,
            "sample_unmatched_refs": sorted(list(set(unmatched)))[:50],
            "sample_updates": [
                {
                    "tool_id": u.tool_id,
                    "name": u.name,
                    "reason": u.reason,
                    "old_info": u.old_info,
                    "new_info": u.new_info,
                }
                for u in updates[:120]
            ],
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"scope: {args.scope}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"strategy: {args.strategy}")
        print(f"workflow_tool_refs_scanned: {len(refs)}")
        print(f"workflow_tool_refs_unmatched: {len(unmatched)}")
        print(f"resolved_unique_tools: {len(tool_rows)}")
        print(f"updated_tools: {len(updates)}")
        print(f"reason_counts: {dict(reason_counts)}")
        if backup_file:
            print(f"backup_file: {backup_file}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

