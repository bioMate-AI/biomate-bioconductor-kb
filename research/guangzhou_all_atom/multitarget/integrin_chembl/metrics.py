"""Metrics + cluster bootstrap (shared by analysis and tests)."""
import numpy as np, pandas as pd
from scipy.stats import rankdata
def rmse(p, y): return float(np.sqrt(np.mean((np.asarray(p) - np.asarray(y)) ** 2)))
def spearman(p, y):
    p = np.asarray(p, float); y = np.asarray(y, float)
    if len(p) < 3 or np.ptp(p) == 0 or np.ptp(y) == 0: return 0.0
    return float(np.corrcoef(rankdata(p), rankdata(y))[0, 1])
def auroc(score, lab):
    score = np.asarray(score, float); lab = np.asarray(lab, int); n1 = lab.sum(); n0 = len(lab) - n1
    if n1 == 0 or n0 == 0: return np.nan
    r = rankdata(score); return float((r[lab == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0))
def sign_acc(p, y, thr=0.3):
    p = np.asarray(p, float); y = np.asarray(y, float); m = np.abs(y) >= thr
    if m.sum() == 0: return np.nan
    return float(np.mean(np.where(p[m] == 0, 0.5, (np.sign(p[m]) == np.sign(y[m])).astype(float))))
def group_index(groups):
    s = pd.Series(np.arange(len(groups))); return [v.values for _, v in s.groupby(np.asarray(groups))]
def boot_draws(gidx, B, seed):
    rng = np.random.RandomState(seed); G = len(gidx)
    for _ in range(B): yield np.concatenate([gidx[g] for g in rng.randint(0, G, G)])
def ci(vals): v = np.asarray(vals, float); v = v[~np.isnan(v)]; return [float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))] if len(v) else [np.nan, np.nan]
def boot_metric(y, preds, groups, fn, B=2000, seed=1):
    """fn(pred, y)->float. Returns dict name -> (point, lo, hi) and paired draws dict for differences."""
    gidx = group_index(groups); y = np.asarray(y); P = {k: np.asarray(v) for k, v in preds.items()}
    point = {k: fn(v, y) for k, v in P.items()}; draws = {k: [] for k in P}
    for ix in boot_draws(gidx, B, seed):
        for k, v in P.items(): draws[k].append(fn(v[ix], y[ix]))
    return point, {k: np.array(v) for k, v in draws.items()}
