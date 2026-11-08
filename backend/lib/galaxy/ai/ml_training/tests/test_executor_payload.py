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
    assert req["parameters"]["gate_threshold"] == 0.7  # CLI evaluates the same gate as executor QC


def test_container_env_override(monkeypatch):
    monkeypatch.setenv("ML_TRAINING_IMAGE", "myregistry/custom-train:v2")
    req = build_execute_request(_cfg(), user_id="u1")
    assert req["compute_config"]["container"] == "myregistry/custom-train:v2"


def test_no_gate_means_no_qc_overrides_key():
    req = build_execute_request(_cfg(gate_threshold=None), user_id="u1")
    assert "qc_overrides" not in req
    assert req["parameters"]["gate_threshold"] is None


def test_is_pilot_flag_propagates():
    assert build_execute_request(_cfg(), user_id="u1", is_pilot=True)["is_pilot"] is True


def test_card_and_direct_executor_preserve_selected_identity_gate_split_and_hyperparameters():
    cfg = _cfg(gate_threshold=0.72, metric="auc", name="Hospital tumor classifier",
               model_type="sklearn_tabular", featurizer="none")
    cfg.dataset.split = "kfold"
    cfg.dataset.cv_folds = 3
    cfg.hyperparams.seed = 91
    cfg.hyperparams.batch_size = 7
    card = cfg.to_workflow_ga()
    direct = build_execute_request(cfg, user_id="owner")
    assert card["parameters"] == direct["parameters"]
    assert card["parameters"]["model_name"] == cfg.name
    assert card["parameters"]["metric"] == cfg.metric
    assert card["parameters"]["gate_threshold"] == 0.72
    assert card["parameters"]["cv_folds"] == 3
    assert card["parameters"]["seed"] == 91
    assert card["parameters"]["batch_size"] == 7
    row_values = {row["name"]: row.get("value") for row in card["optional_params"]}
    assert row_values["model_name"] == cfg.name
    assert row_values["metric"] == cfg.metric
    assert row_values["gate_threshold"] == 0.72


def test_llm_card_contains_actual_task_and_model_identity():
    from galaxy.ai.ml_training.config import LLMSpec
    cfg = _cfg(name="Hospital language model", model_type="ludwig_llm", task_type="text_generation",
               llm=LLMSpec(), metric="loss")
    card = cfg.to_workflow_ga()
    rows = {row["name"]: row.get("value") for row in card["optional_params"]}
    assert rows["task_type"] == "text_generation"
    assert card["parameters"]["task_type"] == "text_generation"
    assert card["parameters"]["model_name"] == cfg.name
    assert card["parameters"]["metric"] == "loss"
