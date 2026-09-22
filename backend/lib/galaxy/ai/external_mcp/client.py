"""
Thin remote MCP JSON-RPC client + SSRF guard (Capability B MVP).

Why hand-rolled (no `mcp` SDK): the official SDK is not installed and targets
Python 3.10+ (dev runs 3.9). For the remote transport MVP a small, auditable
HTTP/SSE JSON-RPC client is safer than pulling a heavy dep — and it lets the
SSRF core run with ZERO third-party imports (stdlib urllib only), so the
security tests run standalone without a Galaxy runtime.

Transport: HTTP POST of JSON-RPC 2.0 requests to a single user-supplied URL
(the "Streamable HTTP" MCP endpoint). The response may come back as a plain
`application/json` body OR as an SSE stream (`text/event-stream`) — both are
parsed here. stdio is intentionally NOT implemented (deferred; RCE surface).

SECURITY (the point of this file):
  * is_safe_url(url) -> (ok, reason): resolve the host and BLOCK
      - loopback           127.0.0.0/8, ::1, 0.0.0.0
      - private            10/8, 172.16/12, 192.168/16, fc00::/7 (ULA)
      - link-local         169.254.0.0/16 (incl. 169.254.169.254 metadata), fe80::/10
      - other non-global   multicast, reserved, unspecified
      - cloud metadata     169.254.169.254, fd00:ec2::254
    Requires `https` in prod; `http` only when the localhost-dev flag is set
    AND the host is an explicit loopback name/addr.
  * Redirects are NEVER auto-followed. On a redirect we re-run is_safe_url on
    the Location target and refuse redirect-to-internal (defense against a
    public host 302-ing to 169.254.169.254).
  * Every request has a hard timeout; the response body is size-capped.

Nothing here executes user commands, eval/exec, or interpolates user text into
a shell. It only makes outbound HTTP calls to a vetted URL.
"""

from __future__ import annotations

import ipaddress
import json
import os
import socket
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# Tunables (all overridable via env, but safe defaults)
# ---------------------------------------------------------------------------

DEFAULT_TIMEOUT_S = float(os.environ.get("EXTERNAL_MCP_TIMEOUT_S", "20"))
MAX_RESPONSE_BYTES = int(os.environ.get("EXTERNAL_MCP_MAX_RESPONSE_BYTES", str(8 * 1024 * 1024)))
MAX_REDIRECTS = 3  # we resolve them manually, re-checking SSRF each hop

# Allow http:// only when this is truthy AND the host is loopback. Off by default.
_LOCALHOST_DEV_ENV = "EXTERNAL_MCP_ALLOW_LOCALHOST_HTTP"

_ALLOWED_SCHEMES = ("http", "https")


class ExternalMCPError(Exception):
    """Any failure talking to a user MCP server (transport, protocol, JSON-RPC error)."""


class SSRFBlockedError(ExternalMCPError):
    """The target URL/host resolved to a blocked (internal) address."""


# ---------------------------------------------------------------------------
# SSRF guard  — the security core (standalone, no Galaxy runtime needed)
# ---------------------------------------------------------------------------

def _localhost_dev_allowed() -> bool:
    return os.environ.get(_LOCALHOST_DEV_ENV, "").lower() in ("1", "true", "yes", "on")


_LOOPBACK_HOSTNAMES = {"localhost", "localhost.localdomain", "ip6-localhost", "ip6-loopback"}


def _ip_is_blocked(ip: ipaddress._BaseAddress) -> Optional[str]:
    """Return a reason string if this resolved IP must be blocked, else None."""
    # Normalise IPv4-mapped IPv6 (e.g. ::ffff:169.254.169.254) to its IPv4 form
    # so the mapped address can't smuggle a link-local target past the checks.
    if isinstance(ip, ipaddress.IPv6Address):
        if ip.ipv4_mapped is not None:
            ip = ip.ipv4_mapped

    if ip.is_loopback:
        return "loopback address blocked (127.0.0.0/8, ::1)"
    if ip.is_link_local:
        # 169.254.0.0/16 (incl. 169.254.169.254 cloud metadata) and fe80::/10
        return "link-local address blocked (169.254.0.0/16 incl. cloud metadata)"
    if ip.is_private:
        # 10/8, 172.16/12, 192.168/16, fc00::/7 (ULA), etc.
        return "private address blocked (RFC1918 / ULA)"
    if ip.is_unspecified:
        return "unspecified address blocked (0.0.0.0 / ::)"
    if ip.is_multicast:
        return "multicast address blocked"
    if ip.is_reserved:
        return "reserved address blocked"
    # Cloud metadata over IPv6 (AWS fd00:ec2::254 lives in ULA fc00::/7 above,
    # but assert explicitly for auditability).
    try:
        if isinstance(ip, ipaddress.IPv6Address) and ip == ipaddress.IPv6Address("fd00:ec2::254"):
            return "cloud metadata (IPv6) blocked"
    except ipaddress.AddressValueError:
        pass
    if not ip.is_global:
        return "non-global address blocked"
    return None


def _resolve_all_ips(host: str) -> List[ipaddress._BaseAddress]:
    """Resolve host → every A/AAAA record. Raises SSRFBlockedError on failure."""
    try:
        infos = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    except socket.gaierror as e:
        raise SSRFBlockedError(f"host resolution failed for {host!r}: {e}")
    ips: List[ipaddress._BaseAddress] = []
    for info in infos:
        sockaddr = info[4]
        try:
            ips.append(ipaddress.ip_address(sockaddr[0]))
        except ValueError:
            continue
    if not ips:
        raise SSRFBlockedError(f"no usable IP addresses resolved for {host!r}")
    return ips


def is_safe_url(url: str, allow_localhost_http: Optional[bool] = None) -> Tuple[bool, str]:
    """
    Validate a user-supplied MCP URL before we ever connect to it.

    Returns (ok, reason). ok=True → safe to connect. ok=False → `reason`
    explains the block (safe to surface to the user; contains no secrets).

    Blocks: loopback, private (RFC1918/ULA), link-local (incl. 169.254.169.254
    cloud metadata), unspecified, multicast, reserved, and any non-global IP —
    checked against EVERY address the host resolves to (DNS may return several;
    if ANY is internal we refuse, to defeat DNS-rebinding-style tricks).

    Scheme policy: https always allowed; http only when localhost-dev is
    enabled AND the host is an explicit loopback. Everything else → blocked.
    """
    if allow_localhost_http is None:
        allow_localhost_http = _localhost_dev_allowed()

    if not url or not isinstance(url, str):
        return False, "empty or non-string URL"

    try:
        parsed = urlparse(url.strip())
    except Exception as e:
        return False, f"unparseable URL: {e}"

    scheme = (parsed.scheme or "").lower()
    if scheme not in _ALLOWED_SCHEMES:
        return False, f"scheme {scheme!r} not allowed (only http/https)"

    host = parsed.hostname
    if not host:
        return False, "URL has no host"
    host = host.lower()

    # ---- Scheme / http-only-for-localhost policy -------------------------
    host_is_loopback_name = host in _LOOPBACK_HOSTNAMES
    host_is_loopback_ip = False
    try:
        _probe = ipaddress.ip_address(host)
        host_is_loopback_ip = _probe.is_loopback
    except ValueError:
        pass
    host_is_loopback = host_is_loopback_name or host_is_loopback_ip

    if scheme == "http":
        if not (allow_localhost_http and host_is_loopback):
            return False, (
                "http scheme rejected in prod (https required; "
                "http allowed only for explicit localhost-dev)"
            )

    # ---- Resolve + block internal targets --------------------------------
    # If the host is a literal IP, check it directly (no DNS needed).
    try:
        literal = ipaddress.ip_address(host)
        reason = _ip_is_blocked(literal)
        if reason:
            # localhost-dev exception ONLY when explicitly opted in via http+loopback.
            if allow_localhost_http and scheme == "http" and literal.is_loopback:
                return True, "localhost-dev loopback allowed (explicit opt-in)"
            return False, reason
        return True, "ok"
    except ValueError:
        pass  # hostname, not a literal IP → resolve below

    # Explicit loopback hostname under localhost-dev http opt-in.
    if host_is_loopback and allow_localhost_http and scheme == "http":
        return True, "localhost-dev loopback allowed (explicit opt-in)"

    for ip in _resolve_all_ips(host):
        reason = _ip_is_blocked(ip)
        if reason:
            return False, f"{host} resolves to {ip} — {reason}"

    return True, "ok"


def _assert_safe(url: str, allow_localhost_http: Optional[bool] = None) -> None:
    ok, reason = is_safe_url(url, allow_localhost_http=allow_localhost_http)
    if not ok:
        raise SSRFBlockedError(reason)


# ---------------------------------------------------------------------------
# Tool-name namespacing
# ---------------------------------------------------------------------------

def _sanitize_component(s: str) -> str:
    """Keep tool/server names to a safe identifier charset for namespacing."""
    out = "".join(c if (c.isalnum() or c in ("_", "-")) else "_" for c in (s or ""))
    return out.strip("_") or "unnamed"


def namespaced_tool_name(server_name: str, tool_name: str) -> str:
    """
    Prefix a server's tool so it can't collide with a built-in tool:
        mcp__<server_name>__<tool>
    Mirrors how this harness surfaces MCP tools (mcp__server__tool).
    """
    return f"mcp__{_sanitize_component(server_name)}__{_sanitize_component(tool_name)}"


# ---------------------------------------------------------------------------
# Thin remote MCP JSON-RPC client
# ---------------------------------------------------------------------------

class ExternalMCPClient:
    """
    Minimal JSON-RPC 2.0 client for a REMOTE MCP server (Streamable HTTP / SSE).

    Usage:
        c = ExternalMCPClient(url, headers={"Authorization": "Bearer …"},
                              server_name="myserver")
        c.initialize()
        tools = c.list_tools()          # namespaced names in each entry["name"]
        result = c.call_tool("<raw tool name>", {"x": 1})

    The client never follows redirects to internal hosts and never opens a
    socket to a URL that fails is_safe_url().
    """

    PROTOCOL_VERSION = "2024-11-05"

    def __init__(
        self,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        server_name: str = "external",
        timeout: float = DEFAULT_TIMEOUT_S,
        allow_localhost_http: Optional[bool] = None,
    ) -> None:
        # Validate BEFORE storing / connecting.
        _assert_safe(url, allow_localhost_http=allow_localhost_http)
        self.url = url
        self.server_name = server_name
        self.timeout = timeout
        self.allow_localhost_http = allow_localhost_http
        self._headers = dict(headers or {})
        self._id = 0
        self._initialized = False

    # -- JSON-RPC plumbing ------------------------------------------------

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def _post(self, payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        POST a JSON-RPC message. Returns the parsed JSON-RPC response dict
        (or None for a notification with no response). Manually resolves
        redirects, re-running the SSRF guard on each hop.
        """
        body = json.dumps(payload).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            # Accept both plain JSON and SSE — Streamable HTTP servers may pick either.
            "Accept": "application/json, text/event-stream",
            "User-Agent": "BioMate-ExternalMCP/1.0",
        }
        headers.update(self._headers)

        current_url = self.url
        for _hop in range(MAX_REDIRECTS + 1):
            _assert_safe(current_url, allow_localhost_http=self.allow_localhost_http)
            req = urllib.request.Request(current_url, data=body, headers=headers, method="POST")
            # A dedicated opener with NO redirect handler → redirects surface as
            # HTTPError(3xx) so we can re-validate the Location ourselves.
            opener = urllib.request.build_opener(_NoRedirect())
            try:
                resp = opener.open(req, timeout=self.timeout)
            except urllib.error.HTTPError as e:
                if e.code in (301, 302, 303, 307, 308):
                    location = e.headers.get("Location")
                    if not location:
                        raise ExternalMCPError(f"redirect {e.code} with no Location header")
                    # Re-validate the redirect target — refuse redirect-to-internal.
                    _assert_safe(location, allow_localhost_http=self.allow_localhost_http)
                    current_url = location
                    continue
                detail = _read_capped(e)
                raise ExternalMCPError(f"HTTP {e.code} from MCP server: {detail[:500]}")
            except urllib.error.URLError as e:
                raise ExternalMCPError(f"transport error contacting MCP server: {e.reason}")

            content_type = (resp.headers.get("Content-Type") or "").lower()
            raw = _read_capped(resp)
            if "text/event-stream" in content_type:
                return _parse_sse_jsonrpc(raw)
            if not raw.strip():
                return None  # notification / empty ack
            try:
                return json.loads(raw)
            except json.JSONDecodeError as e:
                raise ExternalMCPError(f"invalid JSON from MCP server: {e}")

        raise ExternalMCPError(f"too many redirects (>{MAX_REDIRECTS})")

    def _rpc(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        # JSON-RPC envelope generalized from the existing (stdio-hardwired) caller
        # backend/tools/biomate_ai_tools/mcp_client.py:44-53 — same
        # {jsonrpc:"2.0", method, params:{name,arguments}, id} shape, transport
        # swapped from subprocess-stdio to HTTP/SSE POST here.
        payload = {"jsonrpc": "2.0", "id": self._next_id(), "method": method}
        if params is not None:
            payload["params"] = params
        resp = self._post(payload)
        if resp is None:
            raise ExternalMCPError(f"no response to {method}")
        if "error" in resp and resp["error"]:
            err = resp["error"]
            raise ExternalMCPError(
                f"JSON-RPC error from {method}: {err.get('code')} {err.get('message')}"
            )
        return resp.get("result")

    def _notify(self, method: str, params: Optional[Dict[str, Any]] = None) -> None:
        payload: Dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        self._post(payload)

    # -- MCP protocol methods --------------------------------------------

    def initialize(self) -> Dict[str, Any]:
        result = self._rpc(
            "initialize",
            {
                "protocolVersion": self.PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "biomate-external-mcp", "version": "1.0"},
            },
        )
        # Best-effort initialized notification (non-fatal if the server ignores it).
        try:
            self._notify("notifications/initialized")
        except ExternalMCPError:
            pass
        self._initialized = True
        return result or {}

    def list_tools(self) -> List[Dict[str, Any]]:
        """
        tools/list → list of tool dicts. Each tool's `name` is NAMESPACED
        (mcp__<server>__<tool>); the original name is preserved as `_raw_name`
        so call_tool can send the server's own name back.
        """
        if not self._initialized:
            self.initialize()
        result = self._rpc("tools/list") or {}
        tools = result.get("tools", []) if isinstance(result, dict) else []
        out: List[Dict[str, Any]] = []
        for t in tools:
            if not isinstance(t, dict):
                continue
            raw = t.get("name", "")
            entry = dict(t)
            entry["_raw_name"] = raw
            entry["name"] = namespaced_tool_name(self.server_name, raw)
            out.append(entry)
        return out

    def call_tool(self, tool_name: str, arguments: Optional[Dict[str, Any]] = None) -> Any:
        """
        tools/call. Accepts either the raw tool name or the namespaced form
        (mcp__<server>__<tool>); the namespace prefix is stripped before send.
        """
        if not self._initialized:
            self.initialize()
        raw = _strip_namespace(tool_name, self.server_name)
        return self._rpc("tools/call", {"name": raw, "arguments": arguments or {}})

    @staticmethod
    def unwrap_content(result: Any) -> Any:
        """
        Convenience: extract the primary payload from a tools/call result the
        way backend/tools/biomate_ai_tools/mcp_client.py:78-85 does — if the
        result has content[0].text, JSON-decode it (else return the text / raw
        result). Callers may prefer the raw envelope; this is opt-in.
        """
        if isinstance(result, dict):
            content = result.get("content")
            if content and isinstance(content, list) and isinstance(content[0], dict):
                text = content[0].get("text")
                if text is not None:
                    try:
                        return json.loads(text)
                    except (json.JSONDecodeError, TypeError):
                        return {"text": text}
        return result


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Turn 3xx into HTTPError so we re-validate the target ourselves."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D401
        return None


def _read_capped(resp) -> str:
    data = resp.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        raise ExternalMCPError(f"response exceeded size cap ({MAX_RESPONSE_BYTES} bytes)")
    try:
        return data.decode("utf-8", errors="replace")
    except Exception:
        return ""


def _parse_sse_jsonrpc(raw: str) -> Optional[Dict[str, Any]]:
    """
    Parse an SSE stream, returning the FIRST JSON-RPC response object found in a
    `data:` field. MCP Streamable-HTTP sends the response as one or more SSE
    events; we take the first well-formed JSON payload that looks like a
    response (has an `id` and `result`/`error`), else the first parseable JSON.
    """
    fallback: Optional[Dict[str, Any]] = None
    for block in raw.split("\n\n"):
        data_lines = [
            line[len("data:"):].strip()
            for line in block.splitlines()
            if line.startswith("data:")
        ]
        if not data_lines:
            continue
        payload = "\n".join(data_lines).strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            if "id" in obj and ("result" in obj or "error" in obj):
                return obj
            if fallback is None:
                fallback = obj
    return fallback


def _strip_namespace(tool_name: str, server_name: str) -> str:
    prefix = f"mcp__{_sanitize_component(server_name)}__"
    if tool_name.startswith(prefix):
        return tool_name[len(prefix):]
    if tool_name.startswith("mcp__"):
        # Generic mcp__<something>__<tool> — take the last segment as the tool.
        parts = tool_name.split("__")
        if len(parts) >= 3:
            return "__".join(parts[2:])
    return tool_name
