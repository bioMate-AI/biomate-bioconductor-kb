"""Tier-S1 fix verification — per-project pipeline_data endpoint.

The IND honest audit (docs/20260603_IND_MODULE_HONEST_AUDIT.md) flagged that
the 5-step pipeline view rendered identical DEMO_* constants regardless of
which project was selected. This module added a sidecar-file-backed endpoint
so different projects show distinct molecules, ADMET pass counts, PBPK
metrics, lead rankings, and audit findings.

These tests prove the bug is gone:
- demo p-bm0042 / p-bm0038 / p-bm0029 return DIFFERENT lead SMILES
- demo p-bm0042 / p-bm0038 / p-bm0029 return DIFFERENT ADMET pass/total
- unknown project returns scaffold shape (not 404) so the page still renders
- malformed project_id (special chars) is rejected with 400
"""
from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from galaxy.ai.drug_discovery import ind_actions_router


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(ind_actions_router.router)
    return TestClient(app)


def test_pipeline_data_returns_seeded_bm0042(client):
    """Sidecar file for p-bm0042 is returned verbatim (minus _private keys)."""
    resp = client.get("/api/ind-report/projects/p-bm0042/pipeline_data")
    assert resp.status_code == 200
    data = resp.json()
    assert data["lead_smiles"] == "CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1"
    assert data["admet"]["summary"] == {"pass": 8, "total": 12}
    # _schema_version / _note must be stripped
    assert not any(k.startswith("_") for k in data.keys())


def test_different_projects_return_different_data(client):
    """The whole point of the Tier-S1 fix: BM-0042 != BM-0038 != BM-0029."""
    a = client.get("/api/ind-report/projects/p-bm0042/pipeline_data").json()
    b = client.get("/api/ind-report/projects/p-bm0038/pipeline_data").json()
    c = client.get("/api/ind-report/projects/p-bm0029/pipeline_data").json()

    # Distinct lead SMILES — the worst offender in the old hardcoded build.
    assert a["lead_smiles"] != b["lead_smiles"]
    assert b["lead_smiles"] != c["lead_smiles"]
    assert a["lead_smiles"] != c["lead_smiles"]

    # Distinct ADMET pass counts.
    assert (
        a["admet"]["summary"]["pass"]
        != b["admet"]["summary"]["pass"]
        != c["admet"]["summary"]["pass"]
    )

    # Distinct top-ranked lead IDs.
    assert a["leads"]["ranking"][0]["id"] == "BM-0042"
    assert b["leads"]["ranking"][0]["id"] == "BM-0038"
    assert c["leads"]["ranking"][0]["id"] == "BM-0029"

    # Distinct PBPK Cmax-within-2-fold metrics.
    assert (
        a["pbpk"]["metrics"]["cmaxWithin2"]
        != b["pbpk"]["metrics"]["cmaxWithin2"]
        != c["pbpk"]["metrics"]["cmaxWithin2"]
    )

    # BM-0029 must be blocked with at least one CRITICAL audit finding.
    severities = [f["severity"] for f in c["audit"]["findings"]]
    assert "CRITICAL" in severities


def test_pbpk_status_differs(client):
    """BM-0042 + BM-0038 pass PBPK; BM-0029 fails it."""
    assert client.get("/api/ind-report/projects/p-bm0042/pipeline_data").json()["pbpk"]["status"] == "pass"
    assert client.get("/api/ind-report/projects/p-bm0038/pipeline_data").json()["pbpk"]["status"] == "pass"
    assert client.get("/api/ind-report/projects/p-bm0029/pipeline_data").json()["pbpk"]["status"] == "fail"


def test_unknown_project_returns_scaffold_not_404(client):
    """Unknown but well-formed project IDs return an empty-pipeline scaffold."""
    resp = client.get("/api/ind-report/projects/not-a-real-id/pipeline_data")
    assert resp.status_code == 200
    data = resp.json()
    # Scaffold shape — all required top-level keys present
    for key in ("admet", "pbpk", "leads", "doc", "audit"):
        assert key in data
    # Scaffold has zero results, not BM-0042 data
    assert data["admet"]["summary"]["total"] == 0
    assert data["leads"]["ranking"] == []
    assert data["doc"]["sections"] == []
    assert data["audit"]["findings"] == []
    # Lead SMILES must NOT be the BM-0042 hardcoded string
    assert data["lead_smiles"] != "CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1"


def test_invalid_project_id_rejected(client):
    """Special-char project_id rejected with 400 via _PROJECT_ID_RE."""
    resp = client.get("/api/ind-report/projects/bad..id!/pipeline_data")
    assert resp.status_code == 400


def test_scaffold_uses_registry_molecule_when_available(client, tmp_path, monkeypatch):
    """When the project is in projects.json but has no sidecar, the scaffold
    pulls the molecule name from the registry row instead of returning a
    bare ID."""
    # Use the existing registry: p-bm0038 has a sidecar so won't exercise this.
    # Instead, point to a synthetic registry that has an entry without a sidecar.
    fake_registry = tmp_path / "projects.json"
    fake_registry.write_text(
        '{"projects":[{"id":"p-bm9999","molecule":"BM-9999","target":"X","indication":"Y","sponsor":"Z","regions":["FDA"],"status":"draft"}]}'
    )
    fake_pipeline_dir = tmp_path / "pipeline_data"
    fake_pipeline_dir.mkdir()
    monkeypatch.setattr(ind_actions_router, "_PROJECTS_PATH", fake_registry)
    monkeypatch.setattr(ind_actions_router, "_PIPELINE_DATA_DIR", fake_pipeline_dir)

    resp = client.get("/api/ind-report/projects/p-bm9999/pipeline_data")
    assert resp.status_code == 200
    data = resp.json()
    assert data["pbpk"]["lead"]["id"] == "BM-9999"
