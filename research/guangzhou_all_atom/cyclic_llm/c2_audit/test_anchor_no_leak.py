"""P-B2 control: changing every held-out-source label must change neither training offsets nor calibrated training labels (it may change only the held-out metric)."""
import os, sys, json, numpy as np, collections
sys.argv = ["x", os.environ["AT_DATA"], "/tmp/at_noleak_out"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anchor_test as A

def offsets_for(h, y_override=None):
    """Replicates what task() feeds the estimator for training sources; y_override replaces labels of source h in the anchor tables only."""
    y, ab, _ = A.world("real")
    if y_override is not None:   # corrupt the held-out source's labels wherever they appear as a PARTNER value
        ab = {s: [dict(a, other_vals={o: (v + 100.0 if o == h else v) for o, v in a["other_vals"].items()}) for a in l] for s, l in ab.items()}
    r = A.restrict(ab, h)
    return A.estimate_offsets(5, 0, r)[0], r

def test_training_offsets_independent_of_heldout_labels():
    n_checked = 0
    for h in ["2015_Ahlbach", "2015_Wang", "2018_Naylor", "2023_Ghosh"]:
        b0, r0 = offsets_for(h); b1, r1 = offsets_for(h, y_override=True)
        assert b0.keys() == b1.keys() and all(abs(b0[s] - b1[s]) < 1e-12 for s in b0), h
        assert all(h not in a["other_sources"] for l in r0.values() for a in l)
        n_checked += 1
    assert n_checked == 4

def test_old_estimator_would_have_leaked():
    """Documents the defect: without restrict(), corrupting held-out partner values moves the offsets."""
    h = "2018_Naylor"; y, ab, _ = A.world("real")
    ab_bad = {s: [dict(a, y_others=float(np.mean([v + 100.0 if o == h else v for o, v in a["other_vals"].items()]))) for a in l] for s, l in ab.items()}
    b_old, _ = A.estimate_offsets(5, 0, {s: l for s, l in ab.items() if s != h}); b_bad, _ = A.estimate_offsets(5, 0, {s: l for s, l in ab_bad.items() if s != h})
    assert any(abs(b_old[s] - b_bad[s]) > 1 for s in b_old)

if __name__ == "__main__":
    test_training_offsets_independent_of_heldout_labels(); print("PASS no-leak"); test_old_estimator_would_have_leaked(); print("PASS old-leaks (documented)")
