"""Unit tests for the MLflow tracker's no-op fallback (no mlflow install needed)."""
import os

import pytest

from galaxy.ai.ml_training.mlflow_tracker import MLflowTracker, _flatten


@pytest.fixture(autouse=True)
def _force_noop(monkeypatch):
    # Guarantee the in-memory no-op path regardless of whether mlflow is installed.
    monkeypatch.setenv("BIOMATE_MLFLOW_DISABLED", "1")


def test_noop_tracker_records_params_and_metrics():
    with MLflowTracker(experiment="test-exp", run_name="run1") as t:
        assert t.active is False
        t.log_params({"model_type": "chemprop_gnn", "hyperparams": {"epochs": 10}})
        t.log_metrics({"val_auc": 0.83, "test_auc": None})  # None dropped
        t.log_artifact("/tmp/artifacts")
        uri = t.register_model("/tmp/artifacts/model", registered_name="herg")
    # nested params flattened
    assert t.logged_params["model_type"] == "chemprop_gnn"
    assert t.logged_params["hyperparams.epochs"] == 10
    # None metric filtered out
    assert t.logged_metrics == {"val_auc": 0.83}
    assert "/tmp/artifacts" in t.logged_artifacts
    assert uri and uri.startswith("runs:/")
    assert t.registered_model_uri == uri


def test_flatten_nested_dict():
    flat = _flatten({"a": 1, "b": {"c": 2, "d": {"e": 3}}})
    assert flat == {"a": 1, "b.c": 2, "b.d.e": 3}
