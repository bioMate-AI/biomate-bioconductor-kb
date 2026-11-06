"""Mark workflows whose own code is a placeholder as non-executable (they can never produce a result).

A workflow is a placeholder when its `.nf` body is an explicit stand-in — the code says so — e.g. Advanced Web
Search Claude returns `results: []` with "Web search placeholder - actual implementation requires API access";
two wet-lab procedures exit with "… no compute equivalent". Routing them shows the user a card that cannot work.
Detection is on the code text (these markers are written by the wrappers themselves), applied catalog-wide; rows
are set executable=0, real_exec_status='placeholder' (guarded by id + current executable=1, FTS-checked).

Usage: PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.placeholder_audit [--apply --db <db>]
"""
from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path
from typing import List, Tuple

from .description_code_audit import _code_path, _SKIP_SOURCES
from .domain_reclassifier import _DEFAULT_DB, assert_fts_consistent

PLACEHOLDER_MARKERS = re.compile(
    r"placeholder\s*-\s*actual implementation|placeholder.{0,40}requires API access|no compute equivalent"
    r"|raise NotImplementedError", re.I)


def find(db: Path) -> List[Tuple[int, str, str]]:
    conn = sqlite3.connect(str(db))
    rows = conn.execute("SELECT id, name, COALESCE(source,''), filename FROM workflows WHERE executable=1").fetchall()
    conn.close()
    out = []
    for wid, name, src, fn in rows:
        if src in _SKIP_SOURCES:
            continue
        p = _code_path(fn or "")
        if p:
            m = PLACEHOLDER_MARKERS.search(p.read_text(errors="replace"))
            if m:
                out.append((wid, name, m.group(0)))
    return out


def apply(db: Path, hits: List[Tuple[int, str, str]]) -> int:
    assert_fts_consistent(db)
    conn = sqlite3.connect(str(db))
    n = sum(conn.execute("UPDATE workflows SET executable = 0, real_exec_status = 'placeholder' WHERE id = ? AND executable = 1",
                         (wid,)).rowcount for wid, _, _ in hits)
    conn.commit(); conn.close()
    return n


def _cli(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=str(_DEFAULT_DB)); ap.add_argument("--apply", action="store_true")
    a = ap.parse_args(argv)
    hits = find(Path(a.db))
    for h in hits:
        print(f"{h[0]}\t{h[1]}\t{h[2]}")
    if a.apply:
        sys.stderr.write(f"marked {apply(Path(a.db), hits)} rows non-executable (placeholder)\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
