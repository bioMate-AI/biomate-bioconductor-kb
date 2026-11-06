"""Contrastive (multi-positive InfoNCE) selector. Run: python3 tests/test_selector_contrastive.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import selector_contrastive as SC
from test_selector import synth, success


def test_finds_planted_signal_across_scales():
    tr, te = synth(seed=0), synth(seed=1)
    s = SC.ContrastiveSelector(lam=0.1).fit(tr)
    default = np.mean([te[c][int(np.argmax([r["confidence_score"] for r in te[c]]))]["dockq"] >= 0.23 for c in te])
    assert success(s, te) > default + 0.25, (success(s, te), default)


def test_ignores_complexes_without_contrast():
    tr = synth(seed=0)
    pad = {f"p{k}": [{"confidence_score": float(i), "iptm": float(-i), "cons_nbr": float((i * 7) % 5), "dockq": 0.6} for i in range(25)] for k in range(60)}
    a = SC.ContrastiveSelector(lam=0.1).fit({**tr, **pad}); b = SC.ContrastiveSelector(lam=0.1).fit(tr)
    assert np.allclose(a.w, b.w), (a.w, b.w)


def test_shuffled_labels_give_chance():
    import random
    tr = synth(seed=0, shuffle=True); te = synth(seed=1)
    assert abs(success(SC.ContrastiveSelector(lam=0.1).fit(tr), te) - 0.3) < 0.2


def test_loss_gradient_is_correct():
    rng = np.random.RandomState(0); X = [rng.randn(8, 3) for _ in range(4)]; y = [(rng.rand(8) < 0.4).astype(int) for _ in range(4)]
    for yy in y: yy[0] = 1; yy[1] = 0
    w = rng.randn(3); f, g = SC.loss_and_grad(w, X, y, 0.3)
    num = np.array([(SC.loss_and_grad(w + 1e-6 * e, X, y, 0.3)[0] - SC.loss_and_grad(w - 1e-6 * e, X, y, 0.3)[0]) / 2e-6 for e in np.eye(3)])
    assert np.allclose(g, num, atol=1e-5), (g, num)


if __name__ == "__main__":
    k = 0
    for name, f in sorted(globals().items()):
        if name.startswith("test_"): f(); k += 1; print("PASS", name)
    print(f"{k} tests passed")
