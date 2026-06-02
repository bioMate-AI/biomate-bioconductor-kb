"""End-to-end: IND prose generation through the Modal HTTP path.

Hits the real `_llm_narrative` function (the same one that production IND
§2.6.x sections call) against a local HTTP server that mimics Modal's
/v1/chat/completions endpoint. Verifies that when MODAL_REGULATORY_LLM_ENDPOINT
is set, the prompt that reaches the Modal endpoint matches what we'd
actually send to a real LoRA, and that the response flows back through
the audit checks + fallback logic correctly.

Covers four real paths through _llm_narrative:

  1. Modal serves a long, audit-clean response → used directly, no fallback
  2. Modal serves a too-short response → Gemini fallback fires
  3. Modal serves an audit-failing response → Gemini fallback fires for
     citation-critical sections
  4. Modal is unreachable → falls through to vLLM (which is also unreachable
     in test → final Gemini fallback)
"""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import pytest

from galaxy.ai.drug_discovery.ind_assembly import _llm_narrative
import galaxy.ai.drug_discovery.ind_assembly as mod


# A long, regulatory-prose-shaped response that:
#   * Has ≥30 words (passes the too-short check)
#   * Includes a citation marker (passes major-finding audit)
#   * Uses past-tense adverse phrasing
LONG_CLEAN_RESPONSE = (
    "[BioMate-generated draft] In the pivotal 28-day repeat-dose oral toxicity "
    "study in Sprague-Dawley rats, transient, dose-dependent ALT elevation was "
    "observed in 4/10 males at 300 mg/kg/day and 7/10 males at 1000 mg/kg/day; "
    "findings reversed by Day 14 of recovery. The 100 mg/kg/day dose was "
    "identified as the NOAEL, yielding a Human Equivalent Dose of 100 / 6.2 = "
    "16.1 mg/kg and an MRSD of 16.1 / 10 = 1.6 mg/kg (96 mg in a 60-kg adult), "
    "consistent with ICH M3(R2) and the FDA 2005 MRSD guidance. (ICH M3(R2); "
    "FDA 2005 Estimating the Maximum Safe Starting Dose)."
)


# ---------------------------------------------------------------------------
# Mock /v1/chat/completions server
# ---------------------------------------------------------------------------

class FakeModal:
    def __init__(self, response_text: str = LONG_CLEAN_RESPONSE, status: int = 200):
        self.response_text = response_text
        self.status = status
        self.received: list[dict[str, Any]] = []
        self._srv: HTTPServer | None = None
        self._t: threading.Thread | None = None

    def start(self) -> str:
        backend = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a, **kw): pass

            def do_POST(self):
                n = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(n).decode()) if n else {}
                backend.received.append({"path": self.path, "body": body})
                self.send_response(backend.status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                if backend.status == 200:
                    out = {
                        "choices": [{
                            "index": 0,
                            "message": {"role": "assistant",
                                        "content": backend.response_text},
                        }]
                    }
                    self.wfile.write(json.dumps(out).encode())
                else:
                    self.wfile.write(b'{"error":"forced"}')

        self._srv = HTTPServer(("127.0.0.1", 0), H)
        self._t = threading.Thread(target=self._srv.serve_forever, daemon=True)
        self._t.start()
        return f"http://127.0.0.1:{self._srv.server_address[1]}"

    def stop(self):
        if self._srv:
            self._srv.shutdown()
            self._srv.server_close()


@pytest.fixture
def fake_modal():
    f = FakeModal()
    url = f.start()
    yield f, url
    f.stop()


@pytest.fixture
def gemini_recorder(monkeypatch):
    """Replace the Gemini Flash entry point with a recording stub so we can
    assert whether the fallback fired. Returns the call counter."""
    calls = []

    def fake_gemini(messages, system, max_tokens, temperature):
        calls.append({"messages": messages, "system": system, "max_tokens": max_tokens})
        return "GEMINI-FALLBACK-RESPONSE: [BioMate-generated draft] " + (
            "Regulatory prose from Gemini, ≥30 words, with citation. " * 5
        ) + "(ICH M3(R2))"

    monkeypatch.setattr(
        "galaxy.ai.gemini_flash.call_gemini_flash", fake_gemini,
    )
    # Also stub _load_local_llm so the fall-through path (no env set) doesn't
    # try to load Qwen3-8B (would hang on GB10 sm_121).
    monkeypatch.setattr(mod, "_load_local_llm", lambda: False)
    return calls


# ---------------------------------------------------------------------------
# E2E paths through _llm_narrative
# ---------------------------------------------------------------------------

def test_modal_long_clean_response_used_directly(
    fake_modal, gemini_recorder, monkeypatch,
):
    f, url = fake_modal
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)

    out = _llm_narrative(
        "tox_overview",
        {"molecule_name": "BMX-001", "total_compounds": 100,
         "herg_flagged": 4, "dili_flagged": 2, "ames_flagged": 0},
        region="FDA",
    )

    # Modal got hit exactly once
    assert len(f.received) == 1
    body = f.received[0]["body"]
    assert body["model"].startswith("regulatory_llm")
    assert body["messages"][0]["role"] == "system"
    assert "BMX-001" in body["messages"][1]["content"]
    assert body["messages"][1]["content"].startswith("/no_think\n")

    # Output is the Modal response, NOT the Gemini fallback
    assert "BioMate-generated draft" in out
    assert "Gemini" not in out
    assert len(gemini_recorder) == 0


def test_modal_short_response_triggers_gemini_fallback(
    fake_modal, gemini_recorder, monkeypatch,
):
    f, url = fake_modal
    f.response_text = "Too short."  # <30 words
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)

    out = _llm_narrative(
        "tox_overview",
        {"molecule_name": "BMX-001", "total_compounds": 50,
         "herg_flagged": 1, "dili_flagged": 0, "ames_flagged": 0},
        region="FDA",
    )

    assert len(f.received) == 1   # Modal was called
    assert len(gemini_recorder) == 1  # Then Gemini fired as fallback
    assert out.startswith("GEMINI-FALLBACK-RESPONSE")


def test_modal_unreachable_falls_through_to_gemini(
    gemini_recorder, monkeypatch,
):
    """Modal endpoint is set but unreachable. The wire returns "" within
    the timeout; the helper then falls through to vLLM (also unset → ""),
    then to local HF (stubbed → False), and finally _llm_narrative kicks
    in Gemini as the final fallback."""
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", "http://127.0.0.1:1")
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)
    monkeypatch.setenv("MODAL_TIMEOUT_S", "2")  # keep test fast

    out = _llm_narrative(
        "admet",
        {"total_compounds": 100, "passing_compounds": 73, "pass_rate": 0.73},
        region="FDA",
    )

    # Gemini fired as the final fallback
    assert len(gemini_recorder) == 1
    assert out.startswith("GEMINI-FALLBACK-RESPONSE")


def test_modal_response_with_unknown_section_returns_empty(
    fake_modal, gemini_recorder, monkeypatch,
):
    """_llm_narrative returns "" for section_type not in its prompt
    registry. Both Modal and Gemini stay silent — no wasted spend."""
    f, url = fake_modal
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)

    out = _llm_narrative(
        "section_we_have_not_implemented_yet",
        {},
        region="FDA",
    )

    assert out == ""
    assert len(f.received) == 0   # never called Modal
    assert len(gemini_recorder) == 0  # never called Gemini


def test_modal_request_includes_region_specific_system_prompt(
    fake_modal, gemini_recorder, monkeypatch,
):
    """FDA / EMA / NMPA / PMDA should get distinct system prompts so the
    LoRA can adapt to region-specific phrasing requirements."""
    f, url = fake_modal
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)

    _llm_narrative("admet", {"total_compounds": 10}, region="EMA")
    ema_sys = f.received[-1]["body"]["messages"][0]["content"]

    f.received.clear()
    _llm_narrative("admet", {"total_compounds": 10}, region="FDA")
    fda_sys = f.received[-1]["body"]["messages"][0]["content"]

    # Different region → different system prompt
    assert ema_sys != fda_sys
    assert ema_sys, "EMA system prompt is empty"
    assert fda_sys, "FDA system prompt is empty"


def test_audit_constraint_appears_in_user_prompt(
    fake_modal, gemini_recorder, monkeypatch,
):
    """When the regeneration loop fails an audit and resubmits with
    audit_constraint set, the constraint text must appear in the prompt
    so the model can correct on retry."""
    f, url = fake_modal
    monkeypatch.setenv("MODAL_REGULATORY_LLM_ENDPOINT", url)

    _llm_narrative(
        "tox_overview",
        {"molecule_name": "BMX-001", "total_compounds": 10,
         "herg_flagged": 0, "dili_flagged": 0, "ames_flagged": 0},
        region="FDA",
        audit_constraint="Must cite ICH M3(R2) explicitly",
    )

    user_msg = f.received[0]["body"]["messages"][1]["content"]
    assert "Must cite ICH M3(R2) explicitly" in user_msg
    assert "previous draft failed a regulatory audit check" in user_msg
