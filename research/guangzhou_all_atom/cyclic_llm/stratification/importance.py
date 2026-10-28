"""Standalone copies of the family permutation-importance and stratum-metric procedures used inline in feat_analysis.py / strat_perf.py, for positive-control testing."""
import numpy as np
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor as H


def family_perm_importance(X, y, folds, families, reps=10, seed=0, max_iter=60):
    """families: name -> list of column indices; folds: list of (train, test). Returns name -> array of Spearman drops (baseline - permuted), joint permutation within held-out folds."""
    rng = np.random.default_rng(seed); n = len(y); base = np.zeros(n); models = []
    for tr, te in folds:
        m = H(max_iter=max_iter, learning_rate=0.1, random_state=0).fit(X[tr], y[tr]); models.append(m); base[te] = m.predict(X[te])
    drops = {f: [] for f in families}
    for _ in range(reps):
        perm = {f: np.zeros(n) for f in families}
        for (tr, te), m in zip(folds, models):
            for f, cols in families.items():
                Xt = X[te].copy(); pi = rng.permutation(len(te)); Xt[:, cols] = Xt[pi][:, cols]; perm[f][te] = m.predict(Xt)
        for f in families: drops[f].append(spearmanr(base, y)[0] - (spearmanr(perm[f], y)[0] if np.std(perm[f]) > 0 else 0.0))
    return {f: np.array(v) for f, v in drops.items()}


def stratum_spearman(pred, y, mask, groups, B=300, seed=0):
    from stats import cluster_boot
    idx = np.where(mask)[0]
    return cluster_boot(lambda i: spearmanr(pred[idx][i], y[idx][i])[0] if np.std(pred[idx][i]) > 0 else 0.0, groups[idx], B=B, seed=seed)
