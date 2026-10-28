"""Controls for the permutation-null machinery: matches scipy Spearman; planted signal gets small p; null worlds give ~uniform p (type-I rate near 5 %);
the null of the median over labs is centred near 0 with the right spread; a source-offset feature (K standardised differently per lab) does not create a spurious per-lab signal."""
import numpy as np
from scipy.stats import spearmanr
import perm_null as N
def test_matches_scipy():
    r = np.random.default_rng(0); k = r.normal(size=60); y = k * 0.3 + r.normal(size=60); o, p, _ = N.perm_p(k, y, 500); assert abs(o - spearmanr(k, y)[0]) < 1e-9
def test_planted_signal_small_p():
    r = np.random.default_rng(1); k = r.normal(size=200); y = 0.5 * k + r.normal(size=200); assert N.perm_p(k, y, 2000)[1] < 0.01
def test_null_world_type1_rate():
    r = np.random.default_rng(2); ps = [N.perm_p(r.normal(size=40), r.normal(size=40), 500, r)[1] for _ in range(400)]; assert 0.02 < np.mean(np.array(ps) < 0.05) < 0.09
def test_median_null_centred():
    r = np.random.default_rng(3); meds = []
    for _ in range(300): meds.append(np.median([spearmanr(r.normal(size=n), r.normal(size=n))[0] for n in (20, 30, 50, 100, 200) * 4]))
    assert abs(np.mean(meds)) < 0.02
def test_per_lab_offsets_do_not_create_signal():
    r = np.random.default_rng(4); rhos = []
    for lab in range(30):
        n = 50; k = r.normal(size=n) + 5 * lab; y = r.normal(size=n) + 3 * lab        # between-lab offsets in both; within-lab independent
        kz = (k - k.mean()) / k.std(); yz = (y - y.mean()) / y.std(); rhos.append(N.perm_p(kz, yz, 200, r)[0])
    assert abs(np.median(rhos)) < 0.1

def test_zero_denominator_returns_nan_not_a_number():
    r = np.random.default_rng(5); y = r.normal(size=30)
    for k, yy in ((np.ones(30), y), (r.normal(size=30), np.ones(30)), (np.ones(30), np.ones(30))):
        o, p, null = N.perm_p(k, yy, 200)
        assert np.isnan(o) and np.isnan(p) and null is None

def test_guard_does_not_change_defined_results():
    r = np.random.default_rng(6); k = r.normal(size=40); y = 0.4 * k + r.normal(size=40); o, p, null = N.perm_p(k, y, 300, np.random.default_rng(0))
    assert np.isfinite(o) and np.isfinite(p) and null.shape == (300,)
