"""HTTP contract of POST /api/drug-discovery/{campaign_id}/lims/poll.

Benchling itself is a recorded-payload fake (see test_benchling_connector);
no live tenant is contacted.
"""
import pytest

pytest.importorskip("fastapi")
pytest.importorskip("rdkit")

from fastapi import FastAPI
from fastapi.testclient import TestClient

from galaxy.ai.drug_discovery import api_router
from galaxy.ai.drug_discovery.tests.test_benchling_connector import (
    MAPPING, FakeResponse, FakeSession, TENANT, _molecules, _result,
)
from integrations.benchling_connector import BenchlingConnector

URL = "/api/drug-discovery/camp/lims/poll"


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(api_router, "_CAMPAIGN_DB_DIR", str(tmp_path / "campaigns"))
    monkeypatch.setenv("BIOMATE_COMPLIANCE_DB_DIR", str(tmp_path / "audit"))
    state = {"results": [_result("res_1"), _result("res_2", mol="mol_B", value=10, qualifier=">",
                                                   unit="uM", modified="2026-10-02T00:00:00Z")],
             "archived": [], "sessions": []}

    def from_env(cls, environ=None, **kw):
        session = FakeSession({
            ("GET", "/api/v2/assay-results"): [lambda p: FakeResponse(200, {
                "assayResults": state["results"] if p["archiveReason"] == "NOT_ARCHIVED"
                else state["archived"]})],
            ("GET", "/api/v2/molecules"): [_molecules],
        })
        state["sessions"].append(session)
        return BenchlingConnector(tenant_url=TENANT, api_key="sk_server_side", session=session,
                                  sleep=lambda s: None)

    monkeypatch.setattr(BenchlingConnector, "from_env", classmethod(from_env))
    app = FastAPI()
    app.include_router(api_router.router)
    return TestClient(app), state


def test_poll_ingests_then_is_incremental_and_idempotent(env):
    client, state = env
    first = client.post(URL, json={"mapping": MAPPING})
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["records_ingested"] == 2 and body["errors"] == [] and body["auth"] == "api_key"
    assert body["watermark"] == {"previous": None, "next": "2026-10-02T00:00:00Z"}
    censored = next(r for r in body["updated_ranks"] if r["compound_id"] == "ACME-0002")
    assert censored["censored_objectives"] == ["potency"]

    # Second poll reuses the stored mapping and watermark; nothing changes.
    second = client.post(URL, json={"schema_id": "assaysch_IC50"})
    assert second.status_code == 200, second.text
    assert second.json()["records_unchanged"] == 2 and second.json()["status"] == "no_new_data"
    params = [c["params"] for c in state["sessions"][-1].calls if c["path"] == "/api/v2/assay-results"]
    assert params[0]["modifiedAt.gte"] == "2026-10-02T00:00:00Z"

    # A result archived in Benchling is withdrawn from the campaign.
    state["results"] = [state["results"][0]]
    state["archived"] = [_result("res_2", archived={"reason": "Made in error"})]
    third = client.post(URL, json={"schema_id": "assaysch_IC50"}).json()
    assert third["records_retracted"] == 1
    assert [r["compound_id"] for r in third["updated_ranks"]] == ["ACME-0001"]


def test_secret_in_query_string_rejected(env):
    client, state = env
    resp = client.post(URL + "?benchling_api_key=sk_leak", json={"mapping": MAPPING})
    assert resp.status_code == 400 and "must not be sent in the URL" in resp.json()["detail"]
    assert state["sessions"] == []


def test_get_no_longer_accepted(env):
    client, _ = env
    assert client.get(URL + "?assay_schema_id=assaysch_IC50").status_code == 405


def test_invalid_or_missing_mapping_is_400(env):
    client, _ = env
    assert client.post(URL, json={"mapping": {**MAPPING, "value_field": ""}}).status_code == 400
    assert client.post(URL, json={"schema_id": "assaysch_unknown"}).status_code == 400
    assert client.post(URL, json={}).status_code == 400


def test_missing_server_configuration_is_503(tmp_path, monkeypatch):
    monkeypatch.setattr(api_router, "_CAMPAIGN_DB_DIR", str(tmp_path / "campaigns"))
    monkeypatch.setenv("BIOMATE_COMPLIANCE_DB_DIR", str(tmp_path / "audit"))
    for var in ("BENCHLING_TENANT_URL", "BENCHLING_API_URL", "BENCHLING_API_KEY",
                "BENCHLING_CLIENT_ID", "BENCHLING_CLIENT_SECRET"):
        monkeypatch.delenv(var, raising=False)
    app = FastAPI()
    app.include_router(api_router.router)
    resp = TestClient(app).post(URL, json={"mapping": MAPPING})
    assert resp.status_code == 503 and "not configured" in resp.json()["detail"]
