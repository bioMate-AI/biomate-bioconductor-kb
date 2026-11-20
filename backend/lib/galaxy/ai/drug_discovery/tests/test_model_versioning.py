"""Durable model versioning: immutable versions, gated promotion, rollback,
restart-safe exact-artifact reload, and old-vs-new comparison on a holdout.

Training is real (RDKit descriptors + scikit-learn GBR via run_training_job);
a fresh CustomModelRegistry instance on the same DB simulates a restart."""
import json
import sqlite3
from pathlib import Path

import pytest

pytest.importorskip("rdkit")
pytest.importorskip("sklearn")

from rdkit import Chem
from rdkit.Chem import Descriptors

from galaxy.ai.drug_discovery.custom_model_registry import (
    ArtifactIntegrityError, CustomModelRegistry, ModelRegistryError, PromotionBlocked,
    artifact_sha256,
)
from galaxy.ai.drug_discovery.custom_model_wrapper import RESTModelWrapper
from galaxy.ai.ml_training import training_job
from galaxy.ai.ml_training.config import DatasetSpec, Hyperparams, TrainingConfig

CAMPAIGN, NAME = "camp", "MW classifier"

_BATCH1 = ["CCO", "CCN", "CCC", "c1ccccc1", "CC(=O)O", "CCOC(=O)C", "CC(C)O", "CCCl",
           "CN1C=NC2=C1C(=O)N(C(=O)N2C)C", "CC(=O)Oc1ccccc1C(=O)O",
           "CN(C)CCC=C1c2ccccc2CCc2ccccc21", "CC(C)NCC(O)COc1cccc2ccccc12",
           "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1", "COc1ccc2[nH]cc(CCN)c2c1",
           "CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC", "CC(C)Cc1ccc(cc1)C(C)C(=O)O"]
_BATCH2 = ["O=C(O)c1ccccc1O", "CC(N)Cc1ccccc1", "CCCCCCCC", "c1ccc2ccccc2c1",
           "c1ccc2c(c1)ccc1ccccc12", "CC1=CC(=O)CC(C)(C)C1", "OCC(O)CO",
           "CC(=O)Nc1ccc(O)cc1", "CN1CCC[C@H]1c1cccnc1", "CC(C)(C)NCC(O)c1ccc(O)c(CO)c1",
           "Cn1cnc2c1c(=O)n(C)c(=O)n2C", "NCCc1ccc(O)c(O)c1"]
_HOLDOUT = ["CCCCO", "CCCCN", "O=C(Nc1ccccc1)c1ccccc1", "CC(C)(C)c1ccc(O)cc1",
            "COc1ccc(CCN(C)C)cc1", "OC(=O)CCc1ccccc1", "CCCCCC", "Clc1ccc(Cl)cc1"]
_THRESHOLD = 150.0


def _label(smi):
    return 1.0 if Descriptors.MolWt(Chem.MolFromSmiles(smi)) > _THRESHOLD else 0.0


def _csv(path, smiles):
    path.write_text("smiles,y\n" + "".join(f"{s},{int(_label(s))}\n" for s in smiles))
    return str(path)


def _cfg(csv, gate):
    return TrainingConfig(name=NAME, campaign_id=CAMPAIGN, model_type="sklearn_gbr",
                          task_type="classification", metric="auc", gate_threshold=gate,
                          dataset=DatasetSpec(path=csv, target_col="y", split="random",
                                              val_frac=0.0, test_frac=0.3),
                          hyperparams=Hyperparams(seed=3))


@pytest.fixture(autouse=True)
def _env(tmp_path, monkeypatch):
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")
    monkeypatch.setenv("ML_TRAINING_ARTIFACT_ROOT", str(tmp_path / "artifacts"))


@pytest.fixture
def two_versions(tmp_path):
    """v1 trained on batch 1, promoted; v2 trained on batch 1 + new batch 2."""
    db = str(tmp_path / "camp.db")
    reg = CustomModelRegistry(db)
    r1 = training_job.run_training_job(_cfg(_csv(tmp_path / "b1.csv", _BATCH1), 0.5),
                                       registry=reg)
    assert (r1.model_version, r1.model_status) == (1, "candidate")
    reg.promote(CAMPAIGN, NAME, 1, actor="reviewer:alice", note="baseline")
    r2 = training_job.run_training_job(
        _cfg(_csv(tmp_path / "b12.csv", _BATCH1 + _BATCH2), 0.5), registry=reg)
    assert (r2.model_version, r2.model_status) == (2, "candidate")
    return db, r1, r2


def test_each_registration_is_an_immutable_version(two_versions):
    db, r1, r2 = two_versions
    reg = CustomModelRegistry(db)
    v1, v2 = reg.list_versions(CAMPAIGN, NAME)
    assert (v1.version, v2.version) == (1, 2)
    assert v1.artifact_dir != v2.artifact_dir
    assert Path(v1.artifact_dir).name.startswith("v0001-")
    assert Path(v2.artifact_dir).name.startswith("v0002-")
    assert v1.artifact_sha256 == artifact_sha256(v1.artifact_dir)       # v1 kept intact
    assert v1.dataset_sha256 != v2.dataset_sha256
    assert v2.parent_version == 1
    assert v1.split["method"] == "random" and v1.metrics.get("test_auc") is not None
    assert v1.gate["passed"] is True and v1.gate["threshold"] == 0.5
    assert (v1.status, v2.status) == ("active", "candidate")
    assert reg.get_version(CAMPAIGN, NAME, 1).events[-1]["actor"] == "reviewer:alice"


def test_restart_loads_exact_active_artifact(two_versions):
    db, r1, _ = two_versions
    fresh = CustomModelRegistry(db)                       # simulated process restart
    scores, _ = fresh.run_named_model(CAMPAIGN, NAME, _HOLDOUT)
    from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
    direct = ChempropModelWrapper(NAME, CAMPAIGN, r1.artifact_dir).score(_HOLDOUT)
    assert scores == direct
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT model_version FROM custom_model_run_log").fetchall() == [(1,)]


def test_hash_mismatch_is_refused(two_versions):
    db, r1, _ = two_versions
    manifest = Path(r1.artifact_dir) / "manifest.json"
    data = json.loads(manifest.read_text())
    data["tampered"] = True
    manifest.write_text(json.dumps(data))
    with pytest.raises(ArtifactIntegrityError, match="refusing to load"):
        CustomModelRegistry(db).run_named_model(CAMPAIGN, NAME, ["CCO"])


def test_promote_blocked_on_failed_or_missing_metric_gate(tmp_path):
    reg = CustomModelRegistry(str(tmp_path / "camp.db"))
    csv = _csv(tmp_path / "b1.csv", _BATCH1)
    failed = training_job.run_training_job(_cfg(csv, 1.01), registry=reg)   # AUC cannot exceed 1
    assert failed.model_status == "rejected"
    with pytest.raises(PromotionBlocked):
        reg.promote(CAMPAIGN, NAME, failed.model_version, actor="reviewer:alice")

    missing = training_job.run_training_job(
        _cfg(csv, 0.5), registry=reg,
        train_fn=lambda cfg, ds, out: _metricless_result(cfg, out))
    mv = reg.get_version(CAMPAIGN, NAME, missing.model_version)
    assert mv.status == "rejected" and "missing" in mv.gate["reason"]
    with pytest.raises(PromotionBlocked):
        reg.promote(CAMPAIGN, NAME, mv.version, actor="reviewer:alice")
    assert reg.get_active_version(CAMPAIGN, NAME) is None


def _metricless_result(cfg, out):
    from galaxy.ai.ml_training.chemprop_trainer import TrainingResult
    (Path(out) / "manifest.json").write_text("{}")
    return TrainingResult(model_type="sklearn_gbr", artifact_dir=out, metrics={},
                          n_train=1, n_val=0, n_test=0)


def test_promote_requires_reviewer(two_versions):
    db, _, _ = two_versions
    with pytest.raises(PromotionBlocked, match="reviewer"):
        CustomModelRegistry(db).promote(CAMPAIGN, NAME, 2, actor="  ")


def test_promote_then_rollback_restores_v1(two_versions):
    db, r1, r2 = two_versions
    reg = CustomModelRegistry(db)
    reg.promote(CAMPAIGN, NAME, 2, actor="reviewer:bob", note="better on holdout")
    assert [v.status for v in reg.list_versions(CAMPAIGN, NAME)] == ["retired", "active"]
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT active_version FROM custom_model_registrations").fetchone() == (2,)

    restored = CustomModelRegistry(db).rollback(CAMPAIGN, NAME, actor="reviewer:bob")
    assert restored.version == 1 and restored.status == "active"
    fresh = CustomModelRegistry(db)
    assert [v.status for v in fresh.list_versions(CAMPAIGN, NAME)] == ["active", "retired"]
    from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
    assert fresh.run_named_model(CAMPAIGN, NAME, _HOLDOUT)[0] == \
        ChempropModelWrapper(NAME, CAMPAIGN, r1.artifact_dir).score(_HOLDOUT)


def test_exactly_one_active_version_enforced_by_db(two_versions):
    db, _, _ = two_versions
    with sqlite3.connect(db) as conn, pytest.raises(sqlite3.IntegrityError):
        conn.execute("UPDATE custom_model_versions SET status='active' WHERE version=2")


def test_rollback_target_must_have_been_active(two_versions):
    db, _, _ = two_versions
    with pytest.raises(ModelRegistryError, match="retired"):
        CustomModelRegistry(db).rollback(CAMPAIGN, NAME, actor="reviewer:bob", to_version=2)


def test_compare_versions_on_same_untouched_holdout(two_versions):
    db, _, _ = two_versions
    holdout = [(s, _label(s)) for s in _HOLDOUT]
    reg = CustomModelRegistry(db)
    result = reg.compare_versions(CAMPAIGN, NAME, 1, 2, holdout, actor="reviewer:alice")
    m1, m2 = result["versions"]["v1"]["metrics"], result["versions"]["v2"]["metrics"]
    assert set(m1) == set(m2) and {"auc", "accuracy", "n", "n_scored"} <= set(m1)
    assert m1["n"] == m2["n"] == len(holdout)
    assert result["training_overlap"] == {"v1": [], "v2": []}
    stored = CustomModelRegistry(db).list_comparisons(CAMPAIGN, NAME)
    assert stored[0]["holdout_sha256"] == result["holdout_sha256"]
    assert stored[0]["metrics_a"] == m1 and stored[0]["metrics_b"] == m2


def test_compare_refuses_holdout_that_overlaps_training(two_versions):
    db, _, _ = two_versions
    leaked = [("CCO", 0.0), ("CCCCO", 0.0)]                 # CCO is in v1/v2 training data
    with pytest.raises(ModelRegistryError, match="not untouched"):
        CustomModelRegistry(db).compare_versions(CAMPAIGN, NAME, 1, 2, leaked)


def test_external_rest_model_survives_restart(tmp_path):
    db = str(tmp_path / "camp.db")
    reg = CustomModelRegistry(db)
    mv = reg.register(RESTModelWrapper("ext", CAMPAIGN, endpoint="https://scorer.example/api",
                                       input_key="smiles", output_path="scores"),
                      config={"registered_by": "user:alice"})
    assert (mv.version, mv.status, mv.gate) == (1, "active", {"status": "not_applicable"})
    wrapper = CustomModelRegistry(db).load_version(CAMPAIGN, "ext")
    assert isinstance(wrapper, RESTModelWrapper)
    assert (wrapper.endpoint, wrapper.output_path) == ("https://scorer.example/api", "scores")
    reg.register(RESTModelWrapper("ext", CAMPAIGN, endpoint="https://scorer.example/v2"))
    assert [v.status for v in CustomModelRegistry(db).list_versions(CAMPAIGN, "ext")] == \
        ["retired", "active"]


def test_trained_artifact_cannot_bypass_gate_via_register(tmp_path):
    from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
    reg = CustomModelRegistry(str(tmp_path / "camp.db"))
    with pytest.raises(ModelRegistryError, match="register_trained_version"):
        reg.register(ChempropModelWrapper(NAME, CAMPAIGN, str(tmp_path)))


def test_unknown_model_raises_keyerror(tmp_path):
    with pytest.raises(KeyError):
        CustomModelRegistry(str(tmp_path / "camp.db")).run_named_model(CAMPAIGN, "nope", ["CCO"])


def test_external_rest_model_registers_and_surfaces(tmp_path):
    """Connector 'A model' mechanism: an external REST scorer registers as an active
    version AND writes a custom_model_registrations row (mode 'rest'), so it surfaces in
    the catalog (_iter_custom_registrations) and is runnable — no training artifact.
    This is exactly what models_inference.register_external_model relies on."""
    db = str(tmp_path / "ext.db")
    reg = CustomModelRegistry(db)
    wrapper = RESTModelWrapper(name="ext scorer", campaign_id="connector-models-u1",
                               endpoint="https://example.test/score",
                               input_key="smiles", output_path="scores")
    mv = reg.register(wrapper, {"registered_by": "u1", "source": "connector"})
    assert mv.version == 1
    assert reg.get_version("connector-models-u1", "ext scorer", 1).status == "active"
    with sqlite3.connect(db) as conn:
        rows = conn.execute(
            "SELECT model_name, mode FROM custom_model_registrations WHERE campaign_id=?",
            ("connector-models-u1",)).fetchall()
    assert ("ext scorer", "rest") in rows
