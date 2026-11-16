"""Guard (Bug 4): the MCP connector's run_workflow must populate the caller's
values into required_params[].value — the key the server-side required-input gate
validates — not only into the parameters{} map.

Before the fix, run_workflow sent a minimal envelope with values only under
parameters{}. The server validated required inputs against
workflowDefinition.required_params[].value, found them empty, and rejected the
launch with `missing_required_params` even though the value was supplied.

NOTE: after the merge onto mainline, run_workflow resolves the workflow via
POST /api/workflows/search (returns `workflow_ga`) rather than get_workflow_spec,
then fills required_params[].value on the resolved workflow_ga. These tests
exercise that merged (search-based + required_params fill) flow.

Skips cleanly if the connector module can't be imported in the sandbox.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]  # /Users/kky/biomate


def _load_client():
    sys.path.insert(0, str(REPO_ROOT))
    import backend.lib.mcp.biomate_mcp_server as m  # noqa: E402
    return m


class _FakeResp:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


def test_run_workflow_fills_required_params_value(monkeypatch):
    try:
        m = _load_client()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"connector not importable: {type(e).__name__}: {e}")

    client = m.BioMateClient("https://dev-public.biomate.ai", "bm_live_test")

    # The search resolver returns a workflow_ga that declares
    # patient_clinical_data as a required param with no value / null default.
    search_resp = {
        "workflow_ga": {
            "name": "cox",
            "nextflow_path": "bioconductor/survival/cox.nf",
            "workflow_type": "nextflow",
            "parameters": {},
            "required_params": [
                {"name": "patient_clinical_data", "label": "Clinical", "default": None},
            ],
            "optional_params": [
                {"name": "ties", "default": "efron"},
            ],
        }
    }

    captured = {}

    def fake_post(url, json=None, timeout=None):
        if url.endswith("/api/workflows/search"):
            return _FakeResp(search_resp)
        captured["url"] = url
        captured["payload"] = json
        return _FakeResp({"run_id": "r1", "status": "configuring"})
    monkeypatch.setattr(client.session, "post", fake_post)

    client.run_workflow(
        "bioconductor/survival/cox.nf",
        {"patient_clinical_data": "s3://bucket/clin.csv"},
    )

    assert captured["url"].endswith("/api/workflows/execute"), (
        "run_workflow must POST the resolved envelope to /api/workflows/execute"
    )
    wf = captured["payload"]["workflowDefinition"]
    req = {p["name"]: p for p in wf["required_params"]}
    assert req["patient_clinical_data"]["value"] == "s3://bucket/clin.csv", (
        "required_params[].value must be filled from the caller's params — "
        "otherwise the server-side gate reports missing_required_params"
    )
    # value also present in the parameters{} map and the top-level params map.
    assert wf["parameters"]["patient_clinical_data"] == "s3://bucket/clin.csv"
    assert captured["payload"]["params"]["patient_clinical_data"] == "s3://bucket/clin.csv"


def test_run_workflow_carries_params_when_no_required_list(monkeypatch):
    """A workflow_ga without a required_params list must still yield a valid
    envelope — the fill loop is a no-op but parameters{} + top-level params still
    carry the caller's values."""
    try:
        m = _load_client()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"connector not importable: {type(e).__name__}: {e}")

    client = m.BioMateClient("https://dev-public.biomate.ai", "bm_live_test")

    search_resp = {
        "workflow_ga": {
            "name": "y",
            "nextflow_path": "x/y.nf",
            "parameters": {},
        }
    }

    captured = {}

    def fake_post(url, json=None, timeout=None):
        if url.endswith("/api/workflows/search"):
            return _FakeResp(search_resp)
        captured["payload"] = json
        return _FakeResp({"run_id": "r2", "status": "configuring"})
    monkeypatch.setattr(client.session, "post", fake_post)

    client.run_workflow("x/y.nf", {"a": "1"})
    wf = captured["payload"]["workflowDefinition"]
    # Minimal but valid envelope: parameters{} + top-level params still carry the value.
    assert wf["parameters"]["a"] == "1"
    assert captured["payload"]["params"]["a"] == "1"
    assert wf["nextflow_path"] == "x/y.nf"


def test_run_workflow_errors_when_search_fails(monkeypatch):
    """If resolution via /api/workflows/search fails, run_workflow returns a
    clear error and never posts to /api/workflows/execute (mainline behavior)."""
    try:
        m = _load_client()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"connector not importable: {type(e).__name__}: {e}")

    client = m.BioMateClient("https://dev-public.biomate.ai", "bm_live_test")

    def fake_post(url, json=None, timeout=None):
        if url.endswith("/api/workflows/search"):
            raise RuntimeError("boom")
        pytest.fail("execute must not be called when search resolution fails")
    monkeypatch.setattr(client.session, "post", fake_post)

    out = client.run_workflow("x/y.nf", {"a": "1"})
    assert isinstance(out, dict) and "error" in out
