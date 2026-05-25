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

import json
import logging
import os
import re
import time
import uuid
from pathlib import Path
from typing import Any, Optional

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


# ---------------------------------------------------------------------------
# IND project registry — lightweight JSON-backed CRUD
#
# The IND Report UI lists "projects" (one per drug-development program).
# Pre-this-route the frontend hardcoded a DEMO_PROJECTS array. This endpoint
# replaces that path with a real persistent store at:
#
#     data/ind_demo/registry/projects.json
#
# Schema is intentionally flat — every field the IndProjectSummary type in
# components/ind-report/IndLeftNav.tsx expects, plus a few audit metadata
# fields. Reads are unauthenticated (the project list is shown in onboarding
# before login on some flows). Writes require the same auth dep as the
# feedback endpoints.
# ---------------------------------------------------------------------------

_PROJECTS_PATH = Path(__file__).resolve().parents[5] / "data" / "ind_demo" / "registry" / "projects.json"

_VALID_ID = re.compile(r"^[a-zA-Z0-9_-]{1,40}$")
_VALID_REGIONS = {"FDA", "EMA", "NMPA", "PMDA"}
_VALID_STATUS = {"in_progress", "signed", "blocked", "draft"}


class ProjectCreate(BaseModel):
    id: Optional[str] = Field(None, description="Stable project id. Auto-generated if omitted.")
    molecule: str = Field(..., min_length=1, max_length=80)
    target: str = Field(..., min_length=1, max_length=120)
    indication: str = Field(..., min_length=1, max_length=120)
    sponsor: str = Field(..., min_length=1, max_length=120)
    sponsor_id: Optional[str] = Field(None, max_length=64)
    regions: list[str] = Field(default_factory=list)
    status: str = Field("draft")
    statusText: Optional[str] = Field(None, max_length=200)
    data_dir: Optional[str] = Field(None, max_length=200)


def _load_projects() -> dict:
    if not _PROJECTS_PATH.exists():
        return {"_schema_version": 1, "projects": []}
    try:
        return json.loads(_PROJECTS_PATH.read_text())
    except json.JSONDecodeError as exc:
        log.error("[projects] registry corrupted: %s", exc)
        raise HTTPException(500, "project registry corrupted")


def _save_projects(registry: dict) -> None:
    _PROJECTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = _PROJECTS_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(registry, indent=2, ensure_ascii=False))
    tmp.replace(_PROJECTS_PATH)


@router.get("/api/ind-report/projects")
async def list_projects():
    """Return all projects in the registry. Anonymous-readable."""
    registry = _load_projects()
    return {"projects": registry.get("projects", [])}


@router.get("/api/ind-report/projects/{project_id}")
async def get_project(project_id: str):
    if not _VALID_ID.match(project_id):
        raise HTTPException(400, "invalid project id")
    registry = _load_projects()
    for p in registry.get("projects", []):
        if p["id"] == project_id:
            return p
    raise HTTPException(404, f"project not found: {project_id}")


@router.post("/api/ind-report/projects")
async def create_project(
    body: ProjectCreate,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """Append a new project. Generates id if none provided; rejects duplicate id."""
    bad_regions = [r for r in body.regions if r not in _VALID_REGIONS]
    if bad_regions:
        raise HTTPException(400, f"invalid regions: {bad_regions}")
    if body.status not in _VALID_STATUS:
        raise HTTPException(400, f"invalid status: {body.status} (allowed: {sorted(_VALID_STATUS)})")

    project_id = body.id or f"p-{uuid.uuid4().hex[:10]}"
    if not _VALID_ID.match(project_id):
        raise HTTPException(400, "invalid project id format")

    registry = _load_projects()
    if any(p["id"] == project_id for p in registry.get("projects", [])):
        raise HTTPException(409, f"project id already exists: {project_id}")

    project = body.model_dump(exclude_none=True)
    project["id"] = project_id
    project.setdefault("created_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    project.setdefault("created_by", user.get("user_id", "anonymous"))
    if x_biomate_org_id:
        project["org_id"] = x_biomate_org_id

    registry.setdefault("projects", []).append(project)
    _save_projects(registry)
    log.info("[projects] created id=%s molecule=%s by=%s",
             project_id, body.molecule, user.get("user_id"))
    return project


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
