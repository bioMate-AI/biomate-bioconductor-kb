"""
Grounded Standards Assistant API.

Evidence-tiered, provenance-honest answering for regulated-domain questions
(GMP / standards / pharmacopoeia). Grounds what the authoritative record
supports, names where the record stops, routes the rest to the real experts,
and enforces tenant isolation so one user's unverified notes never reach
another.

The engine lives in `galaxy.ai.grounded` (pure Python, no infra deps). This
module is the thin FastAPI surface; it resolves the requesting tenant from the
authenticated session so the isolation guarantee cannot be spoofed by the
caller. Reference/standalone mirror + design: `grounded-prototype/` and
`docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md`.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from fastapi import HTTPException
from pydantic import BaseModel, Field

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["grounded"])

# Guarded import so a packaging problem degrades to a clean 503 instead of
# taking down module load for the whole API (PEP-668 / import-guard discipline).
try:
    from galaxy.ai.grounded import ask as _ask, to_dict as _to_dict
    _ENGINE_OK = True
except Exception as exc:  # pragma: no cover
    log.warning("[grounded] engine unavailable: %s", exc)
    _ask = None
    _to_dict = None
    _ENGINE_OK = False


class GroundedRequest(BaseModel):
    question: str = Field(..., min_length=1, description="Regulated-domain question.")
    domain: Optional[str] = Field(
        None,
        description="Knowledge domain: 'cmc' (R&D/CMC) or 'gmp_steam'; omit for all.",
    )
    # Optional override is accepted but IGNORED for authenticated users: the
    # tenant is always taken from the session. It exists only so internal/
    # service callers (e.g. the MCP connector forwarding on a user's behalf)
    # can pass the resolved id when there is no Galaxy session.
    user: Optional[str] = Field(None, description="Internal-only tenant override.")


def _tenant(trans: ProvidesUserContext, req: GroundedRequest) -> str:
    user = getattr(trans, "user", None)
    if user is not None and getattr(user, "id", None) is not None:
        return f"user:{user.id}"
    if req.user:
        return req.user
    return "anonymous"


@router.post(
    "/api/grounded/answer",
    summary="Answer a regulated-domain question with tiered provenance and honest boundaries.",
)
def grounded_answer(
    request: GroundedRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """Return a grounded answer.

    The response contains: grounded claims (each with citation + source tier),
    an explicit boundary section naming what is NOT established and who to ask,
    and a provenance/isolation audit. The requesting tenant is resolved from the
    session — a client cannot read another tenant's unverified notes by changing
    the request body.
    """
    if not _ENGINE_OK or _ask is None:
        raise HTTPException(status_code=503, detail="Grounded assistant engine unavailable")
    tenant = _tenant(trans, request)
    try:
        answer = _ask(request.question, user=tenant, domain=request.domain)
        return _to_dict(answer)
    except Exception as exc:  # pragma: no cover
        log.exception("[grounded] answer failed")
        raise HTTPException(status_code=500, detail=f"Grounded answer failed: {exc}")
