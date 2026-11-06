#!/usr/bin/env python3
"""Register the Pharma-Chemist Experience KB into BioMate's product surface.

The KB (experience_kb.resolve) is the authoritative in-code store. This script SURFACES it in the product so
the composer / param-prefill see KB-driven defaults, via the existing `tools.scientific_context_v2` column of
the workflow DB (galaxy_ai_tools.db).

HONEST CONSTRAINT: that DB is ~324 MB and gitignored — the canonical copy lives on dev/S3, the local file is a
copy. So this script is DRY-RUN by default (prints the UPDATEs it would make, writes nothing). `--apply` writes
to the --db target; the canonical production apply is the dev step documented below, not a local force-write.

Read path for the product: `kb_defaults_for(target)` returns the KB-resolved {tool_params, eval_criteria,
provenance} — param-prefill / the composer call this directly (resolve() is code, no DB round-trip needed);
the registered scientific_context_v2 is the persisted, searchable surface of the same knowledge.

Usage:
  python register_experience_kb.py                 # dry-run: show what would be written
  python register_experience_kb.py --apply --db <path>   # write (run against the DEV db, not a stale local copy)
"""
from __future__ import annotations
import os, sys, json, glob, argparse, sqlite3, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import experience_kb as kb

PARENT = os.path.dirname(HERE)
DEFAULT_DB = os.path.join(os.path.dirname(os.path.dirname(PARENT)), "backend", "database", "galaxy_ai_tools.db")
# physics tools the KB guidance attaches to (name match in the `tools` table)
TOOL_NAME_HINTS = ("cofold", "mmgbsa", "mm-gbsa", "mm_gbsa", "openfe", "rbfe", "gromacs", "boltz", "fep")
KB_MARKER = "[experience_kb]"   # idempotency marker so re-apply merges, never duplicates


# suffixes that mark non-canonical artifacts in target_kb/ (induced rules, generated/loop/neural scratch), not targets
_ARTIFACT_MARKERS = ("_induced_rule", "_generated_", "_loop_result", "_neural_", "_result", "_HX")


def kb_targets() -> list[str]:
    """Canonical targets the KB knows about = target_kb/*.json minus the non-target scratch artifacts."""
    tk = os.path.join(HERE, "target_kb")
    names = (os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(tk, "*.json")))
    return sorted(n for n in names if not any(m in n for m in _ARTIFACT_MARKERS))


def kb_defaults_for(target: str) -> dict:
    """READ PATH: KB-resolved defaults for a target, for the composer / param-prefill (wraps resolve)."""
    return kb.resolve(target)


def _context_payload(target: str) -> dict:
    """Compact, provenance-tiered KB context for a target — the scientific_context_v2 addendum."""
    r = kb.resolve(target)
    return {
        "marker": KB_MARKER, "target": target, "target_class": r["target_class"],
        "tool_params": r["tool_params"],
        "eval_criteria": [{"criterion": c["criterion"], "mode": c["mode"],
                           "tier": c["tier"], "verified": c["verified"]} for c in r["eval_criteria"]],
        "provenance": [{"entry": p["entry"], "tier": p["tier"], "verified": p["verified"]}
                       for p in r["provenance"]],
        "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    }


def _physics_tool_ids(con) -> list[tuple]:
    cur = con.cursor()
    try:
        cur.execute("SELECT id, name FROM tools")
    except Exception:
        return []
    rows = cur.fetchall()
    out = []
    for tid, name in rows:
        nm = (name or "").lower()
        if any(h in nm for h in TOOL_NAME_HINTS):
            out.append((tid, name))
    return out


def register(db_path: str, apply: bool) -> dict:
    targets = kb_targets()
    payloads = {t: _context_payload(t) for t in targets}
    kb_block = {"experience_kb": {"version": "1.0-firstslice", "targets": payloads}}
    plan = {"db": db_path, "apply": apply, "targets": targets, "tool_updates": [], "note": None}
    if not os.path.exists(db_path):
        plan["note"] = f"DB not found at {db_path} — dev-apply step required (canonical DB is on dev/S3)."
        return plan
    con = sqlite3.connect(db_path)
    try:
        tools = _physics_tool_ids(con)
        plan["tool_updates"] = [{"tool_id": tid, "name": nm} for tid, nm in tools]
        if apply:
            cur = con.cursor()
            now = datetime.datetime.utcnow().isoformat() + "Z"
            for tid, nm in tools:
                cur.execute("SELECT scientific_context_v2 FROM tools WHERE id=?", (tid,))
                row = cur.fetchone()
                existing = {}
                if row and row[0]:
                    try:
                        existing = json.loads(row[0]) if isinstance(row[0], str) else dict(row[0])
                    except Exception:
                        existing = {"_prior_nonjson": str(row[0])[:200]}
                existing.update(kb_block)                     # merge under the experience_kb key (idempotent)
                cur.execute("UPDATE tools SET scientific_context_v2=?, scientific_context_v2_at=? WHERE id=?",
                            (json.dumps(existing), now, tid))
            con.commit()
            plan["applied"] = len(tools)
    finally:
        con.close()
    return plan


def main():
    ap = argparse.ArgumentParser(description="Register the Experience KB into tools.scientific_context_v2")
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--apply", action="store_true", help="WRITE (run against the dev DB, not a stale local copy)")
    a = ap.parse_args()
    plan = register(a.db, a.apply)
    print(json.dumps(plan, indent=2, default=str))
    if not a.apply:
        print("\nDRY-RUN — nothing written. KB targets:", ", ".join(plan["targets"]))
        print(f"Would attach the KB context block to {len(plan.get('tool_updates', []))} physics tool(s).")
        print("PRODUCTION APPLY (dev): run `--apply --db <dev galaxy_ai_tools.db>` on dev (NOT the local copy),")
        print("then let the normal DB sync carry it; locally the read path is kb_defaults_for(target).")


if __name__ == "__main__":
    main()
