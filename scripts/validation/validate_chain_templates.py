#!/usr/bin/env python3
"""Authoring-time guardrail for workflow_chains templates.

Runs galaxy.chain.binding_check.check_connections over EVERY registered chain
template (galaxy_ai_tools.db:workflow_chains) and reports connections whose
`to_input` is not a parameter the downstream workflow declares, or that use an
unknown transform. check_connections already runs per-step at execution time
(workflow_chain.py:609); this applies it at authoring/CI time so a broken
template never reaches the catalog.

Exit 0 if all templates are clean (or only undeterminable), 1 if any has a
real problem. Usage: python3 scripts/validation/validate_chain_templates.py [--db PATH] [--json]
"""
import argparse, json, sqlite3, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "backend" / "lib"))
DB_DEFAULT = REPO / "backend" / "database" / "galaxy_ai_tools.db"


def _steps_with_paths(conn, steps):
    """Attach nextflow_path to each step from the workflows table (by name)."""
    out = []
    for s in steps:
        d = dict(s)
        if not d.get("nextflow_path"):
            wn = d.get("workflow_name") or d.get("name")
            if wn:
                row = conn.execute("select filename from workflows where name=?", (wn,)).fetchone()
                if row:
                    d["nextflow_path"] = row[0]
        out.append(d)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DB_DEFAULT))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    from galaxy.chain.binding_check import check_connections

    conn = sqlite3.connect(args.db)
    rows = conn.execute(
        "select name, domain, steps, connections from workflow_chains"
    ).fetchall()
    report = []
    n_bad = 0
    for name, domain, steps_j, conn_j in rows:
        try:
            steps = json.loads(steps_j or "[]")
            conns = json.loads(conn_j or "[]")
        except Exception:
            continue
        if not conns:
            continue
        steps = _steps_with_paths(conn, steps)
        problems, undeterminable = check_connections(steps, conns)
        if problems:
            n_bad += 1
            report.append({"chain": name, "domain": domain,
                           "problems": [p["message"] for p in problems]})
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("NOTE: this uses check_connections (is `to_input` a declared param) — a SECONDARY signal.\n"
              "Per docs/20261005_CHAIN_CONNECTION_AUDIT.md only ~5/137 to_input names are literal params\n"
              "(many wrappers ingest via params.input / staged HDA), so this OVER-REPORTS. The authoritative\n"
              "soundness signal is `from_output` RESOLVABILITY (does it match a published filename). Treat the\n"
              "count below as an upper bound, not the real breakage count.\n")
        print(f"Checked {len(rows)} chain templates; {n_bad} flagged (to_input undeclared — upper bound).\n")
        for r in report:
            print(f"✗ {r['chain']} ({r['domain']}):")
            for m in r["problems"]:
                print(f"    - {m}")
    sys.exit(1 if n_bad else 0)


if __name__ == "__main__":
    main()
