"""KN-2 candidate plan tests. Run: python3 test_kn2_plan.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import kn2_make_plan as P
from knowledge_liability_flags import parse_helm

def test_plan_groups_sizes_uniqueness_and_constraints():
    plan = P.build(); g = {}
    for e in plan["peptides"]["avb6_kn2"]: g.setdefault(e["group"], []).append(e)
    assert {k: len(v) for k, v in g.items()} == {"L0": 100, "L1_9": 100, "L1_other": 100, "L2": 100, "L3": 100, "POS": 2, "NEG": 4}, {k: len(v) for k, v in g.items()}
    allh = [e["helm"] for e in plan["peptides"]["avb6_kn2"]]; assert len(set(allh)) == len(allh)
    ring = lambda h: len(h[h.index("(") + 1:h.rindex(")")].split("-"))
    assert all(ring(e["helm"]) == 9 and "R-G-D-L" in e["helm"] for e in g["L1_9"]) and all(ring(e["helm"]) != 9 and "R-G-D-L" in e["helm"] for e in g["L1_other"])
    assert all("R-G-D" in e["helm"] for e in g["L2"]) and all(ring(e["helm"]) == 9 and e["helm"].count("[dP]-[NMeK]") == 1 for e in g["L0"])

def test_pep_sequences_are_length_preserving_and_have_no_unmapped_residue():
    for e in P.build()["peptides"]["avb6_kn2"]:
        res, _, sc = parse_helm(e["helm"]); n = len(e["helm"][e["helm"].index("(") + 1:e["helm"].rindex(")")].split("-"))
        assert len(e["pep"]) == n == len(res) and "X" not in e["pep"] and not sc["unmapped"], e

def test_controls_present_and_deterministic():
    a = P.build(); b = P.build(); assert a == b
    ids = {e["id"] for e in a["peptides"]["avb6_kn2"]}; assert {"CTRL-TRIVEHEXIN", "CTRL-AVEBEHEXIN"} <= ids and sum(i.startswith("NEG-") for i in ids) == 4

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
