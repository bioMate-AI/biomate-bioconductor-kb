"""HTTP contract of the campaign proposal endpoints: every route that returns
surrogate scores also returns per-compound uncertainty and says whether the
surrogate can rank the candidates at all."""
import csv
import io

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("rdkit")
pytest.importorskip("sklearn")

from fastapi import FastAPI
from fastapi.testclient import TestClient

from galaxy.ai.drug_discovery import api_router
from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
from galaxy.ai.drug_discovery.auto_retrain import CAMPAIGN_OBJECTIVE, save_virtual_library, stop_background_loop

POTENCY = [("A", "CCO", "IC50", "1"), ("B", "CCN", "IC50", "10"), ("C", "CCC", "IC50", "100")]
SAFETY = [("A", "CCO", "hERG", "1"), ("B", "CCN", "hERG", "50"), ("C", "CCC", "hERG", "25")]
LIBRARY = ["CCCC", "CCCO", "CCCN", "CCCl"]


def _ingest(db, path, rows, unit, campaign="camp"):
    path.write_text("compound_id,smiles,assay_type,value,unit,assay_date,operator\n" + "".join(
        f"{c},{s},{a},{v},{unit},2026-10-01,=\n" for c, s, a, v in rows))
    AssayIngestionService(db).ingest(campaign, str(path))


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(api_router, "_CAMPAIGN_DB_DIR", str(tmp_path / "campaigns"))
    monkeypatch.setenv("BIOMATE_COMPLIANCE_DB_DIR", str(tmp_path / "audit"))
    db = api_router._campaign_db("camp")
    _ingest(db, tmp_path / "p.csv", POTENCY, "nM")
    _ingest(db, tmp_path / "s.csv", SAFETY, "uM")
    save_virtual_library(db, "camp", LIBRARY, n_propose=2)
    app = FastAPI()
    app.include_router(api_router.router)
    yield TestClient(app)
    stop_background_loop("camp")


def _assert_cannot_rank(report):
    assert report["can_discriminate"] is False
    disc = report["objectives"][CAMPAIGN_OBJECTIVE]["discrimination"]
    assert disc["max_pairwise_order_probability"] < disc["threshold"]


# /propose keeps its n_initial=16 minimum, so it gets a 16-compound campaign
# with a structure-activity signal (acids potent, non-acids weak).
ACIDS = ["CC(=O)O", "CCC(=O)O", "CCCC(=O)O", "CCCCC(=O)O", "OC(=O)c1ccccc1",
         "OC(=O)c1ccc(C)cc1", "OC(=O)c1ccc(Cl)cc1", "OC(=O)C1CCCCC1"]
NON_ACIDS = ["CCCCC", "CCCCCC", "c1ccccc1", "Cc1ccccc1", "Clc1ccccc1", "CCc1ccccc1",
             "C1CCCCC1", "CC(C)C"]


def test_propose_returns_flag_stds_and_requested_count(client, tmp_path):
    rows = ([(f"A{i}", s, "IC50", "1") for i, s in enumerate(ACIDS)]
            + [(f"N{i}", s, "IC50", "1000") for i, s in enumerate(NON_ACIDS)])
    _ingest(api_router._campaign_db("sar"), tmp_path / "sar.csv", rows, "nM", campaign="sar")
    library = ["OC(=O)CCCCCC", "OC(=O)c1ccc(F)cc1", "CCCCCCC", "Fc1ccccc1",
               "CCCCCCCC(=O)O", "CC(=O)O"]
    r = client.post("/api/drug-discovery/sar/propose",
                    json={"virtual_library_smiles": library, "n_propose": 6})
    assert r.status_code == 200, r.text
    body = r.json()
    # CC(=O)O is already measured, so 5 of the 6 requested are usable.
    assert (body["n_requested"], body["n_proposed"]) == (6, 5)
    assert body["surrogate_report"]["n_proposed"] == 5
    assert any(w.startswith("fewer_than_requested") for w in body["surrogate_report"]["warnings"])
    assert body["can_discriminate"] is True and body["surrogate_report"]["can_discriminate"] is True
    scores = dict(zip(body["proposed_smiles"], body["predicted_scores"][CAMPAIGN_OBJECTIVE]))
    assert min(scores["OC(=O)CCCCCC"], scores["OC(=O)c1ccc(F)cc1"]) > max(
        scores["CCCCCCC"], scores["Fc1ccccc1"])
    assert len(body["gp_stds"][CAMPAIGN_OBJECTIVE]) == 5


def test_retrain_endpoints_and_auto_proposal_carry_the_flag(client):
    r = client.post("/api/drug-discovery/camp/retrain")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["can_discriminate"] is False and len(body["gp_stds"][CAMPAIGN_OBJECTIVE]) == 2
    _assert_cannot_rank(body["surrogate_report"])

    r = client.post("/api/drug-discovery/camp/retrain/trigger")
    assert r.status_code == 200, r.text
    shaped = r.json()
    assert shaped["can_discriminate"] is False
    assert all(isinstance(i["std"], float) and i["std"] > 0 for i in shaped["items"])

    latest = client.get("/api/drug-discovery/camp/auto-proposal").json()
    assert latest["round"] == shaped["round"] and latest["can_discriminate"] is False
    assert [i["std"] for i in latest["items"]] == [i["std"] for i in shaped["items"]]

    r = client.get("/api/drug-discovery/camp/auto-proposal", params={"format": "csv"})
    assert r.status_code == 200, r.text
    rows = list(csv.DictReader(io.StringIO(r.text)))
    assert len(rows) == 2 and all(float(row["std"]) > 0 for row in rows)
