#!/usr/bin/env python3
"""
Backfill execution_info.memory using module label + workflow-specific base.config.

Evidence chain per assignment:
- tool -> nf-core module main.nf label (e.g., process_low)
- workflow -> conf/base.config label memory value

Only writes memory when both are explicitly present.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


LABEL_RE = re.compile(r"label\s+['\"](process_[a-z_]+)['\"]", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Backfill memory from module label + workflow context")
    p.add_argument("--db", default="backend/database/galaxy_ai_tools.db")
    p.add_argument("--apply", action="store_true")
    p.add_argument(
        "--report-json",
        default="backend/database/tmp/execution_info_module_label_workflow_report.json",
    )
    return p.parse_args()


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def normalize_exec(raw: Any) -> dict[str, Any]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return dict(raw)
    text = str(raw).strip()
    if not text or text in ("{}", "null"):
        return {}
    try:
        val = json.loads(text)
    except Exception:
        return {}
    return val if isinstance(val, dict) else {}


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


def locate_workflow_dir(repo_root: Path, filename: str) -> Path | None:
    filename = (filename or "").strip()
    if not filename:
        return None
    # Absolute path stored in DB
    abs_path = Path(filename)
    if abs_path.is_absolute() and abs_path.exists():
        return abs_path.parent
    # Relative path from repo root
    rel_path = repo_root / filename
    if rel_path.exists():
        return rel_path.parent
    if filename.startswith("nfcore/") and "/subworkflows/" not in filename and "/modules/" not in filename:
        rel = filename[len("nfcore/") :]
        p = repo_root / "backend" / "nf-core-workflows" / rel
        if p.exists():
            return p.parent
    if filename.startswith("backend/nf-core-workflows/"):
        p = repo_root / filename
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
    if "backend/biomni_workflows/nextflow_nfcore/" in filename:
        i = filename.index("backend/biomni_workflows/nextflow_nfcore/")
        p = repo_root / filename[i:]
        if p.exists():
            return p.parent
    return None


def parse_base_config_label_memory(base_config_path: Path) -> dict[str, float]:
    text = base_config_path.read_text(encoding="utf-8", errors="ignore")
    out: dict[str, float] = {}
    for label in ("process_single", "process_low", "process_medium", "process_high", "process_high_memory"):
        patterns = [
            rf"withLabel:\s*{label}\s*\{{[\s\S]*?memory\s*=\s*\{{\s*check_max\(\s*([0-9]+(?:\.[0-9]+)?)\.GB",
            rf"withLabel:\s*{label}\s*\{{[\s\S]*?memory\s*=\s*\{{\s*([0-9]+(?:\.[0-9]+)?)\.GB",
        ]
        v = None
        for p in patterns:
            m = re.search(p, text, flags=re.IGNORECASE)
            if m:
                v = float(m.group(1))
                break
        if v is not None:
            out[label] = v
    return out


def extract_label_from_module(main_nf_path: Path) -> str | None:
    txt = main_nf_path.read_text(encoding="utf-8", errors="ignore")
    m = LABEL_RE.search(txt)
    return m.group(1) if m else None


def candidate_module_paths(repo_root: Path, tool_id: str) -> list[Path]:
    module_root = repo_root / "backend" / "nf-core-modules" / "modules" / "nf-core"
    paths: list[Path] = []
    tid = tool_id.strip()
    if not tid:
        return paths

    cands = set()
    if "/" in tid and not tid.startswith("toolshed.g2.bx.psu.edu/"):
        cands.add(tid)
        cands.add(tid.replace("_", "/"))

    parts = tid.split("/")
    if tid.startswith("toolshed.g2.bx.psu.edu/") and len(parts) >= 2:
        # typically .../repos/<owner>/<repo>/<tool>/<version>
        if len(parts) >= 4:
            repo = parts[-3]
            tool = parts[-2]
            cands.add(repo)
            cands.add(tool)
            cands.add(repo.replace("_", "/"))
            cands.add(tool.replace("_", "/"))

    # e.g., ensemblvep_vep -> ensemblvep/vep
    cands.add(tid.replace("_", "/"))

    for c in sorted(cands):
        c = c.strip("/")
        if not c:
            continue
        p = module_root / c / "main.nf"
        if p.exists():
            paths.append(p)
    return paths


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    repo_root = Path(__file__).resolve().parents[2]

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        workflows = cur.fetchall()
        cur.execute("SELECT tool_id, name, execution_info FROM tools")
        tool_rows = cur.fetchall()

        by_id = {str(r["tool_id"]).lower(): r for r in tool_rows if r["tool_id"]}
        by_name = {str(r["name"]).lower(): r for r in tool_rows if r["name"]}

        def resolve(ref: str):
            cands = [ref]
            if "/" in ref:
                cands.append(ref.split("/")[-1])
            for c in cands:
                row = by_id.get(c.lower()) or by_name.get(c.lower())
                if row:
                    return row
            p = ref.lower()
            for r in tool_rows:
                tid = str(r["tool_id"] or "").lower()
                nm = str(r["name"] or "").lower()
                if p and (p in tid or p in nm):
                    return r
            return None

        # Build workflow-specific label-memory maps
        wf_label_mem: dict[str, dict[str, float]] = {}
        for wf in workflows:
            wf_dir = locate_workflow_dir(repo_root, str(wf["filename"]))
            if not wf_dir:
                continue
            base_cfg = wf_dir / "conf" / "base.config"
            if base_cfg.exists():
                wf_label_mem[str(wf["filename"])] = parse_base_config_label_memory(base_cfg)

        # Determine module label per tool candidate
        tool_label: dict[str, tuple[str, str]] = {}  # tool_id -> (label, module_path)
        unresolved_label = []
        for tr in tool_rows:
            tid = str(tr["tool_id"] or "")
            if not tid:
                continue
            info = normalize_exec(tr["execution_info"])
            if "memory" in info and str(info.get("memory", "")).strip():
                continue
            module_paths = candidate_module_paths(repo_root, tid)
            labels = []
            for mp in module_paths:
                lbl = extract_label_from_module(mp)
                if lbl:
                    labels.append((lbl, str(mp.relative_to(repo_root))))
            labels_unique = sorted(set(labels))
            if len(labels_unique) == 1:
                tool_label[tid] = labels_unique[0]
            elif len(labels_unique) > 1:
                unresolved_label.append({"tool_id": tid, "reason": "multiple_labels", "labels": labels_unique})

        # Aggregate memory evidence from workflow contexts
        tool_mem_values: dict[str, list[float]] = defaultdict(list)
        tool_sources: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for wf in workflows:
            wf_file = str(wf["filename"])
            refs = parse_tools_used(wf["tools_used"])
            label_mem = wf_label_mem.get(wf_file, {})
            if not label_mem:
                continue
            for ref in refs:
                row = resolve(ref)
                if not row:
                    continue
                tid = str(row["tool_id"] or "")
                if tid not in tool_label:
                    continue
                label, module_path = tool_label[tid]
                mem = label_mem.get(label)
                if mem is None:
                    continue
                tool_mem_values[tid].append(mem)
                tool_sources[tid].append(
                    {
                        "workflow": str(wf["name"]),
                        "filename": wf_file,
                        "label": label,
                        "memory_gb": mem,
                        "module_main": module_path,
                    }
                )

        updates = []
        for tr in tool_rows:
            tid = str(tr["tool_id"] or "")
            if tid not in tool_mem_values:
                continue
            info = normalize_exec(tr["execution_info"])
            if "memory" in info and str(info.get("memory", "")).strip():
                continue
            mem = max(tool_mem_values[tid])
            new_info = dict(info)
            new_info["memory"] = f"{mem}GB"
            new_info["evidence_source"] = {
                "type": "module_label_workflow_base_config",
                "samples": tool_sources[tid][:20],
                "count": len(tool_sources[tid]),
                "resolved_at": datetime.now(timezone.utc).isoformat(),
            }
            updates.append((json.dumps(new_info), tid))

        backup = None
        if args.apply and updates:
            backup = backup_db(db_path)
            cur.executemany("UPDATE tools SET execution_info = ? WHERE tool_id = ?", updates)
            conn.commit()

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "apply": args.apply,
            "tools_with_single_module_label": len(tool_label),
            "tools_with_memory_evidence": len(tool_mem_values),
            "updates": len(updates),
            "unresolved_label_cases": unresolved_label[:200],
            "backup_file": str(backup) if backup else None,
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"tools_with_single_module_label: {len(tool_label)}")
        print(f"tools_with_memory_evidence: {len(tool_mem_values)}")
        print(f"updates: {len(updates)}")
        if backup:
            print(f"backup_file: {backup}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

