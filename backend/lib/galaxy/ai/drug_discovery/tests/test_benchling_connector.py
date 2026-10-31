"""Benchling REST connector: auth, tenant, pagination, retries, explicit
mapping, molecule resolution and the shared ingestion path.

The external Benchling HTTP API is replaced by a recorded-payload fake
session (payload shapes follow docs.benchling.com, checked 2026-10-30). This
is NOT verification against a live Benchling tenant.
"""
from __future__ import annotations

import base64
from urllib.parse import parse_qs

import pytest

from integrations.benchling_connector import (
    BenchlingAPIError, BenchlingConfigError, BenchlingConnector, normalize_tenant_url,
)
from galaxy.ai.drug_discovery.benchling_connector import (
    BenchlingAssayPoller, BenchlingMappingError, BenchlingSchemaMapping, load_sync_state,
    save_sync_state,
)

TENANT = "https://acme.benchling.com"


class FakeResponse:
    def __init__(self, status=200, body=None, headers=None):
        self.status_code = status
        self._body = body if body is not None else {}
        self.headers = headers or {}
        self.content = b"x"
        self.text = str(self._body)

    def json(self):
        return self._body


class FakeSession:
    """Routes (method, path) to queued responses and records every request."""

    def __init__(self, routes):
        self.routes = {k: list(v) for k, v in routes.items()}
        self.calls = []

    def request(self, method, url, timeout=None, params=None, json=None, data=None, headers=None):
        path = url.split(".benchling.com", 1)[1]
        self.calls.append({"method": method, "path": path, "params": dict(params or {}),
                           "data": data, "headers": dict(headers or {})})
        queue = self.routes.get((method, path))
        if not queue:
            raise AssertionError(f"unexpected request {method} {path} {params}")
        handler = queue[0] if len(queue) == 1 else queue.pop(0)
        return handler(params or {}) if callable(handler) else handler


def _client(routes, **kw):
    session = FakeSession(routes)
    sleeps = []
    kw.setdefault("api_key", "sk_test")
    client = BenchlingConnector(tenant_url=TENANT, session=session, sleep=sleeps.append, **kw)
    return client, session, sleeps


# ── Recorded-shape payloads ─────────────────────────────────────────────────

def _result(rid, mol="mol_A", value=12.5, qualifier="=", reviewed=True, modified="2026-10-01T10:00:00Z",
            unit="nM", validation=None, archived=None):
    return {
        "id": rid, "schema": {"id": "assaysch_IC50", "name": "Kinase IC50"},
        "entryId": "etr_123", "projectId": "src_1", "isReviewed": reviewed,
        "createdAt": "2026-09-30T08:00:00Z", "modifiedAt": modified,
        "creator": {"id": "ent_user", "handle": "chemist", "name": "Chem Ist"},
        "archiveRecord": archived, "validationStatus": validation,
        "fields": {
            "compound": {"type": "molecule_link", "value": mol, "displayValue": "ACME-0001",
                         "isMulti": False, "textValue": "ACME-0001"},
            "ic50": {"type": "float", "value": value, "displayValue": str(value), "isMulti": False},
            "ic50_qualifier": {"type": "dropdown", "value": "sfso_q1", "textValue": qualifier,
                               "displayValue": qualifier, "isMulti": False},
            "ic50_unit": {"type": "dropdown", "value": "sfso_u1", "textValue": unit,
                          "displayValue": unit, "isMulti": False},
            "hill_slope": {"type": "float", "value": 1.1, "isMulti": False},
            "test_conc": {"type": "float", "value": 30.0, "isMulti": False},
            "replicate": {"type": "integer", "value": 2, "isMulti": False},
            "run": {"type": "assay_run_link", "value": "asrun_9", "isMulti": False},
            "assay_date": {"type": "date", "value": "2026-09-29", "isMulti": False},
        },
    }


MOLECULES = {
    "mol_A": {"id": "mol_A", "name": "ACME-0001", "entityRegistryId": "ACME-0001",
              "canonicalizedSmiles": "CCN", "originalSmiles": "CCN.Cl"},
    "mol_B": {"id": "mol_B", "name": "ACME-0002", "entityRegistryId": "ACME-0002",
              "canonicalizedSmiles": "CCO", "originalSmiles": "OCC"},
    "mol_U": {"id": "mol_U", "name": "unreg", "entityRegistryId": None,
              "canonicalizedSmiles": "CCC", "originalSmiles": "CCC"},
}


def _molecules(params):
    ids = params["ids"].split(",")
    return FakeResponse(200, {"molecules": [MOLECULES[i] for i in ids if i in MOLECULES]})


MAPPING = dict(schema_id="assaysch_IC50", compound_field="compound", compound_entity_type="molecule",
               value_field="ic50", assay_type="IC50", unit_field="ic50_unit",
               operator_field="ic50_qualifier", assay_date_field="assay_date",
               replicate_field="replicate", assay_run_field="run")


# ── Tenant + auth ───────────────────────────────────────────────────────────

@pytest.mark.parametrize("given, expected", [
    ("acme", TENANT), ("acme.benchling.com", TENANT), ("https://acme.benchling.com/api/v2", TENANT),
])
def test_tenant_url_normalised(given, expected):
    assert normalize_tenant_url(given) == expected


@pytest.mark.parametrize("bad", ["", "https://api.benchling.com", "https://benchling.com",
                                 "http://acme.benchling.com", "https://evil.example.com",
                                 "https://user:pw@acme.benchling.com"])
def test_tenant_url_required_and_checked(bad):
    with pytest.raises(BenchlingConfigError):
        normalize_tenant_url(bad)


def test_no_credentials_raises_instead_of_mock_mode():
    with pytest.raises(BenchlingConfigError, match="credentials required"):
        BenchlingConnector(tenant_url=TENANT)
    with pytest.raises(BenchlingConfigError, match="tenant URL is required"):
        BenchlingConnector.from_env({"BENCHLING_API_KEY": "sk_x"})


def test_api_key_uses_basic_auth_never_bearer():
    client, session, _ = _client({("GET", "/api/v2/projects"): [FakeResponse(200, {"projects": []})]},
                                 api_key="sk_secret")
    client.list_projects()
    auth = session.calls[0]["headers"]["Authorization"]
    assert auth == "Basic " + base64.b64encode(b"sk_secret:").decode()
    assert "Bearer" not in auth and client.auth_kind == "api_key"


def test_oauth_client_credentials_token_reused_then_renewed():
    now = [0.0]
    token_calls = []

    def token(_params):
        token_calls.append(1)
        return FakeResponse(200, {"access_token": f"tok{len(token_calls)}", "token_type": "Bearer",
                                  "expires_in": 900})
    session = FakeSession({("POST", "/oauth/token"): [token],
                           ("GET", "/api/v2/projects"): [FakeResponse(200, {"projects": []})]})
    client = BenchlingConnector(tenant_url=TENANT, client_id="cid", client_secret="csec",
                                session=session, sleep=lambda s: None, clock=lambda: now[0])
    client.list_projects()
    client.list_projects()
    assert len(token_calls) == 1
    tok_req = session.calls[0]
    assert tok_req["data"] == {"grant_type": "client_credentials", "client_id": "cid",
                               "client_secret": "csec"}
    assert session.calls[1]["headers"]["Authorization"] == "Bearer tok1"
    now[0] = 900.0                                          # 15-min token expired → new token
    client.list_projects()
    assert len(token_calls) == 2 and session.calls[-1]["headers"]["Authorization"] == "Bearer tok2"


def test_oauth_401_requests_a_new_token_once():
    session = FakeSession({
        ("POST", "/oauth/token"): [lambda p: FakeResponse(200, {"access_token": "t", "expires_in": 900})],
        ("GET", "/api/v2/projects"): [FakeResponse(401, {"error": {"message": "expired"}}),
                                      FakeResponse(200, {"projects": [{"id": "p"}]})],
    })
    client = BenchlingConnector(tenant_url=TENANT, client_id="c", client_secret="s", session=session,
                                sleep=lambda s: None)
    assert client.list_projects() == [{"id": "p"}]
    assert sum(c["path"] == "/oauth/token" for c in session.calls) == 2


def test_from_env_prefers_app_credentials():
    client = BenchlingConnector.from_env({"BENCHLING_TENANT_URL": "acme", "BENCHLING_CLIENT_ID": "c",
                                          "BENCHLING_CLIENT_SECRET": "s", "BENCHLING_API_KEY": "k"})
    assert client.auth_kind == "oauth_client_credentials" and client.api_url == TENANT


# ── Listing, pagination, retries ────────────────────────────────────────────

def test_list_assay_results_requires_schema_and_paginates():
    client, session, _ = _client({("GET", "/api/v2/assay-results"): [
        FakeResponse(200, {"assayResults": [_result("res_1")], "nextToken": "nt1"}),
        FakeResponse(200, {"assayResults": [_result("res_2")]}),
    ]})
    with pytest.raises(BenchlingConfigError):
        client.list_assay_results("")
    results = client.list_assay_results("assaysch_IC50", modified_after="2026-09-01T00:00:00Z",
                                        page_size=500)
    assert [r["id"] for r in results] == ["res_1", "res_2"]
    first, second = session.calls
    assert first["params"] == {"schemaId": "assaysch_IC50", "sort": "modifiedAt:asc",
                               "archiveReason": "NOT_ARCHIVED", "modifiedAt.gte": "2026-09-01T00:00:00Z",
                               "pageSize": 100}
    assert second["params"]["nextToken"] == "nt1"


def test_retries_429_and_5xx_with_backoff():
    client, session, sleeps = _client({("GET", "/api/v2/projects"): [
        FakeResponse(429, {"error": {"message": "Rate limit exceeded."}}, {"Retry-After": "3"}),
        FakeResponse(503),
        FakeResponse(200, {"projects": []}),
    ]})
    assert client.list_projects() == []
    assert len(session.calls) == 3 and sleeps[0] == 3.0 and len(sleeps) == 2


def test_gives_up_after_max_retries():
    client, _, sleeps = _client({("GET", "/api/v2/projects"): [FakeResponse(500)]}, max_retries=2)
    with pytest.raises(BenchlingAPIError) as exc:
        client.list_projects()
    assert exc.value.status == 500 and len(sleeps) == 2


def test_client_errors_are_not_retried():
    client, session, sleeps = _client({("GET", "/api/v2/projects"): [FakeResponse(403, {"error": {
        "message": "no access"}})]})
    with pytest.raises(BenchlingAPIError, match="403"):
        client.list_projects()
    assert len(session.calls) == 1 and sleeps == []


def test_molecules_fetched_in_chunks_of_100():
    client, session, _ = _client({("GET", "/api/v2/molecules"): [
        lambda p: FakeResponse(200, {"molecules": [{"id": i} for i in p["ids"].split(",")]})]})
    found = client.get_molecules([f"mol_{i:03d}" for i in range(150)])
    assert len(found) == 150 and len(session.calls) == 2
    assert all(len(c["params"]["ids"].split(",")) <= 100 for c in session.calls)


# ── Mapping configuration ───────────────────────────────────────────────────

@pytest.mark.parametrize("change, message", [
    (dict(value_field=""), "value_field is required"),
    (dict(assay_type=None), "exactly one of assay_type"),
    (dict(assay_type_field="kind"), "exactly one of assay_type"),
    (dict(assay_type="IC50nM"), "not supported"),
    (dict(unit="nM"), "exactly one of unit"),
    (dict(compound_entity_type="sample"), "compound_entity_type"),
    (dict(compound_entity_type="custom_entity"), "custom_entity_structure_field"),
    (dict(review_policy="anything"), "review_policy"),
    (dict(operator_values={"gt": ">="}), "invalid operators"),
    (dict(assay_date_field="$now"), "metadata sources"),
    (dict(value_feild="ic50"), "unknown mapping keys"),
])
def test_mapping_is_explicit_and_validated(change, message):
    with pytest.raises(BenchlingMappingError, match=message):
        BenchlingSchemaMapping.from_dict({**MAPPING, **change})


# ── Poller: review policy, resolution, mapping, provenance ──────────────────

def _poller(results, archived=None, mapping=None):
    routes = {
        ("GET", "/api/v2/assay-results"): [lambda p: FakeResponse(200, {
            "assayResults": results if p["archiveReason"] == "NOT_ARCHIVED" else (archived or [])})],
        ("GET", "/api/v2/molecules"): [_molecules],
    }
    client, session, _ = _client(routes)
    return BenchlingAssayPoller(client, BenchlingSchemaMapping.from_dict(mapping or MAPPING)), session


def test_poll_maps_reviewed_results_to_ingestion_rows():
    poller, session = _poller([
        _result("res_1"),
        _result("res_2", mol="mol_B", value=10, qualifier=">", unit="uM", modified="2026-10-02T00:00:00Z"),
        _result("res_3", reviewed=False, modified="2026-10-01T12:00:00Z"),
        _result("res_4", validation="INVALID"),
        _result("res_5", mol="mol_U", modified="2026-10-03T00:00:00Z"),
    ])
    out = poller.poll()
    rows = {r["source_record_id"]: r for r in out.rows}
    assert set(rows) == {"res_1", "res_2"}
    r1 = rows["res_1"]
    assert {k: r1[k] for k in ("compound_id", "smiles", "assay_type", "value", "unit", "operator",
                               "assay_date", "source_system")} == {
        "compound_id": "ACME-0001", "smiles": "CCN", "assay_type": "IC50", "value": 12.5, "unit": "nM",
        "operator": "=", "assay_date": "2026-09-29", "source_system": "benchling"}
    assert r1["provenance"] == {
        "benchling_result_id": "res_1", "schema_id": "assaysch_IC50", "assay_run_id": "asrun_9",
        "entry_id": "etr_123", "project_id": "src_1", "creator_id": "ent_user",
        "created_at": "2026-09-30T08:00:00Z", "modified_at": "2026-10-01T10:00:00Z", "is_reviewed": True,
        "compound_entity_type": "molecule", "compound_entity_id": "mol_A",
        "entity_registry_id": "ACME-0001", "original_smiles": "CCN.Cl", "replicate": 2,
        "tenant_host": "acme.benchling.com"}
    # Not the "first numeric field" (hill_slope / test_conc): the configured value field.
    assert rows["res_2"]["value"] == 10 and rows["res_2"]["operator"] == ">"
    assert {s["benchling_result_id"]: s["reason"] for s in out.skipped} == {
        "res_3": "not_reviewed", "res_4": "validation_invalid", "res_5": "unregistered_compound"}
    # Watermark held at the oldest result that may become ingestible later.
    assert out.next_watermark == "2026-10-01T12:00:00Z"
    mol_calls = [c for c in session.calls if c["path"] == "/api/v2/molecules"]
    assert len(mol_calls) == 1 and set(mol_calls[0]["params"]["ids"].split(",")) == {"mol_A", "mol_B", "mol_U"}


def test_poll_watermark_advances_when_nothing_is_held():
    poller, _ = _poller([_result("res_1", modified="2026-10-01T00:00:00Z"),
                         _result("res_2", modified="2026-10-05T00:00:00Z")])
    assert poller.poll().next_watermark == "2026-10-05T00:00:00Z"


def test_include_unreviewed_policy():
    poller, _ = _poller([_result("res_3", reviewed=False)], mapping={**MAPPING,
                                                                     "review_policy": "include_unreviewed"})
    out = poller.poll()
    assert [r["source_record_id"] for r in out.rows] == ["res_3"]
    assert out.rows[0]["provenance"]["is_reviewed"] is False


def test_poll_reports_archived_results_since_watermark():
    poller, session = _poller([_result("res_1")], archived=[_result("res_9", archived={"reason": "Made in error"})])
    out = poller.poll(modified_after="2026-09-01T00:00:00Z")
    assert out.archived_result_ids == ["res_9"]
    reasons = [c["params"]["archiveReason"] for c in session.calls if c["path"] == "/api/v2/assay-results"]
    assert reasons == ["NOT_ARCHIVED", "ANY_ARCHIVED"]


def test_custom_entity_compound_resolved_through_structure_link():
    result = _result("res_1")
    result["fields"]["compound"] = {"type": "custom_entity_link", "value": "bfi_C1", "isMulti": False}
    routes = {
        ("GET", "/api/v2/assay-results"): [FakeResponse(200, {"assayResults": [result]})],
        ("GET", "/api/v2/custom-entities:bulk-get"): [FakeResponse(200, {"customEntities": [{
            "id": "bfi_C1", "name": "Cpd 1", "entityRegistryId": "CPD-0001",
            "fields": {"structure": {"type": "molecule_link", "value": "mol_B"}}}]})],
        ("GET", "/api/v2/molecules"): [_molecules],
    }
    client, _, _ = _client(routes)
    mapping = BenchlingSchemaMapping.from_dict({**MAPPING, "compound_entity_type": "custom_entity",
                                                "custom_entity_structure_field": "structure"})
    out = BenchlingAssayPoller(client, mapping).poll()
    assert out.rows[0]["compound_id"] == "CPD-0001" and out.rows[0]["smiles"] == "CCO"


def test_unmapped_assay_type_value_is_rejected_by_validator(tmp_path):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    result = _result("res_1")
    result["fields"]["kind"] = {"type": "dropdown", "value": "sfso_k", "textValue": "IC50 (biochemical)"}
    mapping = {**MAPPING, "assay_type": None, "assay_type_field": "kind"}
    poller, _ = _poller([result], mapping=mapping)
    ingest = AssayIngestionService(str(tmp_path / "c.db")).ingest_rows("camp", poller.poll().rows)
    assert ingest["ingested"] == 0 and "Row benchling:res_1: unsupported assay_type" in ingest["errors"][0]
    poller, _ = _poller([result], mapping={**mapping, "assay_type_values": {"IC50 (biochemical)": "IC50"}})
    assert AssayIngestionService(str(tmp_path / "d.db")).ingest_rows("camp", poller.poll().rows)["ingested"] == 1


# ── Shared ingestion path, idempotency, retraction, sync state ──────────────

def test_polled_rows_ingest_idempotently_with_censoring_and_provenance(tmp_path):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    svc = AssayIngestionService(str(tmp_path / "c.db"))
    results = [_result("res_1"), _result("res_2", mol="mol_B", value=10, qualifier=">", unit="uM")]
    poller, _ = _poller(results)
    first = svc.ingest_rows("camp", poller.poll().rows)
    assert (first["ingested"], first["errors"]) == (2, [])
    second = svc.ingest_rows("camp", poller.poll().rows)
    assert (second["ingested"], second["updated"], second["unchanged"]) == (0, 0, 2)
    stored = {r["source_record_id"]: r for r in svc.get_campaign_results("camp")}
    assert stored["res_1"]["compound_id"] == "ACME-0001" and stored["res_1"]["value_uM"] == pytest.approx(0.0125)
    assert stored["res_2"]["censored"] is True and stored["res_2"]["operator"] == ">"
    assert '"benchling_result_id": "res_1"' in stored["res_1"]["provenance_json"]
    ranked = {r["compound_id"]: r for r in svc.get_ranked_compounds("camp")}
    assert ranked["ACME-0002"]["censored_objectives"] == ["potency"]
    assert svc.retract_records("camp", "benchling", ["res_2"])["retracted"] == 1
    assert {r["source_record_id"] for r in svc.get_campaign_results("camp")} == {"res_1"}


def test_sync_state_round_trip(tmp_path):
    db = str(tmp_path / "c.db")
    mapping = BenchlingSchemaMapping.from_dict(MAPPING)
    assert load_sync_state(db, "camp", "assaysch_IC50") is None
    save_sync_state(db, "camp", mapping, "acme.benchling.com", "2026-10-01T00:00:00Z")
    state = load_sync_state(db, "camp", "assaysch_IC50")
    assert state["watermark"] == "2026-10-01T00:00:00Z" and state["tenant_host"] == "acme.benchling.com"
    assert BenchlingSchemaMapping.from_dict(state["mapping"]) == mapping
