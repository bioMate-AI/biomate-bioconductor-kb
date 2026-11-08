"""Statistics helpers (Part A5/A6/A8): cluster bootstrap, DerSimonian-Laird random-effects meta-analysis, Benjamini-Hochberg."""
import numpy as np
from scipy.stats import spearmanr, norm


def cluster_boot(values_fn, groups, B=1000, seed=0):
    """Resample clusters with replacement; values_fn(idx_array) -> statistic. Returns (point, lo, hi)."""
    rng = np.random.default_rng(seed); ug, inv = np.unique(groups, return_inverse=True)
    by = [np.where(inv == k)[0] for k in range(len(ug))]
    point = values_fn(np.arange(len(groups)))
    vals = [values_fn(np.concatenate([by[k] for k in rng.integers(0, len(ug), len(ug))])) for _ in range(B)]
    vals = [v for v in vals if v == v]
    return float(point), float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))


def dl_meta(effects, variances):
    """DerSimonian-Laird random effects. Returns dict(pooled, se, lo, hi, tau2, I2, k)."""
    e = np.asarray(effects, float); v = np.asarray(variances, float); ok = np.isfinite(e) & np.isfinite(v) & (v > 0)
    e, v = e[ok], v[ok]; k = len(e)
    if k == 0: return dict(pooled=np.nan, se=np.nan, lo=np.nan, hi=np.nan, tau2=np.nan, I2=np.nan, k=0)
    w = 1 / v; fixed = np.sum(w * e) / np.sum(w); Q = np.sum(w * (e - fixed) ** 2)
    c = np.sum(w) - np.sum(w ** 2) / np.sum(w); tau2 = max(0.0, (Q - (k - 1)) / c) if k > 1 and c > 0 else 0.0
    ws = 1 / (v + tau2); pooled = np.sum(ws * e) / np.sum(ws); se = np.sqrt(1 / np.sum(ws))
    I2 = max(0.0, (Q - (k - 1)) / Q) if Q > 0 and k > 1 else 0.0
    return dict(pooled=float(pooled), se=float(se), lo=float(pooled - 1.96 * se), hi=float(pooled + 1.96 * se), tau2=float(tau2), I2=float(I2), k=int(k))


def smd_within_source(z, flag, min_side=5):
    """Mean difference (present - absent) of within-source-standardised labels for one source; returns (effect, variance) or (nan, nan)."""
    z = np.asarray(z, float); f = np.asarray(flag, bool); n1, n0 = int(f.sum()), int((~f).sum())
    if n1 < min_side or n0 < min_side: return np.nan, np.nan
    s2 = ((n1 - 1) * z[f].var(ddof=1) + (n0 - 1) * z[~f].var(ddof=1)) / (n1 + n0 - 2)
    return float(z[f].mean() - z[~f].mean()), float(s2 * (1 / n1 + 1 / n0))


def bh_fdr(p, q=0.10):
    p = np.asarray(p, float); n = len(p); order = np.argsort(p); ranked = p[order] * n / (np.arange(n) + 1)
    adj = np.minimum.accumulate(ranked[::-1])[::-1]; out = np.empty(n); out[order] = np.minimum(adj, 1.0)
    return out, out <= q


def p_from_ci(est, se):
    return float(2 * (1 - norm.cdf(abs(est / se)))) if se and se > 0 else 1.0
