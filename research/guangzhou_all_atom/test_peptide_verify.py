"""Unit tests for peptide_verify.py — PURE-LOGIC ONLY.

The heavy scorers (RDKit ensembles on CycPeptMPDB/PepMSND, AWS MM-GBSA/FEP) are MOCKED via the
``_scorers`` injection hook. These tests exercise: the dataclass, aggregation into the property
vector, provenance/uncertainty plumbing, the ``only=`` subset path, and — the important one —
FAIL-SAFE degradation (one broken scorer must NOT crash verify or the other fields).

No GPU, no subprocess, no training data touched. Run: ``python -m pytest test_peptide_verify.py``.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location(
    "peptide_verify", Path(__file__).resolve().parent / "peptide_verify.py")
pv_mod = importlib.util.module_from_spec(_spec)
sys.modules["peptide_verify"] = pv_mod  # dataclass introspection needs the module registered
_spec.loader.exec_module(pv_mod)

verify_peptide = pv_mod.verify_peptide
verify_batch = pv_mod.verify_batch
PropertyValue = pv_mod.PropertyValue
PeptideProperties = pv_mod.PeptideProperties
MEASURED, PREDICTED, PROXY, UNAVAILABLE = (
    pv_mod.MEASURED, pv_mod.PREDICTED, pv_mod.PROXY, pv_mod.UNAVAILABLE)


# ------------------------------------------------------------------ mock scorer builders
def _good_scorers():
    """All four fields succeed with representative provenance tags."""
    return {
        "affinity_dG": lambda ctx: PropertyValue(-34.2, MEASURED, None, "mmgbsa.sh", "kcal/mol"),
        "permeability": lambda ctx: PropertyValue(-5.1, PREDICTED, 0.42, "perm", "log Papp"),
        "synthetic_accessibility": lambda ctx: PropertyValue(3.8, PROXY, None, "sa", "SA"),
        "safety": lambda ctx: PropertyValue(0.71, PROXY, 0.09, "stab", "P(stable)"),
    }


# ------------------------------------------------------------------ dataclass
def test_property_value_ok():
    assert PropertyValue(1.0).ok() is True
    assert PropertyValue(None).ok() is False
    assert PropertyValue(0.0).ok() is True  # zero is a real value, not "missing"


def test_scored_fields_and_completeness():
    p = verify_peptide(seq="ACDEF", _scorers=_good_scorers())
    assert set(p.scored_fields().keys()) == {
        "affinity_dG", "permeability", "synthetic_accessibility", "safety"}
    assert p.is_complete() is True
    assert p.errors == {}


# ------------------------------------------------------------------ aggregation & plumbing
def test_aggregation_values_provenance_uncertainty():
    p = verify_peptide(seq="ACDEF", smiles="CC", identifier="d1", _scorers=_good_scorers())
    assert p.sequence == "ACDEF" and p.smiles == "CC" and p.identifier == "d1"
    assert p.affinity_dG.value == -34.2 and p.affinity_dG.provenance == MEASURED
    assert p.permeability.value == -5.1 and p.permeability.uncertainty == 0.42
    assert p.permeability.provenance == PREDICTED
    assert p.synthetic_accessibility.provenance == PROXY
    assert p.safety.uncertainty == 0.09
    d = p.to_dict()
    assert d["permeability"]["uncertainty"] == 0.42  # nested dataclass serializes


def test_requires_seq_or_smiles():
    with pytest.raises(ValueError):
        verify_peptide(_scorers=_good_scorers())


# ------------------------------------------------------------------ FAIL-SAFE (the core rule)
def test_one_scorer_raises_only_that_field_degrades():
    s = _good_scorers()
    def boom(ctx):
        raise RuntimeError("GPU exploded")
    s["affinity_dG"] = boom
    p = verify_peptide(seq="ACDEF", _scorers=s)
    # broken field degraded, NOT crashed
    assert p.affinity_dG.value is None
    assert p.affinity_dG.provenance == UNAVAILABLE
    assert "GPU exploded" in p.errors["affinity_dG"]
    # every OTHER field still scored fine
    assert p.permeability.value == -5.1
    assert p.safety.value == 0.71
    assert p.is_complete() is False


def test_all_scorers_raise_still_returns_object():
    def boom(ctx):
        raise ValueError("nope")
    s = {k: boom for k in _good_scorers()}
    p = verify_peptide(smiles="CC", _scorers=s)
    assert isinstance(p, PeptideProperties)
    assert all(not pvv.ok() for pvv in p.scored_fields().values())
    assert len(p.errors) == 4


def test_scorer_returning_unavailable_with_reason_surfaces_in_errors():
    s = _good_scorers()
    s["affinity_dG"] = lambda ctx: PropertyValue(
        None, UNAVAILABLE, detail="no physics result JSON supplied")
    p = verify_peptide(seq="ACDEF", _scorers=s)
    assert p.affinity_dG.value is None
    assert "no physics result JSON" in p.errors["affinity_dG"]


def test_scorer_returning_wrong_type_is_caught():
    s = _good_scorers()
    s["safety"] = lambda ctx: {"value": 0.5}  # not a PropertyValue
    p = verify_peptide(seq="ACDEF", _scorers=s)
    assert p.safety.value is None
    assert "TypeError" in p.errors["safety"]
    assert p.permeability.value == -5.1  # others unaffected


# ------------------------------------------------------------------ only= subset (A3 pre-filter)
def test_only_subset_scores_requested_fields_only():
    p = verify_peptide(seq="ACDEF", only=["permeability", "synthetic_accessibility"],
                       _scorers=_good_scorers())
    assert p.permeability.value == -5.1
    assert p.synthetic_accessibility.value == 3.8
    # unrequested fields remain default/unavailable
    assert p.affinity_dG.value is None
    assert p.affinity_dG.provenance == UNAVAILABLE
    assert p.safety.value is None


def test_unknown_field_in_only_records_error():
    p = verify_peptide(seq="ACDEF", only=["permeability", "bogus"], _scorers=_good_scorers())
    assert p.permeability.value == -5.1
    assert "no scorer registered" in p.errors["bogus"]


# ------------------------------------------------------------------ ctx wiring
def test_context_passed_to_scorers():
    seen = {}
    def capture(ctx):
        seen.update(ctx)
        return PropertyValue(1.0, MEASURED)
    verify_peptide(seq="AC", smiles="CC", identifier="x1",
                   physics_json="/tmp/does_not_matter.json", _scorers={"affinity_dG": capture})
    assert seen["identifier"] == "x1"
    assert seen["seq"] == "AC" and seen["smiles"] == "CC"
    assert str(seen["physics_json"]).endswith("does_not_matter.json")


# ------------------------------------------------------------------ batch fail-safe
def test_verify_batch_per_candidate_and_per_field_failsafe():
    s = _good_scorers()
    results = verify_batch(
        [{"seq": "ACDEF", "identifier": "a"},
         {"identifier": "b"},          # no seq/smiles -> candidate-level error, batch survives
         {"smiles": "CC", "identifier": "c"}],
        _scorers=s)
    assert len(results) == 3
    assert results[0].is_complete() is True
    assert results[1].errors.get("_candidate")           # bad candidate captured, not raised
    assert results[1].affinity_dG.value is None
    assert results[2].is_complete() is True
