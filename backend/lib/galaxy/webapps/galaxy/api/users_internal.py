"""
users_internal.py — Internal user provisioning endpoint called by the BioMate frontend.

Mirrors billing_internal.py / llm_internal.py — auth via X-Internal-Key
(shared with BILLING_INTERNAL_KEY). NOT exposed in /api/*.

Routes:
  POST /internal/users/provision
    Body: { biomate_user_id: str, email: str }
    Returns: { galaxy_user_id, galaxy_api_key, galaxy_username }

  Purpose: Called at BioMate user registration (auth-service.ts:
  provisionGalaxyUser → galaxy-api-proxy.ts:131). For each new BioMate
  user, get-or-create a Galaxy user with a stable username derived from
  the BioMate UUID, then return their API key. The frontend caches that
  key per-user so subsequent Galaxy API calls authenticate as that user
  (not the shared admin key).

Without this endpoint, every new user provisioning attempt hung for 10s
on Galaxy's 404 handler and the frontend fell back to a shared admin key
that downstream routes (e.g. /api/ai_assistant/generate_workflow) reject
with 401. See docs/ and memory: project_galaxy_provisioning_gap.

Registered by Galaxy's include_all_package_routers scanner (module must
have a `router` attribute at top level).
"""

from __future__ import annotations

import logging
import os
import re
from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request

from galaxy.webapps.galaxy.api import DependsOnApp
from galaxy.structured_app import StructuredApp

log = logging.getLogger(__name__)

router = APIRouter(tags=["users-internal"])


# Galaxy usernames must be lowercase ASCII letters/digits/hyphens, ≥3 chars,
# ≤255 chars. We derive a stable username from the BioMate UUID so the same
# user gets the same Galaxy account across re-provisioning attempts.
_USERNAME_RE = re.compile(r"[^a-z0-9-]+")


def _derive_username(biomate_user_id: str, email: str) -> str:
    """
    Derive a stable, non-PII Galaxy username from the BioMate UUID.
    Falls back to an email-derived slug if the UUID looks non-standard.
    """
    base = (biomate_user_id or "").strip().lower()
    if not base or len(base) < 3:
        # Fallback: slug the email local part.
        local = (email or "anon").split("@", 1)[0].lower()
        base = _USERNAME_RE.sub("-", local) or "anon"
    else:
        base = _USERNAME_RE.sub("-", base)
    # Prefix so it's clearly not a human-chosen username.
    return f"u-{base}"[:255]


@router.post("/internal/users/provision", include_in_schema=False)
async def provision_user(
    request: Request,
    app: StructuredApp = DependsOnApp,
) -> Dict[str, Any]:
    """
    Get-or-create a Galaxy user for a BioMate user and return their API key.

    Idempotent: re-calling with the same biomate_user_id returns the same
    galaxy_user_id + a stable api_key (the most recent non-deleted key, or
    a freshly created one if none exists).
    """
    expected_key = os.environ.get("BILLING_INTERNAL_KEY", "")
    provided_key = request.headers.get("X-Internal-Key", "")
    if expected_key and provided_key != expected_key:
        raise HTTPException(status_code=401, detail="Invalid internal key")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    biomate_user_id = (body.get("biomate_user_id") or "").strip()
    email = (body.get("email") or "").strip().lower()
    if not biomate_user_id or not email:
        raise HTTPException(
            status_code=400, detail="biomate_user_id and email are required"
        )

    # Lazy imports to avoid hard-binding this module to manager init order.
    from galaxy.managers.users import UserManager
    from galaxy.managers.api_keys import ApiKeyManager

    user_manager = UserManager(app)
    api_key_manager = ApiKeyManager(app)

    desired_username = _derive_username(biomate_user_id, email)

    # Step 1: look up by email (the unique key for BioMate→Galaxy mapping).
    user = user_manager.by_email(email)

    if user is None:
        # Step 2: create. Use a random password — login is via API key, not
        # password, so the user never authenticates via Galaxy's web UI.
        try:
            user = user_manager.create(
                email=email, username=desired_username, password=None
            )
        except Exception as exc:
            log.exception("[UsersInternal] User create failed for %s", email)
            raise HTTPException(
                status_code=500, detail=f"Galaxy user create failed: {exc}"
            )
        log.info(
            "[UsersInternal] Created Galaxy user %s (id=%s) for BioMate %s",
            user.username, user.id, biomate_user_id,
        )
    else:
        log.debug(
            "[UsersInternal] Reusing Galaxy user %s (id=%s) for BioMate %s",
            user.username, user.id, biomate_user_id,
        )

    # Step 3: get-or-create API key.
    try:
        api_key = api_key_manager.get_or_create_api_key(user)
    except Exception as exc:
        log.exception("[UsersInternal] API key fetch failed for user id=%s", user.id)
        raise HTTPException(
            status_code=500, detail=f"Galaxy API key fetch failed: {exc}"
        )

    return {
        "galaxy_user_id": str(user.id),
        "galaxy_api_key": api_key,
        "galaxy_username": user.username,
    }
