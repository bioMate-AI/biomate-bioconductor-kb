"""REAL end-to-end test through the Ludwig low-code DL engine (CPU, no GPU).

Trains an actual Ludwig neural network over RDKit descriptors and runs it through
the orchestrator → QC gate → CustomModelRegistry → load-from-artifact inference.
This is the proof that "low-code DL" uses a real open-source framework (Ludwig),
not the self-built layer.

Skipped automatically when ludwig / rdkit / pandas are absent (dep-light CI),
so the fast suite stays dependency-free. Heavy: trains a small NN — kept to a
few epochs.
"""
import statistics

import pytest

pytest.importorskip("ludwig")
pytest.importorskip("rdkit")
pytest.importorskip("pandas")

from rdkit import Chem
from rdkit.Chem import Descriptors

from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec, Hyperparams
from galaxy.ai.ml_training import training_job
from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry

# A larger valid-SMILES set so the NN has something to fit (MolWt-median label).
_SMILES = [
    "CCO", "CCN", "CCC", "CCCC", "CCCCC", "CCCCCC", "CCCCCCC", "CCCCCCCC",
    "c1ccccc1", "Cc1ccccc1", "CCc1ccccc1", "c1ccc2ccccc2c1", "c1ccc2c(c1)ccc1ccccc12",
    "CC(=O)O", "CCC(=O)O", "CCCC(=O)O", "CC(=O)Oc1ccccc1C(=O)O", "O=C(O)c1ccccc1O",
    "CN1C=NC2=C1C(=O)N(C(=O)N2C)C", "Cn1cnc2c1c(=O)n(C)c(=O)n2C",
    "CN(C)CCC=C1c2ccccc2CCc2ccccc21", "CC(C)NCC(O)COc1cccc2ccccc12",
    "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1",
    "CC(C)Cc1ccc(cc1)C(C)C(=O)O", "CC(=O)Nc1ccc(O)cc1", "NCCc1ccc(O)c(O)c1",
    "CC(C)(C)NCC(O)c1ccc(O)c(CO)c1", "O=C(Cc1ccccc1)Nc1ccccc1",
    "OCC(O)CO", "CC(N)Cc1ccccc1", "CN1CCC[C@H]1c1cccnc1", "CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC",
]


@pytest.fixture(autouse=True)
def _noop_mlflow(monkeypatch):
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")


@pytest.fixture(scope="module")
def herg_like_csv(tmp_path_factory):
    mw = {s: Descriptors.MolWt(Chem.MolFromSmiles(s))
          for s in _SMILES if Chem.MolFromSmiles(s)}
    thr = statistics.median(mw.values())
    path = tmp_path_factory.mktemp("ludwig") / "data.csv"
    with path.open("w") as f:
        f.write("smiles,Y\n")
        for s, w in mw.items():
            f.write(f"{s},{1 if w > thr else 0}\n")
    return str(path)


def test_ludwig_low_code_dl_end_to_end(herg_like_csv, tmp_path):
    # No QC gate here: on a ~30-row random split the held-out AUC is noisy
    # (a split can be single-class), so gating would be flaky. The gate
    # pass/fail behaviour is covered deterministically by test_real_sklearn_e2e.
    cfg = TrainingConfig(
        name="hERG (Ludwig NN)", model_type="ludwig_tabular",
        task_type="classification", metric="auc", campaign_id="camp1",
        dataset=DatasetSpec(path=herg_like_csv, smiles_col="smiles", target_col="Y",
                            val_frac=0.2, test_frac=0.2),
        hyperparams=Hyperparams(epochs=5, batch_size=8, hidden_size=16, seed=1),
    )
    reg = CustomModelRegistry(str(tmp_path / "reg.db"))
    r = training_job.run_training_job(cfg, artifact_dir=str(tmp_path / "art"), registry=reg)

    # a real Ludwig NN trained and produced an artifact + framework version
    assert r.training is not None
    assert r.training.framework_version.startswith("ludwig==")
    assert (tmp_path / "art" / "ludwig_model").exists()
    # _extract_metrics pulled a real metric out of Ludwig's TrainingStats object
    assert any(k.endswith("_auc") for k in r.training.metrics), r.training.metrics
    assert r.gate.value is not None                   # gate saw a real measured metric
    assert r.registered is True                       # no threshold → registers on success
    assert "hERG (Ludwig NN)" in [m["model_name"] for m in reg.list_models("camp1")]

    # load-from-artifact inference through the same BaseModelWrapper contract
    w = ChempropModelWrapper("hERG (Ludwig NN)", "camp1", r.artifact_dir)
    scores = w.score(["CCO", "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1"])
    assert set(scores) == {"CCO", "Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1"}
    assert all(v == v for v in scores.values())       # not NaN
