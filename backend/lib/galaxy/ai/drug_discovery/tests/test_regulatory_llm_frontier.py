"""Frontier-model regulatory LLM path tests.

Covers the env-routed path that currently serves IND prose in production
(GPT-5 / Sonnet 4.6 / Gemini) until BioMate v6 lands on Modal/vLLM.

Pattern: monkeypatch urllib.request.urlopen for OpenAI/Anthropic/Gemini
endpoints so we exercise the real adapter code (URL, headers, payload
shape, model-specific quirks) without burning paid API calls.
"""
from __future__ import annotations

import io
import json
from unittest.mock import patch

import pytest

import galaxy.ai.drug_discovery.ind_assembly as mod
from galaxy.ai.drug_discovery.ind_assembly import (
    _call_frontier_regulatory_llm,
    _call_local_regulatory_llm,
)


class FakeResp:
    def __init__(self, body):
        self._body = json.dumps(body).encode()
    def read(self):
        return self._body
    def __enter__(self):
        return self
    def __exit__(self, *a, **kw):
        return False


@pytest.fixture
def captured_urlopen(monkeypatch):
    """Capture every urllib.request.urlopen call so tests can assert URL,
    headers, payload — and inject a canned response per call."""
    calls = []

    def fake_urlopen(req, timeout=None):
        body = req.data.decode() if req.data else ""
        calls.append({
            "url": req.full_url,
            "headers": dict(req.headers),
            "method": req.get_method(),
            "body": json.loads(body) if body else {},
            "timeout": timeout,
        })
        return FakeResp(calls[-1].get("__response__", calls[-1].get("response", _default_response_for(req.full_url))))

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    return calls


def _default_response_for(url: str) -> dict:
    if "openai" in url:
        return {"choices": [{"message": {"content": "GPT response"}}]}
    if "anthropic" in url:
        return {"content": [{"type": "text", "text": "Claude response"}]}
    if "googleapis" in url:
        return {"candidates": [{"content": {"parts": [{"text": "Gemini response"}]}}]}
    return {"choices": [{"message": {"content": ""}}]}


# ---------------------------------------------------------------------------
# Model-prefix routing
# ---------------------------------------------------------------------------

def test_gpt5_routes_to_openai_with_completion_tokens(captured_urlopen, monkeypatch):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gpt-5")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")

    out = _call_frontier_regulatory_llm("sys", "user prompt", max_new_tokens=200)
    assert out == "GPT response"
    assert len(captured_urlopen) == 1
    call = captured_urlopen[0]
    assert "openai.com" in call["url"]
    assert call["body"]["model"] == "gpt-5"
    # gpt-5 requires max_completion_tokens, not max_tokens, and rejects temperature
    assert "max_completion_tokens" in call["body"]
    assert "max_tokens" not in call["body"]
    assert "temperature" not in call["body"]
    # Reasoning-token headroom: 6× requested, min 2400
    assert call["body"]["max_completion_tokens"] >= 2400
    # Bearer auth, not anthropic header
    assert call["headers"].get("Authorization") == "Bearer sk-test"


def test_gpt4o_keeps_classic_max_tokens(captured_urlopen, monkeypatch):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gpt-4o")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    _call_frontier_regulatory_llm("sys", "u", max_new_tokens=400)
    body = captured_urlopen[0]["body"]
    assert body["max_tokens"] == 400
    assert body["temperature"] == 0.3
    assert "max_completion_tokens" not in body


def test_claude_sonnet_routes_to_anthropic(captured_urlopen, monkeypatch):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "claude-sonnet-4-6")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-test")
    out = _call_frontier_regulatory_llm("sys", "u")
    assert out == "Claude response"
    call = captured_urlopen[0]
    assert "anthropic.com" in call["url"]
    assert call["body"]["model"] == "claude-sonnet-4-6"
    assert call["body"]["system"] == "sys"
    assert call["body"]["temperature"] == 0.3
    # urllib normalizes custom header keys to title-case with lowercase after dashes
    headers_lc = {k.lower(): v for k, v in call["headers"].items()}
    assert headers_lc.get("x-api-key") == "ant-test"
    assert headers_lc.get("anthropic-version") == "2023-06-01"


def test_claude_opus_4_8_drops_temperature(captured_urlopen, monkeypatch):
    """Anthropic deprecated temperature for opus-4-8 — sending it returns 400."""
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "claude-opus-4-8")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-test")
    _call_frontier_regulatory_llm("sys", "u")
    body = captured_urlopen[0]["body"]
    assert "temperature" not in body


def test_gemini_routes_to_googleapis_with_key_param(captured_urlopen, monkeypatch):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gemini-3.1-pro-preview")
    monkeypatch.setenv("GEMINI_API_KEY", "gkey")
    out = _call_frontier_regulatory_llm("sys", "u")
    assert out == "Gemini response"
    call = captured_urlopen[0]
    assert "generativelanguage.googleapis.com" in call["url"]
    assert "key=gkey" in call["url"]
    assert call["body"]["system_instruction"]["parts"][0]["text"] == "sys"
    assert call["body"]["contents"][0]["parts"][0]["text"] == "u"


def test_unknown_model_prefix_returns_empty_and_does_not_call_apis(
    captured_urlopen, monkeypatch,
):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "llama-3-70b")
    out = _call_frontier_regulatory_llm("sys", "u")
    assert out == ""
    assert len(captured_urlopen) == 0


def test_unset_env_returns_empty(captured_urlopen, monkeypatch):
    monkeypatch.delenv("REGULATORY_LLM_FRONTIER_MODEL", raising=False)
    assert _call_frontier_regulatory_llm("s", "u") == ""
    assert len(captured_urlopen) == 0


def test_missing_api_key_returns_empty(captured_urlopen, monkeypatch):
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gpt-5")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    assert _call_frontier_regulatory_llm("s", "u") == ""


# ---------------------------------------------------------------------------
# Backend-selection priority: frontier > modal > vllm > local
# ---------------------------------------------------------------------------

def test_frontier_preferred_over_modal_and_vllm(captured_urlopen, monkeypatch):
    """All three envs set — frontier should win, modal/vllm never called."""
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gpt-5")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", "http://modal.example")
    monkeypatch.setenv("VLLM_BASE_URL", "http://vllm.example")

    out = _call_local_regulatory_llm(
        section_type="tox", system="s", user_prompt="u",
        max_new_tokens=200, temperature=0.3,
    )
    assert out == "GPT response"
    # Only one call — to OpenAI
    assert len(captured_urlopen) == 1
    assert "openai.com" in captured_urlopen[0]["url"]


def test_frontier_failure_falls_through_to_modal(monkeypatch):
    """If the frontier API errors, the helper falls through to Modal."""
    monkeypatch.setenv("REGULATORY_LLM_FRONTIER_MODEL", "gpt-5")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", "http://modal.example")

    def fake_urlopen(req, timeout=None):
        if "openai.com" in req.full_url:
            raise OSError("simulated 503")
        # Modal returns success
        return FakeResp({"choices": [{"message": {"content": "FROM-MODAL"}}]})

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    out = _call_local_regulatory_llm(
        section_type="tox", system="s", user_prompt="u",
        max_new_tokens=200, temperature=0.3,
    )
    assert out == "FROM-MODAL"


def test_no_envs_returns_empty(monkeypatch):
    """No backend env set, local HF stubbed → returns "" without crash."""
    for k in ("REGULATORY_LLM_FRONTIER_MODEL", "MODAL_REGULATORY_LLM_ENDPOINT", "VLLM_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setattr(mod, "_load_local_llm", lambda: False)
    assert _call_local_regulatory_llm(
        section_type="tox", system="s", user_prompt="u",
        max_new_tokens=200, temperature=0.3,
    ) == ""
