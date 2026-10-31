"""Contracts the experimental learning loop relies on:

  * a configured QC gate fails closed on missing / non-numeric / non-finite metrics;
  * split='scaffold' is a real Bemis–Murcko group split, and the method actually
    used is recorded in the training metadata;
  * the unimplemented Chemprop trainer fails instead of producing an artifact.
"""
import math
from pathlib import Path

import pytest

from galaxy.ai.ml_training import training_job
from galaxy.ai.ml_training.chemprop_trainer import TrainingResult, train
from galaxy.ai.ml_training.config import (ConfigError, DatasetSpec, Hyperparams, LLMSpec,
                                          TrainingConfig)
from galaxy.ai.ml_training.datasets import LoadedDataset


@pytest.fixture(autouse=True)
def _noop_mlflow(monkeypatch):
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")


def _cfg(**over):
    base = dict(name="qa", campaign_id="qa", dataset=DatasetSpec(name="fixture"),
                metric="auc", gate_threshold=0.7)
    base.update(over)
    return TrainingConfig(**base)


def _result(metrics):
    return TrainingResult(model_type="sklearn_gbr", artifact_dir="/unused", metrics=metrics,
                          n_train=3, n_val=1, n_test=2)


# --- QC gate ----------------------------------------------------------------

@pytest.mark.parametrize("metrics,reason_part", [
    ({}, "missing"),
    ({"val_loss": 0.1}, "missing"),
    ({"val_auc": float("inf")}, "not finite"),
    ({"val_auc": float("-inf")}, "not finite"),
    ({"val_auc": float("nan")}, "not finite"),
    ({"val_auc": None}, "missing"),
    ({"val_auc": "high"}, "not numeric"),
])
def test_configured_gate_fails_closed(metrics, reason_part):
    gate = training_job._evaluate_gate(_cfg(), _result(metrics))
    assert gate.passed is False
    assert reason_part in gate.reason
    assert gate.to_sse_payload()["gates"][0]["status"] == "halt"


def test_valid_metric_passes_and_poor_metric_fails():
    ok = training_job._evaluate_gate(_cfg(), _result({"val_auc": 0.8}))
    bad = training_job._evaluate_gate(_cfg(), _result({"val_auc": 0.6}))
    assert ok.passed is True and ok.value == 0.8
    assert bad.passed is False and "<" in bad.reason


def test_lower_is_better_metric_direction():
    cfg = _cfg(metric="mae", gate_threshold=0.5)
    assert training_job._evaluate_gate(cfg, _result({"test_mae": 0.4})).passed is True
    assert training_job._evaluate_gate(cfg, _result({"test_mae": 0.6})).passed is False
    assert training_job._evaluate_gate(cfg, _result({"test_mae": math.nan})).passed is False


def test_no_gate_configured_passes_with_reason():
    gate = training_job._evaluate_gate(_cfg(gate_threshold=None), _result({}))
    assert gate.passed is True and gate.reason == "no_gate_configured"


def test_sse_payload_has_no_nonfinite_measured_value():
    gate = training_job._evaluate_gate(_cfg(), _result({"val_auc": float("inf")}))
    assert gate.to_sse_payload()["gates"][0]["measured"] is None


@pytest.mark.parametrize("thr", [float("inf"), float("nan"), "0.7x"])
def test_nonfinite_or_nonnumeric_threshold_rejected_by_config(thr):
    with pytest.raises(ConfigError, match="gate_threshold"):
        _cfg(gate_threshold=thr).validate()


def test_missing_metric_blocks_registration(tmp_path, monkeypatch):
    from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry
    monkeypatch.setenv("ML_TRAINING_ARTIFACT_ROOT", str(tmp_path / "artifacts"))
    reg = CustomModelRegistry(str(tmp_path / "reg.db"))
    cfg = _cfg()
    result = training_job.run_training_job(
        cfg, registry=reg,
        load_fn=lambda _spec: LoadedDataset([("CCO", 0.0), ("CCN", 1.0)], "smiles", "y",
                                            source="fixture"),
        train_fn=lambda cfg, ds, out: _result({}),
    )
    assert result.gate.passed is False
    assert result.registered is False and result.model_status == "rejected"
    assert reg.get_active_version(cfg.campaign_id, cfg.name) is None


# --- Split contract ---------------------------------------------------------

_SMILES = [
    "c1ccccc1C", "c1ccccc1CC", "c1ccccc1CCC", "c1ccccc1O", "c1ccccc1N",
    "C1CCCCC1C", "C1CCCCC1N", "C1CCCCC1O",
    "c1ccncc1C", "c1ccncc1N",
    "c1ccc2ccccc2c1C", "c1ccc2ccccc2c1O",
    "C1CCNCC1C", "C1CCNCC1CC",
    "c1ccoc1C", "c1ccsc1C", "c1cc[nH]c1C", "C1CC1C", "C1CCC1C", "C1CCCC1C",
    "CCO", "CCN", "CCCC", "CC(=O)O",
]


def test_scaffold_split_is_groupwise_deterministic_and_sized():
    pytest.importorskip("rdkit")
    from galaxy.ai.ml_training.splits import bemis_murcko_scaffold, scaffold_split

    a = scaffold_split(_SMILES, val_frac=0.2, test_frac=0.2, seed=7)
    b = scaffold_split(_SMILES, val_frac=0.2, test_frac=0.2, seed=7)
    assert (a.train, a.val, a.test) == (b.train, b.val, b.test)
    assert a.method == "bemis_murcko_scaffold"

    parts = [set(a.train), set(a.val), set(a.test)]
    assert sorted(i for p in parts for i in p) == list(range(len(_SMILES)))
    scaf = [{bemis_murcko_scaffold(_SMILES[i]) for i in p} for p in parts]
    assert not (scaf[0] & scaf[1]) and not (scaf[0] & scaf[2]) and not (scaf[1] & scaf[2])
    assert a.n_groups == len(set().union(*scaf))
    # Group-wise assignment only approximates the requested 60/20/20 sizes.
    assert abs(len(a.train) - 0.6 * len(_SMILES)) <= 4
    assert a.test, "scaffold split must leave a held-out test partition"


def test_scaffold_split_seed_changes_assignment():
    pytest.importorskip("rdkit")
    from galaxy.ai.ml_training.splits import scaffold_split

    seen = {tuple(scaffold_split(_SMILES, 0.2, 0.2, seed=s).test) for s in range(6)}
    assert len(seen) > 1


def test_unknown_split_rejected():
    from galaxy.ai.ml_training.splits import split_dataset
    with pytest.raises(ValueError, match="unsupported split"):
        split_dataset(_SMILES, "stratified", 0.1, 0.1, seed=0)


def _sklearn_cfg(split):
    return TrainingConfig(
        name="split-check", model_type="sklearn_gbr", task_type="regression",
        metric="mae", dataset=DatasetSpec(path="unused.csv", split=split,
                                          val_frac=0.2, test_frac=0.2),
        hyperparams=Hyperparams(seed=3))


def _regression_ds():
    from rdkit import Chem
    from rdkit.Chem import Descriptors
    rows = [(s, Descriptors.MolWt(Chem.MolFromSmiles(s))) for s in _SMILES]
    return LoadedDataset(rows, "smiles", "y", source="fixture")


def test_sklearn_baseline_performs_and_records_scaffold_split(tmp_path):
    pytest.importorskip("rdkit")
    pytest.importorskip("sklearn")
    from galaxy.ai.ml_training.splits import bemis_murcko_scaffold, scaffold_split

    result = train(_sklearn_cfg("scaffold"), _regression_ds(), str(tmp_path))
    meta = result.extra["split"]
    assert meta["requested"] == "scaffold" and meta["method"] == "bemis_murcko_scaffold"
    expected = scaffold_split(_SMILES, 0.2, 0.2, seed=3)
    assert (result.n_train, result.n_val, result.n_test) == (
        len(expected.train), len(expected.val), len(expected.test))
    train_scaf = {bemis_murcko_scaffold(_SMILES[i]) for i in expected.train}
    test_scaf = {bemis_murcko_scaffold(_SMILES[i]) for i in expected.test}
    assert not train_scaf & test_scaf
    assert "test_mae" in result.metrics


def test_sklearn_baseline_records_random_split(tmp_path):
    pytest.importorskip("rdkit")
    pytest.importorskip("sklearn")
    result = train(_sklearn_cfg("random"), _regression_ds(), str(tmp_path))
    assert result.extra["split"]["method"] == "random"


def test_llm_config_rejects_scaffold_split():
    with pytest.raises(ConfigError, match="scaffold"):
        TrainingConfig(name="llm", task_type="text_generation", model_type="ludwig_llm",
                       dataset=DatasetSpec(name="fixture:instruct", split="scaffold"),
                       llm=LLMSpec()).validate()


# --- Unimplemented trainer --------------------------------------------------

def test_chemprop_trainer_fails_explicitly_without_artifact(tmp_path):
    cfg = TrainingConfig(name="gnn", model_type="chemprop_gnn",
                         dataset=DatasetSpec(name="fixture:herg"))
    with pytest.raises(NotImplementedError, match="not implemented"):
        train(cfg, LoadedDataset([("CCO", 0.0), ("CCN", 1.0)], "smiles", "y", source="fixture"),
              str(tmp_path))
    assert not (Path(tmp_path) / "manifest.json").exists()
