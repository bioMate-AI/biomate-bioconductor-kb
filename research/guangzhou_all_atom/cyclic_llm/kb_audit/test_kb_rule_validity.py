"""Positive/negative controls for kb_rule_validity: a within-source effect must be recovered, a pure between-source confound must NOT be
called validated, shuffled labels must give INCONCLUSIVE, and a reversed rule must be CONTRADICTED. Run: python3 -m pytest -q test_kb_rule_validity.py"""
import numpy as np
import kb_rule_validity as K

def world(beta, confound=0.0, n_src=12, n=60, seed=0):
    rng = np.random.default_rng(seed); X, Y, S = [], [], []
    for s in range(n_src):
        off = rng.normal(0, 2.0); mean_x = confound * off      # confound: sources with higher labels also have higher feature
        x = rng.normal(mean_x, 1.0, n); y = off + beta * x + rng.normal(0, 1.0, n)
        X += list(x); Y += list(y); S += [f"src{s}"] * n
    return np.array(X), np.array(Y), np.array(S)

def test_recovers_planted_within_source_effect():
    x, y, s = world(beta=0.5); st = K.within_source_stats(x, y, s, B=500)
    assert st["median_within_rho"] > 0.2 and K.verdict(st, +1) == "VALIDATED"

def test_between_source_confound_is_not_validated():
    x, y, s = world(beta=0.0, confound=1.5); st = K.within_source_stats(x, y, s, B=500)
    assert st["pooled_rho"] > 0.4                      # pooled analysis is fooled
    assert K.verdict(st, +1) != "VALIDATED"            # within-source analysis is not

def test_shuffled_labels_inconclusive():
    x, y, s = world(beta=0.5); rng = np.random.default_rng(1)
    y2 = y.copy()
    for src in set(s.tolist()):
        m = s == src; y2[m] = rng.permutation(y[m])
    st = K.within_source_stats(x, y2, s, B=500); assert K.verdict(st, +1) in ("INCONCLUSIVE",)

def test_reversed_rule_is_contradicted():
    x, y, s = world(beta=-0.5); st = K.within_source_stats(x, y, s, B=500)
    assert K.verdict(st, +1) == "CONTRADICTED"

def test_too_few_sources_is_insufficient():
    x, y, s = world(beta=0.5, n_src=3); st = K.within_source_stats(x, y, s, B=100)
    assert K.verdict(st, +1) == "INSUFFICIENT"
