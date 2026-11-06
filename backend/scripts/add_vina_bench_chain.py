#!/usr/bin/env python3
"""Upsert the vina_virtual_screening_bench chain into workflow_chains.

  python3 backend/scripts/add_vina_bench_chain.py --dry-run   # show the action, change nothing
  python3 backend/scripts/add_vina_bench_chain.py             # backup DB, then insert/update in one transaction

Reads backend/config/vina_bench_chain.json. Before writing, every step's pinned workflow_id is checked against the
workflows table (must exist, executable=1, filename == the step's workflow_file). Properties:
  * idempotent: an identical existing row is left alone ('no changes'); a differing row is updated in place
    (usage_count / success_rate / created_at are preserved);
  * transactional, updated_at refreshed only when something changed;
  * the DB is copied to a backup directory first (free disk >= 1.2 GB required).
Stdlib only; Python 3.9 safe.
"""
import argparse
import json
import os
import shutil
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DB = os.path.join(HERE, "..", "database", "galaxy_ai_tools.db")
DEFAULT_SPEC = os.path.join(HERE, "..", "config", "vina_bench_chain.json")
DEFAULT_BACKUP_DIR = ("/private/tmp/claude-501/-Users-kky-biomate-review/"
                      "e2e14cda-6579-4c7a-a736-fb8889964229/scratchpad")
MIN_FREE_BYTES = int(1.2 * 1024 ** 3)
JSON_COLS = ("steps", "connections", "required_inputs", "expected_outputs", "example_queries", "tags")
TEXT_COLS = ("display_name", "domain", "description", "source")


def build_row(spec):
    """Spec -> column dict (JSON columns as canonical strings); informational keys are stripped."""
    steps = []
    for s in spec["steps"]:
        steps.append({k: s[k] for k in ("order", "workflow_name", "role", "params_template", "workflow_id")})
    conns = []
    for c in spec["connections"]:
        d = {k: c[k] for k in ("from_step", "from_output", "to_step", "to_input")}
        if c.get("transform"):
            d["transform"] = c["transform"]
        conns.append(d)
    row = {"steps": steps, "connections": conns}
    for k in JSON_COLS[2:]:
        row[k] = spec.get(k, [])
    out = {k: json.dumps(row[k]) for k in JSON_COLS}
    for k in TEXT_COLS:
        out[k] = spec[k]
    return out


def check_pins(spec, db):
    """Return a list of problems with the steps' workflow_id pins (empty = ok)."""
    problems = []
    for s in spec["steps"]:
        r = db.execute("SELECT filename, executable FROM workflows WHERE id=?", (int(s["workflow_id"]),)).fetchone()
        if not r:
            problems.append("step %s: workflow_id %s not in workflows" % (s["order"], s["workflow_id"]))
        elif not r[1]:
            problems.append("step %s: workflow_id %s is not executable" % (s["order"], s["workflow_id"]))
        elif s.get("workflow_file") and r[0] != s["workflow_file"]:
            problems.append("step %s: workflow_id %s is %s, spec expects %s" % (s["order"], s["workflow_id"], r[0], s["workflow_file"]))
    return problems


def run(db_path, spec_path, dry_run, backup_dir, out=print):
    """Returns (action, backup_path_or_None); action in {'insert','update','none'}. Raises SystemExit on a bad pin."""
    with open(spec_path) as f:
        spec = json.load(f)
    want = build_row(spec)
    ro = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db_path), uri=True)
    try:
        problems = check_pins(spec, ro)
        cols = ", ".join(JSON_COLS + TEXT_COLS)
        cur = ro.execute("SELECT %s FROM workflow_chains WHERE name=?" % cols, (spec["name"],)).fetchone()
    finally:
        ro.close()
    if problems:
        for p in problems:
            out("PIN PROBLEM %s" % p)
        raise SystemExit("ABORT: %d unverifiable workflow pin(s)" % len(problems))
    if cur is None:
        action = "insert"
    else:
        have = dict(zip(JSON_COLS + TEXT_COLS, cur))
        # compare JSON columns semantically (whitespace-insensitive)
        same = all((json.loads(have[k]) == json.loads(want[k])) if k in JSON_COLS else have[k] == want[k]
                   for k in JSON_COLS + TEXT_COLS)
        action = "none" if same else "update"
    out("chain %s: %s (%d steps, %d connections)" % (spec["name"], action, len(spec["steps"]), len(spec["connections"])))
    for c in spec["connections"]:
        t = (c.get("transform") or {}).get("name")
        out("   step%s %s -> step%s %s%s" % (c["from_step"], c["from_output"], c["to_step"], c["to_input"],
                                           " [transform %s]" % t if t else ""))
    if dry_run:
        out("dry-run: nothing written")
        return action, None
    if action == "none":
        out("no changes")
        return action, None

    free = shutil.disk_usage(backup_dir).free
    if free < MIN_FREE_BYTES:
        raise SystemExit("ABORT: only %.2f GB free in %s (need >= 1.2 GB for the DB backup)" % (free / 1024 ** 3, backup_dir))
    backup = os.path.join(backup_dir, "galaxy_ai_tools.db.pre_vina_bench_chain.%s" % time.strftime("%Y%m%d_%H%M%S"))
    shutil.copy2(db_path, backup)
    out("backup: %s" % backup)

    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    rw = sqlite3.connect(db_path)
    try:
        rw.execute("BEGIN")
        if action == "insert":
            rw.execute("INSERT INTO workflow_chains (name, %s, usage_count, success_rate, created_at, updated_at) "
                       "VALUES (?, %s, 0, 0.0, ?, ?)" % (", ".join(JSON_COLS + TEXT_COLS), ", ".join("?" * len(JSON_COLS + TEXT_COLS))),
                       (spec["name"],) + tuple(want[k] for k in JSON_COLS + TEXT_COLS) + (now, now))
        else:
            rw.execute("UPDATE workflow_chains SET %s, updated_at=? WHERE name=?" % ", ".join("%s=?" % k for k in JSON_COLS + TEXT_COLS),
                       tuple(want[k] for k in JSON_COLS + TEXT_COLS) + (now, spec["name"]))
        rw.commit()
    except Exception:
        rw.rollback()
        raise
    finally:
        rw.close()
    out("applied: %s" % action)
    return action, backup


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--spec", default=DEFAULT_SPEC)
    ap.add_argument("--backup-dir", default=DEFAULT_BACKUP_DIR)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    run(a.db, a.spec, a.dry_run, a.backup_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
