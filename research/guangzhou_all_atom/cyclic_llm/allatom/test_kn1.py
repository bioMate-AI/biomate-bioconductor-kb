import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kn1_frontier as K
def test_samplers_obey_their_constraints():
    rng = random.Random(1)
    for _ in range(300):
        l1 = K.sample("L1", rng).replace("cyclo(", "").rstrip(")").split("-"); assert 7 <= len(l1) <= 11 and sum(t in K.LYS for t in l1) == 1
        s = "-".join(l1); assert "R-G-D-L" in s
        l2 = "-".join(K.sample("L2", rng).replace("cyclo(", "").rstrip(")").split("-")); assert "R-G-D" in l2
        l0 = K.sample("L0", rng).replace("cyclo(", "").rstrip(")").split("-"); assert len(l0) == 9 and l0[1:5] == ["R", "G", "D", "L"] and l0[7:] == ["[dP]", "[NMeK]"]
def test_wilson_bounds():
    lo, hi = K.wilson(0, 100); assert lo == 0 and 0 < hi < 0.05
    lo, hi = K.wilson(50, 100); assert lo < 0.5 < hi
if __name__ == "__main__":
    test_samplers_obey_their_constraints(); test_wilson_bounds(); print("2 tests passed")
