#!/usr/bin/env python3
"""Pre-sync lint for curated workflow chains (read-only, stdlib only, Python 3.9 safe).

  python3 scripts/lint_workflow_chains.py [--db PATH] [--workflows-root DIR] [--required-clean a,b,c] [--all]

For every chain on the required-clean list: FAIL if a step resolves to no executable workflow, or if a connection's to_input is not a
parameter the downstream workflow declares. 'undeterminable' connections (downstream file missing / params declared elsewhere) are WARN:
listed, but they do not fail. A required chain absent from the DB is a FAIL. Other chains get a one-line count summary (--all: details).
Resolution logic is imported from scripts/audit_workflow_chains.py (one definition). See docs/20261101_WORKFLOW_CHAIN_AUDIT.md.
Exit code 0 only if every required chain passes.
"""
import argparse
import importlib.util
import json
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.join(HERE, "..", "backend")
DEFAULT_DB = os.path.join(BACKEND, "database", "galaxy_ai_tools.db")
DEFAULT_WF = os.path.join(BACKEND, "biomni_workflows")
# Chains promised to bind and resolve end to end. Add a chain here only when it passes; the others are tracked in
# docs/20261101_CHAIN_FIX_PLAN.md (andv_inhibitor_track_v1, bulk_rnaseq_de_analysis, rare_disease_multimodal_workup,
# bioc_bulk_rnaseq_de_v2 still have handoffs that need a decision or a new transform).
REQUIRED_CLEAN = [
    "vina_virtual_screening_bench",
    "drug_discovery_screening",
    "drug_discovery_admet_gated_screening",
]


def load_audit(db_path, wf_root):
    """Import audit_workflow_chains.py by path and rebind its module-level connection / workflows root."""
    spec = importlib.util.spec_from_file_location("audit_workflow_chains", os.path.join(HERE, "audit_workflow_chains.py"))
    mod = importlib.util.module_from_spec(spec)
    real_connect = sqlite3.connect
    sqlite3.connect = lambda *a, **k: real_connect(":memory:")  # the audit connects to the default DB at import time
    try:
        spec.loader.exec_module(mod)
    finally:
        sqlite3.connect = real_connect
    mod.c = real_connect("file:%s?mode=ro" % os.path.abspath(db_path), uri=True)
    mod.WF = wf_root
    return mod


def check_chain(audit, name, steps_json, conns_json):
    """Return (unresolved step names, mismatches, undeterminable) for one chain."""
    steps = json.loads(steps_json)
    paths = [audit.resolve(s.get("workflow_name"), s.get("workflow_id")) for s in steps]
    unresolved = ["step %d %s" % (i + 1, s.get("workflow_name")) for i, (s, p) in enumerate(zip(steps, paths)) if not p]
    mism, unk = [], []
    for cn in json.loads(conns_json or "[]"):
        d = int(cn["to_step"]) - 1
        fn = paths[d] if 0 <= d < len(paths) else None
        ps = audit.declared_params(fn) if fn else None
        desc = "%s -> step %s input '%s'" % (cn.get("from_step", "?"), cn["to_step"], cn["to_input"])
        if ps is None:
            unk.append(desc)
        elif cn["to_input"] not in ps:
            mism.append(desc)
    return unresolved, mism, unk


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--workflows-root", default=DEFAULT_WF)
    ap.add_argument("--required-clean", default=",".join(REQUIRED_CLEAN))
    ap.add_argument("--all", action="store_true", help="print details for non-required chains too")
    a = ap.parse_args(argv)
    if not os.path.exists(a.db):
        print("FAIL: database not found: %s" % a.db)
        return 1
    audit = load_audit(a.db, a.workflows_root)
    required = [x.strip() for x in a.required_clean.split(",") if x.strip()]
    rows = {r[0]: r for r in audit.c.execute("select name,steps,connections from workflow_chains")}
    failed = warned = 0
    for n in required:
        if n not in rows:
            print("[FAIL] %s: chain missing from DB" % n)
            failed += 1
            continue
        un, mm, uk = check_chain(audit, n, rows[n][1], rows[n][2])
        status = "FAIL" if (un or mm) else "PASS"
        failed += status == "FAIL"
        warned += len(uk)
        print("[%s] %s: %d unresolved step(s), %d mismatching connection(s), %d undeterminable" % (status, n, len(un), len(mm), len(uk)))
        for x in un:
            print("    unresolved: %s" % x)
        for x in mm:
            print("    mismatch (to_input not declared downstream): %s" % x)
        for x in uk:
            print("    WARN undeterminable: %s" % x)
    others = [n for n in sorted(rows) if n not in required]
    bad = 0
    for n in others:
        un, mm, uk = check_chain(audit, n, rows[n][1], rows[n][2])
        bad += bool(un or mm)
        if a.all:
            print("[info] %s: %d unresolved, %d mismatch, %d undeterminable" % (n, len(un), len(mm), len(uk)))
            for x in un + mm:
                print("    %s" % x)
    print("other chains: %d checked, %d with unresolved steps or mismatches (not enforced)%s" % (len(others), bad, "" if a.all else "; use --all for details"))
    print("%s: %d of %d required chains failed, %d warning(s)" % ("FAIL" if failed else "PASS", failed, len(required), warned))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
