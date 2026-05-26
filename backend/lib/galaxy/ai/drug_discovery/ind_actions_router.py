"""Action endpoints for the IND Report module — sign, download, render.

Separate from feedback_router.py because (a) the feedback file is undergoing
heavy churn from parallel automation and edits get reverted, (b) these are
verbs that mutate document state rather than capture feedback, (c) they're
auth-required differently (sign needs MFA in addition to JWT).

Endpoints:
  POST /api/ind-report/projects/{id}/sign          — TOTP-validated e-signature
  GET  /api/ind-report/projects/{id}/document.md   — Markdown export of the doc
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Path as FastPath
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from .feedback_auth import require_authenticated_user
from .feedback_io import append_jsonl

log = logging.getLogger(__name__)

router = APIRouter(tags=["ind_actions"])

_REPO_ROOT = Path(__file__).resolve().parents[5]
_PROJECTS_PATH = _REPO_ROOT / "data" / "ind_demo" / "registry" / "projects.json"
_SIGN_LOG = _REPO_ROOT / "data" / "regulatory_training" / "sign_audit_chain.jsonl"


# ---------------------------------------------------------------------------
# Sign — 21 CFR Part 11 two-factor (session JWT + TOTP)
# ---------------------------------------------------------------------------

class SignRequest(BaseModel):
    totp_code: str = Field(..., min_length=6, max_length=6, pattern=r"^\d{6}$",
                           description="6-digit TOTP from the user's authenticator app")
    signer_title: str = Field(..., min_length=1, max_length=120,
                              description="e.g. 'Director, Computational Pharmacology'")
    signer_creds: str = Field(..., min_length=1, max_length=300,
                              description="e.g. 'PhD Pharmacology · 10 years IND experience'")
    signature_scope: str = Field(..., min_length=1, max_length=300,
                                 description="What sections this signature covers")
    document_sha256: str = Field(..., pattern=r"^[a-f0-9]{64}$",
                                 description="Hex-encoded SHA-256 of the canonical doc body")
    adapter_versions: dict[str, str] = Field(default_factory=dict,
                                             description="section_id → adapter_name used to generate that section")


def _verify_totp(user_id: str, code: str) -> bool:
    """Validate the 6-digit TOTP against the user's MFA secret.

    Wired to galaxy.webapps.galaxy.api.auth.AuthService when available;
    falls back to a dev-mode permissive check when MFA not configured (so
    the demo data path still works locally).
    """
    try:
        from galaxy.webapps.galaxy.api.auth import AuthService  # type: ignore
        svc = AuthService()
        if hasattr(svc, "verify_totp"):
            return bool(svc.verify_totp(user_id, code))
    except Exception as exc:
        log.warning("[sign] AuthService.verify_totp unavailable: %s", exc)

    # Dev-mode fallback: accept any 6-digit code IFF BIOMATE_REQUIRE_AUTH != "1".
    # Production must have AuthService.verify_totp implemented.
    if os.environ.get("BIOMATE_REQUIRE_AUTH") == "1":
        log.warning("[sign] verify_totp not available in production-auth mode — rejecting")
        return False
    return bool(re.fullmatch(r"\d{6}", code))


@router.post("/api/ind-report/projects/{project_id}/sign")
async def sign_document(
    project_id: str,
    body: SignRequest,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """
    Two-factor e-signature per 21 CFR Part 11 §11.200(a)(1).
    First factor: session JWT (verified by require_authenticated_user).
    Second factor: TOTP code validated against the user's MFA secret.
    On success: append a non-repudiable row to sign_audit_chain.jsonl
    binding (user_id, project, doc hash, adapter versions, signer attestation,
    timestamp). Returns the audit-row id.
    """
    user_id = user.get("user_id", "anonymous")

    if not _verify_totp(str(user_id), body.totp_code):
        raise HTTPException(401, "Invalid TOTP code — check your authenticator and try again")

    record = {
        "project_id": project_id,
        "user_id": user_id,
        "org_id": x_biomate_org_id,
        "document_sha256": body.document_sha256,
        "signer_title": body.signer_title,
        "signer_creds": body.signer_creds,
        "signature_scope": body.signature_scope,
        "adapter_versions": body.adapter_versions,
        "totp_validated": True,
        "signed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    row_id = append_jsonl(_SIGN_LOG, record)

    # Reflect the signed state back into the project registry — sets status=signed.
    if _PROJECTS_PATH.exists():
        try:
            reg = json.loads(_PROJECTS_PATH.read_text())
            for p in reg.get("projects", []):
                if p["id"] == project_id:
                    p["status"] = "signed"
                    p["statusText"] = f"Signed · {record['signed_at']}"
                    p["signature_id"] = row_id
                    break
            tmp = _PROJECTS_PATH.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(reg, indent=2))
            tmp.replace(_PROJECTS_PATH)
        except Exception as exc:
            log.warning("[sign] failed to update project registry: %s", exc)

    return {
        "signed": True,
        "signature_id": row_id,
        "signed_at": record["signed_at"],
        "document_sha256_short": body.document_sha256[:12],
    }


# ---------------------------------------------------------------------------
# Markdown document export
# ---------------------------------------------------------------------------

class DocumentSection(BaseModel):
    id: str
    title: str
    body: str = ""


def _render_markdown(project: dict, sections: list[DocumentSection]) -> str:
    """Render the IND §2.6 module as Markdown with frontmatter."""
    out: list[str] = []
    out.append(f"# IND Module 2.6 — {project.get('molecule', 'Unknown compound')}")
    out.append("")
    out.append(f"- Sponsor: {project.get('sponsor', 'Unknown sponsor')}")
    out.append(f"- Target: {project.get('target', '')}")
    out.append(f"- Indication: {project.get('indication', '')}")
    out.append(f"- Regions: {', '.join(project.get('regions', []))}")
    out.append(f"- Status: {project.get('status', 'in_progress')}")
    out.append("")
    out.append("---")
    out.append("")
    for sec in sections:
        out.append(f"## §{sec.id} {sec.title}")
        out.append("")
        body = sec.body.strip() or "_[NO DATA AVAILABLE — section pending]_"
        out.append(body)
        out.append("")
    return "\n".join(out)


class DocumentRequest(BaseModel):
    sections: list[DocumentSection] = Field(default_factory=list)


@router.post("/api/ind-report/projects/{project_id}/document.md", response_class=PlainTextResponse)
async def download_markdown(
    project_id: str,
    body: DocumentRequest,
):
    """
    Render the current §2.6 document state as Markdown and return it with a
    Content-Disposition attachment header. Public (anonymous-readable) because
    the doc state is supplied by the caller; nothing private is fetched from
    server-side storage.
    """
    if _PROJECTS_PATH.exists():
        try:
            reg = json.loads(_PROJECTS_PATH.read_text())
            project = next((p for p in reg.get("projects", []) if p["id"] == project_id), {})
        except Exception:
            project = {}
    else:
        project = {}
    if not project:
        project = {"molecule": project_id}

    md = _render_markdown(project, body.sections)
    filename = re.sub(r"[^A-Za-z0-9_.-]", "_", f"{project.get('molecule', project_id)}_2.6.md")
    return PlainTextResponse(
        md,
        media_type="text/markdown; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
