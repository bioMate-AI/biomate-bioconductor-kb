#!/usr/bin/env python3
"""
Generate an actionable gap report for tools.execution_info coverage.

Focuses on Nextflow-referenced tools and reports:
- unresolved workflow tool refs (cannot map to tool_id)
- mapped tools missing execution_info
- mapped tools with execution_info but missing memory
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Report execution_info coverage gaps.")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument(
        "--json-out",
        default="backend/database/tmp/execution_info_gap_report.json",
        help="JSON output path",
    )
    parser.add_argument(
        "--md-out",
        default="docs/QC/20260311_EXECUTION_INFO_GAP_REMEDIATION_REPORT.md",
        help="Markdown output path",
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
            values = json.loads(text)
            if isinstance(values, list):
                return [str(v).strip() for v in values if str(v).strip()]
        except Exception:
            pass
    parts = re.split(r"[,;\n]+", text)
    return [p.strip().strip("\"'") for p in parts if p.strip()]


def normalize_exec(raw: Any) -> dict[str, Any] | None:
    if raw is None:
        return None
    if isinstance(raw, dict):
        return raw
    text = str(raw).strip()
    if not text or text in ("{}", "null"):
        return None
    try:
        parsed = json.loads(text)
    except Exception:
        return None
    return parsed if isinstance(parsed, dict) else None


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    json_out = Path(args.json_out).resolve()
    md_out = Path(args.md_out).resolve()
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        workflows = cur.fetchall()

        cur.execute("SELECT tool_id, name, execution_info, container_info, requirements FROM tools")
        tools = cur.fetchall()

        by_id = {str(r["tool_id"]).lower(): r for r in tools if r["tool_id"]}
        by_name = {str(r["name"]).lower(): r for r in tools if r["name"]}

        def resolve(ref: str):
            candidates = [ref]
            if "/" in ref:
                candidates.append(ref.split("/")[-1])
            for c in candidates:
                row = by_id.get(c.lower()) or by_name.get(c.lower())
                if row:
                    return row
            patt = ref.lower()
            for row in tools:
                tid = str(row["tool_id"] or "").lower()
                nm = str(row["name"] or "").lower()
                if patt and (patt in tid or patt in nm):
                    return row
            return None

        unresolved_refs: list[dict[str, str]] = []
        missing_exec: list[dict[str, str]] = []
        missing_memory: list[dict[str, str]] = []
        seen_exec = set()
        seen_mem = set()

        for wf in workflows:
            wf_name = str(wf["name"])
            wf_file = str(wf["filename"])
            refs = parse_tools_used(wf["tools_used"])
            for ref in refs:
                row = resolve(ref)
                if not row:
                    unresolved_refs.append({"workflow": wf_name, "filename": wf_file, "tool_ref": ref})
                    continue
                tool_id = str(row["tool_id"] or "").strip()
                if not tool_id:
                    unresolved_refs.append({"workflow": wf_name, "filename": wf_file, "tool_ref": ref})
                    continue
                exec_info = normalize_exec(row["execution_info"])
                key = (tool_id, wf_file)
                if exec_info is None:
                    if key not in seen_exec:
                        missing_exec.append(
                            {
                                "tool_id": tool_id,
                                "tool_name": str(row["name"] or tool_id),
                                "workflow": wf_name,
                                "filename": wf_file,
                                "container_info": str(row["container_info"] or ""),
                                "requirements": str(row["requirements"] or ""),
                            }
                        )
                        seen_exec.add(key)
                    continue
                if "memory" not in exec_info:
                    if key not in seen_mem:
                        missing_memory.append(
                            {
                                "tool_id": tool_id,
                                "tool_name": str(row["name"] or tool_id),
                                "workflow": wf_name,
                                "filename": wf_file,
                                "container_info": str(row["container_info"] or ""),
                                "requirements": str(row["requirements"] or ""),
                            }
                        )
                        seen_mem.add(key)

        missing_exec_unique = sorted({r["tool_id"] for r in missing_exec})
        missing_mem_unique = sorted({r["tool_id"] for r in missing_memory})

        unresolved_counter = Counter([r["tool_ref"] for r in unresolved_refs])
        mem_counter = Counter([r["tool_id"] for r in missing_memory])

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "nextflow_workflows": len(workflows),
            "unresolved_refs_total": len(unresolved_refs),
            "unresolved_refs_unique": len(unresolved_counter),
            "missing_execution_info_refs": len(missing_exec),
            "missing_execution_info_unique_tools": len(missing_exec_unique),
            "missing_memory_refs": len(missing_memory),
            "missing_memory_unique_tools": len(missing_mem_unique),
            "missing_execution_info_tool_ids": missing_exec_unique,
            "top_unresolved_refs": unresolved_counter.most_common(100),
            "top_missing_memory_tools": mem_counter.most_common(100),
            "sample_unresolved_refs": unresolved_refs[:200],
            "sample_missing_execution_info": missing_exec[:200],
            "sample_missing_memory": missing_memory[:200],
        }
        json_out.write_text(json.dumps(report, indent=2), encoding="utf-8")

        md_lines = [
            "# Execution Info Gap Remediation Report",
            "",
            f"- Generated: `{report['timestamp_utc']}`",
            f"- DB: `{db_path}`",
            "",
            "## Summary",
            "",
            f"- Nextflow workflows scanned: `{report['nextflow_workflows']}`",
            f"- Unresolved tool refs: `{report['unresolved_refs_total']}` (`{report['unresolved_refs_unique']}` unique tokens)",
            f"- Missing `execution_info`: `{report['missing_execution_info_refs']}` refs (`{report['missing_execution_info_unique_tools']}` unique tools)",
            f"- Missing `memory` in `execution_info`: `{report['missing_memory_refs']}` refs (`{report['missing_memory_unique_tools']}` unique tools)",
            "",
            "## Missing execution_info tool IDs",
            "",
        ]
        for tool_id in missing_exec_unique:
            md_lines.append(f"- `{tool_id}`")

        md_lines.extend(["", "## Top unresolved refs", ""])
        for token, count in unresolved_counter.most_common(30):
            md_lines.append(f"- `{token}`: `{count}`")

        md_lines.extend(["", "## Top missing-memory tools", ""])
        for tool_id, count in mem_counter.most_common(30):
            md_lines.append(f"- `{tool_id}`: `{count}` refs")

        md_lines.extend(
            [
                "",
                "## Artifacts",
                "",
                f"- Full JSON report: `{json_out}`",
            ]
        )
        md_out.write_text("\n".join(md_lines) + "\n", encoding="utf-8")

        print(f"json_report: {json_out}")
        print(f"md_report: {md_out}")
        print(f"unresolved_refs_total: {len(unresolved_refs)}")
        print(f"missing_execution_info_unique_tools: {len(missing_exec_unique)}")
        print(f"missing_memory_unique_tools: {len(missing_mem_unique)}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

