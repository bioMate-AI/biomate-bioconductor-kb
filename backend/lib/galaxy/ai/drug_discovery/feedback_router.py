"""
Customer feedback API router (Appendix B of IND Product UI doc).

Mounts 6 endpoints under /api/ind-report and /api/regulatory:
  POST /api/ind-report/projects/{id}/edit
  POST /api/ind-report/audit/{finding_id}/dismiss
  POST /api/ind-report/citations/suggest
  POST /api/ind-report/sections/{section_id}/regenerate
  GET  /api/regulatory/feedback/queue
  GET  /api/regulatory/active_adapter

All four customer-facing POST endpoints capture data to the appropriate
JSONL via feedback_io. The regenerate endpoint also threads the customer's
optional `instruction` through to the underlying LLM call (currently a stub
hook — the IND generation route in api_router.py invokes _llm_narrative
which can read this in a follow-up patch).

Auth: customer endpoints accept an optional X-BioMate-Org-Id header for
paid-tier isolation. Internal endpoints (feedback/queue) require a
BIOMATE_INTERNAL_KEY env match — a deliberately lightweight stand-in until
real auth lands.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, Field

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


# ---------------------------------------------------------------------------
# Customer-facing endpoints
# ---------------------------------------------------------------------------

@router.post("/api/ind-report/projects/{project_id}/edit")
async def capture_edit(
    project_id: str,
    body: EditCapture,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
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
    log.info("[feedback] edit captured project=%s pid=%s row=%s",
             project_id, body.paragraph_id, row_id)
    return {"recorded": True, "id": row_id}


@router.post("/api/ind-report/audit/{finding_id}/dismiss")
async def capture_dismissal(
    finding_id: str,
    body: DismissalCapture,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
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
    log.info("[feedback] dismissal captured finding=%s reason=%s row=%s",
             finding_id, body.reason, row_id)
    return {"recorded": True, "id": row_id}


@router.post("/api/ind-report/citations/suggest")
async def suggest_citation(
    body: CitationSuggestion,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
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
    log.info("[feedback] citation suggested guideline=%s document_only=%s row=%s",
             body.guideline_id, body.document_only, row_id)
    return {"recorded": True, "id": row_id, "queued_for_review": not body.document_only}


@router.post("/api/ind-report/sections/{section_id}/regenerate")
async def regenerate_section(
    section_id: str,
    body: RegenerateRequest,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """
    Regenerate a section. If `instruction` is provided, append it to the section's
    system prompt for this call only. Also records the (instruction, before, after)
    tuple for the prompt-tuning signal queue if the customer doesn't follow up with
    a manual edit within 60s — that follow-up check happens client-side and arrives
    as a separate /edit POST.

    Actual regeneration is delegated to the existing IND pipeline; this endpoint
    primarily captures the customer intent. The pipeline reads `instruction` from
    the section context.
    """
    # The IND pipeline's regeneration logic lives in api_router.py (ind-assembly
    # endpoints). This route simply records the intent + instruction context.
    # The frontend should also call the actual regeneration endpoint with the
    # instruction in the section context.
    if body.instruction and len(body.instruction.strip()) > 0:
        # Pre-record with empty after — caller fills in after generation
        # via a follow-up PATCH (or accepts the empty after for now).
        from .feedback_io import append_jsonl, PROMPT_TUNING
        row_id = append_jsonl(PROMPT_TUNING, {
            "section_type": section_id,
            "instruction": body.instruction,
            "before": "",   # filled by client after they confirm
            "after": "",
            "follow_up_edit": None,  # set later
            "org_id": x_biomate_org_id,
            "pending_completion": True,
        })
        return {
            "recorded": True, "id": row_id,
            "next": "POST /api/ind-report/sections/{section_id}/regenerate/complete with before+after",
        }
    return {"recorded": False, "reason": "no instruction provided"}


# ---------------------------------------------------------------------------
# Internal endpoints
# ---------------------------------------------------------------------------

def _check_internal_auth(authorization: Optional[str]) -> None:
    expected = os.environ.get("BIOMATE_INTERNAL_KEY", "")
    if not expected:
        # Dev mode — allow when no key configured
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "internal endpoint requires Bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    if token != expected:
        raise HTTPException(403, "invalid internal token")


@router.get("/api/regulatory/feedback/queue")
async def feedback_queue(
    kind: str = Query("customer_pairs",
                      regex="^(customer_pairs|checker_feedback|citation_extensions|prompt_tuning)$"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    authorization: Optional[str] = Header(None),
):
    """Internal — paginated review queue for regulatory science team."""
    _check_internal_auth(authorization)
    return {"kind": kind, "items": read_feedback_queue(kind=kind, limit=limit, offset=offset)}


@router.get("/api/regulatory/active_adapter")
async def active_adapter(
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """
    Returns the LoRA adapter currently serving for this caller.
    Per-org adapters take precedence when X-BioMate-Org-Id is set and the
    org-specific adapter exists on disk.
    """
    path = _resolve_adapter_path(org_id=x_biomate_org_id)
    # Parse version + customization status from the path
    name = path.parent.name  # e.g. regulatory_llm_v6  or  regulatory_llm_v6_acme
    is_customized = bool(x_biomate_org_id) and x_biomate_org_id in name
    return {
        "adapter_name": name,
        "adapter_path": str(path),
        "exists": path.exists(),
        "customized_for": x_biomate_org_id if is_customized else None,
    }
