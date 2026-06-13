"""B1 smoke + correctness."""
from __future__ import annotations
import pytest
from galaxy.ai.drug_discovery.mrsd_calculator import (
    compute_mrsd, compute_mrsd_tool_schema, DEFAULT_SAFETY_FACTOR,
)
from galaxy.ai.drug_discovery.mrsd_verifier import verify_mrsd


def test_rat_canonical():
    # FDA 2005 worked example: rat NOAEL 6 mg/kg → HED ~0.968 → MRSD ~0.0968
    r = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    assert r.species == "rat"
    assert abs(r.hed_mg_per_kg - 0.968) < 0.01
    assert abs(r.mrsd_mg_per_kg - 0.0968) < 0.001
    assert abs(r.mrsd_mg_per_patient - 5.8) < 0.2


def test_mouse_higher_divisor_lower_hed():
    rm = compute_mrsd(noael_mg_per_kg=6.0, species="mouse")
    rr = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    assert rm.hed_mg_per_kg < rr.hed_mg_per_kg


def test_dog_lower_divisor_higher_hed():
    rd = compute_mrsd(noael_mg_per_kg=6.0, species="dog")
    rr = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    assert rd.hed_mg_per_kg > rr.hed_mg_per_kg


def test_safety_factor_below_default_warns():
    r = compute_mrsd(noael_mg_per_kg=6.0, species="rat", safety_factor=5)
    assert any("safety_factor_below_default" in n for n in r.notes)


def test_invalid_inputs_raise():
    with pytest.raises(ValueError):
        compute_mrsd(noael_mg_per_kg=0, species="rat")
    with pytest.raises(ValueError):
        compute_mrsd(noael_mg_per_kg=-1, species="rat")
    with pytest.raises(ValueError):
        compute_mrsd(noael_mg_per_kg=6, species="rat", safety_factor=0)
    with pytest.raises(ValueError, match="unknown_species"):
        compute_mrsd(noael_mg_per_kg=6, species="capybara")


def test_species_alias_normalisation():
    r1 = compute_mrsd(noael_mg_per_kg=6.0, species="rats")
    r2 = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    assert abs(r1.hed_mg_per_kg - r2.hed_mg_per_kg) < 1e-9


def test_to_prose_mentions_keywords():
    r = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    prose = r.to_prose()
    for kw in ("rat", "NOAEL", "HED", "MRSD", "60-kg"):
        assert kw in prose


def test_verifier_agrees_with_calculator():
    """Round-trip: prose from calculator must pass the post-hoc verifier."""
    r = compute_mrsd(noael_mg_per_kg=6.0, species="rat")
    finding = verify_mrsd(r.to_prose())
    assert finding.grounded
    assert finding.issues == [], f"verifier disagrees: {finding.issues}"


def test_tool_schema_well_formed():
    s = compute_mrsd_tool_schema()
    assert s["type"] == "function"
    assert s["function"]["name"] == "compute_mrsd"
    required = s["function"]["parameters"]["required"]
    assert "noael_mg_per_kg" in required
    assert "species" in required
    assert "safety_factor" not in required
    assert "human_weight_kg" not in required
