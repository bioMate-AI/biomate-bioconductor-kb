#!/usr/bin/env python3
"""Pin workflow_id on every step of the 4 bioconductor handoff chains.

After this script runs each chain step JSON carries:

    {order, workflow_name, workflow_id, role, params_template}

The resolver in workflow_chain.py (resolve_workflow_name_to_path) checks
workflow_id first — pinning makes chain execution deterministic across
re-indexing, where the LIMIT 1 name-cascade can otherwise re-pick a
different row of the same name (e.g. one of 12 'deseq2' rows).

Idempotent: re-running on an already-pinned chain skips it.
Dry-run by default; pass --apply to write.

Strategy per step:
  1. Resolve via the existing cascade (which already handles the
     BIOC_<PKG> prefix-strip and the 7-query fallback).
  2. SELECT id FROM workflows WHERE filename = <resolved_path>.
  3. Persist that id back into steps[].workflow_id.

If the cascade returns nothing for a step, log a warning and leave
the step untouched (the runner will hit the same dead end at runtime
either way — pinning a missing id is no better than not pinning).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sqlite3
import sys
from typing import Any, Dict, List, Optional

BIOC_CHAINS = [
    "bulk_rnaseq_de_analysis",
    "scrna_consensus_de_bioc",
    "methylation_450k_array_analysis",
    "scrna_pseudobulk_de_bioc",
]

DB_PATH = os.path.join(
    os.path.dirname(__file__), "..", "database", "galaxy_ai_tools.db"
)

log = logging.getLogger("pin_bioc_chain_workflow_ids")
logging.basicConfig(level=logging.INFO, format="%(message)s")


def _resolver():
    """Import the production resolver — same cascade the runner uses."""
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
    from galaxy.webapps.galaxy.api.workflow_chain import (  # noqa: PLC0415
        resolve_workflow_name_to_path,
    )
    return resolve_workflow_name_to_path


def _id_for_filename(conn: sqlite3.Connection, filename: str) -> Optional[int]:
    row = conn.execute(
        "SELECT id FROM workflows WHERE filename=? AND executable=1 LIMIT 1",
        (filename,),
    ).fetchone()
    return int(row[0]) if row and row[0] is not None else None


def pin_chain(conn: sqlite3.Connection, chain_name: str, resolve, apply: bool) -> Dict[str, Any]:
    row = conn.execute(
        "SELECT id, steps FROM workflow_chains WHERE name=?", (chain_name,)
    ).fetchone()
    if not row:
        return {"chain": chain_name, "status": "missing"}
    chain_id, steps_json = row
    steps: List[Dict[str, Any]] = json.loads(steps_json) if steps_json else []
    if not steps:
        return {"chain": chain_name, "status": "no_steps"}

    already_pinned = all("workflow_id" in s for s in steps)
    if already_pinned:
        return {"chain": chain_name, "status": "already_pinned", "steps": len(steps)}

    report = {"chain": chain_name, "id": chain_id, "steps": []}
    changed = False
    for step in steps:
        wname = step.get("workflow_name") or ""
        if not wname:
            report["steps"].append({"order": step.get("order"), "status": "no_name"})
            continue
        if "workflow_id" in step and step["workflow_id"]:
            report["steps"].append({
                "order": step.get("order"),
                "workflow_name": wname,
                "status": "skip_pinned",
                "workflow_id": step["workflow_id"],
            })
            continue
        path = resolve(wname)
        if not path:
            report["steps"].append({
                "order": step.get("order"),
                "workflow_name": wname,
                "status": "unresolved",
            })
            continue
        wid = _id_for_filename(conn, path)
        if wid is None:
            report["steps"].append({
                "order": step.get("order"),
                "workflow_name": wname,
                "path": path,
                "status": "no_id_for_path",
            })
            continue
        step["workflow_id"] = wid
        changed = True
        report["steps"].append({
            "order": step.get("order"),
            "workflow_name": wname,
            "path": path,
            "workflow_id": wid,
            "status": "pinned",
        })

    if changed and apply:
        conn.execute(
            "UPDATE workflow_chains SET steps=? WHERE id=?",
            (json.dumps(steps), chain_id),
        )
        conn.commit()
        report["written"] = True
    elif changed:
        report["written"] = False
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true",
                    help="Write pinned ids to DB (default: dry-run).")
    ap.add_argument("--chain", action="append",
                    help="Specific chain name to pin (default: 4 bioc chains).")
    args = ap.parse_args()

    chains = args.chain or BIOC_CHAINS
    db = os.path.normpath(DB_PATH)
    if not os.path.exists(db):
        log.error("DB not found: %s", db)
        return 1
    resolve = _resolver()
    with sqlite3.connect(db) as conn:
        for c in chains:
            report = pin_chain(conn, c, resolve, args.apply)
            log.info("=== %s ===", c)
            log.info(json.dumps(report, indent=2, default=str))
    if not args.apply:
        log.info("\n(dry-run; re-run with --apply to persist)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
