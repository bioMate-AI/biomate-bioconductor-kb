#!/usr/bin/env python3
"""
Prioritize remaining execution_info.memory gaps with evidence paths.

Read-only analysis: no DB modifications.
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
    parser = argparse.ArgumentParser(description="Prioritize memory-gap closure tasks")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db")
    parser.add_argument("--top", type=int, default=50)
    parser.add_argument(
        "--json-out",
        default="backend/database/tmp/memory_gap_priority_report.json",
    )
    parser.add_argument(
        "--md-out",
        default="docs/QC/20260311_MEMORY_GAP_PRIORITY_REPORT.md",
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


def locate_workflow_dir(repo_root: Path, filename: str) -> Path | None:
    filename = (filename or "").strip()
    if not filename:
        return None
    if filename.startswith("nfcore/") and "/subworkflows/" not in filename and "/modules/" not in filename:
        rel = filename[len("nfcore/") :]
        p = repo_root / "backend" / "nf-core-workflows" / rel
        if p.exists():
            return p.parent
    if filename.startswith("nfcore/subworkflows/"):
        rel = filename[len("nfcore/subworkflows/") :]
        p_rel = rel if rel.endswith(".nf") else f"{rel}/main.nf"
        p = repo_root / "backend" / "nf-core-modules" / "subworkflows" / "nf-core" / p_rel
        if p.exists():
            return p.parent
    if filename.startswith("nfcore/modules/"):
        rel = filename[len("nfcore/modules/") :]
        p_rel = rel if rel.endswith(".nf") else f"{rel}/main.nf"
        p = repo_root / "backend" / "nf-core-modules" / "modules" / "nf-core" / p_rel
        if p.exists():
            return p.parent
    if filename.startswith("biomni_nf/"):
        rel = filename[len("biomni_nf/") :]
        p = repo_root / "backend" / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / rel
        if p.exists():
            return p.parent
        p2 = repo_root / "backend" / "biomni_workflows" / "nextflow_nfcore" / "workflows" / rel
        if p2.exists():
            return p2.parent
    return None


def find_evidence_files(wf_dir: Path, repo_root: Path) -> dict[str, list[str]]:
    cfg_files: list[str] = []
    trace_files: list[str] = []

    for p in [wf_dir / "nextflow.config", wf_dir / "main.nf"]:
        if p.exists():
            cfg_files.append(str(p.relative_to(repo_root)))

    conf_dir = wf_dir / "conf"
    if conf_dir.exists():
        for p in sorted(conf_dir.rglob("*.config")):
            cfg_files.append(str(p.relative_to(repo_root)))

    for p in sorted(wf_dir.rglob("trace*.txt")):
        trace_files.append(str(p.relative_to(repo_root)))
    for p in sorted(wf_dir.rglob(".nextflow.log*")):
        trace_files.append(str(p.relative_to(repo_root)))

    return {"config_files": cfg_files[:20], "trace_files": trace_files[:20]}


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    json_out = Path(args.json_out).resolve()
    md_out = Path(args.md_out).resolve()
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    repo_root = Path(__file__).resolve().parents[2]

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        workflows = cur.fetchall()
        cur.execute("SELECT tool_id, name, category, availability_status, execution_info FROM tools")
        tools = cur.fetchall()

        by_id = {str(r["tool_id"]).lower(): r for r in tools if r["tool_id"]}
        by_name = {str(r["name"]).lower(): r for r in tools if r["name"]}

        def resolve(ref: str):
            cands = [ref]
            if "/" in ref:
                cands.append(ref.split("/")[-1])
            for c in cands:
                row = by_id.get(c.lower()) or by_name.get(c.lower())
                if row:
                    return row
            patt = ref.lower()
            for r in tools:
                tid = str(r["tool_id"] or "").lower()
                nm = str(r["name"] or "").lower()
                if patt and (patt in tid or patt in nm):
                    return r
            return None

        refs_by_tool = Counter()
        wf_context: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for wf in workflows:
            refs = parse_tools_used(wf["tools_used"])
            for ref in refs:
                row = resolve(ref)
                if not row:
                    continue
                tool_id = str(row["tool_id"])
                info = normalize_exec(row["execution_info"])
                if not info or "memory" not in info:
                    refs_by_tool[tool_id] += 1
                    wf_context[tool_id].append(
                        {
                            "workflow": wf["name"],
                            "filename": wf["filename"],
                        }
                    )

        ranked = refs_by_tool.most_common(args.top)
        entries = []
        for tool_id, ref_count in ranked:
            row = by_id.get(tool_id.lower())
            if not row:
                continue
            contexts = wf_context.get(tool_id, [])
            evidence_paths = []
            for c in contexts[:5]:
                wf_dir = locate_workflow_dir(repo_root, c["filename"])
                if wf_dir is None:
                    continue
                paths = find_evidence_files(wf_dir, repo_root)
                evidence_paths.append(
                    {
                        "workflow": c["workflow"],
                        "filename": c["filename"],
                        **paths,
                    }
                )

            category = str(row["category"] or "")
            availability = str(row["availability_status"] or "")
            if category == "nextflow_token":
                action = "Promote token to canonical tool mapping or extract per-process resource docs."
            elif availability == "installable":
                action = "Pull memory evidence from tool wrapper docs or runtime traces."
            else:
                action = "Collect explicit memory from workflow process directives or execution traces."

            entries.append(
                {
                    "tool_id": tool_id,
                    "tool_name": str(row["name"] or tool_id),
                    "category": category,
                    "availability_status": availability,
                    "ref_count": ref_count,
                    "recommended_action": action,
                    "evidence_paths": evidence_paths,
                }
            )

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "top_n": args.top,
            "total_tools_missing_memory": len(refs_by_tool),
            "top_entries": entries,
        }
        json_out.write_text(json.dumps(report, indent=2), encoding="utf-8")

        lines = [
            "# Memory Gap Priority Report",
            "",
            f"- Generated: `{report['timestamp_utc']}`",
            f"- DB: `{db_path}`",
            f"- Tools missing memory (unique): `{report['total_tools_missing_memory']}`",
            f"- Ranked entries included: `{len(entries)}`",
            "",
            "## Top Priority List",
            "",
        ]
        for e in entries:
            lines.append(
                f"- `{e['tool_id']}` ({e['ref_count']} refs) | category=`{e['category']}` | action: {e['recommended_action']}"
            )
        lines.extend(
            [
                "",
                "## Artifacts",
                "",
                f"- JSON: `{json_out}`",
            ]
        )
        md_out.write_text("\n".join(lines) + "\n", encoding="utf-8")

        print(f"json_report: {json_out}")
        print(f"md_report: {md_out}")
        print(f"total_tools_missing_memory: {len(refs_by_tool)}")
        print(f"ranked_entries: {len(entries)}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

