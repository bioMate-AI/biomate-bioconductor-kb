"""Tests for the feature-flagged router entry used by ai_assistant.

Locks the generate_workflow_unified-shaped contract the hook returns, and the
flag gating — so the (unimportable-here) ai_assistant hook stays a thin
delegate whose behaviour is fully covered by these tests.
"""
import pytest

from galaxy.ai.ml_training.routing import route_ml_training_result


def test_disabled_flag_returns_none_even_for_training_intent():
    assert route_ml_training_result("train a hERG classifier", enabled=False) is None


def test_enabled_training_intent_returns_unified_shaped_result():
    r = route_ml_training_result("train a classifier for hERG blockers", enabled=True)
    assert r is not None
    # exact keys generate_workflow_unified callers expect
    assert set(r) == {"success", "workflow_ga", "source", "confidence",
                      "message", "datasets_assigned"}
    assert r["success"] is True
    assert r["source"] == "ml_training"
    assert r["confidence"] == 1.0
    assert r["datasets_assigned"] is False
    assert r["workflow_ga"]["domain"] == "ml_training"
    assert r["message"]  # rationale carried through, non-empty


def test_enabled_non_training_intent_returns_none():
    assert route_ml_training_result("predict hERG for aspirin", enabled=True) is None


def test_enabled_but_unresolvable_dataset_returns_none():
    # training intent, no recognised assay / no data → fall through to normal search
    assert route_ml_training_result("train a classifier for my endpoint", enabled=True) is None


def test_env_flag_default_off(monkeypatch):
    monkeypatch.delenv("ML_TRAINING_ROUTING", raising=False)
    assert route_ml_training_result("train a hERG classifier") is None


def test_env_flag_on(monkeypatch):
    monkeypatch.setenv("ML_TRAINING_ROUTING", "1")
    r = route_ml_training_result("train a hERG classifier")
    assert r is not None and r["source"] == "ml_training"


def test_user_data_flows_into_workflow_ga(monkeypatch):
    monkeypatch.setenv("ML_TRAINING_ROUTING", "1")
    r = route_ml_training_result("train a hERG classifier on my data",
                                 dataset_s3_uri="s3://b/mine.csv")
    ds = r["workflow_ga"]["required_params"]
    dataset_val = next(p["value"] for p in ds if p["name"] == "dataset")
    assert dataset_val == "s3://b/mine.csv"
