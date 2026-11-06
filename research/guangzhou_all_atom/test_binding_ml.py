"""Unit tests for the G3 learned-binding wiring (binding_ml.py + peptide_verify.affinity_ml).

The honesty contract is the thing under test: affinity_ml is an ADVISORY channel that (1) is NOT
part of the gated property vector, (2) is NOT a selection objective, (3) is flagged out-of-domain /
low-confidence for novel targets, and (4) degrades gracefully when xgboost/model are absent. No GPU;
xgboost need not be installed (the model path is mocked / allowed to degrade).
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pytest

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bml = _load("binding_ml")
pv = _load("peptide_verify")
sel = _load("peptide_select")

_RDKIT = True
try:
    import rdkit  # noqa: F401
except Exception:  # noqa: BLE001
    _RDKIT = False


# ---------------------------------------------------------------- applicability domain
def test_tanimoto_bounds():
    a = np.array([1, 1, 0, 0], np.uint8)
    ref = np.array([[1, 1, 0, 0], [0, 0, 1, 1]], np.uint8)
    assert bml.tanimoto_max(a, ref) == 1.0
    assert bml.tanimoto_max(a, np.zeros((0, 4))) == 0.0


def test_in_domain_requires_both_target_and_ligand():
    a = np.array([1, 1, 1, 0, 0], np.uint8)
    ref = np.array([[1, 1, 1, 0, 0]], np.uint8)  # identical -> ligand in AD
    assert bml.applicability(a, target_in_distribution=True, _ref_override=ref)["status"] == "in_domain"
    # novel target overrides a familiar ligand
    v = bml.applicability(a, target_in_distribution=False, _ref_override=ref)
    assert v["status"] == "out_of_domain" and v["low_confidence"] is True


def test_novel_ligand_is_out_of_domain():
    cand = np.array([0, 0, 0, 1, 0], np.uint8)
    ref = np.array([[1, 1, 1, 0, 0]], np.uint8)
    v = bml.applicability(cand, target_in_distribution=True, _ref_override=ref, ad_threshold=0.5)
    assert v["ligand_in_domain"] is False and v["status"] == "out_of_domain"


def test_no_fingerprint_is_unknown():
    v = bml.applicability(None, target_in_distribution=True)
    assert v["status"] == "unknown" and v["low_confidence"] is True


# ---------------------------------------------------------------- prediction graceful degrade
def test_missing_model_degrades_without_raising():
    val, info = bml.predict_paffinity("ACDEF", None, model_path="/no/such/model.pkl")
    assert val is None and "error" in info


@pytest.mark.skipif(not _RDKIT, reason="rdkit needed to build features")
def test_mocked_predictor_feature_wiring():
    class _Stub:
        def predict(self, x):
            assert x.shape[1] == 2068  # ECFP4(2048)+16 desc+4 assay one-hot
            return np.array([7.5], np.float32)
    bundle = {"model": _Stub(), "assay_types": ["IC50", "Ki", "EC50", "Kd"], "feat_dim": 2068}
    val, info = bml.predict_paffinity("ACDEFGHIK", None, _bundle=bundle, assay_type="Kd")
    assert val == 7.5


# ---------------------------------------------------------------- honesty-by-construction in verify
def test_affinity_ml_not_in_gated_vector_or_objectives():
    p = pv.verify_peptide(seq="ACDEF", only=["synthetic_accessibility"])
    assert "affinity_ml" not in p.scored_fields()          # excluded from is_complete()
    assert "affinity_ml" in p.extra_fields()               # present as an advisory channel
    assert "affinity_ml" not in sel.OBJECTIVE_DIRECTIONS    # never a selection objective


def test_opt_in_off_by_default_leaves_affinity_ml_untouched():
    p = pv.verify_peptide(seq="ACDEF", only=["synthetic_accessibility"])
    assert p.affinity_ml.value is None
    assert p.affinity_ml.provenance == pv.UNAVAILABLE
    assert p.affinity_ml.applicability is None  # scorer never ran


@pytest.mark.skipif(not _RDKIT, reason="rdkit needed for the AD fingerprint")
def test_novel_target_flagged_low_confidence_when_opted_in():
    # xgboost may be absent -> value None, but the AD verdict must still be computed + flagged.
    p = pv.verify_peptide(seq="ACDEFGHIK", score_ml_affinity=True,
                          only=["synthetic_accessibility"])  # novel target by default
    assert p.affinity_ml.applicability in ("out_of_domain", "unknown")
    assert p.affinity_ml.low_confidence is True
    # whatever happens, it never corrupts the gated fields
    assert p.synthetic_accessibility.ok()


def test_mocked_scorers_path_skips_ml_channel():
    # injecting _scorers (test hook) must not trigger the ml channel (keeps mocked tests clean)
    scorers = {"affinity_dG": lambda ctx: pv.PropertyValue(-30.0, pv.MEASURED)}
    p = pv.verify_peptide(seq="ACDEF", score_ml_affinity=True, _scorers=scorers)
    assert p.affinity_ml.applicability is None  # not run under _scorers injection
