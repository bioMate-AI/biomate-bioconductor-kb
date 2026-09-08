"""
Dataset-object API — lineage / consumers / versions for a dataset reference.

Backs the DatasetObject panel (frontend components/datasets/dataset-object.tsx),
whose Lineage / Consumers / Versions tabs previously rendered a flat
"not available yet". These three endpoints populate them from data BioMate
ALREADY tracks — no fabrication:

  GET  /api/datasets/{ref}/lineage    -> which run/workflow/step PRODUCED it
  GET  /api/datasets/{ref}/consumers  -> which runs READ it as an input
  GET  /api/datasets/{ref}/versions   -> prior versions (honest single current)
  POST /api/datasets/{ref}/versions   -> append a {note} to an append-only log
  GET  /api/datasets/{ref}/ro-crate   -> RO-Crate metadata assembled from the
                                         real lineage / provenance / versions

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

import datetime
import hashlib
import json
import logging
import os
import re
from typing import Any, Dict, List, Optional
from urllib.parse import unquote

from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["datasets"])


# --------------------------------------------------------------------------- #
# append-only version log — a JSONL sidecar keyed by a hash of the ref
# --------------------------------------------------------------------------- #
#
# BioMate does not (yet) copy-on-write a dataset's bytes, so a "version" here is
# an append-only annotation an operator adds to a dataset object (a note, a QC
# sign-off, a re-derivation marker). The log is strictly append-only: each
# ``POST .../versions`` writes ONE new JSON line and never rewrites a prior one.
# It lives beside the dataset metadata under a dedicated directory so it does
# not touch the dataset bytes themselves (which may be an immutable S3 object).
#
#   <BIOMATE_DATASET_META_DIR>/dataset_versions/<sha256(norm_ref)>.jsonl
#
# The base dir defaults to a sibling of the Nextflow work dir so a single
# volume/mount carries both. Nothing here is fabricated: an absent log means the
# dataset has only its implicit ``v1 · current`` (from real file metadata).


def _version_log_base() -> str:
    """Directory that holds per-dataset version logs. Env-overridable."""
    explicit = os.environ.get("BIOMATE_DATASET_META_DIR")
    if explicit:
        base = explicit
    else:
        work_dir = os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")
        base = os.path.join(os.path.dirname(work_dir.rstrip("/")) or "/tmp",
                            "biomate_dataset_meta")
    return os.path.join(base, "dataset_versions")


def _version_log_path(decoded_ref: str) -> str:
    """Path to the JSONL version log for ``decoded_ref`` (hashed for safety)."""
    key = hashlib.sha256(_norm(decoded_ref).encode("utf-8")).hexdigest()
    return os.path.join(_version_log_base(), f"{key}.jsonl")


def _read_version_log(decoded_ref: str) -> List[Dict[str, Any]]:
    """Read the append-only log for ``decoded_ref``. Empty list when none.

    Best-effort: a malformed line is skipped (never raises) so a partially
    written record can't break the whole tab.
    """
    path = _version_log_path(decoded_ref)
    entries: List[Dict[str, Any]] = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    if isinstance(obj, dict):
                        entries.append(obj)
                except (ValueError, TypeError):
                    log.debug("[datasets] skipping malformed version-log line in %s", path)
    except FileNotFoundError:
        return []
    except OSError as exc:
        log.debug("[datasets] version-log read failed for %s: %s", path, exc)
        return []
    return entries


def _append_version_log(decoded_ref: str, entry: Dict[str, Any]) -> None:
    """Append ONE record to the log for ``decoded_ref`` (creates dir/file)."""
    path = _version_log_path(decoded_ref)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, sort_keys=True) + "\n")


class DatasetVersionRequest(BaseModel):
    # The human note that motivates this version entry (required, trimmed).
    note: Optional[str] = None
    # Optional author label (a user id / email). Recorded verbatim when given.
    author: Optional[str] = None


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


def _producing_run_for(decoded_ref: str) -> tuple:
    """(run_id, created_at) of the run that wrote ``decoded_ref``, if known.

    Resolves first from the output-prefix convention, then by scanning tracked
    run records for one whose outputs match. Returns ``(None, None)`` when no
    surviving provenance ties the ref to a run — honest, never guessed.
    """
    run_id = _run_id_from_ref(decoded_ref)
    records = _iter_run_records()
    if run_id and run_id in records:
        rec = records[run_id]
        return run_id, rec.get("started_at") or rec.get("created_at")
    for rid, rec in records.items():
        if any(_refs_match(o, decoded_ref) for o in _run_output_refs(rec)):
            return rid, rec.get("started_at") or rec.get("created_at")
    return run_id, None


def _build_versions(decoded_ref: str) -> List[Dict[str, Any]]:
    """Build the version list for an ALREADY-decoded ref (v1 + append log).

    The current dataset is always ``v1`` (real file metadata). The append-only
    log (``POST .../versions``) is replayed on top as ``v2, v3, …`` in write
    order; the newest entry is marked ``current``. Empty log -> single honest
    ``v1 · current``. Empty list only when ``decoded_ref`` is falsy.
    """
    if not decoded_ref:
        return []

    run_id, created_at = _producing_run_for(decoded_ref)
    versions: List[Dict[str, Any]] = [
        {
            "version": "v1",
            "label": "v1 · current",
            "current": True,
            "ref": decoded_ref,
            "createdAt": created_at,
            "producedByRunId": run_id,
            "note": None,
            "author": None,
        }
    ]

    for i, entry in enumerate(_read_version_log(decoded_ref), start=2):
        versions.append(
            {
                "version": f"v{i}",
                "label": f"v{i}",
                "current": False,
                "ref": decoded_ref,
                "createdAt": entry.get("createdAt"),
                "producedByRunId": run_id,
                "note": entry.get("note"),
                "author": entry.get("author"),
            }
        )

    # The newest entry is the current one; demote v1 when a log exists.
    if len(versions) > 1:
        versions[0]["current"] = False
        versions[0]["label"] = "v1"
        versions[-1]["current"] = True
        versions[-1]["label"] = f"{versions[-1]['version']} · current"

    return versions


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

    The current dataset is always ``v1`` — built from real file metadata (the
    ref itself, and its producing run's timestamp when known). On top of that we
    replay the append-only log (``POST .../versions``): each logged entry
    becomes ``v2, v3, …`` in write order, and the LAST one is marked
    ``current``. When the log is empty we return the single honest
    ``v1 · current`` entry, never a fabricated revision chain. Returns ``[]``
    only when there is no resolvable ref at all.
    """
    decoded = unquote(ref or "")
    return {"ref": decoded, "versions": _build_versions(decoded)}


@router.post("/api/datasets/{ref:path}/versions", summary="Append a version-log entry for a dataset")
def append_dataset_version(ref: str, request: DatasetVersionRequest) -> Dict[str, Any]:
    """Append ONE entry to the dataset's append-only version log.

    This never mutates or rewrites a prior entry — it only appends. The written
    record carries the caller's ``note`` (required) + optional ``author``, plus
    a server-generated UTC ``createdAt``. Returns the full, freshly re-read
    version list so the UI reflects the new state without a second request.
    """
    decoded = unquote(ref or "")
    note = (request.note or "").strip()
    if not decoded:
        return {"ref": decoded, "error": "missing dataset reference", "versions": []}
    if not note:
        return {"ref": decoded, "error": "a non-empty note is required", "versions": _build_versions(decoded)}

    entry = {
        "note": note,
        "author": (request.author or "").strip() or None,
        "createdAt": datetime.datetime.now(datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
    }
    try:
        _append_version_log(decoded, entry)
    except OSError as exc:
        log.warning("[datasets] failed to append version log for %s: %s", decoded, exc)
        return {"ref": decoded, "error": "could not persist version entry", "versions": _build_versions(decoded)}

    return {"ref": decoded, "appended": entry, "versions": _build_versions(decoded)}


@router.get("/api/datasets/{ref:path}/ro-crate", summary="RO-Crate metadata for a dataset")
def dataset_ro_crate(ref: str) -> Dict[str, Any]:
    """Return an ``ro-crate-metadata.json`` describing this dataset.

    RO-Crate (https://www.researchobject.org/ro-crate/) is a JSON-LD manifest
    that packages a research object with its provenance. We assemble it ENTIRELY
    from data BioMate already tracks — the dataset ref, its producing run /
    workflow (lineage), the runs that read it (consumers), the workflow
    parameters/software recorded on that run, and the append-only version log.
    Nothing is invented: where a field is unknown it is simply omitted, and a
    sparse dataset yields an honest minimal crate (root + the file entity). We
    never fabricate a checksum, a license, or a date we do not have.

    The response sets ``Content-Disposition: attachment`` so the browser saves
    it as ``ro-crate-metadata.json``.
    """
    from fastapi.responses import JSONResponse

    decoded = unquote(ref or "")
    crate = _assemble_ro_crate(decoded)
    filename = "ro-crate-metadata.json"
    return JSONResponse(
        content=crate,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _assemble_ro_crate(decoded_ref: str) -> Dict[str, Any]:
    """Build an RO-Crate 1.1 JSON-LD graph from real BioMate provenance.

    Graph entities (only those we actually have):
      * the crate descriptor + root Dataset (RO-Crate spec requirement)
      * a File entity for the dataset itself (its ref, name, size unknown -> omit)
      * a CreateAction + SoftwareApplication for the producing run/workflow
      * a CreateAction per consuming run (``object`` = this file)
      * a version note (Comment) per append-only log entry
    """
    data_name = _basename(decoded_ref) or decoded_ref or "dataset"
    graph: List[Dict[str, Any]] = []

    # 1) RO-Crate descriptor (fixed, spec-mandated).
    graph.append(
        {
            "@type": "CreativeWork",
            "@id": "ro-crate-metadata.json",
            "conformsTo": {"@id": "https://w3id.org/ro/crate/1.1"},
            "about": {"@id": "./"},
        }
    )

    # 2) Root data entity — the crate itself. hasPart references the file.
    root: Dict[str, Any] = {
        "@id": "./",
        "@type": "Dataset",
        "name": f"BioMate dataset object — {data_name}",
        "description": (
            "RO-Crate assembled from BioMate-tracked provenance for a single "
            "dataset object. All fields are derived from real run records; "
            "unknown fields are omitted rather than fabricated."
        ),
        "hasPart": [{"@id": decoded_ref or data_name}],
    }
    graph.append(root)

    # 3) The dataset file entity. Only fields we truly have (ref + name).
    file_entity: Dict[str, Any] = {
        "@id": decoded_ref or data_name,
        "@type": "File",
        "name": data_name,
    }
    if decoded_ref.startswith("s3://") or decoded_ref.startswith("http"):
        file_entity["contentUrl"] = decoded_ref

    # 4) Producing run -> CreateAction + SoftwareApplication (lineage).
    prod = dataset_lineage(decoded_ref)
    produced_by = prod.get("producedBy") if prod.get("available") else None
    part_of_actions: List[str] = []
    if produced_by:
        run_id = produced_by.get("runId")
        wf = produced_by.get("workflow")
        wf_path = produced_by.get("workflowPath")
        created_at = produced_by.get("createdAt")
        action_id = f"#run-{run_id}" if run_id else "#producing-run"
        action: Dict[str, Any] = {
            "@id": action_id,
            "@type": "CreateAction",
            "name": f"Run {run_id}" if run_id else "Producing run",
            "result": {"@id": decoded_ref or data_name},
        }
        if produced_by.get("status"):
            action["actionStatus"] = produced_by["status"]
        if created_at:
            action["startTime"] = _iso_or_none(created_at)
        if wf or wf_path:
            sw_id = f"#software-{wf or 'workflow'}"
            sw: Dict[str, Any] = {"@id": sw_id, "@type": "SoftwareApplication"}
            if wf:
                sw["name"] = wf
            if wf_path:
                sw["url"] = wf_path
            action["instrument"] = {"@id": sw_id}
            graph.append(sw)
        graph.append(action)
        part_of_actions.append(action_id)
        # Record real workflow parameters when the live record still holds them.
        params = _run_parameters(run_id) if run_id else None
        if params:
            action["object"] = [
                {"@type": "PropertyValue", "name": k, "value": _scalar(v)}
                for k, v in params.items()
                if _scalar(v) is not None
            ]

    # 5) Consuming runs -> a UseAction each (consumers).
    cons = dataset_consumers(decoded_ref).get("consumers") or []
    for c in cons:
        crid = c.get("runId")
        use_id = f"#use-{crid}" if crid else None
        if not use_id:
            continue
        use_action: Dict[str, Any] = {
            "@id": use_id,
            "@type": "UseAction",
            "name": f"Read by run {crid}",
            "object": {"@id": decoded_ref or data_name},
        }
        if c.get("workflow"):
            use_action["description"] = c["workflow"]
        if c.get("status"):
            use_action["actionStatus"] = c["status"]
        graph.append(use_action)

    # 6) Version-log entries -> Comment entities linked from the file.
    versions = _build_versions(decoded_ref)
    version_refs: List[Dict[str, str]] = []
    for v in versions:
        note = v.get("note")
        if not note:
            continue  # v1 has no note — nothing to attach
        cid = f"#version-{v.get('version')}"
        comment: Dict[str, Any] = {
            "@id": cid,
            "@type": "Comment",
            "name": v.get("label") or v.get("version"),
            "text": note,
        }
        if v.get("createdAt"):
            comment["dateCreated"] = _iso_or_none(v["createdAt"])
        if v.get("author"):
            comment["author"] = v["author"]
        graph.append(comment)
        version_refs.append({"@id": cid})
    if version_refs:
        file_entity["comment"] = version_refs

    # Attach the file entity (after we may have added comment refs).
    graph.append(file_entity)

    return {
        "@context": "https://w3id.org/ro/crate/1.1/context",
        "@graph": graph,
    }


def _run_parameters(run_id: Optional[str]) -> Optional[Dict[str, Any]]:
    """Real workflow parameters recorded on ``run_id`` (or None)."""
    if not run_id:
        return None
    rec = _iter_run_records().get(run_id)
    if not isinstance(rec, dict):
        return None
    params = rec.get("parameters") or rec.get("params")
    return params if isinstance(params, dict) else None


def _scalar(v: Any) -> Optional[str]:
    """Stringify a param value for a PropertyValue; drop non-scalars honestly."""
    if v is None:
        return None
    if isinstance(v, (str, int, float, bool)):
        return str(v)
    return None


def _iso_or_none(v: Any) -> Optional[str]:
    """Return an ISO-8601 string for a timestamp we already have, else None.

    Accepts an epoch (int/float) or an already-ISO string. Never invents a date.
    """
    if v is None:
        return None
    if isinstance(v, (int, float)):
        try:
            return (
                datetime.datetime.fromtimestamp(v, tz=datetime.timezone.utc)
                .isoformat()
                .replace("+00:00", "Z")
            )
        except (OverflowError, OSError, ValueError):
            return None
    return str(v)
