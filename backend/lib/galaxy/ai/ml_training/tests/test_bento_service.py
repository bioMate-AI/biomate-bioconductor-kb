"""Unit tests for the BentoML serving scaffold (bentoml-free core)."""
import pytest

from galaxy.ai.ml_training.bento_service import (
    predict_with_wrapper, PredictResponse, build_bento_service, _bentoml_available,
)
from galaxy.ai.ml_training.chemprop_wrapper import ChempropModelWrapper


def test_predict_with_wrapper_is_framework_agnostic():
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x",
                             predict_fn=lambda s: {x: 0.42 for x in s})
    resp = predict_with_wrapper(w, ["CCO", "CCN"])
    assert isinstance(resp, PredictResponse)
    assert resp.model == "herg"
    assert resp.scores == {"CCO": 0.42, "CCN": 0.42}
    assert resp.to_dict() == {"model": "herg", "scores": {"CCO": 0.42, "CCN": 0.42}}


def test_build_service_requires_bentoml():
    w = ChempropModelWrapper("herg", "camp1", "/tmp/x", predict_fn=lambda s: {x: 0.1 for x in s})
    if _bentoml_available():
        pytest.skip("bentoml installed — build path exercised elsewhere")
    with pytest.raises(ImportError):
        build_bento_service(w)
