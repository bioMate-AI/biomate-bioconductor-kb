"""Backfill workflows.description from .nf header comments where the DB
description is broken — i.e. it's a substring of the workflow name (parent-
package leak), or the literal "Bioconductor module: <pkg>" auto-extraction
failure string.

Header format expected (consistent across the bioconductor subworkflows):

    #!/usr/bin/env nextflow
    // ============================================================
    // Bioconductor workflow: <pkg> — <role>
    // <one-line description>          <-- this line is what we want
    // Input: ...

Strategy: parse the line immediately after the `// Bioconductor workflow:` /
`// nextflow workflow:` / `// Workflow:` line. Strip the leading `// `.
Reject if the candidate is itself trivial (empty, just the package name,
or shorter than the original).

Usage:
    python scripts/backfill_descriptions_from_nf_headers.py --dry-run
    python scripts/backfill_descriptions_from_nf_headers.py --apply [--limit N]
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import time
from pathlib import Path

DB = Path(__file__).resolve().parents[1] / "database" / "galaxy_ai_tools.db"
WORKFLOWS_ROOT = Path(__file__).resolve().parents[1] / "biomni_workflows"

_HEADER_PATTERNS = [
    re.compile(r"^//\s*Bioconductor workflow:.*$", re.IGNORECASE),
    re.compile(r"^//\s*Bioconductor module:.*$", re.IGNORECASE),
    re.compile(r"^//\s*Nextflow workflow:.*$", re.IGNORECASE),
    re.compile(r"^//\s*Workflow:.*$", re.IGNORECASE),
]
_DESC_LINE = re.compile(r"^//\s*(?P<desc>.+?)\s*$")
_REJECT_PREFIXES = (
    "input:", "output:", "container:", "r packages:", "bioconductor:",
    "requires:", "visualizations:", "generated", "document-derived",
    "steps:", "============", "tools:", "category:", "tags:",
)


def is_broken(description: str, name: str) -> bool:
    if not description:
        return True
    d = description.strip()
    if not d:
        return True
    if d == name:
        return True
    if d.lower().startswith("bioconductor module:"):
        return True
    # description is a short substring of name (parent-package leak: e.g.
    # name='chipseeker_peak_annotation', description='chipseeker')
    if len(d) <= 30 and d.lower() in name.lower() and d.lower() != name.lower():
        return True
    return False


def extract_description_from_nf(nf_path: Path) -> str | None:
    """Read the .nf header and return the one-line description.

    Returns None if no plausible description line is found.
    """
    try:
        with nf_path.open("r", encoding="utf-8", errors="replace") as fh:
            lines = [fh.readline() for _ in range(25)]
    except OSError:
        return None

    # Locate the header line that names the workflow.
    for i, line in enumerate(lines):
        if any(p.match(line.strip()) for p in _HEADER_PATTERNS):
            # The next non-trivial `// ` line is the description.
            for j in range(i + 1, min(i + 5, len(lines))):
                m = _DESC_LINE.match(lines[j].rstrip())
                if not m:
                    continue
                cand = m.group("desc").strip()
                if not cand:
                    continue
                low = cand.lower()
                if any(low.startswith(p) for p in _REJECT_PREFIXES):
                    continue
                if cand.startswith("="):  # divider line
                    continue
                if len(cand) < 20:  # too terse to be a real description
                    continue
                return cand
    return None


def find_candidates(con: sqlite3.Connection) -> list[tuple[str, str, str]]:
    rows = con.execute(
        "SELECT name, filename, coalesce(description,'') FROM workflows "
        "WHERE filename != '' AND filename IS NOT NULL"
    ).fetchall()
    out = []
    for name, filename, desc in rows:
        if is_broken(desc, name):
            out.append((name, filename, desc))
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--apply", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--limit", type=int, default=0, help="Only process N candidates (0=all)")
    p.add_argument("--report", default="", help="Write a per-row report to this JSON path")
    args = p.parse_args()
    if not (args.apply or args.dry_run):
        p.error("pass --dry-run or --apply")

    con = sqlite3.connect(DB)
    try:
        candidates = find_candidates(con)
        print(f"Detected {len(candidates)} broken-description candidates.")
        if args.limit:
            candidates = candidates[: args.limit]
            print(f"Processing first {len(candidates)} only (--limit).")

        plans: list[dict] = []
        for name, filename, old_desc in candidates:
            nf_path = WORKFLOWS_ROOT / filename
            resolved_via = "direct"
            if not nf_path.exists():
                # Fall back to the parent package's main.nf — sub-role .nf files
                # often don't exist; the truth lives in the package's main.nf.
                pkg_dir = nf_path.parent
                fallback = pkg_dir / "main.nf"
                if fallback.exists():
                    nf_path = fallback
                    resolved_via = "parent_main_nf"
                else:
                    plans.append({"name": name, "status": "skip_no_file",
                                  "filename": filename})
                    continue
            new_desc = extract_description_from_nf(nf_path)
            if new_desc is None:
                plans.append({"name": name, "status": "skip_no_header_match", "filename": filename})
                continue
            if new_desc == old_desc:
                plans.append({"name": name, "status": "skip_unchanged", "filename": filename})
                continue
            if len(new_desc) <= len(old_desc):
                plans.append({"name": name, "status": "skip_not_longer",
                              "filename": filename, "old": old_desc, "new": new_desc})
                continue
            plans.append({"name": name, "status": "apply", "filename": filename,
                          "resolved_via": resolved_via,
                          "old": old_desc, "new": new_desc})

        counts: dict[str, int] = {}
        for plan in plans:
            counts[plan["status"]] = counts.get(plan["status"], 0) + 1
        print("Plan summary:")
        for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
            print(f"  {k:25}  {v}")

        # Show a handful of sample apply rows
        sample = [p for p in plans if p["status"] == "apply"][:6]
        print("\nSample applies:")
        for s in sample:
            print(f"  {s['name']}")
            print(f"    old: {s['old']!r}")
            print(f"    new: {s['new'][:120]!r}")

        if args.report:
            Path(args.report).write_text(json.dumps(plans, indent=2))
            print(f"\nFull plan written to {args.report}")

        if args.dry_run:
            print("\n(dry-run — no changes written)")
            return 0

        applies = [p for p in plans if p["status"] == "apply"]
        if not applies:
            print("Nothing to apply.")
            return 0

        backup_path = DB.parent / f"backfill_descriptions_backup_{time.strftime('%Y%m%dT%H%M%S')}.json"
        names = [p["name"] for p in applies]
        cur = con.execute(
            f"SELECT name, description FROM workflows WHERE name IN ({','.join('?'*len(names))})",
            names,
        )
        backup = [dict(zip([c[0] for c in cur.description], r)) for r in cur.fetchall()]
        backup_path.write_text(json.dumps(backup, indent=2, default=str))
        print(f"\nbacked up {len(backup)} rows to {backup_path}")

        with con:
            now = time.strftime("%Y-%m-%dT%H:%M:%S")
            for p in applies:
                con.execute(
                    "UPDATE workflows SET description=? WHERE name=?",
                    (p["new"], p["name"]),
                )
            print(f"Updated {len(applies)} rows.")

        print("done.")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())
