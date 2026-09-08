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


def _resolve_path(dataset_ref: str) -> Optional[str]:
    """Resolve a datasetRef to a readable local file path.

    Currently supports a plain filesystem path (absolute or relative to CWD).
    Non-existent / unresolvable refs return None so the caller emits an honest
    ``blocked`` profile instead of fabricating one.
    """
    if not dataset_ref:
        return None
    # Strip an optional file:// scheme.
    ref = dataset_ref
    if ref.startswith("file://"):
        ref = ref[len("file://"):]
    if os.path.isabs(ref) and os.path.exists(ref):
        return ref
    if os.path.exists(ref):
        return os.path.abspath(ref)
    return None


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

    return profile_dataset(path, name=request.name)
