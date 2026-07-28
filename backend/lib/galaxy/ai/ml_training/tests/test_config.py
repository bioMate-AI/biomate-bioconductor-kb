"""Unit tests for the declarative TrainingConfig (low-code surface)."""
import pytest

from galaxy.ai.ml_training.config import (
    TrainingConfig, DatasetSpec, Hyperparams, ConfigError,
    MODEL_TYPES, TASK_TYPES,
)


def _valid_cfg(**over):
    base = dict(
        name="hERG blocker classifier",
        dataset=DatasetSpec(name="tdc:hERG", target_col="y"),
    )
    base.update(over)
    return TrainingConfig(**base)


def test_valid_config_passes_validation():
    cfg = _valid_cfg().validate()
    assert cfg.name.startswith("hERG")
    assert cfg.model_type in MODEL_TYPES
    assert cfg.task_type in TASK_TYPES


def test_missing_name_rejected():
    with pytest.raises(ConfigError):
        _valid_cfg(name="  ").validate()


def test_bad_model_type_rejected():
    with pytest.raises(ConfigError):
        _valid_cfg(model_type="magic_net").validate()


def test_dataset_requires_exactly_one_source():
    # zero sources
    with pytest.raises(ConfigError):
        DatasetSpec().validate()
    # two sources
    with pytest.raises(ConfigError):
        DatasetSpec(name="tdc:hERG", path="/tmp/x.csv").validate()
    # exactly one → ok
    assert DatasetSpec(path="/tmp/x.csv").source_kind() == "path"


def test_dataset_split_fractions_must_leave_training_room():
    with pytest.raises(ConfigError):
        DatasetSpec(name="tdc:hERG", val_frac=0.6, test_frac=0.5).validate()


def test_hyperparam_bounds():
    with pytest.raises(ConfigError):
        Hyperparams(epochs=0).validate()
    with pytest.raises(ConfigError):
        Hyperparams(dropout=1.0).validate()
    with pytest.raises(ConfigError):
        Hyperparams(learning_rate=0).validate()


def test_roundtrip_to_from_dict():
    cfg = _valid_cfg(gate_threshold=0.75)
    d = cfg.to_dict()
    cfg2 = TrainingConfig.from_dict(d)
    cfg2.validate()
    assert cfg2.to_dict() == d
    assert isinstance(cfg2.dataset, DatasetSpec)
    assert isinstance(cfg2.hyperparams, Hyperparams)


def test_workflow_ga_param_contract_shape():
    cfg = _valid_cfg()
    params = cfg.to_workflow_ga_params()
    assert set(params) == {"required_params", "optional_params"}
    req_names = {p["name"] for p in params["required_params"]}
    assert {"dataset", "target_col"} <= req_names
    # select params expose allowed_values for the frontend dropdown renderer
    model_param = next(p for p in params["optional_params"] if p["name"] == "model_type")
    assert model_param["type"] == "select"
    assert set(MODEL_TYPES) <= set(model_param["allowed_values"])


def test_workflow_ga_stub_has_ml_training_domain():
    ga = _valid_cfg().to_workflow_ga()
    assert ga["domain"] == "ml_training"
    assert ga["format"] == "nextflow"
    assert ga["nextflow_path"].startswith("ml_training/")
    assert "required_params" in ga and "optional_params" in ga
