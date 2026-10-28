"""Same permutation machinery as lolo_permutation_null.py, as a testable function."""
import numpy as np
from scipy.stats import rankdata
def perm_p(k, y, B=5000, rng=None):
    rng = rng or np.random.default_rng(0)
    rk = rankdata(k) - (len(y) + 1) / 2; ry = rankdata(y) - (len(y) + 1) / 2; den = np.sqrt((rk ** 2).sum() * (ry ** 2).sum()); obs = (rk * ry).sum() / den
    idx = np.argsort(rng.random((B, len(rk))), axis=1); null = (rk[idx] * ry).sum(1) / den
    return float(obs), float((np.sum(np.abs(null) >= abs(obs)) + 1) / (B + 1)), null
