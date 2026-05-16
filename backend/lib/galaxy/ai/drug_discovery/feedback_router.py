"""
Customer feedback API router (Appendix B of IND Product UI doc).

Mounts 6 endpoints under /api/ind-report and /api/regulatory:
  POST /api/ind-report/projects/{id}/edit
  POST /api/ind-report/audit/{finding_id}/dismiss
  POST /api/ind-report/citations/suggest
  POST /api/ind-report/sections/{section_id}/regenerate
  GET  /api/regulatory/feedback/queue
  GET  /api/regulatory/active_adapter

Customer-facing POST endpoints require a Bearer JWT (verified via the
AuthService in webapps/galaxy/api/auth.py) and are rate-limited per IP.
The internal endpoints fail closed when BIOMATE_INTERNAL_KEY is unset.
The active-adapter endpoint gates org-id routing by billing-tier
entitlement (paid_orgs.json).

See feedback_auth.py for the dependency implementations.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field

from .feedback_auth import (
    is_org_entitled_to_adapter,
    require_authenticated_user,
    require_internal_key,
)
from .feedback_io import (
    read_feedback_queue,
    record_audit_dismissal,
    record_citation_suggestion,
    record_customer_edit,
    record_prompt_tuning_signal,
)
from .ind_assembly import _resolve_adapter_path

log = logging.getLogger(__name__)

router = APIRouter(tags=["customer_feedback"])


# ---------------------------------------------------------------------------
# Request bodies
# ---------------------------------------------------------------------------

class EditCapture(BaseModel):
    paragraph_id: str
    original: str
    edited: str
    section_type: str
    structured_input: str = Field("", description="The prompt context that generated this paragraph")


class DismissalCapture(BaseModel):
    rule_id: str
    section_type: str
    reason: str = Field(..., pattern="^(not_applicable|already_addressed|acceptable_risk|disagree)$")
    free_text: Optional[str] = None
    document_state_hash: Optional[str] = None


class CitationSuggestion(BaseModel):
    guideline_id: str
    rationale: str
    document_only: bool = False


class RegenerateRequest(BaseModel):
    instruction: Optional[str] = None
    before: Optional[str] = None
    after: Optional[str] = None


# ---------------------------------------------------------------------------
# Customer-facing endpoints — auth + rate-limited
# ---------------------------------------------------------------------------

@router.post("/api/ind-report/projects/{project_id}/edit")
async def capture_edit(
    project_id: str,
    body: EditCapture,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """
    Capture a paragraph edit as a DPO pair candidate.
    Called by the IND Report TipTap editor on debounced save (~5s after last keystroke).
    """
    if len(body.edited.strip()) == 0:
        raise HTTPException(400, "edited content cannot be empty")
    if body.edited.strip() == body.original.strip():
        return {"recorded": False, "reason": "no change"}
    row_id = record_customer_edit(
        prompt=body.structured_input,
        chosen=body.edited,
        rejected=body.original,
        section_type=body.section_type,
        paragraph_id=body.paragraph_id,
        org_id=x_biomate_org_id,
    )
    log.info("[feedback] edit captured project=%s pid=%s row=%s user=%s",
             project_id, body.paragraph_id, row_id, user.get("user_id"))
    return {"recorded": True, "id": row_id}


@router.post("/api/ind-report/audit/{finding_id}/dismiss")
async def capture_dismissal(
    finding_id: str,
    body: DismissalCapture,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """Capture an audit-finding dismissal with reason → checker rule refinement queue."""
    row_id = record_audit_dismissal(
        finding_id=finding_id,
        rule_id=body.rule_id,
        section_type=body.section_type,
        reason=body.reason,
        free_text=body.free_text,
        document_state_hash=body.document_state_hash,
        org_id=x_biomate_org_id,
    )
    log.info("[feedback] dismissal captured finding=%s reason=%s row=%s user=%s",
             finding_id, body.reason, row_id, user.get("user_id"))
    return {"recorded": True, "id": row_id}


@router.post("/api/ind-report/citations/suggest")
async def suggest_citation(
    body: CitationSuggestion,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """
    Customer-suggested missing citation. If document_only=True, the suggestion
    is local to their draft (caller inserts it). If False, it also enters the
    corpus-extension review queue.
    """
    if not body.guideline_id.strip():
        raise HTTPException(400, "guideline_id required")
    row_id = record_citation_suggestion(
        guideline_id=body.guideline_id,
        rationale=body.rationale,
        document_only=body.document_only,
        org_id=x_biomate_org_id,
    )
    log.info("[feedback] citation suggested guideline=%s document_only=%s row=%s user=%s",
             body.guideline_id, body.document_only, row_id, user.get("user_id"))
    return {"recorded": True, "id": row_id, "queued_for_review": not body.document_only}


@router.post("/api/ind-report/sections/{section_id}/regenerate")
async def regenerate_section(
    section_id: str,
    body: RegenerateRequest,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """
    Records a regenerate-with-instruction request as a prompt-tuning signal.
    If `before` and `after` are provided in the same POST (single-shot mode),
    the record is complete. Otherwise the row is marked pending and the
    client may PATCH `before`/`after` later (not yet implemented).

    Note: actual section regeneration is delegated to the existing IND
    pipeline endpoints in api_router.py; this route captures the prompt-
    tuning intent only.
    """
    if not body.instruction or not body.instruction.strip():
        return {"recorded": False, "reason": "no instruction provided"}
    row_id = record_prompt_tuning_signal(
        section_type=section_id,
        instruction=body.instruction,
        before=body.before or "",
        after=body.after or "",
        follow_up_edit=False,
        org_id=x_biomate_org_id,
    )
    return {"recorded": True, "id": row_id}


# ---------------------------------------------------------------------------
# Internal endpoints — fail closed
# ---------------------------------------------------------------------------

@router.get("/api/regulatory/feedback/queue")
async def feedback_queue(
    kind: str = Query("customer_pairs",
                      regex="^(customer_pairs|checker_feedback|citation_extensions|prompt_tuning)$"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: None = Depends(require_internal_key),
):
    """Internal — paginated review queue. Fails closed when
    BIOMATE_INTERNAL_KEY is not set."""
    return {"kind": kind, "items": read_feedback_queue(kind=kind, limit=limit, offset=offset)}


@router.get("/api/regulatory/active_adapter")
async def active_adapter(
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """
    Returns the LoRA adapter currently serving for this caller.
    Per-org adapters take precedence when X-BioMate-Org-Id is set AND the
    org is on the paid-orgs entitlement list AND the org-specific adapter
    exists on disk. Unentitled org_ids silently fall back to the public adapter.
    """
    effective_org = x_biomate_org_id if is_org_entitled_to_adapter(x_biomate_org_id) else None
    path = _resolve_adapter_path(org_id=effective_org)
    name = path.parent.name
    is_customized = bool(effective_org) and effective_org in name
    return {
        "adapter_name": name,
        "adapter_path": str(path),
        "exists": path.exists(),
        "customized_for": effective_org if is_customized else None,
        "entitled": bool(effective_org),
    }
