"""Deploy-layout-independent resolution of the writable `data/` root.

Historically every module here computed its data path as
`Path(__file__).resolve().parents[5] / "data" / ...`. That index assumes the
local checkout layout (`<repo>/backend/lib/galaxy/ai/drug_discovery/<file>`),
where `parents[5]` is the repo root and `<repo>/data` is writable. On the
deployed container the code lives one level shallower (`/app/lib/galaxy/ai/
drug_discovery/<file>`), so `parents[5]` overshoots to `/`, `data_root()`
became `/data`, and the first write (`mkdir`) failed with
`[Errno 13] Permission denied: '/data'` — which is why the Adapt-track retrain
submit 502'd on dev while the serving-side rule *readers* silently pointed at
the same non-existent dir.

The fix is to stop hard-coding a parent index and instead *find a writable
root at runtime*, identically for every reader and writer in this package so
they always agree:

  1. `BIOMATE_DATA_ROOT` env override wins (points directly at the `data` dir).
  2. The repo/app root — the nearest ancestor that holds `data/` alongside a
     repo marker (`backend`/`.git`/`lib`) — giving `<root>/data` (local + any
     seeded deploy; preserves existing behaviour exactly).
  3. Deployed Galaxy layout: beside the `lib/` dir, trying `<app>/data` then
     `<app>/database/data` (the DB dir is chowned writable on dev, persists
     across restarts).
  4. A writable temp dir as a never-crash last resort.

Each candidate is *probed* (mkdir + os.access) so we return a path that is
actually writable, never one that merely looks right. Pure stdlib, Python
3.9-safe — safe to import anywhere in the Galaxy chain.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import List, Optional

_MARKERS = ("backend", ".git", "lib")


def _first_writable(cands: List[Path]) -> Path:
    for c in cands:
        try:
            c.mkdir(parents=True, exist_ok=True)
            if os.access(c, os.W_OK):
                return c
        except (PermissionError, OSError):
            continue
    # cands always ends with the temp dir, which is writable; but be defensive.
    return cands[-1] if cands else Path(tempfile.gettempdir()) / "biomate_data"


def _candidate_data_dirs() -> List[Path]:
    here = Path(__file__).resolve()
    cands: List[Path] = []
    env = os.environ.get("BIOMATE_DATA_ROOT")
    if env:
        cands.append(Path(env))
    # (2) repo/app root already carrying a seeded data/ dir
    for anc in here.parents:
        if (anc / "data").is_dir() and any((anc / m).exists() for m in _MARKERS):
            cands.append(anc / "data")
            break
    # (3) deployed layout: the app root is the parent of the 'lib' dir
    for anc in here.parents:
        if anc.name == "lib":
            approot = anc.parent
            cands.append(approot / "data")
            cands.append(approot / "database" / "data")
            break
    # (4) last resort — note the trailing "data" so `data_root().parent / "data"`
    # (how the call sites compose paths) stays equal to `data_root()`.
    cands.append(Path(tempfile.gettempdir()) / "biomate" / "data")
    # de-dup preserving order
    seen = set()
    uniq: List[Path] = []
    for c in cands:
        s = str(c)
        if s not in seen:
            seen.add(s)
            uniq.append(c)
    return uniq


_cached: Optional[Path] = None


def data_root() -> Path:
    """The writable `data/` directory for this deployment (cached per process)."""
    global _cached
    if _cached is None:
        _cached = _first_writable(_candidate_data_dirs())
    return _cached


def repo_root() -> Path:
    """Best-effort repo/app root (parent of the resolved `data/` dir).

    For non-`data/` siblings such as `models/`. Not write-probed — callers that
    write under it should route through `data_root()` instead.
    """
    return data_root().parent
