"""HTTP contract for model versions: shared registry across requests, gated
promotion with a named reviewer, rollback, holdout comparison, and the
retrain route table."""
import pytest

pytest.importorskip("fastapi")
pytest.importorskip("rdkit")
pytest.importorskip("sklearn")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from rdkit import Chem
from rdkit.Chem import Descriptors

from galaxy.ai.drug_discovery import api_router
from galaxy.ai.drug_discovery import custom_model_registry as cmr
from galaxy.ai.ml_training import training_job
from galaxy.ai.ml_training.config import DatasetSpec, Hyperparams, TrainingConfig

CAMPAIGN, NAME = "apicamp", "mw-clf"
_TRAIN = ["CCO", "CCN", "CCC", "c1ccccc1", "CC(=O)O", "CCOC(=O)C", "CC(C)O", "CCCl",
          "CN1C=NC2=C1C(=O)N(C(=O)N2C)C", "CC(=O)Oc1ccccc1C(=O)O",
          "CN(C)CCC=C1c2ccccc2CCc2ccccc21", "CC(C)NCC(O)COc1cccc2ccccc12",
          "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1", "COc1ccc2[nH]cc(CCN)c2c1",
          "CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC", "CC(C)Cc1ccc(cc1)C(C)C(=O)O"]
_HOLDOUT = ["CCCCO", "O=C(Nc1ccccc1)c1ccccc1", "CC(C)(C)c1ccc(O)cc1", "CCCCCC"]


def _label(s):
    return 1 if Descriptors.MolWt(Chem.MolFromSmiles(s)) > 150 else 0


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(api_router, "_CAMPAIGN_DB_DIR", str(tmp_path / "campaigns"))
    monkeypatch.setenv("BIOMATE_COMPLIANCE_DB_DIR", str(tmp_path / "audit"))
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")
    monkeypatch.setenv("ML_TRAINING_ARTIFACT_ROOT", str(tmp_path / "artifacts"))
    (tmp_path / "campaigns").mkdir()
    csv = tmp_path / "train.csv"
    csv.write_text("smiles,y\n" + "".join(f"{s},{_label(s)}\n" for s in _TRAIN))
    db = api_router._campaign_db(CAMPAIGN)
    for gate in (0.5, 1.01):                       # v1 passes, v2 fails its gate
        training_job.run_training_job(
            TrainingConfig(name=NAME, campaign_id=CAMPAIGN, model_type="sklearn_gbr",
                           metric="auc", gate_threshold=gate,
                           dataset=DatasetSpec(path=str(csv), split="random", val_frac=0.0,
                                               test_frac=0.3),
                           hyperparams=Hyperparams(seed=3)),
            registry=cmr.CustomModelRegistry(db))
    # Same-gate retrain as v3 so there is a second promotable version.
    training_job.run_training_job(
        TrainingConfig(name=NAME, campaign_id=CAMPAIGN, model_type="sklearn_gbr",
                       metric="auc", gate_threshold=0.5,
                       dataset=DatasetSpec(path=str(csv), split="random", val_frac=0.0,
                                           test_frac=0.3),
                       hyperparams=Hyperparams(seed=4)),
        registry=cmr.CustomModelRegistry(db))
    cmr._REGISTRIES.clear()                        # requests start from a cold process cache
    app = FastAPI()
    app.include_router(api_router.router)
    return TestClient(app)


def _url(path):
    return f"/api/drug-discovery/{CAMPAIGN}/models/{NAME}{path}"


def test_version_lifecycle_over_http(client):
    listing = client.get(_url("/versions")).json()
    assert [v["status"] for v in listing["versions"]] == ["candidate", "rejected", "candidate"]
    assert listing["active_version"] is None

    assert client.post(_url("/versions/1/promote"), json={"reviewer": " "}).status_code == 400
    blocked = client.post(_url("/versions/2/promote"), json={"reviewer": "Dr. Li"})
    assert blocked.status_code == 409 and "gate" in blocked.json()["detail"]

    ok = client.post(_url("/versions/1/promote"), json={"reviewer": "Dr. Li", "note": "baseline"})
    assert ok.status_code == 200 and ok.json()["status"] == "active"
    assert "Dr. Li" in ok.json()["status_changed_by"]

    run = client.post(f"/api/drug-discovery/{CAMPAIGN}/models/{NAME}/run", json=_HOLDOUT)
    assert run.status_code == 200 and run.json()["model_version"] == 1

    client.post(_url("/versions/3/promote"), json={"reviewer": "Dr. Li"})
    assert client.post(f"/api/drug-discovery/{CAMPAIGN}/models/{NAME}/run",
                       json=_HOLDOUT).json()["model_version"] == 3

    back = client.post(_url("/rollback"), json={"reviewer": "Dr. Li"})
    assert back.status_code == 200 and back.json()["version"] == 1
    assert client.get(_url("/versions")).json()["active_version"] == 1


def test_compare_over_http_records_both_metrics(client):
    body = {"version_a": 1, "version_b": 3,
            "holdout": [{"smiles": s, "label": _label(s)} for s in _HOLDOUT]}
    res = client.post(_url("/compare"), json=body)
    assert res.status_code == 200
    data = res.json()
    assert set(data["versions"]["v1"]["metrics"]) == set(data["versions"]["v3"]["metrics"])
    assert client.get(_url("/comparisons")).json()["comparisons"][0]["holdout_sha256"] == \
        data["holdout_sha256"]
    leaked = dict(body, holdout=[{"smiles": "CCO", "label": 0}])
    assert client.post(_url("/compare"), json=leaked).status_code == 422


def test_register_rest_model_is_versioned_and_found_on_next_request(client):
    res = client.post(f"/api/drug-discovery/{CAMPAIGN}/models/register",
                      json={"name": "ext", "mode": "rest", "endpoint": "https://scorer.example/x",
                            "output_field": "scores"})
    assert res.status_code == 200, res.text
    assert (res.json()["version"], res.json()["version_status"]) == (1, "active")
    cmr._REGISTRIES.clear()
    models = client.get(f"/api/drug-discovery/{CAMPAIGN}/models").json()["models"]
    ext = next(m for m in models if m["model_name"] == "ext")
    assert ext["active_version"] == 1


def test_single_post_retrain_route():
    posts = [r for r in api_router.router.routes
             if getattr(r, "path", "") == "/api/drug-discovery/{campaign_id}/retrain"
             and "POST" in r.methods]
    assert len(posts) == 1


def test_retrain_trigger_reports_admet_followup_explicitly(client, tmp_path):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    from galaxy.ai.drug_discovery.auto_retrain import save_virtual_library, stop_background_loop
    db = api_router._campaign_db("retraincamp")
    csv = tmp_path / "assay.csv"
    csv.write_text("compound_id,smiles,assay_type,value,unit,assay_date,operator\n"
                   "A,CCO,IC50,1,nM,2026-10-01,=\nB,CCN,IC50,10,nM,2026-10-01,=\n"
                   "C,CCC,IC50,100,nM,2026-10-01,=\n")
    AssayIngestionService(db).ingest("retraincamp", str(csv))
    save_virtual_library(db, "retraincamp", ["CCCC", "CCCO", "CCCN"], n_propose=2)
    try:
        res = client.post("/api/drug-discovery/retraincamp/retrain/trigger")
    finally:
        stop_background_loop("retraincamp")
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["round"] == 1 and len(data["items"]) == 2
    assert data["admet_followup"]["submitted"] is False
    assert data["admet_followup"]["proposed_smiles"] == [i["smiles"] for i in data["items"]]
