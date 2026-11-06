"""
Data-perception API — thin endpoint over the rules-first profiler.

POST /api/perception/profile  { datasetRef }  ->  DataProfile

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

import logging
import os
import tempfile
from typing import Any, Dict, Optional

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

    def resolved_ref(self) -> Optional[str]:
        return self.datasetRef or self.dataset_ref


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
        suffix = os.path.splitext(key)[1] or ""
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
    from galaxy.ai.data_perception import DataProfile, profile_dataset

    ref = request.resolved_ref()
    if not ref:
        return DataProfile(
            quality="blocked",
            notes=["No datasetRef provided."],
        ).to_dict()

    path = _resolve_path(ref)
    if not path:
        return DataProfile(
            quality="blocked",
            notes=[f"Could not resolve datasetRef to a readable file: {ref!r}."],
        ).to_dict()

    try:
        return profile_dataset(path, name=request.name)
    finally:
        # Clean up an S3 download; leave local/mounted files untouched.
        if _is_perception_tempfile(path):
            try:
                os.remove(path)
            except OSError:
                pass
