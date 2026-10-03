"""
External MCP Server API — register / list / delete a user's remote MCP servers,
discover their tools, and dispatch tool calls to them.

Capability B of docs/20260922_CONNECTOR_PRIVATE_DB_AND_EXTERNAL_MCP_PLAN.md.
Mirrors private_db_api.py / credentials_api.py (Router auto-discovered by
include_all_package_routers). All state is per-user, Vault-backed, and scoped
to `trans.user`.

Endpoints:
  POST   /api/biomate/mcp-servers              — register a remote MCP server
                                               (name, transport sse|http, url,
                                                optional auth_header). Runs the
                                                SSRF check + stdio-reject that
                                                already live in the external_mcp
                                                module, then best-effort discovers
                                                the server's tool names.
  GET    /api/biomate/mcp-servers              — list this user's servers (auth masked)
  DELETE /api/biomate/mcp-servers/{server_id}  — delete a server (404-not-403)
  POST   /api/biomate/mcp-servers/{server_id}/tools — connect + tools/list; returns
                                               discovered namespaced tool names
  GET    /api/biomate/mcp-tools                — aggregate: every tool across all of
                                               this user's servers, namespaced. This
                                               is the single call the chat tool-
                                               assembly path makes per turn.
  POST   /api/biomate/mcp-servers/{server_id}/call — dispatch a tools/call to an owned
                                               server (used by the LLM tool loop).

Security: the SSRF guard (is_safe_url) and stdio-reject are enforced INSIDE
`ExternalMCPRegistry.register` / `ExternalMCPClient` — this API calls them, it
does not re-implement or bypass them. Ownership is enforced by the registry
(every resolve is scoped to trans.user; unknown ids → None → 404). Auth headers
live only in the encrypted Vault blob and are never returned by any read path.
"""
import logging
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import DependsOnTrans, Router

log = logging.getLogger(__name__)

router = Router(tags=["external_mcp"])


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class RegisterMCPServerRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)  # accept auth_header or authHeader

    name: str = Field(..., description="Friendly server name")
    transport: str = Field(default="sse", description="Remote transport: sse | http (stdio deferred)")
    url: str = Field(..., description="Remote MCP endpoint URL (https; http only for localhost-dev)")
    # The UI sends a single header string ("Authorization: Bearer xyz") OR just the
    # token value. Accept both plus a structured dict, normalized in the route.
    auth_header: Optional[str] = Field(
        default=None,
        alias="authHeader",
        description="Optional auth header, e.g. 'Authorization: Bearer <token>' (stored encrypted)",
    )
    scope: str = Field(default="account", description="account only; project/request scope is not implemented")
    project_id: Optional[str] = Field(default=None, description="Reserved for future project-scoped registrations")


class CallMCPToolRequest(BaseModel):
    tool: str = Field(..., description="Tool name (raw or namespaced mcp__<server>__<tool>)")
    arguments: Dict[str, Any] = Field(default_factory=dict, description="Tool arguments")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _require_user(trans: ProvidesUserContext) -> None:
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")


def _registry(trans: ProvidesUserContext):
    """Build a user-scoped registry. PermissionError → 401 (no authenticated user)."""
    from galaxy.ai.external_mcp.registry import ExternalMCPRegistry

    try:
        return ExternalMCPRegistry(trans)
    except PermissionError:
        raise HTTPException(status_code=401, detail="Authentication required")


def _parse_auth_header(auth_header: Optional[str]) -> Dict[str, str]:
    """
    Normalize the UI's single auth-header field into a {name: value} dict for the
    registry. Accepts 'Header-Name: value' or a bare token (assumed Authorization
    Bearer). Empty → no headers.
    """
    if not auth_header:
        return {}
    raw = auth_header.strip()
    if not raw:
        return {}
    if ":" in raw:
        name, _, value = raw.partition(":")
        name = name.strip()
        value = value.strip()
        if name and value:
            return {name: value}
    # Bare token → assume a Bearer Authorization header.
    return {"Authorization": raw if raw.lower().startswith("bearer ") else f"Bearer {raw}"}


def _discover_tool_names(reg, server_id: str, user_id: Any) -> List[str]:
    """Best-effort tools/list → namespaced names. Never raises (returns [])."""
    try:
        tools = reg.list_tools(server_id, user_id=user_id)
        return [t.get("name") for t in tools if isinstance(t, dict) and t.get("name")]
    except Exception as e:  # transport/protocol/SSRF error — surface as empty, log
        # Upstream-controlled HTTP/JSON-RPC error text can contain arbitrary
        # content. Do not place it in logs or a user response, where a broken
        # provider could echo an authorization value or misleading instructions.
        log.info("[ExternalMCP] tool discovery failed for %s (%s)", server_id, type(e).__name__)
        return []


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post(
    "/api/biomate/mcp-servers",
    summary="Register a remote MCP server (SSRF-checked, stdio rejected) and discover its tools",
)
def register_mcp_server(
    request: RegisterMCPServerRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    _require_user(trans)
    reg = _registry(trans)
    headers = _parse_auth_header(request.auth_header)
    try:
        record = reg.register(
            name=request.name,
            transport=request.transport,
            url=request.url,
            headers=headers,
            scope=request.scope,
            project_id=request.project_id,
        )
    except ValueError as e:
        # bad transport / scope / unsafe URL (SSRF) — safe to surface, no secrets.
        raise HTTPException(status_code=400, detail=str(e))

    # Best-effort discovery so the UI toast can report a tool count immediately.
    tools = _discover_tool_names(reg, record["id"], getattr(trans.user, "id", None))
    record["tools"] = tools
    return {"success": True, "server": record, "tools": tools, **record}


@router.get(
    "/api/biomate/mcp-servers",
    summary="List the current user's remote MCP servers (auth masked)",
)
def list_mcp_servers(
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    _require_user(trans)
    reg = _registry(trans)
    servers: List[Dict[str, Any]] = []
    for rec in reg.list():
        # Normalize masked record → UI contract (hasAuth, tools[]).
        rec["hasAuth"] = bool(rec.pop("has_auth", False))
        rec["tools"] = _discover_tool_names(reg, rec["id"], getattr(trans.user, "id", None))
        servers.append(rec)
    return {"servers": servers}


@router.delete(
    "/api/biomate/mcp-servers/{server_id}",
    summary="Delete a remote MCP server",
)
def delete_mcp_server(
    server_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    _require_user(trans)
    reg = _registry(trans)
    existed = reg.delete(server_id)
    if not existed:
        # 404-not-403: do not reveal existence of another user's server.
        raise HTTPException(status_code=404, detail="MCP server not found")
    return {"success": True, "deleted": server_id}


@router.post(
    "/api/biomate/mcp-servers/{server_id}/tools",
    summary="Discover a server's tools (connect + tools/list, namespaced names)",
)
def list_mcp_server_tools(
    server_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    _require_user(trans)
    reg = _registry(trans)
    try:
        tools = reg.list_tools(server_id, user_id=getattr(trans.user, "id", None))
    except PermissionError:
        raise HTTPException(status_code=404, detail="MCP server not found")
    except Exception as e:
        # Never return arbitrary upstream response text; it may contain a secret
        # reflected by the remote server. The server id identifies the connection
        # the user should check without exposing transport internals.
        log.info("[ExternalMCP] tool listing failed for %s (%s)", server_id, type(e).__name__)
        raise HTTPException(status_code=502, detail="MCP server is unreachable or returned an invalid response")
    return {"server_id": server_id, "tools": tools}


@router.get(
    "/api/biomate/mcp-tools",
    summary="Aggregate: every namespaced tool across all of the user's MCP servers",
)
def list_all_mcp_tools(
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Single call the chat tool-assembly path makes per turn. Returns each tool's
    namespaced name (mcp__<server>__<tool>), its owning server_id, description,
    and inputSchema — enough for the LLM tool loop to expose + dispatch. Servers
    that are unreachable this turn contribute zero tools (never fail the whole
    call — the model keeps its built-in tools).
    """
    _require_user(trans)
    reg = _registry(trans)
    out: List[Dict[str, Any]] = []
    for rec in reg.list():
        sid = rec["id"]
        try:
            tools = reg.list_tools(sid, user_id=getattr(trans.user, "id", None))
        except Exception as e:
            log.info("[ExternalMCP] skipping server %s in aggregate (%s)", sid, type(e).__name__)
            continue
        for t in tools:
            if not isinstance(t, dict) or not t.get("name"):
                continue
            out.append({
                "server_id": sid,
                "server_name": rec.get("name"),
                "name": t.get("name"),  # namespaced mcp__<server>__<tool>
                "raw_name": t.get("_raw_name"),
                "description": t.get("description") or "",
                "input_schema": t.get("inputSchema") or t.get("input_schema") or {"type": "object", "properties": {}},
            })
    return {"tools": out}


@router.post(
    "/api/biomate/mcp-servers/{server_id}/call",
    summary="Dispatch a tools/call to an owned MCP server (used by the LLM tool loop)",
)
def call_mcp_tool(
    server_id: str,
    request: CallMCPToolRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Ownership-checked tool dispatch. Resolves the owned server, builds its client
    (re-runs is_safe_url on the stored URL), and forwards a tools/call. The tool
    name may be raw or namespaced — the client strips the mcp__<server>__ prefix.
    """
    _require_user(trans)
    reg = _registry(trans)
    try:
        client = reg.client_for(server_id)  # PermissionError if not owned
    except PermissionError:
        raise HTTPException(status_code=404, detail="MCP server not found")
    try:
        result = client.call_tool(request.tool, request.arguments or {})
    except Exception as e:
        log.info("[ExternalMCP] tool call failed for %s (%s)", server_id, type(e).__name__)
        raise HTTPException(status_code=502, detail="MCP tool call failed; check the server endpoint and authorization")
    return {"server_id": server_id, "tool": request.tool, "result": result}
