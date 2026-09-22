"""
External MCP Connect (Capability B, MVP) — unit tests.

Security core (SSRF blocklist) MUST run standalone with NO Galaxy runtime:
we import `client` directly by file path (no `galaxy.*` package needed), so
`pytest backend/tests/test_external_mcp.py -k ssrf` passes on a bare checkout.

Covers:
  * SSRF blocklist — 127.0.0.1, 169.254.169.254 (cloud metadata), 10.x, ::1,
    private/link-local/loopback/unspecified/ULA all REJECTED; http-in-prod
    REJECTED; a normal public https host ALLOWED.
  * Redirect-to-internal refusal.
  * Tool-name namespacing (mcp__<server>__<tool>) + strip.
  * Registration round-trip through a mock Vault (fake trans), ownership scope.
  * (marked) list/call round-trip against a spawned local echo MCP server over
    HTTP — reference for the plan's subprocess-MCP harness pattern.

Run: PYTHONPATH=. pytest backend/tests/test_external_mcp.py -v
     PYTHONPATH=. pytest backend/tests/test_external_mcp.py -k ssrf   # security core, standalone
"""

from __future__ import annotations

import importlib.util
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Import the modules by file path so the SSRF tests need NO galaxy runtime.
# ---------------------------------------------------------------------------

_MODULE_DIR = (
    Path(__file__).resolve().parents[1]
    / "lib" / "galaxy" / "ai" / "external_mcp"
)


def _load(name: str):
    spec = importlib.util.spec_from_file_location(
        f"_ext_mcp_{name}", _MODULE_DIR / f"{name}.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


client = _load("client")
is_safe_url = client.is_safe_url
namespaced_tool_name = client.namespaced_tool_name
ExternalMCPClient = client.ExternalMCPClient
SSRFBlockedError = client.SSRFBlockedError


# ===========================================================================
# SSRF blocklist — the security core (standalone)
# ===========================================================================

SSRF_BLOCKED_URLS = [
    # loopback
    "https://127.0.0.1/mcp",
    "http://127.0.0.1:8080/mcp",
    "https://127.0.0.5/mcp",
    "https://[::1]/mcp",
    "https://localhost/mcp",
    # cloud metadata (link-local)
    "https://169.254.169.254/latest/meta-data/",
    "http://169.254.169.254/",
    # link-local generic
    "https://169.254.10.10/mcp",
    # private RFC1918
    "https://10.0.0.5/mcp",
    "https://10.255.255.255/mcp",
    "https://172.16.0.1/mcp",
    "https://172.31.255.1/mcp",
    "https://192.168.1.1/mcp",
    # unspecified
    "https://0.0.0.0/mcp",
    # IPv6 ULA (fc00::/7) + IPv4-mapped metadata smuggle
    "https://[fc00::1]/mcp",
    "https://[fd00::1]/mcp",
    "https://[::ffff:169.254.169.254]/mcp",
]


@pytest.mark.parametrize("url", SSRF_BLOCKED_URLS)
def test_ssrf_blocks_internal_targets(url):
    ok, reason = is_safe_url(url, allow_localhost_http=False)
    assert ok is False, f"SSRF guard FAILED to block {url} (reason={reason!r})"
    assert reason  # non-empty explanation


def test_ssrf_blocks_http_scheme_in_prod():
    # http to a public host must be rejected when localhost-dev is off.
    ok, reason = is_safe_url("http://example.com/mcp", allow_localhost_http=False)
    assert ok is False
    assert "http" in reason.lower()


def test_ssrf_blocks_metadata_ipv4_explicitly():
    ok, reason = is_safe_url("https://169.254.169.254/latest/meta-data/", allow_localhost_http=False)
    assert ok is False
    assert "link-local" in reason.lower() or "metadata" in reason.lower()


def test_ssrf_allows_public_https_host():
    # A normal public https host (literal public IP → no DNS needed, deterministic).
    ok, reason = is_safe_url("https://93.184.216.34/mcp", allow_localhost_http=False)
    assert ok is True, f"public https literal IP wrongly blocked: {reason!r}"


def test_ssrf_rejects_non_http_schemes():
    for url in ("ftp://example.com", "file:///etc/passwd", "gopher://x", "stdio://cmd"):
        ok, reason = is_safe_url(url, allow_localhost_http=False)
        assert ok is False, f"{url} should be rejected"


def test_ssrf_localhost_dev_opt_in_allows_loopback_http():
    # Explicit dev opt-in: http+loopback allowed ONLY when the flag is on.
    ok, _ = is_safe_url("http://127.0.0.1:9000/mcp", allow_localhost_http=True)
    assert ok is True
    # But still off by default.
    ok2, _ = is_safe_url("http://127.0.0.1:9000/mcp", allow_localhost_http=False)
    assert ok2 is False


def test_ssrf_localhost_dev_does_not_open_private_ranges():
    # localhost-dev must NOT unblock 10.x / metadata even when the flag is on.
    for url in ("http://10.0.0.5/mcp", "http://169.254.169.254/"):
        ok, _ = is_safe_url(url, allow_localhost_http=True)
        assert ok is False


def test_client_constructor_rejects_ssrf_url():
    with pytest.raises(SSRFBlockedError):
        ExternalMCPClient("https://169.254.169.254/mcp")
    with pytest.raises(SSRFBlockedError):
        ExternalMCPClient("http://10.0.0.1/mcp")


# ===========================================================================
# Tool-name namespacing
# ===========================================================================

def test_namespacing_prefixes_server_and_tool():
    assert namespaced_tool_name("myserver", "search") == "mcp__myserver__search"


def test_namespacing_sanitizes_unsafe_chars():
    name = namespaced_tool_name("my server/v1", "do:thing!")
    assert name.startswith("mcp__")
    # No characters outside [A-Za-z0-9_-] beyond the mcp__ scheme.
    body = name[len("mcp__"):]
    assert all(c.isalnum() or c in ("_", "-") for c in body)


def test_namespacing_prevents_builtin_collision():
    # A user tool literally named "query_database" cannot shadow the built-in.
    assert namespaced_tool_name("evil", "query_database") == "mcp__evil__query_database"


def test_strip_namespace_roundtrip():
    strip = client._strip_namespace
    assert strip("mcp__srv__mytool", "srv") == "mytool"
    assert strip("mytool", "srv") == "mytool"  # already raw
    assert strip("mcp__other__deep__tool", "srv") == "deep__tool"


# ===========================================================================
# Registration round-trip (mock Vault) + ownership
# ===========================================================================

class _FakeVault:
    """In-memory stand-in for UserVaultWrapper."""

    def __init__(self, store):
        self._store = store

    def write_secret(self, path, value):
        self._store[path] = value

    def read_secret(self, path):
        return self._store.get(path)


class _FakeApp:
    def __init__(self):
        self.vault = object()  # UserVaultWrapper is patched, so this is unused


class _FakeUser:
    def __init__(self, uid):
        self.id = uid
        self.preferences = {}


class _FakeSession:
    def commit(self):
        pass


class _FakeTrans:
    def __init__(self, uid, shared_store):
        self.user = _FakeUser(uid)
        self.app = _FakeApp()
        self.sa_session = _FakeSession()
        self._shared_store = shared_store


@pytest.fixture
def registry_module(monkeypatch):
    """Load registry.py with UserVaultWrapper patched to the fake vault."""
    reg = _load("registry")

    # Patch the vault import that registry._vault() performs lazily.
    shared = {}

    class _FakeVaultModule:
        @staticmethod
        def UserVaultWrapper(vault, user):
            # One vault namespace PER USER (keyed by user id) — models per-user isolation.
            return _FakeVault(shared.setdefault(f"user:{user.id}", {}))

    import sys
    sys.modules["galaxy"] = type(sys)("galaxy")
    sys.modules["galaxy.security"] = type(sys)("galaxy.security")
    sys.modules["galaxy.security.vault"] = _FakeVaultModule
    return reg, shared


def _make_trans(uid):
    return _FakeTrans(uid, None)


def test_registration_roundtrip(registry_module):
    reg_mod, _shared = registry_module
    trans = _make_trans(42)
    registry = reg_mod.ExternalMCPRegistry(trans)

    safe = registry.register(
        name="myserver",
        transport="http",
        url="https://93.184.216.34/rpc",
        headers={"Authorization": "Bearer SECRET"},
        scope="account",
    )
    assert "headers" not in safe  # secret masked
    assert safe["has_auth"] is True
    assert safe["name"] == "myserver"
    sid = safe["id"]

    listed = registry.list()
    assert len(listed) == 1
    assert listed[0]["id"] == sid
    assert "headers" not in listed[0]  # never leak secrets in list view

    # get returns masked; _resolve_raw returns the secret for internal use.
    assert registry.get(sid)["has_auth"] is True
    raw = registry._resolve_raw(sid)
    assert raw["headers"]["Authorization"] == "Bearer SECRET"


def test_registration_rejects_stdio_transport(registry_module):
    reg_mod, _ = registry_module
    registry = reg_mod.ExternalMCPRegistry(_make_trans(1))
    with pytest.raises(ValueError):
        registry.register(name="x", transport="stdio", url="https://mcp.example.com/")


def test_registration_rejects_ssrf_url(registry_module):
    reg_mod, _ = registry_module
    registry = reg_mod.ExternalMCPRegistry(_make_trans(1))
    with pytest.raises(ValueError):
        registry.register(name="x", transport="http", url="https://169.254.169.254/")


def test_ownership_cross_user_isolation(registry_module):
    reg_mod, _shared = registry_module
    reg_a = reg_mod.ExternalMCPRegistry(_make_trans(100))
    reg_b = reg_mod.ExternalMCPRegistry(_make_trans(200))

    safe = reg_a.register(name="a-server", transport="http", url="https://93.184.216.34/")
    sid = safe["id"]

    # User B cannot see or resolve user A's server (404-not-403 → None).
    assert reg_b.get(sid) is None
    assert reg_b._resolve_raw(sid) is None
    assert reg_b.list() == []
    with pytest.raises(PermissionError):
        reg_b.client_for(sid)

    # Owner still sees it.
    assert reg_a.get(sid) is not None


def test_delete_removes_server(registry_module):
    reg_mod, _ = registry_module
    registry = reg_mod.ExternalMCPRegistry(_make_trans(7))
    sid = registry.register(name="s", transport="http", url="https://93.184.216.34/")["id"]
    assert registry.delete(sid) is True
    assert registry.get(sid) is None
    assert registry.delete(sid) is False  # idempotent


# ===========================================================================
# list/call round-trip against a spawned local echo MCP server (HTTP)
# ===========================================================================
# Reference for the plan's subprocess/echo-server harness. Uses the
# localhost-dev opt-in so the SSRF guard permits the loopback test target.

class _EchoMCPHandler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"
        req = json.loads(body.decode())
        method = req.get("method")
        rid = req.get("id")
        if method == "initialize":
            result = {"protocolVersion": "2024-11-05",
                      "serverInfo": {"name": "echo", "version": "1"},
                      "capabilities": {"tools": {}}}
        elif method == "tools/list":
            result = {"tools": [{"name": "echo",
                                 "description": "echo back",
                                 "inputSchema": {"type": "object"}}]}
        elif method == "tools/call":
            result = {"content": [{"type": "text",
                                   "text": json.dumps(req["params"]["arguments"])}]}
        elif method and method.startswith("notifications/"):
            self.send_response(202)
            self.end_headers()
            return
        else:
            self._send({"jsonrpc": "2.0", "id": rid,
                        "error": {"code": -32601, "message": "method not found"}})
            return
        self._send({"jsonrpc": "2.0", "id": rid, "result": result})

    def _send(self, obj):
        payload = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


@pytest.fixture
def echo_mcp_server():
    server = HTTPServer(("127.0.0.1", 0), _EchoMCPHandler)
    port = server.server_address[1]
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    yield f"http://127.0.0.1:{port}/mcp"
    server.shutdown()
    server.server_close()


def test_client_list_and_call_roundtrip(echo_mcp_server):
    c = ExternalMCPClient(echo_mcp_server, server_name="echo", allow_localhost_http=True)
    init = c.initialize()
    assert init["serverInfo"]["name"] == "echo"

    tools = c.list_tools()
    assert len(tools) == 1
    assert tools[0]["name"] == "mcp__echo__echo"  # namespaced
    assert tools[0]["_raw_name"] == "echo"

    # call by namespaced name — prefix is stripped before send.
    result = c.call_tool("mcp__echo__echo", {"hello": "world"})
    echoed = json.loads(result["content"][0]["text"])
    assert echoed == {"hello": "world"}

    # unwrap_content mirrors mcp_client.py's content[0].text JSON-decode.
    assert ExternalMCPClient.unwrap_content(result) == {"hello": "world"}
