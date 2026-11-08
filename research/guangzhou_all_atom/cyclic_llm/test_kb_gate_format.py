"""Regression test: methodology_close.to_helm must produce a string the gate providers actually parse
(a one-token parse silently turned kb_admissible into a no-op / reject-all). Run: python3 test_kb_gate_format.py"""
import sys; sys.path.insert(0, ".")
import methodology_close as mc, score as sc
from acceptance_gate import raw_tokens, avb6_gate

def test_tokens_are_per_residue():
    m = ["F", "R", "G", "D", "L", "A", "F", "dP", "NMeK"]
    assert len(raw_tokens(mc.to_helm(m))) == len(m), "to_helm must yield one token per monomer"

def test_valid_rgd_peptide_passes_avb6_rule():
    assert avb6_gate(mc.to_helm(["F", "R", "G", "D", "L", "A", "F", "dP", "NMeK"]))["PASS_H1_H5"]

def test_non_rgd_rejected():
    assert not mc.kb_admissible(list("AAAAAAAAA"), "avb6")[0]

def test_liabilities_detected():
    assert "deamidation" in sc.developability(mc.to_helm(list("ANGAAFAAA")))["liabilities"]
    assert not mc.kb_admissible(list("ANGAAFAAA"), None)[0], "developability gate must reject Asn-Gly"
    assert not mc.kb_admissible(list("AWAAWFAAA"), None)[0], "developability gate must reject double Trp"

def test_benign_passes():
    assert mc.kb_admissible(list("AAFAAGAAA"), None)[0]

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"):
            f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
