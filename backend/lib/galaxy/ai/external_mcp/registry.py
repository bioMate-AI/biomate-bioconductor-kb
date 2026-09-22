"""
Per-user registration store for external (remote) MCP servers.

Reuses the Galaxy Vault storage pattern from
`backend/lib/galaxy/webapps/galaxy/api/credentials_api.py` — one encrypted
secret per server at `biomate/mcp-servers/<server_id>`, plus a per-user index
so servers can be listed. Auth headers/tokens live INSIDE the encrypted blob
and are never returned by the list view.

This is NOT LICENSE_REGISTRY-gated (an MCP server is not a license tool) — it
is its own record type, exactly as the plan (§2.2 / §3.2) prescribes.

Ownership: every read/resolve is scoped to `trans.user`; a `server_id` that is
not present in the requesting user's own vault index simply resolves to None
(the caller returns 404-not-403). There is no cross-user path.

Record shape (stored, encrypted):
    {
      "id": "<server_id>",
      "name": "<friendly name>",
      "transport": "sse" | "http",   # remote only; stdio is DEFERRED
      "url": "https://…",
      "headers": {"Authorization": "Bearer …"},   # secret; never listed
      "scope": "account" | "project" | "request",
      "project_id": "<optional>",
      "created_at": "<iso8601>"
    }
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

try:
    from .client import ExternalMCPClient, is_safe_url
except ImportError:  # loaded by file path (standalone tests) — resolve sibling
    import importlib.util as _ilu
    from pathlib import Path as _Path

    _spec = _ilu.spec_from_file_location(
        "_ext_mcp_client_sib", _Path(__file__).resolve().parent / "client.py"
    )
    _client = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(_client)
    ExternalMCPClient = _client.ExternalMCPClient
    is_safe_url = _client.is_safe_url

log = logging.getLogger(__name__)

VAULT_PREFIX = "biomate/mcp-servers"
INDEX_KEY = f"{VAULT_PREFIX}/_index"  # per-user list of server_ids
PREFS_KEY = "biomate_mcp_servers"  # fallback when vault not configured

# Remote transports only. stdio is deliberately absent (RCE surface, deferred).
ALLOWED_TRANSPORTS = ("sse", "http")
ALLOWED_SCOPES = ("account", "project", "request")

# Keys that must NEVER be returned to the client in a list/get view.
_SECRET_KEYS = ("headers", "auth", "token")


class ExternalMCPRegistry:
    """
    Vault-backed per-user store. Construct with a Galaxy `trans` (must have
    `.user`, `.app.vault`). All methods are scoped to that user.
    """

    def __init__(self, trans: Any) -> None:
        self.trans = trans
        if getattr(trans, "user", None) is None:
            raise PermissionError("external MCP registry requires an authenticated user")
        self.user = trans.user

    # -- Vault primitives (mirror credentials_api._store/_get/_delete) -----

    def _vault(self):
        from galaxy.security.vault import UserVaultWrapper

        return UserVaultWrapper(self.trans.app.vault, self.user)

    def _write_secret(self, path: str, value: str) -> None:
        try:
            self._vault().write_secret(path, value)
            return
        except Exception as e:  # vault unconfigured → preferences fallback
            log.warning("[ExternalMCP] Vault unavailable (%s), using preferences fallback", e)
        raw = self.user.preferences.get(PREFS_KEY, "{}")
        try:
            store = json.loads(raw)
        except Exception:
            store = {}
        store[path] = value
        self.user.preferences[PREFS_KEY] = json.dumps(store)
        self.trans.sa_session.commit()

    def _read_secret(self, path: str) -> Optional[str]:
        try:
            raw = self._vault().read_secret(path)
            if raw:
                return raw
        except Exception:
            pass
        try:
            store = json.loads(self.user.preferences.get(PREFS_KEY, "{}"))
            return store.get(path)
        except Exception:
            return None

    # -- Index (list of this user's server_ids) ---------------------------

    def _load_index(self) -> List[str]:
        raw = self._read_secret(INDEX_KEY)
        if not raw:
            return []
        try:
            ids = json.loads(raw)
            return [str(i) for i in ids] if isinstance(ids, list) else []
        except Exception:
            return []

    def _save_index(self, ids: List[str]) -> None:
        self._write_secret(INDEX_KEY, json.dumps(sorted(set(ids))))

    def _record_path(self, server_id: str) -> str:
        return f"{VAULT_PREFIX}/{server_id}"

    # -- Public API -------------------------------------------------------

    def register(
        self,
        name: str,
        transport: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        scope: str = "account",
        project_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Validate + persist a new remote MCP server for this user.
        Returns the SAFE (masked) record. Raises ValueError on bad input,
        SSRFBlockedError (via is_safe_url) on an unsafe URL.
        """
        transport = (transport or "").lower()
        if transport not in ALLOWED_TRANSPORTS:
            raise ValueError(
                f"transport {transport!r} not allowed (remote only: {ALLOWED_TRANSPORTS}); "
                "stdio is deferred"
            )
        if scope not in ALLOWED_SCOPES:
            raise ValueError(f"scope {scope!r} not allowed ({ALLOWED_SCOPES})")

        ok, reason = is_safe_url(url)
        if not ok:
            # Do not persist an unsafe target at all.
            raise ValueError(f"unsafe MCP URL rejected: {reason}")

        server_id = uuid.uuid4().hex
        record = {
            "id": server_id,
            "name": name or "unnamed",
            "transport": transport,
            "url": url,
            "headers": dict(headers or {}),
            "scope": scope,
            "project_id": project_id,
            "owner_user_id": getattr(self.user, "id", None),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        self._write_secret(self._record_path(server_id), json.dumps(record))
        index = self._load_index()
        index.append(server_id)
        self._save_index(index)
        log.info("[ExternalMCP] Registered server %s (%s) for user %s",
                 server_id, transport, getattr(self.user, "id", "?"))
        return _mask(record)

    def _resolve_raw(self, server_id: str) -> Optional[Dict[str, Any]]:
        """Return the FULL record (with secrets) IFF owned by this user, else None."""
        if server_id not in self._load_index():
            return None  # ownership: not in this user's index → 404-not-403
        raw = self._read_secret(self._record_path(server_id))
        if not raw:
            return None
        try:
            record = json.loads(raw)
        except Exception:
            return None
        # Defense in depth: verify owner even if the index says so.
        owner = record.get("owner_user_id")
        if owner is not None and getattr(self.user, "id", None) not in (owner, None):
            return None
        return record

    def get(self, server_id: str) -> Optional[Dict[str, Any]]:
        """Return the SAFE (masked) record for this user, or None."""
        record = self._resolve_raw(server_id)
        return _mask(record) if record else None

    def list(self) -> List[Dict[str, Any]]:
        """Return all of this user's servers, masked (no secrets)."""
        out: List[Dict[str, Any]] = []
        for sid in self._load_index():
            record = self._resolve_raw(sid)
            if record:
                out.append(_mask(record))
        return out

    def delete(self, server_id: str) -> bool:
        """Delete a server owned by this user. Returns True if it existed."""
        if server_id not in self._load_index():
            return False
        self._write_secret(self._record_path(server_id), "")
        self._save_index([i for i in self._load_index() if i != server_id])
        return True

    def client_for(self, server_id: str) -> ExternalMCPClient:
        """
        Build an ExternalMCPClient for an owned server. Raises PermissionError
        if the server_id is not owned by / known to this user.
        """
        record = self._resolve_raw(server_id)
        if not record:
            raise PermissionError(f"MCP server {server_id!r} not found for this user")
        return ExternalMCPClient(
            url=record["url"],
            headers=record.get("headers") or {},
            server_name=record.get("name") or "external",
        )

    def list_tools(self, server_id: str, user_id: Optional[Any] = None) -> List[Dict[str, Any]]:
        """
        Resolve + connect + initialize + tools/list for an owned server.
        `user_id`, when provided, is asserted against the record owner as an
        extra ownership guard (the registry is already user-scoped via trans).
        Returns namespaced tool schemas (mcp__<server>__<tool>).
        """
        record = self._resolve_raw(server_id)
        if not record:
            raise PermissionError(f"MCP server {server_id!r} not found for this user")
        if user_id is not None:
            owner = record.get("owner_user_id")
            if owner is not None and owner != user_id:
                raise PermissionError("ownership mismatch for MCP server")
        client = ExternalMCPClient(
            url=record["url"],
            headers=record.get("headers") or {},
            server_name=record.get("name") or "external",
        )
        client.initialize()
        return client.list_tools()


def _mask(record: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Return a copy safe to send to the client — secrets removed / booleanized."""
    if record is None:
        return None
    safe = dict(record)
    headers = safe.get("headers") or {}
    safe["has_auth"] = bool(headers)
    for k in _SECRET_KEYS:
        safe.pop(k, None)
    return safe
