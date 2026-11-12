"""
Data-perception API — thin endpoint over the rules-first profiler.

POST /api/perception/profile  { datasetRef }  ->  DataProfile
POST /api/perception/rows     { datasetRef, offset, limit }  ->  one page of FULL rows
POST /api/perception/folder_profile { path, projectId, files: [{name, datasetRef}] } -> FolderProfile

Both per-file calls accept an optional ``folderContext`` = ``{name, siblings}`` (the file's
project path and the other paths of its folder). The Node server that owns the project's file
list adds it; the profiler uses it for folder-level facts (a FASTQ's mate, a 10x TSV's role).

The profiler ``galaxy.ai.data_perception`` does all the numeric work
(deterministic, no LLM, no network). This module only resolves ``datasetRef``
to a local file path and returns the emitted ``DataProfile`` dict verbatim so
ingest / the workflow composer can call it.

Auto-discovered exactly like ``nextflow_executor.py``: this package's
``router`` object is picked up by
``galaxy.webapps.base.api.include_all_package_routers``.
"""
# CRITICAL: keep this first. PEP 604 union syntax on Python 3.9 needs it and
# auto-sync has stripped it from sibling modules before, crash-looping gunicorn.
from __future__ import annotations

import hashlib
import json
import logging
import os
import tempfile
import time
from typing import Any, Dict, List, Optional

from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["perception"])


class PerceptionProfileRequest(BaseModel):
    # Accept either camelCase (frontend) or snake_case (server) for the ref.
    datasetRef: Optional[str] = None
    dataset_ref: Optional[str] = None
    # Optional display name for header crumb / notes only.
    name: Optional[str] = None
    # {"name": <project path>, "siblings": [<other paths in the same folder>]} — set by the
    # Node server from project_files, never trusted for access (that is checked upstream).
    folderContext: Optional[Dict[str, Any]] = None

    def resolved_ref(self) -> Optional[str]:
        return self.datasetRef or self.dataset_ref


class PerceptionRowsRequest(PerceptionProfileRequest):
    offset: int = 0
    limit: int = 200


# S3 key prefixes used by BioMate uploads / run outputs. An uploaded file's
# datasetRef arrives as a bare key like "projects/<id>/inputs/counts.csv"
# (no bucket), so we resolve it against the default nextflow/uploads bucket.
_S3_KEY_PREFIXES = ("projects/", "nextflow/", "uploads/", "inputs/", "outputs/")


def _download_s3_to_temp(bucket: str, key: str) -> Optional[str]:
    """Download an S3 object to a temp file; return its path or None on failure.

    boto3 + creds are present in the backend (same path the nextflow executor
    uses). Any failure degrades to None so the caller emits an honest
    ``blocked`` profile rather than fabricating one.
    """
    if not bucket or not key:
        return None
    try:
        import boto3  # available in the Galaxy backend
    except Exception as exc:  # pragma: no cover
        log.warning("[perception] boto3 unavailable: %s", exc)
        return None
    try:
        s3 = boto3.client("s3")
        # Keep the key's whole basename (all of "x.fastq.gz", "x.ome.tiff"): the profiler sniffs
        # the format from the name, and splitext kept only the last suffix (".gz").
        base = os.path.basename(key)
        suffix = "_" + "".join(c if (c.isalnum() or c in "._-") else "_" for c in base)[-80:]
        fd, tmp = tempfile.mkstemp(prefix="perception_", suffix=suffix)
        os.close(fd)
        s3.download_file(bucket, key, tmp)
        return tmp
    except Exception as exc:
        log.warning("[perception] S3 fetch failed for s3://%s/%s: %s", bucket, key, exc)
        return None


def _resolve_path(dataset_ref: str) -> Optional[str]:
    """Resolve a datasetRef to a readable local file path.

    Handles: a filesystem path (absolute or relative to CWD), an ``s3://bucket/key``
    URI, and a bare S3 upload key (``projects/<id>/inputs/…``) resolved against the
    default uploads bucket — uploaded files live in S3, not the local FS, which is
    why the Preview data-table was empty for real uploads. Unresolvable refs return
    None so the caller emits an honest ``blocked`` profile.
    """
    if not dataset_ref:
        return None
    ref = dataset_ref
    if ref.startswith("file://"):
        ref = ref[len("file://"):]
    # Local filesystem (dev / mounted inputs).
    if os.path.isabs(ref) and os.path.exists(ref):
        return ref
    if os.path.exists(ref):
        return os.path.abspath(ref)
    # Full S3 URI.
    if ref.startswith("s3://"):
        bkey = ref[len("s3://"):]
        if "/" in bkey:
            bucket, key = bkey.split("/", 1)
            return _download_s3_to_temp(bucket, key)
        return None
    # Bare S3 upload key -> default uploads bucket.
    if ref.lstrip("/").startswith(_S3_KEY_PREFIXES):
        bucket = (
            os.environ.get("AWS_S3_NEXTFLOW_BUCKET")
            or os.environ.get("AWS_S3_UPLOAD_BUCKET")
            or "biomate-nextflow-work"
        )
        return _download_s3_to_temp(bucket, ref.lstrip("/"))
    return None


def _is_perception_tempfile(path: Optional[str]) -> bool:
    """True if `path` is a temp file we created for an S3 download (safe to delete)."""
    if not path:
        return False
    return (
        os.path.dirname(path) == tempfile.gettempdir()
        and os.path.basename(path).startswith("perception_")
    )


@router.post("/api/perception/profile", summary="Profile a dataset and return a DataProfile")
def perception_profile(request: PerceptionProfileRequest) -> Dict[str, Any]:
    """Return the frontend ``DataProfile`` for ``datasetRef``.

    Degrades honestly: an unresolvable / unreadable ref yields a ``blocked``
    profile with a note, never a fabricated leakage / balance number.
    """
    from galaxy.ai.data_perception import blocked_profile, profile_dataset

    ref = request.resolved_ref()
    if not ref:
        return blocked_profile("no_ref", "No datasetRef provided.").to_dict()

    path = _resolve_path(ref)
    if not path:
        # The ref is not echoed: it can be an internal key or path.
        p = blocked_profile("unresolvable_ref", "")
        p.view_kind = "unknown"
        return p.to_dict()

    try:
        return profile_dataset(path, name=request.name, context=request.folderContext)
    finally:
        # Clean up an S3 download; leave local/mounted files untouched.
        if _is_perception_tempfile(path):
            try:
                os.remove(path)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Paged FULL rows (the Preview table) — same parser as the profiler.
# ---------------------------------------------------------------------------
# Paging re-reads the file once per page, so S3 objects are kept in a small on-disk
# cache keyed by (bucket, key, ETag): a replaced object (new ETag) is never served
# stale, and every gunicorn worker shares the cache (same tmp dir, atomic rename).
_ROWS_CACHE_DIR = os.path.join(tempfile.gettempdir(), "perception_rows_cache")
_ROWS_CACHE_MAX_FILES = 24
_ROWS_CACHE_MAX_BYTES = 4 * 1024 * 1024 * 1024


def _split_s3_ref(dataset_ref: str):
    """(bucket, key) for an S3 datasetRef, else None (local paths are read in place)."""
    ref = dataset_ref
    if ref.startswith("s3://"):
        bkey = ref[len("s3://"):]
        if "/" not in bkey:
            return None
        bucket, key = bkey.split("/", 1)
        return bucket, key
    if ref.lstrip("/").startswith(_S3_KEY_PREFIXES) and not os.path.exists(ref):
        bucket = (
            os.environ.get("AWS_S3_NEXTFLOW_BUCKET")
            or os.environ.get("AWS_S3_UPLOAD_BUCKET")
            or "biomate-nextflow-work"
        )
        return bucket, ref.lstrip("/")
    return None


def _prune_rows_cache() -> None:
    try:
        entries = []
        for name in os.listdir(_ROWS_CACHE_DIR):
            full = os.path.join(_ROWS_CACHE_DIR, name)
            if name.endswith(".part") or name.endswith(".meta.json"):
                continue
            st = os.stat(full)
            entries.append((st.st_mtime, st.st_size, full))
        entries.sort(reverse=True)  # newest first
        kept_bytes = 0
        for i, (_mtime, size, full) in enumerate(entries):
            kept_bytes += size
            if i >= _ROWS_CACHE_MAX_FILES or kept_bytes > _ROWS_CACHE_MAX_BYTES:
                for victim in (full, full + ".meta.json"):
                    try:
                        os.remove(victim)
                    except OSError:
                        pass
    except OSError:
        pass


def _cached_s3_path(bucket: str, key: str) -> Optional[str]:
    """Local cached copy of s3://bucket/key for the object's CURRENT ETag, or None."""
    try:
        import boto3  # available in the Galaxy backend
    except Exception as exc:  # pragma: no cover
        log.warning("[perception] boto3 unavailable: %s", exc)
        return None
    try:
        s3 = boto3.client("s3")
        etag = str(s3.head_object(Bucket=bucket, Key=key).get("ETag", "")).strip('"')
        os.makedirs(_ROWS_CACHE_DIR, exist_ok=True)
        digest = hashlib.sha256(f"{bucket}/{key}#{etag}".encode("utf-8")).hexdigest()[:32]
        # Keep the key's extension(s) — the parser sniffs kind/gzip from the name.
        base = os.path.basename(key)
        suffix = "".join(c if (c.isalnum() or c in "._-") else "_" for c in base)[-80:]
        path = os.path.join(_ROWS_CACHE_DIR, f"{digest}_{suffix}")
        if os.path.exists(path):
            os.utime(path, None)
            return path
        part = f"{path}.{os.getpid()}.{int(time.time() * 1000)}.part"
        s3.download_file(bucket, key, part)
        os.replace(part, path)
        _prune_rows_cache()
        return path
    except Exception as exc:
        log.warning("[perception] S3 rows fetch failed for s3://%s/%s: %s", bucket, key, exc)
        return None


def _reader_version() -> str:
    from galaxy.ai.data_perception import READ_ROWS_VERSION

    return READ_ROWS_VERSION


def _read_meta(path: str, layout_key: str = "") -> Optional[Dict[str, Any]]:
    try:
        with open(path + ".meta.json", "r", encoding="utf-8") as f:
            meta = json.load(f)
        # Columns / totals cached by an older reader (e.g. before header inference, when line 1
        # was always the header) describe different rows: re-read instead of serving them.
        if meta.get("reader") != _reader_version():
            return None
        # Same bytes read under a different folder context (a features.tsv that has since gained
        # its 10x matrix sibling) have a different header decision.
        if meta.get("layout", "") != layout_key:
            return None
        if isinstance(meta.get("columns"), list) and isinstance(meta.get("totalRows"), int):
            return meta
    except (OSError, ValueError):
        pass
    return None


def _write_meta(path: str, columns: Any, total: int, layout_key: str = "") -> None:
    tmp = f"{path}.meta.json.{os.getpid()}.part"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"columns": columns, "totalRows": total, "reader": _reader_version(),
                       "layout": layout_key}, f)
        os.replace(tmp, path + ".meta.json")
    except OSError:
        pass


@router.post("/api/perception/rows", summary="One page of a table-like dataset's full rows")
def perception_rows(request: PerceptionRowsRequest) -> Dict[str, Any]:
    """Return ``{kind, tabular, columns, rows, offset, limit, totalRows}`` for ``datasetRef``.

    Rows are parsed by ``galaxy.ai.data_perception.read_rows`` — the SAME CSV/TSV/JSONL
    readers the profiler uses — so the table and the QC card describe the same rows.
    Unresolvable refs return ``{"error": ...}`` (the Node layer maps it to an HTTP status).
    """
    from galaxy.ai.data_perception import read_rows, rows_layout_key

    ref = request.resolved_ref()
    layout_key = rows_layout_key(request.folderContext)
    if not ref:
        return {"error": "no_ref"}
    s3_ref = _split_s3_ref(ref)
    if s3_ref:
        path = _cached_s3_path(*s3_ref)
        cached = True
    else:
        path = _resolve_path(ref)
        cached = False
    if not path:
        return {"error": "unresolvable_ref"}
    known = _read_meta(path, layout_key) if cached else None
    try:
        page = read_rows(path, request.offset, request.limit, known=known, context=request.folderContext,
                         name=request.name or os.path.basename(s3_ref[1] if s3_ref else path))
    except Exception as exc:  # noqa: BLE001 — a parse error is a result, not a crash
        # The detail stays in the log: exception text carries temp paths and library internals.
        log.warning("[perception] rows read failed for %s: %s", ref, exc)
        return {"error": "parse_failed"}
    if cached and known is None and page.get("tabular"):
        _write_meta(path, page.get("columns", []), int(page.get("totalRows", 0)), layout_key)
    return page


# ---------------------------------------------------------------------------
# Folder profile — what a project folder holds as a whole (pairs, 10x sets, roll-up).
# ---------------------------------------------------------------------------
class FolderProfileRequest(BaseModel):
    path: str = ""
    # The project the folder belongs to (the Node server resolved it and checked the caller's
    # access). Every datasetRef must be an S3 key inside ``projects/<projectId>/``.
    projectId: Optional[str] = None
    # [{"name": <project path>, "datasetRef": <S3 key>}] — every file below `path` (set by the
    # Node server from project_files; entries without a string name are ignored).
    files: List[Dict[str, Any]] = []


_HEAD_BYTES = 64 * 1024


def _decompress_head(raw: bytes) -> bytes:
    """Decompress the leading bytes of a gzip / bzip2 stream (a partial stream is fine)."""
    import zlib

    if raw[:2] == b"\x1f\x8b":
        try:
            return zlib.decompressobj(wbits=47).decompress(raw)
        except zlib.error:
            return b""
    if raw[:3] == b"BZh":
        import bz2

        try:
            return bz2.BZ2Decompressor().decompress(raw)
        except (OSError, EOFError):
            return b""
    return raw


def _default_bucket() -> str:
    return (
        os.environ.get("AWS_S3_NEXTFLOW_BUCKET")
        or os.environ.get("AWS_S3_UPLOAD_BUCKET")
        or "biomate-nextflow-work"
    )


_PROJECT_KEY_PREFIX = "projects/"


def _project_of_key(key: str) -> Optional[str]:
    """``<id>`` of a ``projects/<id>/<path>`` key, or None for any other / unsafe key."""
    if not key.startswith(_PROJECT_KEY_PREFIX) or "\\" in key or "\x00" in key:
        return None
    parts = key.split("/")
    if len(parts) < 3 or not parts[1] or not parts[-1] or any(p in ("", ".", "..") for p in parts[1:]):
        return None
    return parts[1]


def folder_object_ref(dataset_ref: Any, project_id: Optional[str]) -> Optional[tuple]:
    """(bucket, key) for a folder-profile datasetRef that is a server-resolved project object:
    a bare ``projects/<projectId>/…`` key (or ``s3://<the uploads bucket>/projects/<projectId>/…``).
    Everything else — absolute or relative local paths, ``file://``, other buckets, keys outside
    the project — is refused (None): the endpoint never reads what a request merely names."""
    if not isinstance(dataset_ref, str) or not dataset_ref or not project_id:
        return None
    ref = dataset_ref
    bucket = _default_bucket()
    if ref.startswith("s3://"):
        bkey = ref[len("s3://"):]
        if "/" not in bkey:
            return None
        b, key = bkey.split("/", 1)
        if b != bucket:
            return None
    elif "://" in ref or ref.startswith("/") or ref.startswith("~"):
        return None
    else:
        key = ref
    if _project_of_key(key) != project_id:
        return None
    return bucket, key


def _s3_head(bucket: str, key: str) -> Optional[bytes]:
    """First _HEAD_BYTES of an object: a ranged GET, never the whole object (a 10x matrix can be
    gigabytes)."""
    try:
        import boto3  # available in the Galaxy backend

        obj = boto3.client("s3").get_object(Bucket=bucket, Key=key, Range=f"bytes=0-{_HEAD_BYTES - 1}")
        return obj["Body"].read()
    except Exception as exc:  # noqa: BLE001
        log.warning("[perception] head read failed for s3://%s/%s: %s", bucket, key, exc)
        return None


def _read_head(obj: Optional[tuple]) -> Optional[str]:
    """First ~64 KB (decompressed) of a validated project object as text; None when unreadable."""
    if not obj:
        return None
    raw = _s3_head(*obj)
    if raw is None:
        return None
    return _decompress_head(raw).decode("utf-8", errors="replace")


def _galaxy_classifier():
    """name → (format key, label) from Galaxy's datatype registry (by filename only), falling
    back to folder_profile's own table when Galaxy's datatypes are unavailable."""
    from galaxy.ai import folder_profile

    try:
        from galaxy.ai import galaxy_formats as gf
    except Exception:  # noqa: BLE001
        return folder_profile.default_classify

    def classify(name: str):
        ext = None
        try:
            ext = gf.extension_for_name(name)
        except Exception:  # noqa: BLE001
            ext = None
        if not ext or ext in gf.GENERIC_EXTS - {"tsv", "tabular", "txt"}:
            return folder_profile.default_classify(name)
        return ext, gf.label_for(ext)

    return classify


@router.post("/api/perception/folder_profile", summary="Profile a project folder as a whole")
def perception_folder_profile(request: FolderProfileRequest) -> Dict[str, Any]:
    """Return the FolderProfile for ``files`` (every file below ``path``; names are project
    paths). Only the matrix of each 10x set is read (its first 64 KB, for cells × genes), and only
    when its datasetRef is an S3 key of the request's project (:func:`folder_object_ref`).

    ``projectId`` comes from the Node server, which resolved the folder's files from the project
    it authorised. Without it nothing is read (the profile is built from the names alone); refs
    naming anything else — a local path, another bucket, another project — are never read.
    """
    from galaxy.ai.folder_profile import profile_folder

    project_id = request.projectId if isinstance(request.projectId, str) and request.projectId else None
    named: Dict[str, Any] = {}
    for f in request.files or []:
        if isinstance(f, dict) and isinstance(f.get("name"), str):
            named[f["name"]] = f.get("datasetRef")
    refs: Dict[str, Optional[tuple]] = {n: folder_object_ref(r, project_id) for n, r in named.items()}
    refused = sum(1 for n, r in named.items() if r is not None and refs[n] is None)
    if refused:
        log.warning("[perception] folder_profile refused %d datasetRef(s) outside projects/%s/", refused,
                    project_id or "?")
    return profile_folder(
        request.path or "",
        list(named),
        read_head=lambda name: _read_head(refs.get(name)),
        classify=_galaxy_classifier(),
    )
