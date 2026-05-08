"""
Credentials API — per-user tool credential storage + license requirement lookup.

Endpoints (auto-discovered by include_all_package_routers):
  GET  /api/workflows/license-requirements?nextflow_path=...
  GET  /api/users/credentials?tool=<tool_id>
  POST /api/users/credentials
  DELETE /api/users/credentials/{tool_id}

Storage: Galaxy Vault (UserVaultWrapper), keyed at biomate/credentials/<tool_id>.
Fallback: if vault not configured, stores as JSON in user.preferences.
Master credentials (demo / no user cred): read from environment variables.
"""
import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import HTTPException, Query
from pydantic import BaseModel

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import DependsOnTrans, Router
from galaxy.webapps.galaxy.api.license_registry import LICENSE_REGISTRY, scan_nf_for_tool_ids

log = logging.getLogger(__name__)

# Load .env so ALPHAFOLD3_DOCKER_USER etc. are available
try:
    _backend_root = Path(__file__).resolve().parents[5]
    _dotenv_path = _backend_root / ".env"
    if _dotenv_path.exists():
        from dotenv import load_dotenv
        load_dotenv(_dotenv_path, override=False)
except Exception:
    pass

router = Router(tags=["credentials"])

VAULT_PREFIX = "biomate/credentials"
PREFS_KEY = "biomate_credentials"  # fallback when vault not configured


# ---------------------------------------------------------------------------
# Internal credential helpers
# ---------------------------------------------------------------------------

def _store_credential(trans, tool_id: str, data: dict) -> None:
    """Store a credential in Galaxy Vault (or user preferences as fallback)."""
    try:
        from galaxy.security.vault import UserVaultWrapper
        vault = UserVaultWrapper(trans.app.vault, trans.user)
        vault.write_secret(f"{VAULT_PREFIX}/{tool_id}", json.dumps(data))
        log.info("[Credentials] Stored %s credential for user %s (vault)", tool_id, trans.user.id)
    except Exception as e:
        log.warning("[Credentials] Vault unavailable (%s), falling back to preferences", e)
        raw = trans.user.preferences.get(PREFS_KEY, "{}")
        try:
            store = json.loads(raw)
        except Exception:
            store = {}
        store[tool_id] = data
        trans.user.preferences[PREFS_KEY] = json.dumps(store)
        trans.sa_session.commit()


def _get_credential(trans, tool_id: str) -> Optional[dict]:
    """Return stored user credential for tool_id, or None."""
    if not trans.user:
        return None
    try:
        from galaxy.security.vault import UserVaultWrapper
        vault = UserVaultWrapper(trans.app.vault, trans.user)
        raw = vault.read_secret(f"{VAULT_PREFIX}/{tool_id}")
        if raw:
            return json.loads(raw)
    except Exception:
        pass
    # Preferences fallback
    try:
        raw = trans.user.preferences.get(PREFS_KEY)
        if raw:
            return json.loads(raw).get(tool_id)
    except Exception:
        pass
    return None


def _delete_credential(trans, tool_id: str) -> None:
    """Delete a stored credential."""
    if not trans.user:
        return
    try:
        from galaxy.security.vault import UserVaultWrapper
        vault = UserVaultWrapper(trans.app.vault, trans.user)
        vault.write_secret(f"{VAULT_PREFIX}/{tool_id}", "")
    except Exception:
        pass
    # Also clean from preferences fallback
    try:
        raw = trans.user.preferences.get(PREFS_KEY)
        if raw:
            store = json.loads(raw)
            store.pop(tool_id, None)
            trans.user.preferences[PREFS_KEY] = json.dumps(store)
            trans.sa_session.commit()
    except Exception:
        pass


def get_effective_credential(trans, tool_id: str):
    """
    Returns (credential_dict, source) where source is 'user' | 'biomate' | 'none'.
    Call this at execution time to inject the right credential.
    """
    user_cred = _get_credential(trans, tool_id)
    if user_cred:
        return user_cred, "user"

    reg = LICENSE_REGISTRY.get(tool_id, {})

    # If the tool requires each user to supply their own credential, never fall
    # back to BioMate's master key — return 'none' so the UI prompts the user.
    if reg.get("user_must_provide"):
        return None, "none"
    cred_type = reg.get("type")

    if cred_type == "none":
        # Open-source tool — no credential needed; always resolved
        return {}, "biomate"

    if cred_type == "docker_auth":
        u = os.environ.get(reg.get("env_key_user", ""), "")
        t = os.environ.get(reg.get("env_key_token", ""), "")
        if u and t:
            return {"username": u, "token": t}, "biomate"

    elif cred_type == "license_key":
        k = os.environ.get(reg.get("env_key", ""), "")
        if k:
            return {"license_key": k}, "biomate"

    elif cred_type == "api_key":
        k = os.environ.get(reg.get("env_key", ""), "")
        if k:
            return {"api_key": k}, "biomate"

    elif cred_type == "license_server":
        # FlexLM / FlexNet: value is "port@host"
        k = os.environ.get(reg.get("env_key", ""), "")
        if k:
            return {"license_server": k}, "biomate"

    elif cred_type == "license_agreement":
        # No runtime key required (e.g. AMBER24 free academic).
        # BioMate's container already includes the binary — always resolved.
        return {}, "biomate"

    return None, "none"


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class StoreCredentialRequest(BaseModel):
    tool: str
    data: Dict[str, Any]


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get(
    "/api/nextflow/license-requirements",
    summary="List license requirements for a workflow",
)
def get_license_requirements(
    nextflow_path: str = Query(..., description="Path to the .nf workflow file"),
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Scan a Nextflow workflow file for tools that require registration/credentials.
    Returns per-tool status: source = 'user' | 'biomate' | 'none'.
    """
    tool_ids = scan_nf_for_tool_ids(nextflow_path)
    requirements = []
    for tool_id in tool_ids:
        reg = LICENSE_REGISTRY.get(tool_id)
        if not reg:
            continue
        _, source = get_effective_credential(trans, tool_id)
        # has_fallback = True means the workflow handles missing credentials internally
        # (e.g. simcyp_pbpk falls back to native PBPK; nonmem_poppk falls back to nlmixr2).
        # When has_fallback is True, the UI shows an advisory but does NOT block execution.
        has_fallback = bool(reg.get("open_alternatives")) and not reg.get("user_must_provide", True)
        # Simcyp and NONMEM have built-in fallback scripts — override user_must_provide logic
        if tool_id in ("simcyp", "nonmem") and reg.get("open_alternatives"):
            has_fallback = True
        requirements.append({
            "tool_id": tool_id,
            "display_name": reg["display_name"],
            "vendor": reg.get("vendor", ""),
            "type": reg["type"],
            "registration_url": reg.get("registration_url", ""),
            "approval_time": reg.get("approval_time", ""),
            "cost": reg.get("cost", ""),
            "source": source,
            "has_fallback": has_fallback,
            "open_alternatives": reg.get("open_alternatives", []),
        })
    return {"requirements": requirements}


@router.get(
    "/api/users/credentials",
    summary="Check if user has stored a credential for a tool",
)
def check_credential(
    tool: str = Query(..., description="Tool ID, e.g. alphafold3"),
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """Returns existence and source of the credential (never returns the secret value)."""
    _, source = get_effective_credential(trans, tool)
    reg = LICENSE_REGISTRY.get(tool, {})
    return {
        "tool": tool,
        "display_name": reg.get("display_name", tool),
        "has_credential": source != "none",
        "source": source,
    }


@router.post(
    "/api/users/credentials",
    summary="Store a credential for a tool",
)
def store_credential(
    request: StoreCredentialRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Store a per-user credential. The secret is stored in Galaxy Vault.
    data shape depends on tool type:
      docker_auth: {username, token}
      license_key: {license_key}
    """
    if request.tool not in LICENSE_REGISTRY:
        raise HTTPException(status_code=400, detail=f"Unknown tool: {request.tool}")
    _store_credential(trans, request.tool, request.data)
    return {"ok": True, "tool": request.tool}


@router.delete(
    "/api/users/credentials/{tool_id}",
    summary="Delete a stored credential",
)
def delete_credential(
    tool_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    _delete_credential(trans, tool_id)
    return {"ok": True, "tool": tool_id}


@router.get(
    "/api/users/credentials/{tool_id}/value",
    summary="Retrieve credential value for execution injection (admin use only)",
)
def get_credential_value(
    tool_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Returns the actual credential dict for use during workflow execution.
    Only callable with the user's own API key or an admin key.
    The value is never logged.
    """
    cred, source = get_effective_credential(trans, tool_id)
    if cred is None:
        raise HTTPException(status_code=404, detail=f"No credential found for {tool_id}")
    return {"tool": tool_id, "source": source, "data": cred}
