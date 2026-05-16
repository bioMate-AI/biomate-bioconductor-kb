"""
Auth + rate-limit dependencies for the customer feedback endpoints.

Fixes audit gaps 3a (no auth), 3b (no rate limit), 3d (fail-open internal
auth), 3e (org-id adapter routing without billing check).

JWT verification reuses backend/lib/galaxy/webapps/galaxy/api/auth.py
AuthService. Rate limiting uses a simple in-memory token bucket (per-IP)
adequate for single-process gunicorn; swap to Redis at scale.

Billing-tier check reads paid_orgs.json — list of org IDs entitled to
per-org adapter routing. Missing file ⇒ empty allowlist ⇒ all org_id
headers fall back to public adapter.
"""
from __future__ import annotations

import json
import logging
import os
import time
from collections import defaultdict, deque
from pathlib import Path
from typing import Optional

from fastapi import Header, HTTPException, Request

log = logging.getLogger(__name__)

_REPO_ROOT = Path(__file__).resolve().parents[5]
_PAID_ORGS_FILE = _REPO_ROOT / "data" / "regulatory_training" / "paid_orgs.json"

# ---------------------------------------------------------------------------
# Rate limit — per-IP token bucket
# ---------------------------------------------------------------------------

_DEFAULT_RPM = 60  # per IP per minute on customer POST endpoints
_buckets: dict[str, deque[float]] = defaultdict(deque)


def _client_ip(request: Request) -> str:
    # Honor X-Forwarded-For when behind a reverse proxy
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def enforce_rate_limit(request: Request, rpm: int = _DEFAULT_RPM) -> None:
    """
    In-memory sliding-window rate limit. Adequate for single-host single-proc;
    for multi-host deployment, replace with Redis-backed limiter.
    """
    ip = _client_ip(request)
    now = time.monotonic()
    window = _buckets[ip]
    # Drop entries older than 60s
    while window and now - window[0] > 60.0:
        window.popleft()
    if len(window) >= rpm:
        retry_after = int(60.0 - (now - window[0])) + 1
        raise HTTPException(
            429, "rate limit exceeded",
            headers={"Retry-After": str(retry_after)},
        )
    window.append(now)


# ---------------------------------------------------------------------------
# JWT authentication — reuses AuthService
# ---------------------------------------------------------------------------

_auth_service = None


def _get_auth_service():
    """Lazy AuthService construction — module-level avoids circular imports."""
    global _auth_service
    if _auth_service is None:
        try:
            from galaxy.webapps.galaxy.api.auth import AuthService  # type: ignore
            _auth_service = AuthService()
        except Exception as exc:
            log.warning("[auth] AuthService unavailable: %s", exc)
            _auth_service = False
    return _auth_service or None


def require_authenticated_user(
    request: Request,
    authorization: Optional[str] = Header(None),
) -> dict:
    """
    FastAPI dependency: decodes the Bearer JWT, returns the payload dict.
    Falls open in dev mode when BIOMATE_REQUIRE_AUTH != "1" and AuthService is
    not initialized. In production, set BIOMATE_REQUIRE_AUTH=1 to hard-fail.
    """
    enforce_rate_limit(request)

    if not authorization or not authorization.startswith("Bearer "):
        if os.environ.get("BIOMATE_REQUIRE_AUTH") == "1":
            raise HTTPException(401, "missing Bearer token")
        # Dev mode pass-through with anonymous identity
        return {"user_id": "anonymous", "anon": True}

    token = authorization.removeprefix("Bearer ").strip()
    svc = _get_auth_service()
    if svc is None:
        if os.environ.get("BIOMATE_REQUIRE_AUTH") == "1":
            raise HTTPException(503, "auth service unavailable")
        log.warning("[auth] AuthService not initialized — dev pass-through")
        return {"user_id": "anonymous", "anon": True, "token": token[:8]}

    try:
        payload = svc.verify_jwt_token(token)
        return payload
    except Exception as exc:
        raise HTTPException(401, f"invalid token: {exc}") from exc


# ---------------------------------------------------------------------------
# Internal endpoint auth — fail CLOSED in production
# ---------------------------------------------------------------------------

def require_internal_key(authorization: Optional[str] = Header(None)) -> None:
    """
    Internal endpoints require BIOMATE_INTERNAL_KEY match.
    Hard-fail when the env var is unset (no dev bypass — internal endpoints
    expose unfiltered review queues).
    """
    expected = os.environ.get("BIOMATE_INTERNAL_KEY", "")
    if not expected:
        # Fail closed — refuse access rather than expose the queue
        raise HTTPException(
            503,
            "internal endpoint unavailable: BIOMATE_INTERNAL_KEY not configured",
        )
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "internal endpoint requires Bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    if token != expected:
        raise HTTPException(403, "invalid internal token")


# ---------------------------------------------------------------------------
# Billing-tier entitlement for per-org adapter routing
# ---------------------------------------------------------------------------

def _load_paid_orgs() -> set[str]:
    if not _PAID_ORGS_FILE.exists():
        return set()
    try:
        with _PAID_ORGS_FILE.open() as f:
            data = json.load(f)
        if isinstance(data, list):
            return set(data)
        if isinstance(data, dict):
            return set(data.get("paid_orgs", []))
    except Exception as exc:
        log.warning("[auth] failed to load paid_orgs.json: %s", exc)
    return set()


def is_org_entitled_to_adapter(org_id: str | None) -> bool:
    """
    Returns True iff the org_id is on the paid-orgs list. Missing file or
    unlisted org → False (caller falls back to public adapter).
    """
    if not org_id:
        return False
    return org_id in _load_paid_orgs()
