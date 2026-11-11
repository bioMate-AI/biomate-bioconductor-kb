"""
POST /api/model-training/plan — structured training plan for the Models panel.

Admin-only (like models_inference): the browser never calls this directly. The
Node server authenticates the user, checks project access, resolves + stages
the project file to a Batch-readable s3:// URI, and forwards the structured
fields with the admin key and ``X-BioMate-User-Id``.

The response is a workflow_ga that Node submits through the ordinary
POST /api/workflows/execute path (run record, SSE, billing, Run Manager).
Validation failures are 400 with the human-readable ConfigError message.
"""
# Keep first: PEP 604 unions on Python 3.9 (gunicorn boot-crash history).
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from fastapi import Body, Header, HTTPException

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["model-training"])


def _dataset_rows(s3_uri: str) -> Optional[int]:
    """Row count of the staged dataset via the perception profiler (the same reader
    the panel's column picker uses). None when it cannot be read — the plan then
    proceeds and the training job reports the problem itself."""
    import os

    from galaxy.ai.data_perception import profile_to_dataclass
    from galaxy.webapps.galaxy.api.perception import _is_perception_tempfile, _resolve_path

    # Only delimited tables have a meaningful row = sample count here; h5ad /
    # JSONL / SDF datasets are sized by their own trainers.
    if not s3_uri.lower().endswith((".csv", ".tsv", ".txt", ".csv.gz", ".tsv.gz")):
        return None
    path = None
    try:
        path = _resolve_path(s3_uri)
        if not path:
            return None
        profile = profile_to_dataclass(path, name=s3_uri.rsplit("/", 1)[-1])
        if profile.quality == "blocked" and not profile.rows:
            return None  # unreadable ≠ zero rows
        return int(profile.rows) if isinstance(profile.rows, int) and profile.rows >= 0 else None
    except Exception as exc:  # profiling is advisory here; never block on a reader bug
        log.warning("[model-training/plan] could not count rows of %s: %s", s3_uri, exc)
        return None
    finally:
        if _is_perception_tempfile(path):
            try:
                os.unlink(path)
            except OSError:
                pass


@router.post(
    "/api/model-training/plan",
    require_admin=True,
    summary="Validate a structured training request and return its workflow_ga.",
)
def plan_model_training(
    body: Dict[str, Any] = Body(...),
    owner_id: Optional[str] = Header(None, alias="X-BioMate-User-Id"),
) -> Dict[str, Any]:
    if not isinstance(owner_id, str) or not owner_id.strip():
        raise HTTPException(status_code=403, detail="Authenticated owner context is required")
    from galaxy.ai.ml_training.config import ConfigError
    from galaxy.ai.ml_training.plan import build_training_plan

    try:
        return build_training_plan(body, rows_of=_dataset_rows)
    except ConfigError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except (TypeError, ValueError) as exc:
        # e.g. a spec field of the wrong type reaching a dataclass validate().
        raise HTTPException(status_code=400, detail=f"invalid training request: {exc}")
