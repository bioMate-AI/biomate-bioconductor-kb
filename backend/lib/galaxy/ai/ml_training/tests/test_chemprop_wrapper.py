"""Unit tests for the trained-model → BaseModelWrapper bridge."""
import json

import pytest

from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper
from galaxy.ai.drug_discovery.custom_model_wrapper import BaseModelWrapper


def test_wrapper_is_base_model_wrapper():
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x", predict_fn=lambda s: {x: 0.5 for x in s})
    assert isinstance(w, BaseModelWrapper)
    assert w._mode() == "python"


def test_injected_predict_fn_scores_and_coerces_float():
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x",
                             predict_fn=lambda s: {x: 1 for x in s})  # int → coerced
    out = w.score(["CCO", "c1ccccc1"])
    assert out == {"CCO": 1.0, "c1ccccc1": 1.0}
    assert all(isinstance(v, float) for v in out.values())


def test_run_produces_audit_record():
    # BaseModelWrapper.run() wraps score() with a ModelRunRecord audit trail.
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x", predict_fn=lambda s: {x: 0.2 for x in s})
    scores, record = w.run(["CCO"])
    assert scores == {"CCO": 0.2}
    assert record.success is True
    assert record.model_name == "herg"
    assert record.mode == "python"


def test_non_dict_predict_fn_rejected():
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x", predict_fn=lambda s: [0.1])
    with pytest.raises(ValueError):
        w.score(["CCO"])


def test_missing_manifest_raises(tmp_path):
    w = ChempropModelWrapper("herg", "camp1", str(tmp_path))  # no predict_fn → must load
    with pytest.raises(FileNotFoundError):
        w.score(["CCO"])


def test_chemprop_artifact_load_is_serving_stub(tmp_path):
    (tmp_path / "manifest.json").write_text(json.dumps({"model_type": "chemprop_gnn"}))
    w = ChempropModelWrapper("herg", "camp1", str(tmp_path))
    with pytest.raises(NotImplementedError):
        w.score(["CCO"])
