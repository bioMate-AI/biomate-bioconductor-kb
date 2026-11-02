"""Connection transforms: turn an upstream artifact FILE into the value a
downstream workflow parameter really expects (inline JSON array, [x, y, z]).

A chain connection may carry ``transform: {"name": ..., "args": {...}}``.
``workflow_chain._apply_connection_handoffs`` picks the upstream file and then
calls :func:`apply`; a :class:`TransformError` fails the step before launch.

stdlib only; Python 3.9 safe.
"""
from __future__ import annotations

import csv
import json
import math
from typing import Any, Callable, Dict, List, Optional


class TransformError(Exception):
    """Raised when a transform cannot produce a usable value."""


_DEFAULT_MAX_SMILES = 5000
_SMILES_COLUMNS = ("smiles", "canonical_smiles", "isomeric_smiles", "smi")
_BOX_PAD = 10.0          # angstrom added to the pocket diameter
_BOX_MIN = 20.0          # angstrom; matches the docking default box
_BOX_MAX = 40.0


def _read_text(path: str) -> str:
    if not path:
        raise TransformError("no local file to transform (artifact has no readable path)")
    try:
        with open(path, "r", encoding="utf-8-sig", errors="replace") as fh:
            return fh.read()
    except OSError as exc:
        raise TransformError("cannot read %s: %s" % (path, exc))


def smiles_file_to_json_list(path: str, args: Dict[str, Any]) -> str:
    """SMILES file -> JSON array string (what ``params.smiles_list`` expects).

    Accepts one SMILES per line, or a CSV/TSV with a header naming a
    smiles/SMILES/canonical_smiles column (or ``args.column``). Blank and
    ``#`` comment lines skipped, duplicates removed preserving order.
    """
    text = _read_text(path)
    try:
        limit = int(args.get("max", _DEFAULT_MAX_SMILES))
    except (TypeError, ValueError):
        raise TransformError("transform arg 'max' must be an integer")
    column = args.get("column")
    lines = [ln.strip() for ln in text.splitlines()]
    lines = [ln for ln in lines if ln and not ln.startswith("#")]
    if not lines:
        raise TransformError("SMILES file %s is empty" % path)

    first = lines[0]
    delim = "\t" if "\t" in first else ("," if "," in first else None)
    values = []  # type: List[str]
    header_idx = None  # type: Optional[int]
    if delim is not None:
        header = [h.strip().strip('"') for h in next(csv.reader([first], delimiter=delim))]
        lowered = [h.lower() for h in header]
        if column:
            if column in header:
                header_idx = header.index(column)
            elif str(column).lower() in lowered:
                header_idx = lowered.index(str(column).lower())
            else:
                raise TransformError("column %r not found in SMILES file header %s" % (column, header))
        else:
            for cand in _SMILES_COLUMNS:
                if cand in lowered:
                    header_idx = lowered.index(cand)
                    break
        if header_idx is not None:
            for row in csv.reader(lines[1:], delimiter=delim):
                if header_idx < len(row) and row[header_idx].strip():
                    values.append(row[header_idx].strip().strip('"'))
        else:
            # Header-less table: first field is the SMILES (extra fields = names).
            for row in csv.reader(lines, delimiter=delim):
                if row and row[0].strip():
                    values.append(row[0].strip().strip('"'))
    else:
        if column:
            raise TransformError("column %r requested but file has no delimiter" % column)
        for ln in lines:
            values.append(ln.split()[0])  # "SMILES name" .smi style

    seen = set()
    out = []  # type: List[str]
    for v in values:
        if v not in seen:
            seen.add(v)
            out.append(v)
    if not out:
        raise TransformError("no SMILES found in %s" % path)
    if len(out) > limit:
        raise TransformError(
            "%d unique SMILES in %s exceeds max=%d (raise args.max or split the file)"
            % (len(out), path, limit))
    return json.dumps(out)


def _num(p: Dict[str, Any], key: str) -> float:
    try:
        v = float(p[key])
    except (KeyError, TypeError, ValueError):
        raise TransformError("pocket %r is missing numeric field %r" % (p.get("pocket_id"), key))
    if math.isnan(v) or math.isinf(v):
        raise TransformError("pocket %r has non-finite %r" % (p.get("pocket_id"), key))
    return v


def pocket_json_to_box_center(path: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """Pocket-detection ``*_pockets.json`` -> docking box for the best pocket.

    Real schema (pocket_detection_druggability/main.nf:198-205, 175-184):
    ``{"target","tool","version","num_pockets","pockets":[{"pocket_id",
    "volume_A3","druggability_score","hydrophobicity","polarity",
    "center_x","center_y","center_z"}],"timestamp"}``.
    Top pocket = highest druggability_score, ties by volume_A3. The detector
    reports no box extent, so box_size is derived from the volume as a sphere
    (diameter + 10 A padding, clamped to 20..40 A per axis).
    """
    text = _read_text(path)
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise TransformError("pocket file %s is not valid JSON: %s" % (path, exc))
    pockets = data.get("pockets") if isinstance(data, dict) else None
    if not isinstance(pockets, list) or not pockets:
        raise TransformError("no pockets found in %s" % path)
    pockets = [p for p in pockets if isinstance(p, dict)]
    if not pockets:
        raise TransformError("no pockets found in %s" % path)
    best = max(pockets, key=lambda p: (_num(p, "druggability_score"), _num(p, "volume_A3")))
    center = [round(_num(best, k), 3) for k in ("center_x", "center_y", "center_z")]
    vol = _num(best, "volume_A3")
    radius = (3.0 * max(vol, 0.0) / (4.0 * math.pi)) ** (1.0 / 3.0)
    side = round(min(_BOX_MAX, max(_BOX_MIN, 2.0 * radius + _BOX_PAD)), 1)
    return {
        "box_center": center,
        "box_size": [side, side, side],
        "pocket_rank": pockets.index(best) + 1,
        "n_pockets": len(pockets),
        "selection": "max druggability_score (ties: volume_A3); pocket_id=%s druggability=%s volume_A3=%s"
                     % (best.get("pocket_id"), best.get("druggability_score"), best.get("volume_A3")),
    }


REGISTRY = {
    "smiles_file_to_json_list": smiles_file_to_json_list,
    "pocket_json_to_box_center": pocket_json_to_box_center,
}  # type: Dict[str, Callable[[str, dict], Any]]


def apply(name: str, artifact_path: str, args: Optional[Dict[str, Any]] = None) -> Any:
    fn = REGISTRY.get(name)
    if fn is None:
        raise TransformError("unknown transform %r (known: %s)" % (name, ", ".join(sorted(REGISTRY))))
    return fn(artifact_path, dict(args or {}))
