"""HTTP-level integration test for the (why?) rationale endpoints.

Hits both endpoints through FastAPI's TestClient — verifies the
router wiring, not just the function body. Covers:
  - GET /api/rationale/:rationale_id  (Phase 2 design-faithful)
  - GET /api/workflows/:name/phases/:phase_id/rationale  (legacy)
  - Missing rows → {}
"""
from __future__ import annotations

import os
import sqlite3
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "backend", "lib"))


def _db_has_table(table: str) -> bool:
    db = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")
    with sqlite3.connect(db) as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            (table,),
        ).fetchone()
    return bool(row)


pytestmark = pytest.mark.skipif(
    not (_db_has_table("rationale_registry")
         and _db_has_table("workflow_phase_rationale")),
    reason="rationale tables not populated; run populate scripts first",
)


@pytest.fixture(scope="module")
def client():
    """FastAPI TestClient over just the nextflow_executor router.

    Avoids booting the full Galaxy app — mounts the rationale endpoints
    onto a minimal FastAPI app and lets the same dispatcher run.
    """
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from galaxy.webapps.galaxy.api import nextflow_executor

    app = FastAPI()
    app.include_router(nextflow_executor.router)
    return TestClient(app)


def test_new_endpoint_returns_bioc_rationale(client):
    r = client.get("/api/rationale/bulk_rnaseq_consensus_de_bioc:B")
    assert r.status_code == 200
    body = r.json()
    assert body["rationale_id"] == "bulk_rnaseq_consensus_de_bioc:B"
    assert "DESeqDataSet" in body["rationale_text"]
    assert body["citation"]["doi"] == "10.1186/s13059-014-0550-8"
    assert body["qc_gate_name"] == "deseq2_negative_binomial_fit"


def test_new_endpoint_methylation_dmrcate(client):
    r = client.get("/api/rationale/methylation_450k_array_analysis:D")
    assert r.status_code == 200
    body = r.json()
    assert "bumphunter" in body["rationale_text"] or "DMR" in body["rationale_text"]
    assert body["citation"]["doi"] == "10.1186/1756-8935-8-6"


def test_new_endpoint_unknown_returns_empty(client):
    r = client.get("/api/rationale/does_not_exist:Z")
    assert r.status_code == 200
    assert r.json() == {}


def test_legacy_endpoint_still_returns_bioc(client):
    r = client.get(
        "/api/workflows/bulk_rnaseq_consensus_de_bioc/phases/B/rationale"
    )
    assert r.status_code == 200
    body = r.json()
    assert "DESeqDataSet" in body["rationale_text"]
    assert body["citation"]["doi"] == "10.1186/s13059-014-0550-8"


def test_legacy_endpoint_unknown_returns_empty(client):
    r = client.get(
        "/api/workflows/does_not_exist/phases/Z/rationale"
    )
    assert r.status_code == 200
    assert r.json() == {}
