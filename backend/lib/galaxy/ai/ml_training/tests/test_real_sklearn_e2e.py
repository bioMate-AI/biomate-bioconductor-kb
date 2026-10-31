"""REAL end-to-end test through the sklearn_gbr baseline (no stubs, no GPU).

Exercises the actual code the unit tests stub out: RDKit featurization + a real
GradientBoosting fit (chemprop_trainer._train_sklearn), the QC gate on a real
metric, registration into a real CustomModelRegistry, and load-from-artifact
inference (chemprop_wrapper._make_sklearn_predict).

Skipped automatically when rdkit / scikit-learn are absent (dep-light CI), so
the fast suite stays dependency-free; runs wherever the ML baseline stack is
installed (training image, dev box).
"""
import statistics

import pytest

pytest.importorskip("rdkit")
pytest.importorskip("sklearn")
pytest.importorskip("numpy")

from rdkit import Chem
from rdkit.Chem import Descriptors

from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec, Hyperparams
from galaxy.ai.ml_training import training_job
from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
from galaxy.ai.ml_training.bento_service import predict_with_wrapper
from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry

_SMILES = [
    "CCO", "CCN", "CCC", "c1ccccc1", "CC(=O)O", "CCOC(=O)C",
    "CN1C=NC2=C1C(=O)N(C(=O)N2C)C", "CC(=O)Oc1ccccc1C(=O)O",
    "CN(C)CCC=C1c2ccccc2CCc2ccccc21", "CC(C)NCC(O)COc1cccc2ccccc12",
    "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1",
    "Clc1ccccc1C1=NCC(=O)Nc2ccc(cc21)[N+](=O)[O-]", "COc1ccc2[nH]cc(CCN)c2c1",
    "CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC", "CC(C)Cc1ccc(cc1)C(C)C(=O)O",
    "O=C(O)c1ccccc1O", "CC(N)Cc1ccccc1", "CCCCCCCC", "c1ccc2ccccc2c1",
    "c1ccc2c(c1)ccc1ccccc12", "CC1=CC(=O)CC(C)(C)C1", "OCC(O)CO",
    "CC(=O)Nc1ccc(O)cc1", "CN1CCC[C@H]1c1cccnc1",
    "CC(C)(C)NCC(O)c1ccc(O)c(CO)c1", "Cn1cnc2c1c(=O)n(C)c(=O)n2C",
    "CC(=O)N", "NCCc1ccc(O)c(O)c1", "O=C(Cc1ccccc1)Nc1ccccc1", "Cc1ccccc1",
]


@pytest.fixture(scope="module")
def herg_like_csv(tmp_path_factory):
    """A learnable classification set: label = MolWt above the median (balanced)."""
    mw = {s: Descriptors.MolWt(Chem.MolFromSmiles(s))
          for s in _SMILES if Chem.MolFromSmiles(s)}
    thr = statistics.median(mw.values())
    path = tmp_path_factory.mktemp("mlt") / "data.csv"
    with path.open("w") as f:
        f.write("smiles,y\n")
        for s, w in mw.items():
            f.write(f"{s},{1 if w > thr else 0}\n")
    return str(path), mw


def _cfg(csv, gate, campaign="camp1"):
    return TrainingConfig(
        name="MolWt clf (real GBR)", model_type="sklearn_gbr",
        task_type="classification", metric="auc", gate_threshold=gate,
        campaign_id=campaign,
        dataset=DatasetSpec(path=csv, smiles_col="smiles", target_col="y", test_frac=0.4),
        hyperparams=Hyperparams(seed=1),
    )


@pytest.fixture(autouse=True)
def _noop_mlflow(monkeypatch, tmp_path):
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")
    monkeypatch.setenv("ML_TRAINING_ARTIFACT_ROOT", str(tmp_path / "artifacts"))


def test_train_gate_register_predict(herg_like_csv, tmp_path):
    csv, mw = herg_like_csv
    reg = CustomModelRegistry(str(tmp_path / "reg.db"))

    # (B) real train → gate pass → register
    r = training_job.run_training_job(_cfg(csv, gate=0.5), registry=reg)
    assert r.training.metrics.get("test_auc") is not None
    assert r.gate.value is not None and r.gate.passed is True
    assert r.registered is True
    assert "MolWt clf (real GBR)" in [m["model_name"] for m in reg.list_models("camp1")]

    # (C) real load-from-artifact inference (no injected predict_fn)
    w = ChempropModelWrapper("MolWt clf", "camp1", r.artifact_dir)
    heavy = "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1"  # ~376 Da
    scores = w.score(["CCO", heavy])                          # ~46 Da vs heavy
    assert all(0.0 <= v <= 1.0 for v in scores.values())
    assert scores[heavy] > scores["CCO"]                      # MolWt signal learned

    # (D) bento predict path over the real model
    resp = predict_with_wrapper(w, ["CCO", "CCN"])
    assert resp.model == "MolWt clf" and set(resp.scores) == {"CCO", "CCN"}


def test_impossible_gate_halts_registration(herg_like_csv, tmp_path):
    csv, _ = herg_like_csv
    reg = CustomModelRegistry(str(tmp_path / "reg2.db"))
    r = training_job.run_training_job(_cfg(csv, gate=1.01), registry=reg)  # AUC can't exceed 1.0
    assert r.gate.passed is False
    assert r.registered is False
