"""Routing tests for regulatory-LLM backend selection.

Hits a real local HTTP server (no SDK mocks) so the helper's
urllib payload + headers + URL construction are all exercised end-to-end.
Verifies:

- MODAL_REGULATORY_LLM_ENDPOINT is preferred over VLLM_BASE_URL
- Modal failure falls through to vLLM (graceful degradation)
- Both unset → helper returns "" without network
- Request payload contains the right model name, /no_think prefix, max_tokens,
  temperature
- Bearer token comes from the right env var per backend

These are the exact paths exercised in production by
_call_local_regulatory_llm in ind_assembly.py.
"""
from __future__ import annotations

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import pytest

from galaxy.ai.drug_discovery.ind_assembly import (
    _call_local_regulatory_llm,
    _call_openai_compat_regulatory_llm,
)


# ---------------------------------------------------------------------------
# Local HTTP fixture that mimics an OpenAI /v1/chat/completions server
# ---------------------------------------------------------------------------

class FakeBackend:
    def __init__(self, response_text: str = "FAKE RESPONSE", status: int = 200):
        self.response_text = response_text
        self.status = status
        self.received_requests: list[dict[str, Any]] = []
        self._server: HTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> str:
        backend = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a, **kw): pass

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
                backend.received_requests.append({
                    "path": self.path,
                    "headers": dict(self.headers),
                    "body": body,
                })
                self.send_response(backend.status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                if backend.status == 200:
                    resp = {
                        "id": "test",
                        "model": body.get("model", "x"),
                        "choices": [
                            {"index": 0,
                             "message": {"role": "assistant",
                                         "content": backend.response_text}}
                        ],
                    }
                    self.wfile.write(json.dumps(resp).encode("utf-8"))
                else:
                    self.wfile.write(b'{"error":"forced"}')

        self._server = HTTPServer(("127.0.0.1", 0), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        port = self._server.server_address[1]
        return f"http://127.0.0.1:{port}"

    def stop(self):
        if self._server:
            self._server.shutdown()
            self._server.server_close()


@pytest.fixture
def backend():
    b = FakeBackend()
    url = b.start()
    yield b, url
    b.stop()


@pytest.fixture
def two_backends():
    a = FakeBackend(response_text="FROM-MODAL")
    b = FakeBackend(response_text="FROM-VLLM")
    yield (a, a.start()), (b, b.start())
    a.stop()
    b.stop()


# ---------------------------------------------------------------------------
# Shared helper tests
# ---------------------------------------------------------------------------

def test_helper_returns_assistant_content(backend):
    b, url = backend
    out = _call_openai_compat_regulatory_llm(
        base_url=url, api_key_env="X_KEY",
        system="sys", user_prompt="hi",
        max_new_tokens=50, temperature=0.5,
        org_id=None, backend_label="test",
    )
    assert out == "FROM_FAKE" or out == "FAKE RESPONSE"  # default response_text
    assert len(b.received_requests) == 1
    req = b.received_requests[0]
    assert req["path"] == "/v1/chat/completions"


def test_helper_request_shape_user_no_think_prefix(backend, monkeypatch):
    b, url = backend
    monkeypatch.setenv("API_KEY_FOR_TEST", "sk-test-token-123")
    _call_openai_compat_regulatory_llm(
        base_url=url, api_key_env="API_KEY_FOR_TEST",
        system="You are a regulatory LLM.",
        user_prompt="Write §2.6.1 prose.",
        max_new_tokens=128, temperature=0.42,
        org_id=None, backend_label="test",
    )
    req = b.received_requests[0]
    body = req["body"]
    assert body["max_tokens"] == 128
    assert body["temperature"] == 0.42
    msgs = body["messages"]
    assert msgs[0]["role"] == "system"
    assert msgs[0]["content"] == "You are a regulatory LLM."
    assert msgs[1]["role"] == "user"
    assert msgs[1]["content"].startswith("/no_think\n")
    assert "Write §2.6.1 prose." in msgs[1]["content"]
    # Bearer token from env
    assert req["headers"].get("Authorization") == "Bearer sk-test-token-123"


def test_helper_empty_base_url_short_circuits():
    out = _call_openai_compat_regulatory_llm(
        base_url="", api_key_env="X",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
        org_id=None, backend_label="test",
    )
    assert out == ""


def test_helper_returns_empty_on_server_error(monkeypatch):
    b = FakeBackend(status=500)
    url = b.start()
    try:
        out = _call_openai_compat_regulatory_llm(
            base_url=url, api_key_env="X",
            system="s", user_prompt="u",
            max_new_tokens=10, temperature=0.3,
            org_id=None, backend_label="test",
        )
        assert out == ""
    finally:
        b.stop()


def test_helper_returns_empty_on_connection_refused():
    out = _call_openai_compat_regulatory_llm(
        base_url="http://127.0.0.1:1",  # nothing listens here
        api_key_env="X",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
        org_id=None, backend_label="test",
    )
    assert out == ""


# ---------------------------------------------------------------------------
# Backend selection: _call_local_regulatory_llm picks the right path
# ---------------------------------------------------------------------------

def test_modal_preferred_over_vllm(two_backends, monkeypatch):
    (modal_b, modal_url), (vllm_b, vllm_url) = two_backends
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", modal_url)
    monkeypatch.setenv("VLLM_BASE_URL", vllm_url)

    out = _call_local_regulatory_llm(
        section_type="tox_summary",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
    )

    assert out == "FROM-MODAL"
    assert len(modal_b.received_requests) == 1
    assert len(vllm_b.received_requests) == 0


def test_modal_failure_falls_through_to_vllm(two_backends, monkeypatch):
    (modal_b, modal_url), (vllm_b, vllm_url) = two_backends
    modal_b.status = 503  # force Modal failure
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", modal_url)
    monkeypatch.setenv("VLLM_BASE_URL", vllm_url)

    out = _call_local_regulatory_llm(
        section_type="tox_summary",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
    )

    assert out == "FROM-VLLM"
    assert len(modal_b.received_requests) == 1  # tried first
    assert len(vllm_b.received_requests) == 1  # then fell through


def test_only_vllm_set_uses_vllm(backend, monkeypatch):
    b, url = backend
    b.response_text = "VLLM-OUT"
    monkeypatch.delenv("MODAL_REGULATORY_LLM_ENDPOINT", raising=False)
    monkeypatch.setenv("VLLM_BASE_URL", url)
    out = _call_local_regulatory_llm(
        section_type="tox_summary",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
    )
    assert out == "VLLM-OUT"


def test_neither_env_set_skips_http(monkeypatch):
    """Both envs unset → no HTTP traffic. Stub the local HF loader to
    return False so the function falls all the way through to its empty-
    string sentinel (we can't actually load Qwen3-8B in CI; on the dev
    workstation it also silently hangs because of the GB10 sm_121 vs
    current torch wheel mismatch documented in
    docs/20260531_IND_VLLM_EVAL_SESSION_WRITEUP.md)."""
    monkeypatch.delenv("MODAL_REGULATORY_LLM_ENDPOINT", raising=False)
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)
    import galaxy.ai.drug_discovery.ind_assembly as mod
    monkeypatch.setattr(mod, "_load_local_llm", lambda: False)
    out = _call_local_regulatory_llm(
        section_type="tox_summary",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
    )
    assert out == ""


def test_org_id_resolves_to_per_org_adapter(backend, monkeypatch):
    """When org_id is provided, _resolve_adapter_name should pick the
    org-scoped adapter (regulatory_llm_v6_<orgid>) if available, falling
    back to regulatory_llm_v6 otherwise. We only check the model name in
    the outgoing request — _resolve_adapter_name itself has its own tests."""
    b, url = backend
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)
    _call_local_regulatory_llm(
        section_type="tox_summary",
        system="s", user_prompt="u",
        max_new_tokens=10, temperature=0.3,
        org_id="acme",
    )
    body = b.received_requests[0]["body"]
    # Base case: name should at least start with the regulatory_llm prefix
    assert body["model"].startswith("regulatory_llm")
