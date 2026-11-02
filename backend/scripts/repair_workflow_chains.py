#!/usr/bin/env python3
"""Apply backend/config/chain_repairs.json to the workflow_chains table.

  python3 backend/scripts/repair_workflow_chains.py --dry-run     # diff only, changes nothing
  python3 backend/scripts/repair_workflow_chains.py               # backup DB, apply in one transaction

Per chain the spec lists connection repairs ({from_step, from_output, to_step, old_to_input,
new_to_input}) and step pins ({order, workflow_id, workflow_name}). Two optional extensions are
for chains whose steps/connections must be re-pointed wholesale (e.g. a retired step replaced by a
different workflow): a step pin may carry new_workflow_name / new_params_template, and a chain may
carry replace_connections {expect_old: [...], new: [...]} that swaps the whole connection list
(refused as drift unless the DB currently holds expect_old or new). Properties:
  * idempotent: entries already at the new value are skipped; a second run reports 'no changes';
  * drift-safe: an entry whose current value is neither old nor new is refused (reported, not applied);
  * transactional: all chains are written in one transaction, updated_at is refreshed on changed rows;
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
DEFAULT_SPEC = os.path.join(HERE, "..", "config", "chain_repairs.json")
DEFAULT_BACKUP_DIR = ("/private/tmp/claude-501/-Users-kky-biomate-review/"
                      "e2e14cda-6579-4c7a-a736-fb8889964229/scratchpad")
MIN_FREE_BYTES = int(1.2 * 1024 ** 3)


def _conn_label(c):
    t = (c.get("transform") or {}).get("name")
    return "step%s %s -> step%s %s%s" % (c.get("from_step"), c.get("from_output"), c.get("to_step"), c.get("to_input"),
                                         " [transform %s]" % t if t else "")


def plan_chain(name, spec, steps, conns, db):
    """Return (new_steps, new_conns, changes, drifts) for one chain; inputs are not mutated."""
    steps = json.loads(json.dumps(steps))
    conns = json.loads(json.dumps(conns))
    changes, drifts = [], []

    for r in spec.get("connections", []):
        match = [c for c in conns
                 if int(c.get("from_step", -1)) == int(r["from_step"])
                 and str(c.get("from_output")) == r["from_output"]
                 and int(c.get("to_step", -1)) == int(r["to_step"])]
        label = "step%s %s -> step%s" % (r["from_step"], r["from_output"], r["to_step"])
        if not match:
            drifts.append("%s: connection %s not found" % (name, label))
            continue
        # prefer a connection still at old value; else one already at new value
        cur = next((c for c in match if c.get("to_input") == r["old_to_input"]), None)
        if cur is None:
            if any(c.get("to_input") == r["new_to_input"] for c in match):
                continue  # already applied
            drifts.append("%s: %s to_input is %r, spec expects %r (refused)"
                          % (name, label, match[0].get("to_input"), r["old_to_input"]))
            continue
        cur["to_input"] = r["new_to_input"]
        changes.append("%s: %s to_input %r -> %r" % (name, label, r["old_to_input"], r["new_to_input"]))

    for s in spec.get("steps", []):
        st = next((x for x in steps if int(x.get("order", -1)) == int(s["order"])), None)
        if st is None:
            drifts.append("%s: step order %s not found" % (name, s["order"]))
            continue
        want = int(s["workflow_id"])
        new_name = s.get("new_workflow_name")
        new_tpl = s.get("new_params_template")
        pinned = st.get("workflow_id") is not None and int(st["workflow_id"]) == want
        if pinned and (not new_name or st.get("workflow_name") == new_name) \
                and (new_tpl is None or st.get("params_template") == new_tpl):
            continue  # already applied
        if st.get("workflow_id") is not None and not pinned:
            drifts.append("%s: step %s already pinned to workflow_id %s, spec wants %s (refused)"
                          % (name, s["order"], st["workflow_id"], want))
            continue
        ok_names = {s.get("workflow_name"), new_name} - {None}
        if ok_names and st.get("workflow_name") not in ok_names:
            drifts.append("%s: step %s workflow_name is %r, spec expects %r (refused)"
                          % (name, s["order"], st.get("workflow_name"), s.get("workflow_name")))
            continue
        row = db.execute("SELECT filename, executable FROM workflows WHERE id=?", (want,)).fetchone()
        if not row or not row[1]:
            drifts.append("%s: workflow_id %s missing or not executable (refused)" % (name, want))
            continue
        st["workflow_id"] = want
        if new_name:
            st["workflow_name"] = new_name
        if new_tpl is not None:
            st["params_template"] = json.loads(json.dumps(new_tpl))
        changes.append("%s: step %s pinned to workflow_id %s (%s)" % (name, s["order"], want, row[0]))

    rc = spec.get("replace_connections")
    if rc:
        old_l, new_l = rc.get("expect_old", []), rc.get("new", [])
        if conns == new_l:
            pass  # already applied
        elif conns == old_l:
            conns = json.loads(json.dumps(new_l))
            changes.append("%s: connection list replaced (%d -> %d connection(s))" % (name, len(old_l), len(new_l)))
        else:
            drifts.append("%s: connection list matches neither expect_old nor new (refused)" % name)
    return steps, conns, changes, drifts


def run(db_path, spec_path, dry_run, backup_dir, out=print):
    """Returns (n_changes, n_drifts, backup_path_or_None)."""
    with open(spec_path) as f:
        spec = json.load(f)
    ro = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db_path), uri=True)
    plans = []
    n_drift = 0
    for name, cs in spec.get("chains", {}).items():
        row = ro.execute("SELECT steps, connections FROM workflow_chains WHERE name=?", (name,)).fetchone()
        if not row:
            out("DRIFT %s: chain not found in DB" % name)
            n_drift += 1
            continue
        steps, conns = json.loads(row[0] or "[]"), json.loads(row[1] or "[]")
        new_steps, new_conns, changes, drifts = plan_chain(name, cs, steps, conns, ro)
        out("== %s" % name)
        if changes:
            for o in conns:
                if o not in new_conns:
                    out("   - %s" % _conn_label(o))
            for n in new_conns:
                if n not in conns:
                    out("   + %s" % _conn_label(n))
            for o, n in zip(steps, new_steps):
                if o != n:
                    out("   - step %s workflow_id=%s name=%s" % (o.get("order"), o.get("workflow_id"), o.get("workflow_name")))
                    out("   + step %s workflow_id=%s name=%s" % (n.get("order"), n.get("workflow_id"), n.get("workflow_name")))
        else:
            out("   no changes")
        for d in drifts:
            out("   DRIFT %s" % d)
        n_drift += len(drifts)
        if changes:
            plans.append((name, new_steps, new_conns, len(changes)))
    ro.close()
    n_changes = sum(p[3] for p in plans)
    if dry_run:
        out("dry-run: %d change(s), %d drift(s); nothing written" % (n_changes, n_drift))
        return n_changes, n_drift, None
    if not plans:
        out("no changes (%d drift(s))" % n_drift)
        return 0, n_drift, None

    free = shutil.disk_usage(backup_dir).free
    if free < MIN_FREE_BYTES:
        raise SystemExit("ABORT: only %.2f GB free in %s (need >= 1.2 GB for the DB backup)" % (free / 1024 ** 3, backup_dir))
    backup = os.path.join(backup_dir, "galaxy_ai_tools.db.pre_chain_repair.%s" % time.strftime("%Y%m%d_%H%M%S"))
    shutil.copy2(db_path, backup)
    out("backup: %s" % backup)

    rw = sqlite3.connect(db_path)
    try:
        rw.execute("BEGIN")
        now = time.strftime("%Y-%m-%dT%H:%M:%S")
        for name, steps, conns, _ in plans:
            rw.execute("UPDATE workflow_chains SET steps=?, connections=?, updated_at=? WHERE name=?",
                       (json.dumps(steps), json.dumps(conns), now, name))
        rw.commit()
    except Exception:
        rw.rollback()
        raise
    finally:
        rw.close()
    out("applied: %d change(s) in %d chain(s), %d drift(s) refused" % (n_changes, len(plans), n_drift))
    return n_changes, n_drift, backup


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
