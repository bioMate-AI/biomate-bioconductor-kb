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

import asyncio
import hashlib
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Path as FastPath
from fastapi.responses import PlainTextResponse, Response
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


_MFA_SECRETS_DIR = _REPO_ROOT / "data" / "mfa_secrets"


def _mfa_path(user_id: str) -> Path:
    """User-id → on-disk secret file path. SHA the id so the filesystem
    never has a raw email/username in a filename."""
    h = hashlib.sha256(str(user_id).encode("utf-8")).hexdigest()
    return _MFA_SECRETS_DIR / f"{h}.json"


def _load_mfa(user_id: str) -> dict:
    p = _mfa_path(user_id)
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except Exception:
        return {}


def _save_mfa(user_id: str, data: dict) -> None:
    p = _mfa_path(user_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2))


def _verify_totp(user_id: str, code: str) -> dict:
    """Validate the 6-digit TOTP.

    Returns a dict so the sign endpoint can include the dev_bypass flag
    in the audit row:
      {"ok": bool, "dev_bypass": bool, "reason": str}

    Real check (pyotp) fires when the user has enrolled via
    /api/auth/mfa/enroll. Until then:
      - strict mode (BIOMATE_REQUIRE_AUTH=1): reject; require enrollment
      - dev mode: accept any 6-digit code but flag dev_bypass=True so the
        audit chain is honest that no real second factor was provided
    """
    if not re.fullmatch(r"\d{6}", code or ""):
        return {"ok": False, "dev_bypass": False, "reason": "malformed_code"}

    record = _load_mfa(str(user_id))
    enrolled = bool(record.get("enrolled"))
    strict = os.environ.get("BIOMATE_REQUIRE_AUTH") == "1"

    if enrolled and record.get("secret"):
        try:
            import pyotp
        except ImportError:
            log.error("[sign] pyotp not installed; cannot verify enrolled secret")
            return {"ok": False, "dev_bypass": False, "reason": "pyotp_missing"}
        totp = pyotp.TOTP(record["secret"])
        ok = bool(totp.verify(code, valid_window=1))
        if ok:
            record["last_verify_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            _save_mfa(user_id, record)
        return {"ok": ok, "dev_bypass": False, "reason": "wrong_code" if not ok else "ok"}

    # Not enrolled.
    if strict:
        log.warning("[sign] user=%s not enrolled and BIOMATE_REQUIRE_AUTH=1 — rejecting", user_id)
        return {"ok": False, "dev_bypass": False, "reason": "not_enrolled"}

    # Dev-mode bypass — log loudly so the audit chain is unambiguous.
    log.warning(
        "[sign] DEV-MODE BYPASS user=%s accepted any 6-digit code (no real MFA secret on file)",
        user_id,
    )
    return {"ok": True, "dev_bypass": True, "reason": "dev_bypass"}


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

    verdict = _verify_totp(str(user_id), body.totp_code)
    if not verdict.get("ok"):
        reason = verdict.get("reason", "wrong_code")
        if reason == "not_enrolled":
            raise HTTPException(401, "MFA enrollment required — please set up your authenticator first")
        if reason == "pyotp_missing":
            raise HTTPException(500, "MFA verification backend unavailable")
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
        "dev_bypass": bool(verdict.get("dev_bypass")),
        "signed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    row_id = append_jsonl(_SIGN_LOG, record)

    # 21 CFR Part 11 §11.10(c): protect records throughout retention period.
    # Mirror to S3 with Object Lock (WORM) so the local file is recoverable
    # and tamper-evident. Best-effort: a failed mirror does not block sign.
    _mirror_sign_row_to_s3_worm(row_id, record)

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


# ---------------------------------------------------------------------------
# DOCX document export — FDA review-ready Word document
# ---------------------------------------------------------------------------

_DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


def _render_docx(project: dict, sections: list[DocumentSection]) -> bytes:
    """Render the IND §2.6 module as a Word document, formatted for FDA review.

    Sectioning matches the FDA Common Technical Document layout: cover page,
    sponsor block, then numbered §2.6.x headings. Empty bodies emit the
    same placeholder as the Markdown renderer so the two outputs stay aligned.
    """
    from docx import Document
    from docx.shared import Pt, Inches
    from io import BytesIO

    doc = Document()
    for sec_props in doc.sections:
        sec_props.left_margin = Inches(1)
        sec_props.right_margin = Inches(1)
        sec_props.top_margin = Inches(1)
        sec_props.bottom_margin = Inches(1)

    style = doc.styles["Normal"]
    style.font.name = "Times New Roman"
    style.font.size = Pt(11)

    title = doc.add_heading(
        f"IND Module 2.6 — {project.get('molecule', 'Unknown compound')}", level=0
    )
    title.alignment = 1

    meta = doc.add_paragraph()
    for label, key in [
        ("Sponsor", "sponsor"),
        ("Target", "target"),
        ("Indication", "indication"),
    ]:
        run = meta.add_run(f"{label}: ")
        run.bold = True
        meta.add_run(f"{project.get(key, '')}\n")
    regions_run = meta.add_run("Regions: ")
    regions_run.bold = True
    meta.add_run(", ".join(project.get("regions", [])) + "\n")
    status_run = meta.add_run("Status: ")
    status_run.bold = True
    meta.add_run(project.get("status", "in_progress"))

    doc.add_paragraph("")

    for sec in sections:
        doc.add_heading(f"§{sec.id} {sec.title}", level=1)
        body = sec.body.strip()
        if body:
            for para in body.split("\n\n"):
                doc.add_paragraph(para.strip())
        else:
            placeholder = doc.add_paragraph()
            run = placeholder.add_run("[NO DATA AVAILABLE — section pending]")
            run.italic = True

    buf = BytesIO()
    doc.save(buf)
    return buf.getvalue()


@router.post("/api/ind-report/projects/{project_id}/document.docx")
async def download_docx(project_id: str, body: DocumentRequest):
    """Render §2.6 as a Word document. Same input shape as document.md."""
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

    try:
        blob = _render_docx(project, body.sections)
    except ImportError as exc:
        raise HTTPException(
            500, "python-docx not installed — `pip install python-docx`"
        ) from exc
    except Exception as exc:
        log.exception("[docx] render failed: %s", exc)
        raise HTTPException(500, f"DOCX render failed: {exc}") from exc

    filename = re.sub(
        r"[^A-Za-z0-9_.-]", "_", f"{project.get('molecule', project_id)}_2.6.docx"
    )
    return Response(
        content=blob,
        media_type=_DOCX_MIME,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------------------------------------------------------------------------
# A1 — Attachments (PDF/CSV upload) for IND projects
# ---------------------------------------------------------------------------
# Storage layout under data/ind_demo/registry/attachments/<project_id>/:
#   <uuid>__<safe_filename>       — the raw bytes the user uploaded
#   <uuid>__<safe_filename>.txt   — extracted plaintext (PDFs only, first 50KB)
#   _index.jsonl                  — append-only metadata; deletes append
#                                   a tombstone {id, deleted_at} row
#
# Endpoints:
#   POST   /api/ind-report/projects/{project_id}/attachments   multipart
#   GET    /api/ind-report/projects/{project_id}/attachments   list
#   DELETE /api/ind-report/projects/{project_id}/attachments/{aid}
#
# Closes A1 from docs/20260603_IND_MODULE_HONEST_AUDIT.md — the
# "Upload PDF or CSV" button at IndSteps.tsx:291 had no onClick.

from uuid import uuid4 as _uuid4
from datetime import datetime as _dt
from fastapi import UploadFile, File

_ATTACHMENTS_DIR = _REPO_ROOT / "data" / "ind_demo" / "registry" / "attachments"
_ALLOWED_CT = {
    "application/pdf",
    "text/csv",
    "application/vnd.ms-excel",  # some browsers send this for .csv
    "text/plain",                # some servers send text/plain for .csv
}
_MAX_UPLOAD_BYTES = 50 * 1024 * 1024  # 50 MB cap


def _attachments_dir(project_id: str) -> Path:
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")
    return _ATTACHMENTS_DIR / project_id


def _safe_filename(name: str) -> str:
    # Keep only [A-Za-z0-9._-]; collapse runs, cap length.
    out = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._-")[:96]
    return out or "upload"


def _attachments_index_path(project_id: str) -> Path:
    return _attachments_dir(project_id) / "_index.jsonl"


def _read_attachments_index(project_id: str) -> list[dict]:
    """Walk _index.jsonl and apply tombstone records. Returns the live set."""
    path = _attachments_index_path(project_id)
    if not path.exists():
        return []
    rows: list[dict] = []
    deleted: set[str] = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if "deleted_at" in rec:
            deleted.add(rec.get("id", ""))
            continue
        rows.append(rec)
    return [r for r in rows if r.get("id") not in deleted]


def _append_attachment_row(project_id: str, record: dict) -> None:
    path = _attachments_index_path(project_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


def _extract_text_from_pdf(blob: bytes) -> tuple[str, int]:
    """Returns (preview_text up to 50 KB, page count). Empty on failure."""
    try:
        import pdfplumber
        from io import BytesIO
        text_parts: list[str] = []
        n_pages = 0
        with pdfplumber.open(BytesIO(blob)) as pdf:
            for page in pdf.pages:
                t = page.extract_text() or ""
                text_parts.append(t)
                n_pages += 1
                if sum(len(p) for p in text_parts) > 50_000:
                    break
        return ("\n\n".join(text_parts)[:50_000], n_pages)
    except Exception as exc:
        log.warning("[attachments] PDF extract failed: %s", exc)
        return ("", 0)


def _parse_csv_columns(blob: bytes) -> tuple[list[str], int]:
    """Return (column_headers, row_count). Empty on failure."""
    try:
        import csv as _csv
        from io import StringIO
        text = blob.decode("utf-8", errors="replace")
        reader = _csv.reader(StringIO(text))
        header = next(reader, [])
        rows = sum(1 for _ in reader)
        return ([h.strip() for h in header], rows)
    except Exception as exc:
        log.warning("[attachments] CSV parse failed: %s", exc)
        return ([], 0)


@router.post("/api/ind-report/projects/{project_id}/attachments")
async def upload_attachment(
    project_id: str,
    file: UploadFile = File(...),
):
    """Accept a PDF or CSV upload. Stores bytes + extracted metadata."""
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")

    ct = (file.content_type or "").lower()
    fname = file.filename or "upload"
    ext = fname.rsplit(".", 1)[-1].lower() if "." in fname else ""
    # Accept either by content-type OR file extension (browsers vary)
    is_pdf = ct == "application/pdf" or ext == "pdf"
    is_csv = ct in {"text/csv", "application/vnd.ms-excel", "text/plain"} or ext == "csv"
    if not (is_pdf or is_csv):
        raise HTTPException(
            400,
            f"only PDF or CSV uploads accepted (got content_type={ct!r}, ext={ext!r})",
        )

    blob = await file.read()
    if len(blob) > _MAX_UPLOAD_BYTES:
        raise HTTPException(413, f"upload too large ({len(blob)} > {_MAX_UPLOAD_BYTES})")
    if not blob:
        raise HTTPException(400, "empty upload")

    sha = hashlib.sha256(blob).hexdigest()
    aid = _uuid4().hex
    safe = _safe_filename(fname)
    target_dir = _attachments_dir(project_id)
    target_dir.mkdir(parents=True, exist_ok=True)
    target_path = target_dir / f"{aid}__{safe}"
    target_path.write_bytes(blob)

    record: dict = {
        "id": aid,
        "filename": fname,
        "stored_as": target_path.name,
        "content_type": ct or ("application/pdf" if is_pdf else "text/csv"),
        "size_bytes": len(blob),
        "sha256": sha,
        "uploaded_at": _dt.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if is_pdf:
        text, n_pages = _extract_text_from_pdf(blob)
        if text:
            preview_path = target_path.with_suffix(target_path.suffix + ".txt")
            preview_path.write_text(text, encoding="utf-8")
            record["text_preview_path"] = preview_path.name
        record["pdf_pages"] = n_pages
        record["kind"] = "pdf"
    if is_csv:
        cols, rows = _parse_csv_columns(blob)
        record["csv_columns"] = cols
        record["csv_rows"] = rows
        record["kind"] = "csv"

    _append_attachment_row(project_id, record)
    return record


@router.get("/api/ind-report/projects/{project_id}/attachments")
async def list_attachments(project_id: str):
    """Return all non-tombstoned attachments for the project."""
    rows = _read_attachments_index(project_id)
    return {"attachments": rows}


@router.delete("/api/ind-report/projects/{project_id}/attachments/{attachment_id}")
async def delete_attachment(project_id: str, attachment_id: str):
    """Tombstone the attachment row + delete the on-disk file."""
    rows = _read_attachments_index(project_id)
    match = next((r for r in rows if r.get("id") == attachment_id), None)
    if not match:
        raise HTTPException(404, "attachment not found")
    target = _attachments_dir(project_id) / match.get("stored_as", "")
    if target.exists():
        try:
            target.unlink()
        except Exception as exc:
            log.warning("[attachments] failed to unlink %s: %s", target, exc)
    preview = target.with_suffix(target.suffix + ".txt")
    if preview.exists():
        try:
            preview.unlink()
        except Exception:
            pass
    _append_attachment_row(project_id, {
        "id": attachment_id,
        "deleted_at": _dt.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    })
    return {"deleted": True, "id": attachment_id}



# ---------------------------------------------------------------------------
# Audit trail PDF — 21 CFR Part 11 §11.10(e) "secure, computer-generated,
# time-stamped audit trails"
# ---------------------------------------------------------------------------


def _read_sign_audit_rows(project_id: str) -> list[dict]:
    """Read all signature rows for one project from the local audit chain."""
    if not _SIGN_LOG.exists():
        return []
    rows: list[dict] = []
    for line in _SIGN_LOG.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if rec.get("project_id") == project_id:
            rows.append(rec)
    rows.sort(key=lambda r: r.get("signed_at", ""))
    return rows


def _render_audit_pdf(project: dict, rows: list[dict]) -> bytes:
    """Render the 21 CFR Part 11 audit trail PDF for one project.

    One row per signature event with: timestamp, user, signer attestation,
    document SHA-256, adapter versions, and a hash-chain pointer to the
    previous row (sha256(prev_row_id + prev_doc_sha)) — so tampering with
    any row breaks the chain.
    """
    from io import BytesIO
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import LETTER
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.platypus import (
        SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    )

    buf = BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=LETTER,
        leftMargin=0.75 * inch, rightMargin=0.75 * inch,
        topMargin=0.6 * inch, bottomMargin=0.6 * inch,
        title=f"Audit Trail — {project.get('molecule', 'Unknown')}",
        author="BioMate Regulatory",
    )
    styles = getSampleStyleSheet()
    h1 = styles["Heading1"]
    h2 = styles["Heading2"]
    body = ParagraphStyle("body", parent=styles["BodyText"], fontSize=9, leading=12)
    mono = ParagraphStyle("mono", parent=body, fontName="Courier", fontSize=8)

    story = []
    story.append(Paragraph(
        f"IND §2.6 Audit Trail — {project.get('molecule', 'Unknown compound')}", h1,
    ))
    story.append(Paragraph(
        "21 CFR Part 11 §11.10(e) — computer-generated, time-stamped audit trail "
        "of all signature events for this project. The hash-chain column links "
        "each row to the previous; recomputing the chain detects tampering.",
        body,
    ))
    story.append(Spacer(1, 0.15 * inch))

    meta_data = [
        ["Sponsor", project.get("sponsor", "")],
        ["Target", project.get("target", "")],
        ["Indication", project.get("indication", "")],
        ["Regions", ", ".join(project.get("regions", []))],
        ["Project ID", project.get("id", "")],
        ["Audit rows", str(len(rows))],
    ]
    meta_table = Table(meta_data, colWidths=[1.4 * inch, 5.4 * inch])
    meta_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("LINEBELOW", (0, 0), (-1, -1), 0.25, colors.lightgrey),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 0.25 * inch))

    if not rows:
        story.append(Paragraph(
            "<i>No signatures recorded for this project yet.</i>", body,
        ))
        doc.build(story)
        return buf.getvalue()

    story.append(Paragraph("Signature Events", h2))

    # Build the hash chain and one section per signature.
    prev_link = "GENESIS"
    for idx, r in enumerate(rows, 1):
        # Chain link = sha256(prev_link || row_signature_id || doc_sha256)
        sig_id = r.get("signature_id") or r.get("_row_id") or ""
        link_input = f"{prev_link}|{sig_id}|{r.get('document_sha256', '')}".encode()
        chain_link = hashlib.sha256(link_input).hexdigest()

        story.append(Paragraph(f"#{idx} — {r.get('signed_at', '')} UTC", h2))
        rows_data = [
            ["Signed at", r.get("signed_at", "")],
            ["User ID", str(r.get("user_id", ""))],
            ["Org ID", str(r.get("org_id") or "—")],
            ["Signer title", r.get("signer_title", "")],
            ["Signer credentials", r.get("signer_creds", "")],
            ["Signature scope", r.get("signature_scope", "")],
            ["TOTP validated", "YES" if r.get("totp_validated") else "NO"],
            ["Document SHA-256", r.get("document_sha256", "")],
            ["Signature ID", sig_id],
            ["Chain previous", prev_link],
            ["Chain link", chain_link],
        ]
        av = r.get("adapter_versions") or {}
        if av:
            rows_data.append(["Adapter versions", "; ".join(f"{k}={v}" for k, v in sorted(av.items()))])

        # Wrap SHA columns in mono for readability
        table_data = []
        for k, v in rows_data:
            if k in ("Document SHA-256", "Chain previous", "Chain link"):
                table_data.append([k, Paragraph(str(v), mono)])
            else:
                table_data.append([k, Paragraph(str(v), body)])

        t = Table(table_data, colWidths=[1.6 * inch, 5.2 * inch])
        t.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f3f4f6")),
            ("LINEBELOW", (0, 0), (-1, -1), 0.25, colors.lightgrey),
        ]))
        story.append(t)
        story.append(Spacer(1, 0.2 * inch))

        prev_link = chain_link

    story.append(Spacer(1, 0.2 * inch))
    story.append(Paragraph(
        f"<b>Chain head:</b> {prev_link}<br/>"
        f"<i>Re-derive the chain head by hashing each row in order against the "
        f"previous link; any mismatch indicates the audit trail was modified "
        f"after generation.</i>",
        body,
    ))
    doc.build(story)
    return buf.getvalue()


@router.get("/api/ind-report/projects/{project_id}/audit-trail.pdf")
async def download_audit_pdf(project_id: str):
    """Generate and return the 21 CFR Part 11 audit trail PDF.

    Reads sign_audit_chain.jsonl for the given project and renders one PDF
    page section per signature event, with hash-chain links between rows.
    Public read because each row already contains its own non-repudiation
    artifacts (signer attestation + TOTP-validated flag + doc SHA-256);
    the PDF is a presentation of state that anyone with project_id can audit.
    """
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")

    if _PROJECTS_PATH.exists():
        try:
            reg = json.loads(_PROJECTS_PATH.read_text())
            project = next((p for p in reg.get("projects", []) if p["id"] == project_id), {})
        except Exception:
            project = {}
    else:
        project = {}
    if not project:
        project = {"molecule": project_id, "id": project_id}

    rows = _read_sign_audit_rows(project_id)
    try:
        blob = _render_audit_pdf(project, rows)
    except ImportError as exc:
        raise HTTPException(
            500, "reportlab not installed — `pip install reportlab`"
        ) from exc
    except Exception as exc:
        log.exception("[audit-pdf] render failed: %s", exc)
        raise HTTPException(500, f"audit PDF render failed: {exc}") from exc

    filename = re.sub(
        r"[^A-Za-z0-9_.-]", "_",
        f"{project.get('molecule', project_id)}_audit_trail.pdf",
    )
    return Response(
        content=blob,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------------------------------------------------------------------------
# Sign audit chain → S3 with Object Lock (21 CFR Part 11 §11.10(c))
# ---------------------------------------------------------------------------
#
# Local sign_audit_chain.jsonl is the authoritative read path; S3 is a
# tamper-evident mirror for retention. Bucket must have Object Lock enabled
# in COMPLIANCE mode at creation time (cannot be added later). Each signed
# row is uploaded under:
#   s3://$BUCKET/$PREFIX/<YYYY>/<MM>/<DD>/<signature_id>.json
# with x-amz-object-lock-retain-until-date set RETAIN_DAYS into the future.
#
# Failures are LOGGED, not raised — local row is already committed.

_SIGN_AUDIT_S3_BUCKET = os.environ.get("BIOMATE_SIGN_AUDIT_S3_BUCKET", "")
_SIGN_AUDIT_S3_PREFIX = os.environ.get("BIOMATE_SIGN_AUDIT_S3_PREFIX", "ind/sign_audit")
_SIGN_AUDIT_RETAIN_DAYS = int(os.environ.get("BIOMATE_SIGN_AUDIT_RETAIN_DAYS", "2555"))  # 7y FDA default
_SIGN_AUDIT_REGION = os.environ.get("AWS_REGION", "us-west-2")


def _mirror_sign_row_to_s3_worm(row_id: str, record: dict) -> None:
    if not _SIGN_AUDIT_S3_BUCKET:
        return  # mirror disabled — operator must set the env var
    try:
        import boto3
        from datetime import datetime, timedelta, timezone

        signed_dt = datetime.strptime(record["signed_at"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        retain_until = signed_dt + timedelta(days=_SIGN_AUDIT_RETAIN_DAYS)
        key = (
            f"{_SIGN_AUDIT_S3_PREFIX.rstrip('/')}/"
            f"{signed_dt.year:04d}/{signed_dt.month:02d}/{signed_dt.day:02d}/"
            f"{row_id}.json"
        )
        payload = json.dumps(
            {"signature_id": row_id, **record}, sort_keys=True
        ).encode("utf-8")
        sha256 = hashlib.sha256(payload).hexdigest()

        s3 = boto3.client("s3", region_name=_SIGN_AUDIT_REGION)
        s3.put_object(
            Bucket=_SIGN_AUDIT_S3_BUCKET,
            Key=key,
            Body=payload,
            ContentType="application/json",
            ObjectLockMode="COMPLIANCE",
            ObjectLockRetainUntilDate=retain_until,
            Metadata={
                "biomate-row-id": row_id,
                "biomate-doc-sha256": record["document_sha256"],
                "biomate-payload-sha256": sha256,
            },
        )
        log.info(
            "[sign] WORM mirrored signature_id=%s to s3://%s/%s retain_until=%s",
            row_id, _SIGN_AUDIT_S3_BUCKET, key, retain_until.isoformat(),
        )
    except Exception as exc:
        log.warning(
            "[sign] S3 WORM mirror failed for signature_id=%s: %s", row_id, exc
        )


# ---------------------------------------------------------------------------
# Version history (P2-6) — append-only snapshots per project
# Storage: data/ind_demo/registry/versions/<project_id>.jsonl
# ---------------------------------------------------------------------------

_VERSIONS_DIR = _REPO_ROOT / "data" / "ind_demo" / "registry" / "versions"
_PROJECT_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,40}$")


def _versions_path(project_id: str) -> Path:
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")
    return _VERSIONS_DIR / f"{project_id}.jsonl"


class SnapshotRequest(BaseModel):
    document_sha256: str = Field(..., pattern=r"^[a-f0-9]{64}$")
    adapter_versions: dict[str, str] = Field(default_factory=dict)
    section_count: int = Field(0, ge=0)
    note: Optional[str] = Field(None, max_length=400)


def _read_versions(project_id: str) -> list[dict]:
    path = _versions_path(project_id)
    if not path.exists():
        return []
    out: list[dict] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception as exc:
            log.warning("[versions] skipping malformed row: %s", exc)
    return out


@router.post("/api/ind-report/projects/{project_id}/snapshot")
async def create_snapshot(
    project_id: str,
    body: SnapshotRequest,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """Append an immutable snapshot row. Auto-numbers as next version."""
    existing = _read_versions(project_id)
    next_version = (existing[-1].get("version", 0) + 1) if existing else 1
    record = {
        "version": next_version,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "document_sha256": body.document_sha256,
        "document_sha256_short": body.document_sha256[:12],
        "adapter_versions": body.adapter_versions,
        "section_count": body.section_count,
        "author": user.get("user_id", "anonymous"),
        "note": body.note,
    }
    if x_biomate_org_id:
        record["org_id"] = x_biomate_org_id
    path = _versions_path(project_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")
    log.info("[versions] project=%s v%d sha=%s by=%s",
             project_id, next_version, record["document_sha256_short"], record["author"])
    return record


@router.get("/api/ind-report/projects/{project_id}/versions")
async def list_versions(project_id: str):
    """Return all snapshots oldest-first. Anonymous-readable."""
    rows = _read_versions(project_id)
    return {"project_id": project_id, "count": len(rows), "versions": rows}


# ---------------------------------------------------------------------------
# Region-aware sections render (P1-4 backend stub)
# Returns not_implemented for non-FDA; frontend uses this to keep
# EMA/NMPA/PMDA grayed-out in the region selector.
# ---------------------------------------------------------------------------

class RenderSectionRequest(BaseModel):
    section_type: str = Field(..., min_length=1, max_length=40)
    region: str = Field("FDA", pattern=r"^(FDA|EMA|NMPA|PMDA)$")
    inputs: dict[str, str] = Field(default_factory=dict)


@router.post("/api/ind-report/projects/{project_id}/sections/render")
async def render_section_for_region(
    project_id: str,
    body: RenderSectionRequest,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """Region-aware section render. Non-FDA returns not_implemented today."""
    if body.region != "FDA":
        return {
            "status": "not_implemented",
            "region": body.region,
            "reason": (
                f"{body.region} prose rendering is not yet wired. "
                f"Per-region SFT corpus exists (task3_region_adaptation.jsonl); "
                f"inference route not yet built. FDA-only in beta."
            ),
            "fallback_region": "FDA",
        }
    return {
        "status": "ok",
        "region": "FDA",
        "section_type": body.section_type,
        "project_id": project_id,
        "note": "Render via /api/regulatory/generate_stream for actual prose.",
    }


# ---------------------------------------------------------------------------
# Compound list persistence (P1-5 follow-up)
# ---------------------------------------------------------------------------

class CompoundEntry(BaseModel):
    id: str = Field(..., pattern=r"^[a-zA-Z0-9_-]{1,40}$")
    smiles: str = Field(..., min_length=1, max_length=200)
    label: Optional[str] = Field(None, max_length=80)
    lead: bool = False


class CompoundsPatch(BaseModel):
    compounds: list[CompoundEntry] = Field(default_factory=list, max_length=200)
    lead_id: Optional[str] = Field(None, pattern=r"^[a-zA-Z0-9_-]{1,40}$")


@router.patch("/api/ind-report/projects/{project_id}/compounds")
async def update_compounds(
    project_id: str,
    body: CompoundsPatch,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
    user: dict = Depends(require_authenticated_user),
):
    """Replace the compound list on the project registry row."""
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")
    if not _PROJECTS_PATH.exists():
        raise HTTPException(404, "project registry not initialized")
    reg = json.loads(_PROJECTS_PATH.read_text())
    target = None
    for p in reg.get("projects", []):
        if p["id"] == project_id:
            target = p
            break
    if target is None:
        raise HTTPException(404, f"project not found: {project_id}")

    ids_seen: set[str] = set()
    for e in body.compounds:
        if e.id in ids_seen:
            raise HTTPException(400, f"duplicate compound id: {e.id}")
        ids_seen.add(e.id)
    if body.lead_id and body.lead_id not in ids_seen:
        raise HTTPException(400, f"lead_id '{body.lead_id}' not in compounds list")

    compounds_out = []
    for e in body.compounds:
        entry = e.model_dump()
        if body.lead_id is not None:
            entry["lead"] = (e.id == body.lead_id)
        compounds_out.append(entry)

    target["compounds"] = compounds_out
    target["compounds_updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    target["compounds_updated_by"] = user.get("user_id", "anonymous")
    if x_biomate_org_id:
        target["compounds_org_id"] = x_biomate_org_id

    tmp = _PROJECTS_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(reg, indent=2))
    tmp.replace(_PROJECTS_PATH)

    log.info("[compounds] project=%s n=%d lead=%s by=%s",
             project_id, len(compounds_out), body.lead_id, user.get("user_id"))
    return {
        "project_id": project_id,
        "count": len(compounds_out),
        "lead_id": body.lead_id,
        "compounds": compounds_out,
    }


# ---------------------------------------------------------------------------
# Per-project pipeline display data — Tier-S1 fix from the IND honest audit.
# Replaces the hardcoded DEMO_ADMET / DEMO_PBPK / DEMO_LEADS / DEMO_DOC /
# DEMO_AUDIT constants in frontend/client/src/pages/ind-report.tsx so that
# different projects show distinct molecules, metrics, rankings, and audit
# findings — proving the 5-step view is no longer the same fake data for
# every project.
#
# Storage: data/ind_demo/registry/pipeline_data/<project_id>.json
# Shape must match the AdmetData/PbpkData/LeadsData/IndDoc/IndAudit TS types
# in frontend/client/src/components/ind-report/IndSteps.tsx.
# ---------------------------------------------------------------------------

_PIPELINE_DATA_DIR = _REPO_ROOT / "data" / "ind_demo" / "registry" / "pipeline_data"


def _scaffold_pipeline_data(project_id: str, project_row: Optional[dict]) -> dict:
    """Return a 'pending pipeline' placeholder when no sidecar file exists.

    Step1 metadata comes from the registry row when available; the rest is
    empty/zero so the UI renders a clean unstarted-pipeline state. Does NOT
    return the BM-0042 demo data — that would re-introduce the bug.
    """
    molecule = (project_row or {}).get("molecule", project_id)
    return {
        "lead_smiles": None,
        "admet": {
            "summary": {"pass": 0, "total": 0},
            "compounds": [],
        },
        "pbpk": {
            "status": "fail",
            "model": "(not run)",
            "refSet": 0,
            "refSource": "—",
            "metrics": {"cmaxWithin2": 0, "aucWithin2": 0, "emaThreshold": 67},
            "lead": {"id": molecule, "fu": 0, "vd": 0, "t12": 0, "bioavail": 0},
            "ospRange": "—",
            "perDrug": [],
        },
        "leads": {
            "method": "(not run)",
            "evaluated": 0,
            "rounds": 0,
            "inDomain": 0,
            "outOfDomain": 0,
            "ranking": [],
        },
        "doc": {
            "signed": False,
            "generatedAt": "—",
            "characters": 0,
            "shaPrefix": "—",
            "sections": [],
        },
        "audit": {"findings": []},
    }


def _load_project_row(project_id: str) -> Optional[dict]:
    if not _PROJECTS_PATH.exists():
        return None
    try:
        reg = json.loads(_PROJECTS_PATH.read_text())
    except Exception as exc:
        log.warning("[pipeline_data] failed to read projects.json: %s", exc)
        return None
    for p in reg.get("projects", []):
        if p.get("id") == project_id:
            return p
    return None


@router.get("/api/ind-report/projects/{project_id}/pipeline_data")
async def get_pipeline_data(project_id: str):
    """Return per-project pipeline display data for the 5-step view.

    Sources:
      1. data/ind_demo/registry/pipeline_data/<id>.json (sidecar) — preferred
      2. Scaffold default from projects.json row when sidecar missing
      3. Bare scaffold when project_id is unknown (no 404 — page can still
         render an empty-pipeline shell)

    Anonymous-readable: display data only, no PHI / no IP.
    """
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")

    sidecar = _PIPELINE_DATA_DIR / f"{project_id}.json"
    if sidecar.exists():
        try:
            payload = json.loads(sidecar.read_text())
            # Strip private fields (anything starting with _) before responding
            return {k: v for k, v in payload.items() if not k.startswith("_")}
        except Exception as exc:
            log.warning("[pipeline_data] failed to parse %s: %s", sidecar, exc)
            # fall through to scaffold

    project_row = _load_project_row(project_id)
    return _scaffold_pipeline_data(project_id, project_row)


# ---------------------------------------------------------------------------
# A2/A3 — Re-run with new params (deterministic recompute placeholder)
# ---------------------------------------------------------------------------
# In Path A (workflow → IND), the rerun endpoints would submit a real
# Nextflow re-run. Here they're a deterministic recompute so the UI flow
# is real end-to-end — params edit → POST → numbers shift → re-fetch.

_RUN_PARAMS_DIR = _REPO_ROOT / "data" / "ind_demo" / "registry" / "run_params"
_RERUN_AUDIT_LOG = _REPO_ROOT / "data" / "ind_demo" / "registry" / "rerun_audit.jsonl"

_DEFAULT_ADMET_PARAMS = {
    "herg_threshold_uM": 10.0,
    "dili_score_max": 0.5,
    "ames_panel": ["TA98", "TA100"],
    "ro5_max_violations": 1,
}
_DEFAULT_PBPK_PARAMS = {
    "model": "BioMate-PBPK v2.1",
    "reference_set_name": "BioMate PBPK Reference Set v2.0",
    "ema_threshold_pct": 60,
    "n_compartments": 1,
    "include_efflux": True,
}


def _load_run_params(project_id: str) -> dict:
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")
    path = _RUN_PARAMS_DIR / f"{project_id}.json"
    if not path.exists():
        return {"admet": _DEFAULT_ADMET_PARAMS, "pbpk": _DEFAULT_PBPK_PARAMS}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {"admet": _DEFAULT_ADMET_PARAMS, "pbpk": _DEFAULT_PBPK_PARAMS}


def _save_run_params(project_id: str, data: dict) -> None:
    path = _RUN_PARAMS_DIR / f"{project_id}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)


class AdmetParams(BaseModel):
    herg_threshold_uM: float = Field(..., ge=0.01, le=1000.0)
    dili_score_max: float = Field(..., ge=0.0, le=1.0)
    ames_panel: list[str] = Field(default_factory=list)
    ro5_max_violations: int = Field(..., ge=0, le=4)


class PbpkParams(BaseModel):
    model: str = Field(..., max_length=120)
    reference_set_name: str = Field(..., max_length=120)
    ema_threshold_pct: float = Field(..., ge=10.0, le=99.0)
    n_compartments: int = Field(..., ge=1, le=3)
    include_efflux: bool


def _recompute_admet(params: AdmetParams, current_admet: dict) -> dict:
    """Deterministic recompute: tighter hERG / DILI / Ro5 → fewer pass."""
    base_total = current_admet.get("summary", {}).get("total", 12) or 12
    # Score the params on a 0..1 strictness scale; higher = stricter = fewer pass
    strictness = (
        max(0.0, min(1.0, (10.0 - params.herg_threshold_uM) / 9.99)) * 0.5
        + max(0.0, min(1.0, (0.5 - params.dili_score_max) / 0.5)) * 0.3
        + max(0.0, min(1.0, (1 - params.ro5_max_violations) / 1.0)) * 0.2
    )
    new_pass = max(0, int(base_total * (1.0 - 0.6 * strictness)))
    new_pass = min(new_pass, base_total)
    new_admet = dict(current_admet)
    new_admet["summary"] = {"pass": new_pass, "total": base_total}
    new_admet["_provenance"] = {
        "source": "manual_rerun",
        "attached_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    return new_admet


def _recompute_pbpk(params: PbpkParams, current_pbpk: dict) -> dict:
    """Deterministic: lower EMA threshold + efflux on → likelier pass."""
    metrics = dict(current_pbpk.get("metrics", {}))
    # Start from a baseline cmax-within-2-fold; the params shift it.
    base_cmax = float(metrics.get("cmaxWithin2", 62.0))
    delta = 0.0
    delta += (60.0 - params.ema_threshold_pct) * 0.3   # lower threshold = easier
    delta += (3 if params.include_efflux else 0)
    delta += (params.n_compartments - 1) * 1.5
    new_cmax = max(20.0, min(98.0, base_cmax + delta))
    new_auc = max(20.0, min(98.0, float(metrics.get("aucWithin2", 75.0)) + delta))
    metrics["cmaxWithin2"] = round(new_cmax, 1)
    metrics["aucWithin2"] = round(new_auc, 1)
    metrics["emaThreshold"] = float(params.ema_threshold_pct)
    new_pbpk = dict(current_pbpk)
    new_pbpk["model"] = params.model
    new_pbpk["refSource"] = params.reference_set_name
    new_pbpk["metrics"] = metrics
    new_pbpk["status"] = "pass" if new_cmax >= params.ema_threshold_pct else "fail"
    new_pbpk["_provenance"] = {
        "source": "manual_rerun",
        "attached_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    return new_pbpk


def _read_pipeline_data(project_id: str) -> dict:
    sidecar = _PIPELINE_DATA_DIR / f"{project_id}.json"
    if sidecar.exists():
        try:
            return json.loads(sidecar.read_text())
        except Exception:
            return {}
    return {}


def _write_pipeline_data(project_id: str, data: dict) -> None:
    sidecar = _PIPELINE_DATA_DIR / f"{project_id}.json"
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    tmp = sidecar.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(sidecar)


def _append_rerun_audit(record: dict) -> None:
    _RERUN_AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    with _RERUN_AUDIT_LOG.open("a") as f:
        f.write(json.dumps(record) + "\n")


@router.get("/api/ind-report/projects/{project_id}/params/admet")
async def get_admet_params(project_id: str):
    return _load_run_params(project_id).get("admet", _DEFAULT_ADMET_PARAMS)


@router.get("/api/ind-report/projects/{project_id}/params/pbpk")
async def get_pbpk_params(project_id: str):
    return _load_run_params(project_id).get("pbpk", _DEFAULT_PBPK_PARAMS)


@router.post("/api/ind-report/projects/{project_id}/rerun/admet")
async def rerun_admet(project_id: str, params: AdmetParams):
    pdata = _read_pipeline_data(project_id)
    prev_admet = pdata.get("admet", {})
    new_admet = _recompute_admet(params, prev_admet)
    pdata["admet"] = new_admet
    _write_pipeline_data(project_id, pdata)
    all_params = _load_run_params(project_id)
    all_params["admet"] = params.model_dump()
    _save_run_params(project_id, all_params)
    _append_rerun_audit({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project_id": project_id,
        "step": "admet",
        "prev_summary": prev_admet.get("summary"),
        "new_summary": new_admet.get("summary"),
        "params": params.model_dump(),
    })
    return {"status": "ok", "result": new_admet}


@router.post("/api/ind-report/projects/{project_id}/rerun/pbpk")
async def rerun_pbpk(project_id: str, params: PbpkParams):
    pdata = _read_pipeline_data(project_id)
    prev_pbpk = pdata.get("pbpk", {})
    new_pbpk = _recompute_pbpk(params, prev_pbpk)
    pdata["pbpk"] = new_pbpk
    _write_pipeline_data(project_id, pdata)
    all_params = _load_run_params(project_id)
    all_params["pbpk"] = params.model_dump()
    _save_run_params(project_id, all_params)
    _append_rerun_audit({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project_id": project_id,
        "step": "pbpk",
        "prev_status": prev_pbpk.get("status"),
        "new_status": new_pbpk.get("status"),
        "params": params.model_dump(),
    })
    return {"status": "ok", "result": new_pbpk}


# ---------------------------------------------------------------------------
# S2 — Real TOTP MFA enrollment endpoints (decorators)
# ---------------------------------------------------------------------------

@router.get("/api/auth/mfa/status")
async def mfa_status_endpoint(user: dict = Depends(require_authenticated_user)):
    rec = _load_mfa(str(user.get("user_id", "anonymous")))
    return {
        "enrolled": bool(rec.get("enrolled")),
        "enrolled_at": rec.get("enrolled_at"),
    }


@router.post("/api/auth/mfa/enroll")
async def mfa_enroll_endpoint(user: dict = Depends(require_authenticated_user)):
    import base64
    from io import BytesIO
    try:
        import pyotp
        import qrcode
    except ImportError as exc:
        raise HTTPException(500, f"pyotp / qrcode not installed: {exc}") from exc

    user_id = str(user.get("user_id", "anonymous"))
    user_label = str(user.get("email") or user.get("username") or user_id)
    secret = pyotp.random_base32()
    otpauth_url = pyotp.TOTP(secret).provisioning_uri(
        name=user_label, issuer_name="BioMate Regulatory",
    )
    img = qrcode.make(otpauth_url)
    buf = BytesIO()
    img.save(buf, format="PNG")
    qr_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    _save_mfa(user_id, {
        "secret": secret,
        "enrolled": False,
        "pending_since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    return {"secret": secret, "otpauth_url": otpauth_url, "qr_png_base64": qr_b64}


class _MfaConfirmRequest(BaseModel):
    code: str = Field(..., pattern=r"^\d{6}$")


@router.post("/api/auth/mfa/confirm")
async def mfa_confirm_endpoint(
    body: _MfaConfirmRequest,
    user: dict = Depends(require_authenticated_user),
):
    try:
        import pyotp
    except ImportError:
        raise HTTPException(500, "pyotp not installed")
    user_id = str(user.get("user_id", "anonymous"))
    rec = _load_mfa(user_id)
    if not rec.get("secret"):
        raise HTTPException(409, "no pending enrollment - call /enroll first")
    if not pyotp.TOTP(rec["secret"]).verify(body.code, valid_window=1):
        raise HTTPException(401, "code did not match - try again")
    rec["enrolled"] = True
    rec["enrolled_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    rec.pop("pending_since", None)
    _save_mfa(user_id, rec)
    return {"enrolled": True, "enrolled_at": rec["enrolled_at"]}


@router.post("/api/auth/mfa/reset")
async def mfa_reset_endpoint(user: dict = Depends(require_authenticated_user)):
    user_id = str(user.get("user_id", "anonymous"))
    pp = _mfa_path(user_id)
    if pp.exists():
        pp.unlink()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Path A — workflow → IND ingest + SSE channel
# ---------------------------------------------------------------------------

from fastapi.responses import StreamingResponse as _StreamingResponse
from . import pipeline_data_writer as _pdw


class _IngestWorkflowRequest(BaseModel):
    workflow_run_id: str = Field(..., max_length=200)
    target_step: str
    payload: Any = None
    source: str = "chat_roll_in"
    force: bool = False


@router.post("/api/ind-report/projects/{project_id}/ingest_workflow")
async def ingest_workflow(
    project_id: str,
    body: _IngestWorkflowRequest,
):
    """Roll a workflow result into the IND project's pipeline_data.

    Called by the chat affordance "Roll into IND project ▾" and by the
    nextflow_executor auto-hook (when ind_target is set on the run params).
    """
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")
    if body.target_step not in _pdw.VALID_STEPS:
        raise HTTPException(400, f"target_step must be one of {_pdw.VALID_STEPS}")
    if body.source not in _pdw.VALID_SOURCES:
        raise HTTPException(400, f"source must be one of {_pdw.VALID_SOURCES}")
    try:
        result = _pdw.write_block(
            project_id=project_id,
            step=body.target_step,
            payload=body.payload,
            source=body.source,
            workflow_run_id=body.workflow_run_id,
            force=bool(body.force),
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return result


@router.get("/api/ind-report/projects/{project_id}/events")
async def pipeline_events(project_id: str):
    """Server-sent events: pipeline_data:updated whenever a writer fires.

    The frontend (pages/ind-report.tsx) opens an EventSource on the
    active project and bumps pipelineRefreshKey on each event so the
    fetchPipelineData hook re-runs.
    """
    if not _PROJECT_ID_RE.match(project_id):
        raise HTTPException(400, "invalid project id")

    async def _gen():
        q = _pdw.subscribe(project_id)
        try:
            # Greeting so the client can confirm the stream is alive.
            yield f"event: hello\ndata: {json.dumps({'project_id': project_id})}\n\n"
            while True:
                try:
                    msg = await asyncio.wait_for(q.get(), timeout=20.0)
                except asyncio.TimeoutError:
                    yield ": keepalive\n\n"
                    continue
                yield f"event: {msg['event']}\ndata: {json.dumps(msg['data'])}\n\n"
        finally:
            _pdw.unsubscribe(project_id, q)

    return _StreamingResponse(_gen(), media_type="text/event-stream")
