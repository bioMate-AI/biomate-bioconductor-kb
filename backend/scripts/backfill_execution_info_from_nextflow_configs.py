#!/usr/bin/env python3
"""
Backfill tools.execution_info using evidence extracted from Nextflow configs.

Evidence sources:
- workflow-local `nextflow.config`
- workflow `main.nf` directives (fallback)

This script is evidence-only:
- sets `gpu=true` only when explicit GPU signals are detected
- sets `memory` only when explicit memory directives are detected
- never guesses defaults
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class WorkflowRow:
    name: str
    filename: str
    tools_used: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill execution_info from Nextflow config evidence.")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument("--apply", action="store_true", help="Persist updates")
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/execution_info_nextflow_evidence_report.json",
        help="Report path",
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


def to_gb(value: float, unit: str) -> float:
    u = unit.lower()
    if u in ("gb", "gib", "g"):
        return value
    return value / 1024.0


def extract_config_evidence(text: str) -> tuple[bool, float | None]:
    lower = text.lower()
    # Conservative policy:
    # workflow-level config may mention GPU for only a subset of processes.
    # Do not assign tool-level gpu=true from workflow-wide evidence.
    gpu = False

    memory_vals: list[float] = []
    for m in re.finditer(r"memory\s*=\s*['\"]?\s*(\d+(?:\.\d+)?)\s*\.?\s*(gb|gib|g|mb|mib|m)\b", lower):
        memory_vals.append(to_gb(float(m.group(1)), m.group(2)))

    # fallback for params like max_memory = '25.MB'
    for m in re.finditer(r"(\d+(?:\.\d+)?)\s*\.?\s*(gb|gib|g|mb|mib|m)\b", lower):
        memory_vals.append(to_gb(float(m.group(1)), m.group(2)))

    memory_gb = max(memory_vals) if memory_vals else None
    return gpu, round(memory_gb, 2) if memory_gb is not None else None


def locate_workflow_dir(repo_root: Path, filename: str) -> Path | None:
    filename = (filename or "").strip()
    if not filename:
        return None

    # Candidate 1: nf-core top-level workflows (db path: nfcore/<pipeline>/main.nf)
    if filename.startswith("nfcore/") and "/subworkflows/" not in filename and "/modules/" not in filename:
        rel = filename[len("nfcore/") :]
        p = repo_root / "backend" / "nf-core-workflows" / rel
        if p.exists():
            return p.parent

    # Candidate 1b: nf-core subworkflows (db path may omit main.nf)
    if filename.startswith("nfcore/subworkflows/"):
        rel = filename[len("nfcore/subworkflows/") :]
        # if rel already includes main.nf keep as-is, else append
        p_rel = rel if rel.endswith(".nf") else f"{rel}/main.nf"
        p = repo_root / "backend" / "nf-core-modules" / "subworkflows" / "nf-core" / p_rel
        if p.exists():
            return p.parent

    # Candidate 1c: nf-core modules
    if filename.startswith("nfcore/modules/"):
        rel = filename[len("nfcore/modules/") :]
        p_rel = rel if rel.endswith(".nf") else f"{rel}/main.nf"
        p = repo_root / "backend" / "nf-core-modules" / "modules" / "nf-core" / p_rel
        if p.exists():
            return p.parent

    # Candidate 2: biomni nextflow nfcore subworkflows
    if filename.startswith("biomni_nf/"):
        rel = filename[len("biomni_nf/") :]
        p = repo_root / "backend" / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / rel
        if p.exists():
            return p.parent
        p2 = repo_root / "backend" / "biomni_workflows" / "nextflow_nfcore" / "workflows" / rel
        if p2.exists():
            return p2.parent

    # Candidate 3: direct under nextflow_nfcore
    p3 = repo_root / "backend" / "biomni_workflows" / "nextflow_nfcore" / filename
    if p3.exists():
        return p3.parent

    return None


def collect_evidence_files(wf_dir: Path, repo_root: Path) -> list[Path]:
    files: list[Path] = []
    nextflow_cfg = wf_dir / "nextflow.config"
    main_nf = wf_dir / "main.nf"
    if nextflow_cfg.exists():
        files.append(nextflow_cfg)
    if main_nf.exists():
        files.append(main_nf)

    conf_dir = wf_dir / "conf"
    if conf_dir.exists():
        for p in sorted(conf_dir.rglob("*.config")):
            files.append(p)

    # Keep unique order
    seen = set()
    unique = []
    for f in files:
        key = str(f.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(f)
    return unique


def normalize_execution_info(raw: Any) -> dict[str, Any]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return dict(raw)
    text = str(raw).strip()
    if not text or text.lower() == "null":
        return {}
    try:
        parsed = json.loads(text)
    except Exception:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        workflows = [WorkflowRow(r["name"], r["filename"], r["tools_used"]) for r in cur.fetchall()]

        cur.execute("SELECT tool_id, name, execution_info FROM tools")
        tool_rows = cur.fetchall()
        by_tool_id = {str(r["tool_id"]).lower(): r for r in tool_rows if r["tool_id"]}
        by_name = {str(r["name"]).lower(): r for r in tool_rows if r["name"]}

        def resolve_tool(ref: str):
            candidates = [ref]
            if "/" in ref:
                candidates.append(ref.split("/")[-1])
            for cand in candidates:
                row = by_tool_id.get(cand.lower()) or by_name.get(cand.lower())
                if row:
                    return row
            patt = ref.lower()
            for row in tool_rows:
                tid = str(row["tool_id"] or "").lower()
                name = str(row["name"] or "").lower()
                if patt and (patt in tid or patt in name):
                    return row
            return None

        # aggregate evidence by tool_id
        tool_evidence: dict[str, dict[str, Any]] = defaultdict(lambda: {"gpu": False, "memory_gb": None, "sources": []})
        unmatched_refs: list[dict[str, str]] = []
        missing_workflow_paths: list[str] = []
        workflows_with_evidence = 0

        for wf in workflows:
            wf_dir = locate_workflow_dir(repo_root, wf.filename)
            if not wf_dir:
                missing_workflow_paths.append(wf.filename)
                continue

            evidence_gpu = False
            evidence_mem = None
            source_files: list[str] = []

            for ev_file in collect_evidence_files(wf_dir, repo_root):
                text = ev_file.read_text(encoding="utf-8", errors="ignore")
                g, m = extract_config_evidence(text)
                evidence_gpu = evidence_gpu or g
                if m is not None:
                    evidence_mem = m if evidence_mem is None else max(evidence_mem, m)
                source_files.append(str(ev_file.relative_to(repo_root)))

            if not evidence_gpu and evidence_mem is None:
                continue

            workflows_with_evidence += 1
            refs = parse_tools_used(wf.tools_used)
            for ref in refs:
                row = resolve_tool(ref)
                if not row:
                    unmatched_refs.append({"workflow": wf.name, "filename": wf.filename, "tool_ref": ref})
                    continue

                tool_id = str(row["tool_id"] or "").strip()
                if not tool_id:
                    unmatched_refs.append({"workflow": wf.name, "filename": wf.filename, "tool_ref": ref})
                    continue

                ev = tool_evidence[tool_id]
                ev["gpu"] = ev["gpu"] or evidence_gpu
                if evidence_mem is not None:
                    ev["memory_gb"] = evidence_mem if ev["memory_gb"] is None else max(ev["memory_gb"], evidence_mem)
                ev["sources"].append(
                    {
                        "workflow": wf.name,
                        "filename": wf.filename,
                        "evidence_files": source_files,
                        "gpu": evidence_gpu,
                        "memory_gb": evidence_mem,
                    }
                )

        updates = []
        for tool_id, ev in tool_evidence.items():
            row = by_tool_id.get(tool_id.lower())
            if not row:
                continue
            current = normalize_execution_info(row["execution_info"])
            new_info = dict(current)
            changed = False

            # Intentionally do not set gpu from workflow-level evidence.
            if ev["memory_gb"] is not None and ("memory" not in new_info or not str(new_info.get("memory", "")).strip()):
                new_info["memory"] = f"{ev['memory_gb']}GB"
                changed = True

            if changed:
                srcs = ev["sources"][:20]
                new_info["evidence_source"] = {
                    "type": "nextflow_config_extract",
                    "count": len(ev["sources"]),
                    "samples": srcs,
                }
                updates.append(
                    {
                        "tool_id": tool_id,
                        "tool_name": row["name"],
                        "old_info": current if current else None,
                        "new_info": new_info,
                    }
                )

        backup_file = None
        if args.apply and updates:
            backup_file = backup_db(db_path)
            cur = conn.cursor()
            for u in updates:
                cur.execute("UPDATE tools SET execution_info = ? WHERE tool_id = ?", (json.dumps(u["new_info"]), u["tool_id"]))
            conn.commit()

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "apply": args.apply,
            "workflows_total": len(workflows),
            "workflows_with_detected_resource_evidence": workflows_with_evidence,
            "tools_with_aggregated_evidence": len(tool_evidence),
            "updated_tools": len(updates),
            "unmatched_refs": len(unmatched_refs),
            "missing_workflow_paths": len(missing_workflow_paths),
            "backup_file": str(backup_file) if backup_file else None,
            "sample_missing_workflow_paths": missing_workflow_paths[:50],
            "sample_unmatched_refs": unmatched_refs[:120],
            "sample_updates": updates[:120],
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"workflows_total: {len(workflows)}")
        print(f"workflows_with_detected_resource_evidence: {workflows_with_evidence}")
        print(f"tools_with_aggregated_evidence: {len(tool_evidence)}")
        print(f"updated_tools: {len(updates)}")
        print(f"unmatched_refs: {len(unmatched_refs)}")
        print(f"missing_workflow_paths: {len(missing_workflow_paths)}")
        if backup_file:
            print(f"backup_file: {backup_file}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

