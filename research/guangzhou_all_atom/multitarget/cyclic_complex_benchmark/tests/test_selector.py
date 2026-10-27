"""Selector tests: it must find a planted signal, collapse to chance on shuffled labels, never accept GT columns, and be invariant to per-complex rescaling.
Run: python3 tests/test_selector.py"""
import os, sys, random
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import selector as S

def synth(n_cplx=40, n=25, signal=1.5, seed=0, shuffle=False):
    rng = np.random.RandomState(seed); out = {}
    for c in range(n_cplx):
        scale, shift = rng.uniform(0.2, 5), rng.uniform(-3, 3)               # per-complex confidence scale differs wildly
        good = rng.rand(n) < 0.3
        sig = good * signal + rng.randn(n)
        rows = []
        for i in range(n):
            r = {"confidence_score": scale * rng.randn() + shift, "iptm": scale * rng.randn() + shift,        # uninformative defaults
                 "cons_nbr": float(sig[i]) * scale + shift, "dockq": 0.5 if good[i] else 0.05}                  # informative consensus feature
            rows.append(r)
        out[f"c{c}"] = rows
    if shuffle:
        allr = [r for rs in out.values() for r in rs]; d = [r["dockq"] for r in allr]; random.Random(1).shuffle(d)
        for r, x in zip(allr, d): r["dockq"] = x
    return out

def success(sel, data, thr=0.23):
    return np.mean([data[c][sel.pick(data[c])]["dockq"] >= thr for c in data])

def test_finds_planted_signal_across_scales():
    tr, te = synth(seed=0), synth(seed=1)
    s = S.Selector().fit(tr)
    default = np.mean([te[c][int(np.argmax([r["confidence_score"] for r in te[c]]))]["dockq"] >= 0.23 for c in te])
    assert success(s, te) > default + 0.25, (success(s, te), default)

def test_shuffled_labels_give_chance():
    tr, te = synth(seed=0, shuffle=True), synth(seed=1)
    base = 0.3                                                              # chance success = fraction acceptable
    assert abs(success(S.Selector().fit(tr), te) - base) < 0.2

def test_mixed_only_ignores_complexes_with_identical_labels():
    tr = synth(seed=0)
    pad = {}
    for k in range(60):                                                     # 60 complexes where EVERY sample succeeds: no ranking information
        pad[f"p{k}"] = [{"confidence_score": float(i), "iptm": float(-i), "cons_nbr": float((i * 7) % 5), "dockq": 0.6} for i in range(25)]
    a = S.Selector(mixed_only=True).fit({**tr, **pad}); b = S.Selector(mixed_only=True).fit(tr)
    assert a.coef() == b.coef(), (a.coef(), b.coef())                      # padding must change nothing
    c = S.Selector().fit({**tr, **pad})                                    # the original selector IS affected by the padding
    assert c.coef() != b.coef()

def test_rejects_ground_truth_features():
    try: S.assert_no_gt_columns(["iptm", "irmsd"]); assert False
    except AssertionError as e: assert "irmsd" in str(e)
    assert not any(f.startswith(S.GT_PREFIXES) or f in ("irmsd", "lrmsd") for f in S.FEATURES)

def test_scale_invariance_within_complex():
    d = synth(seed=3); s = S.Selector().fit(d)
    r = d["c0"]; p1 = s.pick(r)
    r2 = [{k: (v * 7 + 11 if k in ("confidence_score", "iptm", "cons_nbr") else v) for k, v in x.items()} for x in r]
    assert s.pick(r2) == p1

def test_trivial_when_no_positives():
    d = {c: [dict(x, dockq=0.01) for x in rs] for c, rs in synth(n_cplx=5).items()}
    s = S.Selector().fit(d); assert s.trivial and isinstance(s.pick(d["c0"]), int)

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
