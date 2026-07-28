"""Unit tests for the TrainingConfig → /api/nextflow/execute payload bridge."""
import pytest

from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec
from galaxy.ai.ml_training.executor_payload import (
    build_execute_request, resolve_dataset_param, DEFAULT_NEXTFLOW_PATH,
)


def _cfg(**over):
    base = dict(name="hERG clf", campaign_id="camp1",
                dataset=DatasetSpec(name="tdc:hERG", target_col="y"))
    base.update(over)
    return TrainingConfig(**base)


def test_payload_has_required_execute_fields():
    req = build_execute_request(_cfg(), user_id="u1")
    assert req["nextflow_path"] == DEFAULT_NEXTFLOW_PATH
    assert req["workflow_domain"] == "ml_training"
    assert req["user_id"] == "u1"
    assert req["compute_config"]["executor"] == "awsbatch"
    # container points at the ml-training image so the TRAIN process has the deps
    assert "biomate/ml-training" in req["compute_config"]["container"]
    # training params are flat scalars
    p = req["parameters"]
    assert p["dataset"] == "tdc:hERG"
    assert p["target_col"] == "y"
    assert p["model_type"] == "chemprop_gnn"
    assert p["epochs"] == 50
    assert all(not isinstance(v, (list, dict)) for v in p.values())


def test_s3_uri_overrides_dataset_param():
    req = build_execute_request(_cfg(), user_id="u1",
                                s3_dataset_uri="s3://bkt/staged/herg.csv")
    assert req["parameters"]["dataset"] == "s3://bkt/staged/herg.csv"


def test_resolve_dataset_prefers_staged_then_spec():
    cfg = _cfg(dataset=DatasetSpec(s3_uri="s3://a/x.csv", target_col="y"))
    assert resolve_dataset_param(cfg) == "s3://a/x.csv"
    assert resolve_dataset_param(cfg, "s3://b/y.csv") == "s3://b/y.csv"  # staged wins


def test_no_dataset_source_raises():
    cfg = _cfg()
    cfg.dataset = DatasetSpec.__new__(DatasetSpec)  # bypass to empty
    cfg.dataset.name = cfg.dataset.path = cfg.dataset.s3_uri = None
    cfg.dataset.smiles_col = "smiles"; cfg.dataset.target_col = "y"
    cfg.dataset.split = "scaffold"; cfg.dataset.val_frac = 0.1; cfg.dataset.test_frac = 0.1
    with pytest.raises(ValueError):
        resolve_dataset_param(cfg)


def test_aws_batch_queue_and_gate_ride_through():
    req = build_execute_request(_cfg(gate_threshold=0.7, metric="auc"),
                                user_id="u1", aws_batch_queue="gpu-queue")
    assert req["compute_config"]["aws_batch_queue"] == "gpu-queue"
    assert req["qc_overrides"]["ml_gate"] == {"metric": "auc", "threshold": 0.7}


def test_container_env_override(monkeypatch):
    monkeypatch.setenv("ML_TRAINING_IMAGE", "myregistry/custom-train:v2")
    req = build_execute_request(_cfg(), user_id="u1")
    assert req["compute_config"]["container"] == "myregistry/custom-train:v2"


def test_no_gate_means_no_qc_overrides_key():
    req = build_execute_request(_cfg(gate_threshold=None), user_id="u1")
    assert "qc_overrides" not in req


def test_is_pilot_flag_propagates():
    assert build_execute_request(_cfg(), user_id="u1", is_pilot=True)["is_pilot"] is True
