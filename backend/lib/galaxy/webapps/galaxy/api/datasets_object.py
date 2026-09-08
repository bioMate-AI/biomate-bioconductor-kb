"""
Dataset-object API — lineage / consumers / versions for a dataset reference.

Backs the DatasetObject panel (frontend components/datasets/dataset-object.tsx),
whose Lineage / Consumers / Versions tabs previously rendered a flat
"not available yet". These three endpoints populate them from data BioMate
ALREADY tracks — no fabrication:

  GET /api/datasets/{ref}/lineage    -> which run/workflow/step PRODUCED it
  GET /api/datasets/{ref}/consumers  -> which runs READ it as an input
  GET /api/datasets/{ref}/versions   -> prior versions (honest single current)

Sources (all real, all already recorded by the Nextflow executor):

  * ``_runs[]`` + the ``RunStateStore`` hold every in-flight / recently-finished
    run record. Each record carries ``nextflow_path`` (workflow), ``parameters``
    (the input files/params a run READ), ``s3_output_files`` (the outputs a run
    WROTE), ``outdir`` and timestamps. We scan those records to answer lineage
    (this ref appears among a run's outputs) and consumers (this ref appears
    among a run's input parameters).
  * The default output prefix ``s3://<bucket>/nextflow/outputs/<user>/<run_id>/``
    lets us recover the producing run_id straight from an S3 key when no live
    record survives.

Where a source genuinely has nothing, the endpoint returns an empty list
(``[]``) — the frontend renders the honest "not available yet" state. We never
invent a run, a consumer, or a version.

``ref`` is URL-encoded by the caller (an S3 key or file path may contain "/"),
so the path is a catch-all and we percent-decode it here.

Auto-discovered exactly like ``perception.py`` / ``nextflow_executor.py``: this
module's module-level ``router`` object is picked up by
``galaxy.webapps.base.api.include_all_package_routers``.
"""
# CRITICAL: keep this first. PEP 604 union syntax on Python 3.9 needs it and
# auto-sync has stripped it from sibling modules before, crash-looping gunicorn.
from __future__ import annotations

import logging
import os
import re
from typing import Any, Dict, List, Optional
from urllib.parse import unquote

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["datasets"])


# --------------------------------------------------------------------------- #
# ref normalisation + matching helpers
# --------------------------------------------------------------------------- #

def _norm(ref: Optional[str]) -> str:
    """Normalise a dataset reference for comparison.

    Strips a ``file://`` scheme and trailing slash; leaves ``s3://`` intact.
    Comparison is done on the basename OR the full ref so that a run that
    recorded an absolute path still matches an S3 key with the same file name.
    """
    if not ref:
        return ""
    r = str(ref).strip()
    if r.startswith("file://"):
        r = r[len("file://"):]
    return r.rstrip("/")


def _basename(ref: str) -> str:
    return _norm(ref).split("/")[-1] if ref else ""


def _refs_match(a: Optional[str], b: Optional[str]) -> bool:
    """True if two references point at the same dataset.

    Exact match on the normalised ref, or (fallback) match on basename when at
    least one side carries a directory — the executor records inputs as full
    paths / S3 URIs while the UI may hold just an S3 key.
    """
    na, nb = _norm(a), _norm(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    ba, bb = _basename(na), _basename(nb)
    return bool(ba) and ba == bb


# Default output-prefix convention:
#   s3://<bucket>/nextflow/outputs/<user_id>/<run_id>/...
# Also matches the project layout:
#   s3://<bucket>/projects/<project_id>/runs/<run_id>/output/...
_OUTPUTS_RUNID_RE = re.compile(r"/nextflow/outputs/[^/]+/([0-9a-fA-F\-]{6,})/")
_PROJECT_RUNID_RE = re.compile(r"/projects/[^/]+/runs/([0-9a-fA-F\-]{6,})/")


def _run_id_from_ref(ref: str) -> Optional[str]:
    """Recover a producing run_id straight from an S3 output key, if it follows
    the BioMate output-prefix convention. Returns None otherwise (honest)."""
    n = _norm(ref)
    for rx in (_OUTPUTS_RUNID_RE, _PROJECT_RUNID_RE):
        m = rx.search(n)
        if m:
            return m.group(1)
    return None


# --------------------------------------------------------------------------- #
# run-record access — scan every run BioMate currently tracks
# --------------------------------------------------------------------------- #

def _iter_run_records() -> Dict[str, Dict[str, Any]]:
    """Return {run_id: record} for every run BioMate currently tracks.

    Union of the in-process ``_runs[]`` (retains terminal runs until the worker
    recycles) and the ``RunStateStore`` active set (cross-worker). Best-effort:
    any import / lookup failure degrades to whatever source is reachable, never
    raises — an empty dict just yields honest-empty tabs.
    """
    records: Dict[str, Dict[str, Any]] = {}
    try:
        from galaxy.webapps.galaxy.api import nextflow_executor as nfe

        with nfe._runs_lock:
            for rid, rec in nfe._runs.items():
                if isinstance(rec, dict):
                    # Drop the un-serialisable Popen handle before copying.
                    records[rid] = {k: v for k, v in rec.items() if k != "process"}
    except Exception as exc:
        log.debug("[datasets] _runs scan unavailable: %s", exc)

    try:
        from galaxy.ai.runs import get_run_state_store

        store = get_run_state_store()
        for rid in store.list_active_runs():
            if rid in records:
                continue
            snap = store.get_run(rid)
            if isinstance(snap, dict):
                records[rid] = {k: v for k, v in snap.items() if k != "process"}
    except Exception as exc:
        log.debug("[datasets] store scan unavailable: %s", exc)

    return records


def _run_output_refs(rec: Dict[str, Any]) -> List[str]:
    """The dataset references a run WROTE.

    ``s3_output_files`` entries are dicts ({s3_uri,name,...}) for S3 runs or
    plain path strings for local runs — handle both.
    """
    out: List[str] = []
    for f in rec.get("s3_output_files") or []:
        if isinstance(f, dict):
            uri = f.get("s3_uri") or f.get("key") or f.get("name")
            if uri:
                out.append(str(uri))
        elif isinstance(f, str):
            out.append(f)
    return out


def _run_input_refs(rec: Dict[str, Any]) -> List[str]:
    """The dataset references a run READ.

    Input files arrive as workflow parameter values; a param value is an input
    ref when it looks like a path / S3 URI. We keep only string-ish scalars and
    flatten one level of list (nf params commonly hold ``[a, b]``).
    """
    refs: List[str] = []
    params = rec.get("parameters") or rec.get("params") or {}
    if not isinstance(params, dict):
        return refs

    def _looks_like_ref(v: Any) -> bool:
        if not isinstance(v, str) or not v:
            return False
        return (
            v.startswith("s3://")
            or v.startswith("file://")
            or v.startswith("/")
            or "/" in v
            and "." in v.rsplit("/", 1)[-1]
        )

    for val in params.values():
        if isinstance(val, list):
            for item in val:
                if _looks_like_ref(item):
                    refs.append(item)
        elif _looks_like_ref(val):
            refs.append(val)
    return refs


def _run_label(run_id: str, rec: Dict[str, Any]) -> Dict[str, Any]:
    """A compact, honest descriptor of a run for the UI."""
    wf = rec.get("nextflow_path") or rec.get("workflow_path") or ""
    wf_name = os.path.basename(str(wf)) if wf else ""
    return {
        "runId": run_id,
        "workflow": wf_name or None,
        "workflowPath": str(wf) or None,
        "status": rec.get("status"),
        "createdAt": rec.get("started_at") or rec.get("created_at") or None,
    }


# --------------------------------------------------------------------------- #
# endpoints
# --------------------------------------------------------------------------- #

@router.get("/api/datasets/{ref:path}/lineage", summary="What run/workflow/step produced a dataset")
def dataset_lineage(ref: str) -> Dict[str, Any]:
    """Return the producing run for ``ref``, derived from run-output provenance.

    Order of evidence:
      1. A live run record whose ``s3_output_files`` contain this ref.
      2. The run_id recovered from the S3 output-prefix convention.
    Empty ``producedBy`` (with ``available: false``) when neither exists — an
    uploaded input has no upstream run, and we do not invent one.
    """
    decoded = unquote(ref or "")
    n = _norm(decoded)

    # 1) Scan tracked runs for one that wrote this dataset — either the ref
    #    appears among the run's listed outputs, or the run's outdir is a
    #    prefix of the ref (outdir is always recorded; s3_output_files is only
    #    populated after completion).
    for run_id, rec in _iter_run_records().items():
        matched = any(_refs_match(o, decoded) for o in _run_output_refs(rec))
        if not matched:
            outdir = _norm(rec.get("outdir") or "")
            if outdir and n.startswith(outdir + "/"):
                matched = True
        if matched:
            return {
                "ref": decoded,
                "available": True,
                "source": "run_output",
                "producedBy": _run_label(run_id, rec),
            }

    # 2) Fall back to the run_id embedded in a BioMate output key.
    rid = _run_id_from_ref(decoded)
    if rid:
        rec = _iter_run_records().get(rid, {})
        label = _run_label(rid, rec)
        return {
            "ref": decoded,
            "available": True,
            "source": "output_prefix",
            "producedBy": label,
        }

    # 3) Honest empty — uploaded input or no surviving provenance record.
    return {"ref": decoded, "available": False, "source": None, "producedBy": None}


@router.get("/api/datasets/{ref:path}/consumers", summary="Which runs read a dataset as input")
def dataset_consumers(ref: str) -> Dict[str, Any]:
    """Return runs that READ ``ref`` as an input parameter.

    A consumer is any tracked run whose input parameter values reference this
    dataset. Empty list (honest) when no tracked run reads it — the UI keeps
    its "consumer tracking is not available yet" copy.
    """
    decoded = unquote(ref or "")
    consumers: List[Dict[str, Any]] = []
    seen: set = set()
    records = _iter_run_records()

    # (a) Direct: a run whose input parameter values reference this dataset.
    for run_id, rec in records.items():
        if run_id in seen:
            continue
        if any(_refs_match(in_ref, decoded) for in_ref in _run_input_refs(rec)):
            consumers.append(_run_label(run_id, rec))
            seen.add(run_id)

    # (b) Resume lineage: a run that resumed from the run that PRODUCED this
    #     dataset consumed that run's outputs. Only counted when we can tie the
    #     ref to a producing run_id (output-prefix convention) — never guessed.
    producer_id = _run_id_from_ref(decoded)
    if not producer_id:
        for rid, rec in records.items():
            outdir = _norm(rec.get("outdir") or "")
            if outdir and _norm(decoded).startswith(outdir + "/"):
                producer_id = rid
                break
    if producer_id:
        for run_id, rec in records.items():
            if run_id in seen:
                continue
            if rec.get("resume_from_run_id") == producer_id:
                consumers.append(_run_label(run_id, rec))
                seen.add(run_id)

    return {"ref": decoded, "consumers": consumers}


@router.get("/api/datasets/{ref:path}/versions", summary="Version history for a dataset")
def dataset_versions(ref: str) -> Dict[str, Any]:
    """Return the version history for ``ref``.

    BioMate does not currently retain prior revisions of a dataset — a file is
    written once by its producing run. We therefore report a single honest
    "v1 · current" entry built from real file metadata (the ref itself, and its
    producing run's timestamp when known), never a fabricated revision chain.
    Returns ``[]`` only when there is no resolvable ref at all.
    """
    decoded = unquote(ref or "")
    if not decoded:
        return {"ref": decoded, "versions": []}

    created_at: Optional[str] = None
    run_id = _run_id_from_ref(decoded)
    records = _iter_run_records()
    if run_id and run_id in records:
        rec = records[run_id]
        created_at = rec.get("started_at") or rec.get("created_at")
    else:
        # Or the run that wrote it, if we can find it by output ref.
        for rid, rec in records.items():
            if any(_refs_match(o, decoded) for o in _run_output_refs(rec)):
                created_at = rec.get("started_at") or rec.get("created_at")
                run_id = rid
                break

    version = {
        "version": "v1",
        "label": "v1 · current",
        "current": True,
        "ref": decoded,
        "createdAt": created_at,
        "producedByRunId": run_id,
    }
    return {"ref": decoded, "versions": [version]}
