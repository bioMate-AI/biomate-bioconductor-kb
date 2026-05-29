"""Integration test for the BioMate vLLM HTTP-client path.

Assumes ``infra/vllm/docker-compose.local.yml`` is already up (typically via
``KEEP_UP=1 infra/vllm/smoke-test.sh``). Sets ``VLLM_BASE_URL`` and exercises
:func:`ind_assembly._call_vllm_regulatory_llm` against the live container,
asserting the output looks like real §2.6.1 regulatory prose.

Skipped (not failed) when the endpoint is unreachable so the test is safe to
run in CI environments without a GPU.
"""
from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

import pytest

VLLM_BASE_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000")
ADAPTER_NAME = os.environ.get("REGULATORY_LLM_ADAPTER_NAME", "regulatory_llm_v6")


def _endpoint_alive(url: str, timeout: float = 2.0) -> bool:
    try:
        with urllib.request.urlopen(f"{url}/health", timeout=timeout) as r:
            return 200 <= r.status < 300
    except (urllib.error.URLError, OSError, ValueError):
        return False


pytestmark = pytest.mark.skipif(
    not _endpoint_alive(VLLM_BASE_URL),
    reason=(
        f"vLLM endpoint {VLLM_BASE_URL}/health not reachable; bring up "
        f"infra/vllm/docker-compose.local.yml first (see smoke-test.sh)"
    ),
)


@pytest.fixture(scope="module")
def ind_assembly_module():
    """Import ind_assembly with backend/ on sys.path and VLLM env wired."""
    repo_root = Path(__file__).resolve().parents[2]
    backend_lib = repo_root / "backend" / "lib"
    if str(backend_lib) not in sys.path:
        sys.path.insert(0, str(backend_lib))

    os.environ["VLLM_BASE_URL"] = VLLM_BASE_URL
    os.environ["REGULATORY_LLM_ADAPTER_NAME"] = ADAPTER_NAME

    from galaxy.ai.drug_discovery import ind_assembly  # noqa: WPS433
    return ind_assembly


def test_call_vllm_regulatory_llm_returns_real_prose(ind_assembly_module):
    """The HTTP client path returns non-empty, prose-like §2.6.1 narrative."""
    ind_assembly = ind_assembly_module

    system = (
        "You are a regulatory medical writer drafting an IND §2.6.1 "
        "Pharmacology Written Summary. Output FDA-style prose with inline "
        "citations like [Study-001]. Begin your reply with the literal "
        "prefix '[BioMate-generated draft]'."
    )
    user_prompt = (
        "Draft §2.6.1.1 (Brief Summary) for compound BMX-001, an oral "
        "small-molecule TYK2 inhibitor in development for moderate-to-"
        "severe plaque psoriasis. Cite the pivotal in vitro kinase panel "
        "[Study-IVK-001] and the 28-day rat tox study [Study-TOX-028]. "
        "Two short paragraphs, ~250 words."
    )

    out = ind_assembly._call_vllm_regulatory_llm(
        system=system,
        user_prompt=user_prompt,
        max_new_tokens=512,
        temperature=0.3,
    )

    assert out, "vLLM client returned empty string (auth/model error?)"
    assert "[BioMate-generated draft]" in out, (
        f"missing required prefix in completion; got: {out[:200]!r}"
    )
    assert len(out) > 200, f"completion too short ({len(out)} chars): {out!r}"
    # At least one bracketed citation token survives.
    assert "[Study-" in out or "Study-" in out, (
        f"no Study- citation token found in completion: {out[:400]!r}"
    )
