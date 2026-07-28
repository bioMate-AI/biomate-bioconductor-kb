"""Unit tests for rule-first ml_training intent routing."""
import pytest

from galaxy.ai.ml_training.routing import (
    detect_training_intent, extract_training_config, route_ml_training,
)


@pytest.mark.parametrize("text,expected", [
    ("Train a classifier to predict hERG blockers", True),
    ("build a QSAR model for solubility", True),
    ("fine-tune a GNN on my compounds", True),
    ("predict hERG for these SMILES", False),         # inference, not training
    ("screen this library for ADMET", False),
    ("what is the logP of aspirin?", False),
    ("", False),
])
def test_intent_detection(text, expected):
    assert detect_training_intent(text) is expected


def test_herg_alias_maps_to_tdc_classification():
    cfg = extract_training_config("train a model to classify hERG blockers")
    assert cfg.dataset.name == "tdc:hERG"
    assert cfg.task_type == "classification"
    assert cfg.model_type == "ludwig_tabular"   # default DL = CPU-runnable Ludwig
    assert cfg.metric == "auc"


def test_chemprop_is_opt_in_by_mention():
    cfg = extract_training_config("train a chemprop GNN to classify hERG blockers")
    assert cfg.model_type == "chemprop_gnn"


def test_regression_alias_maps_correctly():
    cfg = extract_training_config("build a model for Caco2 permeability")
    assert cfg.dataset.name == "tdc:Caco2_Wang"
    assert cfg.task_type == "regression"
    assert cfg.metric == "mae"


def test_baseline_hint_selects_sklearn():
    cfg = extract_training_config("train a quick baseline classifier for hERG")
    assert cfg.model_type == "sklearn_gbr"


def test_user_data_overrides_alias_dataset_but_keeps_target():
    cfg = extract_training_config("train a hERG classifier on my data",
                                  dataset_s3_uri="s3://b/mine.csv")
    assert cfg.dataset.s3_uri == "s3://b/mine.csv"
    assert cfg.dataset.target_col == "Y"   # from hERG alias


def test_regression_hint_without_alias():
    cfg = extract_training_config("train a model to predict IC50 values",
                                  dataset_s3_uri="s3://b/x.csv")
    assert cfg.task_type == "regression"


def test_unresolvable_dataset_raises_without_llm():
    with pytest.raises(ValueError):
        extract_training_config("train a classifier for my target")


def test_llm_fallback_fills_dataset_gap():
    def fake_llm(_text):
        return {"dataset": "tdc:AMES", "task_type": "classification", "target_col": "Y"}
    cfg = extract_training_config("train a mutagenicity model", llm_fill=fake_llm)
    assert cfg.dataset.name == "tdc:AMES"


def test_route_returns_workflow_ga_for_training_intent():
    ga = route_ml_training("train a classifier for hERG blockers")
    assert ga is not None
    assert ga["domain"] == "ml_training"
    assert "required_params" in ga and "scientific_rationale" in ga


def test_route_returns_none_for_non_training():
    assert route_ml_training("predict hERG for aspirin") is None


def test_route_returns_none_when_ambiguous():
    # training intent but no resolvable dataset → fall through to normal router
    assert route_ml_training("train a classifier for my custom endpoint") is None
