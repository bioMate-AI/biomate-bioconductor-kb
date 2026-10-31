"""Unit tests for the end-to-end orchestrator wiring (no ML stack needed).

Heavy steps are injected as stubs; the tests assert the orchestration:
MLflow logging, QC-gate evaluation, and gated registry registration.
"""
import pytest

from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec
from galaxy.ai.ml_training.datasets import LoadedDataset
from galaxy.ai.ml_training.chemprop_trainer import TrainingResult
from galaxy.ai.ml_training.mlflow_tracker import MLflowTracker
from galaxy.ai.ml_training import training_job


@pytest.fixture(autouse=True)
def _noop_mlflow(monkeypatch):
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")


@pytest.fixture(autouse=True)
def _artifact_root(tmp_path, monkeypatch):
    monkeypatch.setenv("ML_TRAINING_ARTIFACT_ROOT", str(tmp_path / "artifacts"))


def _registry(tmp_path):
    from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry
    return CustomModelRegistry(str(tmp_path / "reg.db"))


def _stub_load(_spec):
    return LoadedDataset([("CCO", 0.0), ("c1ccccc1", 1.0)], "smiles", "y", source="stub")


def _make_train_stub(metrics):
    def _train(cfg, dataset, artifact_dir):
        return TrainingResult(
            model_type=cfg.model_type, artifact_dir=artifact_dir, metrics=metrics,
            n_train=len(dataset), n_val=0, n_test=0, framework_version="stub==0",
        )
    return _train


def _cfg(tmp_path, **over):
    base = dict(name="hERG clf", campaign_id="camp1",
                dataset=DatasetSpec(name="fixture:herg", target_col="y"),
                metric="auc")
    base.update(over)
    return TrainingConfig(**base)


def test_full_loop_logs_and_registers_on_gate_pass(tmp_path):
    cfg = _cfg(tmp_path, gate_threshold=0.7)
    reg = _registry(tmp_path)
    tracker = MLflowTracker(run_name=cfg.name)
    result = training_job.run_training_job(
        cfg, registry=reg,
        load_fn=_stub_load, train_fn=_make_train_stub({"val_auc": 0.83}), tracker=tracker,
    )
    # gate passed (0.83 >= 0.7, higher-is-better metric) → candidate v1, not yet served
    assert result.gate.passed is True
    assert result.registered is True
    assert (result.model_version, result.model_status) == (1, "candidate")
    mv = reg.get_version("camp1", "hERG clf", 1)
    assert mv.artifact_dir == result.artifact_dir and mv.artifact_sha256
    assert mv.dataset_sha256 and mv.gate["passed"] is True
    assert reg.get_active_version("camp1", "hERG clf") is None
    # MLflow received params + metrics + gate flag
    assert tracker.logged_params["model_type"] == "chemprop_gnn"
    assert tracker.logged_metrics["val_auc"] == 0.83
    assert tracker.logged_metrics["gate_passed"] == 1.0


def test_gate_fail_does_not_register(tmp_path):
    cfg = _cfg(tmp_path, gate_threshold=0.9)
    reg = _registry(tmp_path)
    result = training_job.run_training_job(
        cfg, registry=reg,
        load_fn=_stub_load, train_fn=_make_train_stub({"val_auc": 0.60}),
    )
    assert result.gate.passed is False           # 0.60 < 0.90
    assert result.registered is False
    assert result.model_status == "rejected"
    assert reg.get_active_version("camp1", "hERG clf") is None


def test_training_failure_rejects_reserved_version(tmp_path):
    reg = _registry(tmp_path)

    def _boom(cfg, dataset, artifact_dir):
        raise NotImplementedError("no trainer")

    with pytest.raises(NotImplementedError):
        training_job.run_training_job(_cfg(tmp_path), registry=reg,
                                      load_fn=_stub_load, train_fn=_boom)
    mv = reg.get_version("camp1", "hERG clf", 1)
    assert mv.status == "rejected" and "training_failed" in mv.status_note


def test_no_gate_threshold_passes_by_default(tmp_path):
    cfg = _cfg(tmp_path, gate_threshold=None)
    result = training_job.run_training_job(
        cfg, artifact_dir=str(tmp_path), registry=None,
        load_fn=_stub_load, train_fn=_make_train_stub({"val_auc": 0.5}),
    )
    assert result.gate.passed is True


def test_lower_is_better_metric_direction(tmp_path):
    # MAE: lower is better → 0.3 passes a threshold of 0.5, 0.7 fails it
    cfg = _cfg(tmp_path, task_type="regression", metric="mae", gate_threshold=0.5)
    passing = training_job.run_training_job(
        cfg, artifact_dir=str(tmp_path), load_fn=_stub_load,
        train_fn=_make_train_stub({"test_mae": 0.3}))
    failing = training_job.run_training_job(
        cfg, artifact_dir=str(tmp_path), load_fn=_stub_load,
        train_fn=_make_train_stub({"test_mae": 0.7}))
    assert passing.gate.passed is True
    assert failing.gate.passed is False
    assert passing.gate.direction == "lower_is_better"


def test_gate_result_sse_payload_shape(tmp_path):
    cfg = _cfg(tmp_path, gate_threshold=0.7)
    result = training_job.run_training_job(
        cfg, artifact_dir=str(tmp_path), load_fn=_stub_load,
        train_fn=_make_train_stub({"val_auc": 0.83}))
    payload = result.gate.to_sse_payload()
    assert "gates" in payload and len(payload["gates"]) == 1
    g = payload["gates"][0]
    assert g["name"] == "auc"
    assert g["measured"] == 0.83
    assert g["status"] == "pass"
