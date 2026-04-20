"""
BioMate Audit Middleware — Phase 2 CRO Compliance

FastAPI dependency that records every regulated write operation to the
tamper-evident audit log.  Mount it on write endpoints via `Depends()`.

Regulated operations (21 CFR Part 11 §11.10(e)):
  POST  /{campaign_id}/ingest-assay     → INGEST_ASSAY
  POST  /{campaign_id}/propose          → PROPOSE_ROUND
  GET   /{campaign_id}/export/cro-order → EXPORT_CRO_ORDER   (read but regulated)
  POST  /{campaign_id}/models/register  → REGISTER_MODEL
  POST  /{campaign_id}/models/*/run     → RUN_MODEL
  GET   /{campaign_id}/lims/poll        → POLL_LIMS
  GET   /model-validation/*             → MODEL_VALIDATION

Optional eSig gate:
  High-stakes actions (EXPORT_CRO_ORDER, PROPOSE_ROUND) can require an
  X-BioMate-ESig header containing a TOTP token.  Set env var
  BIOMATE_ESIG_REQUIRED=1 to enforce; default is advisory-only (records
  whether a signature was present).
"""

import hashlib
import logging
import os
from typing import Optional

from fastapi import Depends, Header, HTTPException, Request

log = logging.getLogger(__name__)

# Actions that support (but by default don't require) an eSig header
_ESIG_SUPPORTED_ACTIONS = {"EXPORT_CRO_ORDER", "PROPOSE_ROUND"}

# Set BIOMATE_ESIG_REQUIRED=1 to enforce eSig on supported actions
_ESIG_REQUIRED = os.environ.get("BIOMATE_ESIG_REQUIRED", "0").strip() == "1"


# ---------------------------------------------------------------------------
# Singleton audit store (shared across all requests)
# ---------------------------------------------------------------------------

_audit_store_instance = None


def _get_audit_store():
    global _audit_store_instance
    if _audit_store_instance is None:
        try:
            from .audit_store import AuditStore
            _audit_store_instance = AuditStore()
        except Exception as exc:
            log.warning("Could not initialise AuditStore: %s", exc)
    return _audit_store_instance


# ---------------------------------------------------------------------------
# User identity extraction
# ---------------------------------------------------------------------------

def _extract_user_id(request: Request) -> str:
    """
    Extract user identity from the request.

    Priority:
    1. JWT Bearer token in Authorization header — decode sub claim
    2. X-BioMate-User-Id header (for service-to-service calls)
    3. Fall back to remote IP + "anonymous"
    """
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:]
        try:
            # Decode without verification (signature is validated upstream by auth middleware)
            import base64 as _b64
            import json as _json
            parts = token.split(".")
            if len(parts) == 3:
                payload_b64 = parts[1] + "=="  # add padding
                payload = _json.loads(_b64.urlsafe_b64decode(payload_b64))
                user_id = payload.get("sub") or payload.get("email") or payload.get("user_id")
                if user_id:
                    return str(user_id)
        except Exception:
            pass

    custom = request.headers.get("X-BioMate-User-Id", "")
    if custom:
        return custom

    ip = getattr(request.client, "host", "unknown")
    return f"anonymous@{ip}"


# ---------------------------------------------------------------------------
# Payload hash helpers
# ---------------------------------------------------------------------------

def _hash_path_params(request: Request) -> str:
    """Hash the path + query string as a stable identifier for GET requests."""
    canonical = f"{request.method} {request.url.path}?{request.url.query}"
    return hashlib.sha256(canonical.encode()).hexdigest()


def _derive_action(method: str, path: str) -> str:
    """Map an HTTP method + path to an AuditAction constant."""
    from .audit_store import AuditAction
    p = path.lower()
    if "ingest-assay" in p:
        return AuditAction.INGEST_ASSAY
    if "propose" in p:
        return AuditAction.PROPOSE_ROUND
    if "export/cro-order" in p or "export" in p:
        return AuditAction.EXPORT_CRO_ORDER
    if "lims/poll" in p or "lims" in p:
        return AuditAction.POLL_LIMS
    if "models" in p and "register" in p:
        return AuditAction.REGISTER_MODEL
    if "models" in p and "run" in p:
        return AuditAction.RUN_MODEL
    if "model-validation" in p:
        return AuditAction.MODEL_VALIDATION
    return AuditAction.SYSTEM


# ---------------------------------------------------------------------------
# FastAPI dependency
# ---------------------------------------------------------------------------

async def audit_regulated_action(
    request: Request,
    campaign_id: Optional[str] = None,
    x_biomate_esig: Optional[str] = Header(default=None, alias="X-BioMate-ESig"),
):
    """
    FastAPI dependency for regulated write/read endpoints.

    Records the operation to the tamper-evident audit log.
    If BIOMATE_ESIG_REQUIRED=1 and the action is in _ESIG_SUPPORTED_ACTIONS,
    validates the TOTP token from the X-BioMate-ESig header.

    Usage in router:
        @router.post("/{campaign_id}/propose")
        async def propose(campaign_id: str, ..., _: None = Depends(audit_regulated_action)):
            ...
    """
    store = _get_audit_store()
    if store is None:
        log.warning("Audit store unavailable — operation proceeding without audit")
        return

    user_id = _extract_user_id(request)
    action = _derive_action(request.method, str(request.url.path))
    resource_id = campaign_id or _extract_campaign_id_from_path(request.url.path)
    payload_hash = _hash_path_params(request)

    # eSig gate for high-stakes actions
    esig_status = "not_required"
    if action in _ESIG_SUPPORTED_ACTIONS:
        if x_biomate_esig:
            esig_status = _validate_esig(user_id, action, x_biomate_esig, store)
        elif _ESIG_REQUIRED:
            raise HTTPException(
                status_code=403,
                detail=(
                    f"Action '{action}' requires an electronic signature. "
                    "Supply a TOTP token in the X-BioMate-ESig header."
                ),
            )
        else:
            esig_status = "not_provided"

    details = f"esig={esig_status}"

    try:
        from .audit_store import AuditEvent
        store.append(AuditEvent(
            user_id=user_id,
            action=action,
            resource_type="campaign" if resource_id else "system",
            resource_id=resource_id or "",
            payload_hash=payload_hash,
            details=details,
        ))
    except Exception as exc:
        log.error("Audit append failed for action=%s: %s", action, exc)
        # In non-strict mode, do NOT block the operation — just log the failure.
        # Set BIOMATE_AUDIT_STRICT=1 to block on audit failure.
        if os.environ.get("BIOMATE_AUDIT_STRICT", "0") == "1":
            raise HTTPException(status_code=500, detail="Audit log unavailable") from exc


def _extract_campaign_id_from_path(path: str) -> str:
    """Best-effort extraction of campaign_id from a drug-discovery path."""
    parts = path.strip("/").split("/")
    # /api/drug-discovery/{campaign_id}/...
    try:
        idx = parts.index("drug-discovery")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    except ValueError:
        pass
    return ""


def _validate_esig(user_id: str, action: str, totp_token: str, store) -> str:
    """Validate a TOTP token and record the eSig.  Returns status string."""
    try:
        from .esig import ESignatureService
        svc = ESignatureService(store)
        if not svc.is_registered(user_id):
            return "user_not_registered"
        svc.sign(
            user_id=user_id,
            action=action,
            meaning=f"Electronically signing {action}",
            totp_token=totp_token,
        )
        return "verified"
    except ValueError as exc:
        log.warning("eSig validation failed for user=%s action=%s: %s", user_id, action, exc)
        if _ESIG_REQUIRED:
            raise HTTPException(status_code=403, detail=f"eSig rejected: {exc}") from exc
        return "invalid"
    except Exception as exc:
        log.error("eSig service error: %s", exc)
        return "error"
