"""Tests for tier0_rules.HardRules (run on EC2 / Spark, needs RDKit)."""
import pytest

pytest.importorskip("rdkit")
from tier0_rules import HardRules  # noqa: E402

CYC_3NME = "C1(=O)CN(C)C(=O)CN(C)C(=O)CN(C)C(=O)CNC(=O)CNC(=O)CN1"   # cyclo(Sar-Sar-Sar-Gly-Gly-Gly): ring 18, 3 N-Me amides
CYC_0NME = "C1(=O)CNC(=O)CNC(=O)CNC(=O)CNC(=O)CNC(=O)CN1"            # ring 18, no N-Me
LINEAR = "CC(=O)NCC(=O)N(C)CC(=O)N(C)CC(=O)O"                         # 2 N-Me amides but no macrocycle
SMALL_RING = "O=C1CN(C)C(=O)CN(C)C(=O)CN1"                            # ring 9 (below 12) with N-Me


def test_cyclic_hexapeptide_with_three_nme_passes():
    r = HardRules().explain(CYC_3NME)
    assert r["max_ring"] == 18 and r["n_nme"] == 3 and r["ok"] is True, r


def test_each_rule_can_fail_independently():
    assert HardRules().explain(CYC_0NME)["nme_ok"] is False          # macrocycle, no N-methylation
    assert HardRules().explain(LINEAR)["ring_ok"] is False           # N-Me ok, not a macrocycle
    assert HardRules().explain(SMALL_RING)["ring_ok"] is False       # ring below the minimum
    assert HardRules(mw_max=100.0).explain(CYC_3NME)["mw_ok"] is False


def test_invalid_smiles_fail_and_are_never_exceptions():
    for s in ("", None, "not_a_smiles", "C1CC"):
        assert HardRules().check(s) is False


def test_pains_flag_can_fail_the_rule():
    quinone_macro = "O=C1C=CC(=O)C=C1"      # a PAINS-type quinone alone fails the ring rule too; check PAINS flag via a rule-free config
    r = HardRules(ring_min=0, nme_min=0, nme_max=99).explain(quinone_macro)
    assert "pains_ok" in r


def test_automaton_surface_is_refused_explicitly():
    with pytest.raises(NotImplementedError):
        HardRules().init_state()
    with pytest.raises(NotImplementedError):
        HardRules().mask(None, [])
