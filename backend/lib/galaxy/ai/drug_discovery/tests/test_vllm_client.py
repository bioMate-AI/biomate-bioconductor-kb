"""
Unit + integration tests for the vLLM HTTP-client path in
ind_assembly._call_local_regulatory_llm.

Test plan:
  VL-CLIENT-1  No VLLM_BASE_URL → returns "" without making any request
  VL-CLIENT-2  VLLM_BASE_URL unreachable → returns "" gracefully (no crash)
  VL-CLIENT-3  HTTP 200 from vLLM → returns the content string
  VL-CLIENT-4  HTTP 500 from vLLM → returns ""
  VL-CLIENT-5  Adapter name resolution — unentitled org → public adapter
  VL-CLIENT-6  Adapter name resolution — env override wins
  VL-CLIENT-7  Payload includes enable_thinking=False + repetition_penalty
  VL-CLIENT-8  Timeout configurable via VLLM_TIMEOUT_S

Run from frontend/ root:
  PYTHONPATH=backend/lib python -m pytest backend/lib/galaxy/ai/drug_discovery/tests/test_vllm_client.py -v

Or as a script:
  PYTHONPATH=backend/lib python backend/lib/galaxy/ai/drug_discovery/tests/test_vllm_client.py
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch

# Allow running as a script
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[5]))

from galaxy.ai.drug_discovery.ind_assembly import (
    _call_vllm_regulatory_llm,
    _resolve_adapter_name,
)


# ---------------------------------------------------------------------------
# Fake vLLM server — accepts /v1/chat/completions and returns a programmable
# response. Used for VL-CLIENT-3, -4, -7.
# ---------------------------------------------------------------------------

class FakeVllm(BaseHTTPRequestHandler):
    response_status = 200
    response_body = {
        "choices": [{"message": {"role": "assistant", "content": "OK from fake vllm"}}]
    }
    captured_payloads: list[dict] = []

    def log_message(self, *_args, **_kwargs):
        pass  # Silence access logs in test output

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_response(404); self.end_headers(); return
        n = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(n).decode())
        FakeVllm.captured_payloads.append(payload)
        self.send_response(self.response_status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(self.response_body).encode())


def start_fake_vllm() -> tuple[HTTPServer, str]:
    FakeVllm.captured_payloads.clear()
    server = HTTPServer(("127.0.0.1", 0), FakeVllm)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{port}"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_no_base_url_returns_empty():
    """VL-CLIENT-1"""
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("VLLM_BASE_URL", None)
        assert _call_vllm_regulatory_llm("sys", "prompt") == ""


def test_unreachable_returns_empty():
    """VL-CLIENT-2 — graceful failure on connection refused."""
    with patch.dict(os.environ, {"VLLM_BASE_URL": "http://127.0.0.1:1"}):
        result = _call_vllm_regulatory_llm("sys", "prompt")
        assert result == ""


def test_200_returns_content():
    """VL-CLIENT-3"""
    server, url = start_fake_vllm()
    try:
        with patch.dict(os.environ, {"VLLM_BASE_URL": url}):
            result = _call_vllm_regulatory_llm("sys", "prompt")
            assert result == "OK from fake vllm"
    finally:
        server.shutdown()


def test_500_returns_empty():
    """VL-CLIENT-4"""
    FakeVllm.response_status = 500
    server, url = start_fake_vllm()
    try:
        with patch.dict(os.environ, {"VLLM_BASE_URL": url}):
            result = _call_vllm_regulatory_llm("sys", "prompt")
            assert result == ""
    finally:
        server.shutdown()
        FakeVllm.response_status = 200


def test_adapter_resolution_no_org():
    """VL-CLIENT-5a — no org → public adapter."""
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("REGULATORY_LLM_ADAPTER_NAME", None)
        name = _resolve_adapter_name()
        assert name.startswith("regulatory_llm_v"), name
        assert "_" not in name.replace("regulatory_llm_v", "").rstrip("0123456789")  # no org suffix


def test_adapter_resolution_unentitled_org_falls_back():
    """VL-CLIENT-5b — unentitled org_id falls back to public adapter."""
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("REGULATORY_LLM_ADAPTER_NAME", None)
        # 'random-org-not-in-paid-list' is not entitled
        name = _resolve_adapter_name(org_id="random-org-not-in-paid-list")
        # Falls back to public — won't contain the unentitled org id
        assert "random-org-not-in-paid-list" not in name


def test_adapter_resolution_env_override_wins():
    """VL-CLIENT-6 — REGULATORY_LLM_ADAPTER_NAME env wins over resolver."""
    with patch.dict(os.environ, {"REGULATORY_LLM_ADAPTER_NAME": "regulatory_llm_v6_debug"}):
        assert _resolve_adapter_name() == "regulatory_llm_v6_debug"


def test_payload_includes_enable_thinking_false():
    """VL-CLIENT-7 — Qwen3 think-mode disabled, repetition_penalty included."""
    server, url = start_fake_vllm()
    try:
        with patch.dict(os.environ, {"VLLM_BASE_URL": url}):
            _call_vllm_regulatory_llm("system msg", "user prompt", max_new_tokens=300)
        assert len(FakeVllm.captured_payloads) == 1
        payload = FakeVllm.captured_payloads[0]
        assert payload["chat_template_kwargs"] == {"enable_thinking": False}
        assert payload["repetition_penalty"] == 1.1
        assert payload["max_tokens"] == 300
        # /no_think prefix appended to user message
        assert payload["messages"][1]["content"].startswith("/no_think")
    finally:
        server.shutdown()


def test_timeout_env_configurable():
    """VL-CLIENT-8 — VLLM_TIMEOUT_S env caps the HTTP timeout."""
    # Slow server: 3s delay
    class SlowVllm(FakeVllm):
        def do_POST(self):
            time.sleep(3)
            super().do_POST()
    server = HTTPServer(("127.0.0.1", 0), SlowVllm)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with patch.dict(os.environ, {
            "VLLM_BASE_URL": f"http://127.0.0.1:{port}",
            "VLLM_TIMEOUT_S": "1",  # 1s < 3s server delay → timeout
        }):
            t0 = time.monotonic()
            result = _call_vllm_regulatory_llm("sys", "prompt")
            elapsed = time.monotonic() - t0
        assert result == ""
        assert elapsed < 2.5, f"timeout didn't fire, elapsed={elapsed:.1f}s"
    finally:
        server.shutdown()


# ---------------------------------------------------------------------------
# Script runner (when pytest isn't available)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    tests = [
        ("VL-CLIENT-1 no_base_url",     test_no_base_url_returns_empty),
        ("VL-CLIENT-2 unreachable",      test_unreachable_returns_empty),
        ("VL-CLIENT-3 200 returns text", test_200_returns_content),
        ("VL-CLIENT-4 500 returns empty",test_500_returns_empty),
        ("VL-CLIENT-5a no_org",          test_adapter_resolution_no_org),
        ("VL-CLIENT-5b unentitled",      test_adapter_resolution_unentitled_org_falls_back),
        ("VL-CLIENT-6 env_override",     test_adapter_resolution_env_override_wins),
        ("VL-CLIENT-7 payload_shape",    test_payload_includes_enable_thinking_false),
        ("VL-CLIENT-8 timeout",          test_timeout_env_configurable),
    ]
    passed = failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"  ✓ {name}")
            passed += 1
        except AssertionError as e:
            print(f"  ✗ {name}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ✗ {name}: {type(e).__name__}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
