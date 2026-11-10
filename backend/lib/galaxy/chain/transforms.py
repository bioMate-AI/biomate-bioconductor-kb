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
import os
import tempfile
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
    If the file carries a ``reference_site`` (a named co-crystallised ligand), the box is built around it.
    Otherwise: top pocket = highest druggability_score, ties by volume_A3. The detector
    reports no box extent, so box_size is derived from the volume as a sphere
    (diameter + 10 A padding, clamped to 20..40 A per axis).
    """
    text = _read_text(path)
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise TransformError("pocket file %s is not valid JSON: %s" % (path, exc))
    ref = data.get("reference_site") if isinstance(data, dict) else None
    if isinstance(ref, dict) and all(k in ref for k in ("center_x", "center_y", "center_z")):
        # A known co-crystallised ligand defines the site (standard practice when a holo structure exists):
        # box = ligand centroid, side = ligand extent + padding, clamped like the pocket-derived box.
        extent = ref.get("extent_A") or [0.0, 0.0, 0.0]
        side = [round(min(_BOX_MAX, max(_BOX_MIN, float(e) + _BOX_PAD)), 1) for e in extent]
        return {
            "box_center": [round(float(ref["center_" + a]), 3) for a in "xyz"],
            "box_size": side,
            "pocket_rank": None,
            "n_pockets": len(data.get("pockets") or []),
            "selection": "reference site: co-crystallised ligand %s (%s atoms)" % (ref.get("ligand"), ref.get("n_atoms")),
        }
    if isinstance(data, dict) and data.get("reference_site_error"):
        raise TransformError("reference site requested but not found: %s" % data["reference_site_error"])
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


def admet_toxicity_to_herg_ic50_nM(path: str, args: Dict[str, Any]) -> str:
    """ADMET ``toxicity_report.json`` -> worst-case hERG IC50 in **nM** for CiPA cardiac models.

    ``predict_admet_properties`` writes ``toxicity.herg_ic50_uM`` as the **worst-case (minimum, most
    potent) IC50 across the whole compound set**. That IC50 is itself an ESTIMATE derived from the
    ADMET-AI hERG *classification probability* via a terfenadine-anchored power law
    (``herg_ic50_method="admet_ai_prob_powerlaw_terfenadine_anchor"``), NOT a measured/assayed IC50 —
    expect it to be off by several-fold from experiment. This transform only does the unit conversion
    (uM -> nM, x1000) and surfaces that estimate to ``cipa_cardiac_safety_ode`` as a conservative
    worst-case gate input (``params.herg_ic50_nM``); it is not a validated affinity.
    """
    text = _read_text(path)
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise TransformError("toxicity report %s is not valid JSON: %s" % (path, exc))
    tox = data.get("toxicity") if isinstance(data, dict) else None
    if not isinstance(tox, dict) or tox.get("herg_ic50_uM") is None:
        raise TransformError("toxicity.herg_ic50_uM not found in %s" % path)
    try:
        uM = float(tox["herg_ic50_uM"])
    except (TypeError, ValueError):
        raise TransformError("herg_ic50_uM is not numeric in %s: %r" % (path, tox.get("herg_ic50_uM")))
    if math.isnan(uM) or math.isinf(uM) or uM <= 0:
        raise TransformError("herg_ic50_uM non-finite/non-positive in %s: %r" % (path, uM))
    return repr(round(uM * 1000.0, 3))  # nM


REGISTRY = {
    "smiles_file_to_json_list": smiles_file_to_json_list,
    "pocket_json_to_box_center": pocket_json_to_box_center,
    "admet_toxicity_to_herg_ic50_nM": admet_toxicity_to_herg_ic50_nM,
}  # type: Dict[str, Callable[[str, dict], Any]]


def apply(name: str, artifact_path: str, args: Optional[Dict[str, Any]] = None) -> Any:
    fn = REGISTRY.get(name)
    if fn is None:
        raise TransformError("unknown transform %r (known: %s)" % (name, ", ".join(sorted(REGISTRY))))
    return fn(artifact_path, dict(args or {}))


# Largest upstream artifact a transform will read (SMILES lists and pocket JSON are small; refuse anything else).
MAX_ARTIFACT_BYTES = 50 * 1024 * 1024


def _default_s3_fetch(uri: str, dest: str) -> None:
    from galaxy.ai.s3_utils import make_s3_client  # lazy: MinIO-aware, only needed on the Batch path
    bucket, _, key = uri[len("s3://"):].partition("/")
    if not bucket or not key:
        raise TransformError("malformed S3 URI %r" % uri)
    client = make_s3_client()
    size = client.head_object(Bucket=bucket, Key=key).get("ContentLength") or 0
    if size > MAX_ARTIFACT_BYTES:
        raise TransformError("artifact %s is %d bytes, above the %d-byte limit for transforms" % (uri, size, MAX_ARTIFACT_BYTES))
    client.download_file(bucket, key, dest)


def apply_to_artifact(name: str, artifact: Optional[Dict[str, Any]], args: Optional[Dict[str, Any]] = None,
                      fetch: Optional[Callable[[str, str], None]] = None) -> Any:
    """Apply a transform to an upstream artifact wherever it lives.

    A local file (`path`) is read in place. An artifact published to S3 (AWS Batch, or MinIO on-prem: `s3_uri`, or a
    `path` that is itself an s3:// URI) is downloaded to a temporary file first and removed afterwards. Failures are
    TransformError, so the chain step fails before the next job launches."""
    artifact = artifact or {}
    local = artifact.get("path") or ""
    if local and not local.startswith("s3://") and os.path.isfile(local):
        return apply(name, local, args)
    uri = artifact.get("s3_uri") or (local if local.startswith("s3://") else "")
    if not uri:
        raise TransformError("no local file or S3 URI for artifact %r" % (artifact.get("filename") or "?"))
    suffix = os.path.splitext(uri)[1] or ".dat"
    fd, tmp = tempfile.mkstemp(prefix="chain_transform_", suffix=suffix)
    os.close(fd)
    try:
        try:
            (fetch or _default_s3_fetch)(uri, tmp)
        except TransformError:
            raise
        except Exception as exc:  # network, permission, missing key
            raise TransformError("could not download %s: %s: %s" % (uri, type(exc).__name__, exc))
        return apply(name, tmp, args)
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass

