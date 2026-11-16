"""Guard (Bug 4): the MCP connector's run_workflow must populate the caller's
values into required_params[].value — the key the server-side required-input gate
validates — not only into the parameters{} map.

Before the fix, run_workflow sent a minimal envelope with values only under
parameters{}. The server validated required inputs against
workflowDefinition.required_params[].value, found them empty, and rejected the
launch with `missing_required_params` even though the value was supplied.

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

    # Spec declares patient_clinical_data as a param with no value / null default.
    def fake_spec(workflow_id):
        return {
            "nextflow_path": workflow_id,
            "workflow_type": "nextflow",
            "workflow_ga": {"name": "cox", "parameters": {}},
            "required_params": [
                {"name": "patient_clinical_data", "label": "Clinical", "default": None},
            ],
            "optional_params": [
                {"name": "ties", "default": "efron"},
            ],
        }
    monkeypatch.setattr(client, "get_workflow_spec", fake_spec)

    captured = {}

    def fake_post(url, json=None, timeout=None):
        captured["url"] = url
        captured["payload"] = json
        return _FakeResp({"run_id": "r1", "status": "configuring"})
    monkeypatch.setattr(client.session, "post", fake_post)

    client.run_workflow(
        "bioconductor/survival/cox.nf",
        {"patient_clinical_data": "s3://bucket/clin.csv"},
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


def test_run_workflow_falls_back_when_spec_unavailable(monkeypatch):
    try:
        m = _load_client()
    except Exception as e:  # pragma: no cover
        pytest.skip(f"connector not importable: {type(e).__name__}: {e}")

    client = m.BioMateClient("https://dev-public.biomate.ai", "bm_live_test")
    monkeypatch.setattr(client, "get_workflow_spec", lambda wid: {"error": "boom"})

    captured = {}

    def fake_post(url, json=None, timeout=None):
        captured["payload"] = json
        return _FakeResp({"run_id": "r2", "status": "configuring"})
    monkeypatch.setattr(client.session, "post", fake_post)

    client.run_workflow("x/y.nf", {"a": "1"})
    wf = captured["payload"]["workflowDefinition"]
    # Minimal but valid envelope: parameters{} + top-level params still carry the value.
    assert wf["parameters"]["a"] == "1"
    assert captured["payload"]["params"]["a"] == "1"
    assert wf["nextflow_path"] == "x/y.nf"
