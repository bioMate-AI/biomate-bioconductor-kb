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
        return build_training_plan(body)
    except ConfigError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except (TypeError, ValueError) as exc:
        # e.g. a spec field of the wrong type reaching a dataclass validate().
        raise HTTPException(status_code=400, detail=f"invalid training request: {exc}")
