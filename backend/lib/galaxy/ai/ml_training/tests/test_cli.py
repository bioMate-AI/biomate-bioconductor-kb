"""Unit tests for the training CLI arg → TrainingConfig mapping."""
import json

import pytest

from galaxy.ai.ml_training.cli import _build_parser, build_config_from_args, main
from galaxy.ai.ml_training.config import ConfigError


def _parse(argv):
    return _build_parser().parse_args(argv)


def test_named_dataset_maps_to_name_source():
    cfg = build_config_from_args(_parse(["--dataset", "tdc:hERG", "--target-col", "y"]))
    assert cfg.dataset.name == "tdc:hERG"
    assert cfg.dataset.path is None and cfg.dataset.s3_uri is None


def test_s3_dataset_maps_to_s3_source():
    cfg = build_config_from_args(_parse(["--dataset", "s3://bkt/x.csv"]))
    assert cfg.dataset.s3_uri == "s3://bkt/x.csv"


def test_local_csv_maps_to_path_source():
    cfg = build_config_from_args(_parse(["--dataset", "/data/herg.csv"]))
    assert cfg.dataset.path == "/data/herg.csv"


def test_hyperparams_and_gate_flow_through():
    cfg = build_config_from_args(_parse([
        "--dataset", "fixture:herg", "--epochs", "10", "--learning-rate", "0.005",
        "--ensemble-size", "3", "--gate-threshold", "0.75", "--metric", "auc",
    ]))
    assert cfg.hyperparams.epochs == 10
    assert cfg.hyperparams.learning_rate == 0.005
    assert cfg.hyperparams.ensemble_size == 3
    assert cfg.gate_threshold == 0.75


def test_invalid_model_type_rejected_by_validation():
    with pytest.raises(ConfigError):
        build_config_from_args(_parse(["--dataset", "fixture:herg", "--model-type", "magic"]))


def test_main_runs_offline_fixture_with_sklearn_stub(tmp_path, monkeypatch):
    # Drive main() end-to-end without a real ML stack by monkeypatching the
    # trainer; asserts the CLI writes metrics.json and returns a gate exit code.
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")
    import galaxy.ai.ml_training.training_job as tj
    from galaxy.ai.ml_training.chemprop_trainer import TrainingResult

    def fake_train(cfg, ds, artifact_dir):
        return TrainingResult("sklearn_gbr", artifact_dir, {"test_auc": 0.9},
                              len(ds), 0, 0, "stub")
    monkeypatch.setattr(tj, "_default_train", fake_train)

    rc = main([
        "--dataset", "fixture:herg", "--model-type", "sklearn_gbr",
        "--task-type", "classification", "--metric", "auc",
        "--gate-threshold", "0.7", "--out", str(tmp_path),
    ])
    assert rc == 0
    metrics = json.loads((tmp_path / "metrics.json").read_text())
    assert metrics["metrics"]["test_auc"] == 0.9
    assert metrics["gate"]["gates"][0]["status"] == "pass"
