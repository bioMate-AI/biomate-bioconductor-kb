"""
External MCP Connect (Capability B, MVP first slice).

Consume a USER's own **remote** MCP server (SSE / HTTP JSON-RPC) so their
proprietary tools show up inside BioMate chat.

Scope (MVP):
  * Remote transport ONLY (HTTP POST JSON-RPC, optional SSE response framing).
  * stdio transport is DEFERRED entirely — launching an arbitrary user-supplied
    local command is RCE-by-design and is out of the MVP (see plan §3.3).

Security posture (see client.py):
  * SSRF blocklist — resolve the URL host and reject private / link-local /
    loopback / cloud-metadata targets BEFORE connecting, re-checked after any
    redirect.
  * https-only in prod (http allowed only for an explicit localhost-dev flag).
  * per-request timeouts, response-size cap, no redirect auto-follow to internal.

Public surface:
  * client.ExternalMCPClient   — thin remote JSON-RPC client.
  * client.is_safe_url         — the SSRF guard (standalone-testable).
  * registry.ExternalMCPRegistry — per-user Vault-backed registration store.
  * registry.namespaced_tool_name — tool-name namespacing helper.
"""

from .client import (  # noqa: F401
    ExternalMCPClient,
    ExternalMCPError,
    SSRFBlockedError,
    is_safe_url,
)

__all__ = [
    "ExternalMCPClient",
    "ExternalMCPError",
    "SSRFBlockedError",
    "is_safe_url",
]
