"""Split iterator shared by every model. Yields dict(split, fold, tr, va, te) of row indices into data/clean.csv."""
import numpy as np, pandas as pd
from common import *

def load():
    return pd.read_csv(CLEAN), pd.read_csv(FOLDS)

def _inner(tr, groups, frac=0.10, seed=0):
    """validation = ~10% of the training GROUPS (whole groups) -> same leakage rule as the outer split."""
    g = groups[tr]; ug = np.unique(g); rng = np.random.default_rng(seed); rng.shuffle(ug)
    cnt = pd.Series(g).value_counts(); va_g, n = [], 0
    for u in ug:
        va_g.append(u); n += cnt[u]
        if n >= frac * len(tr): break
    m = np.isin(g, va_g)
    return tr[~m], tr[m]

def splits(which=("S0", "S1", "S2", "S3"), s0_seeds=5):
    c, f = load(); N = len(c); out = []
    rows = np.arange(N)
    if "S0" in which:
        for s in range(s0_seeds):
            lab = f[f"s0_seed{s}"].values
            out.append(dict(split="S0", fold=s, tr=rows[lab == "train"], va=rows[lab == "val"], te=rows[lab == "test"]))
    if "S1" in which:
        for k in range(5):
            te = rows[f.s1_fold.values == k]; tr = rows[f.s1_fold.values != k]
            tr, va = _inner(tr, c.scaf.values, seed=k)
            out.append(dict(split="S1", fold=k, tr=tr, va=va, te=te))
    if "S2" in which:
        for k in range(5):
            te = rows[f.s2_fold.values == k]; tr = rows[f.s2_fold.values != k]
            tr, va = _inner(tr, f.s2_cluster.values, seed=k)
            out.append(dict(split="S2", fold=k, tr=tr, va=va, te=te))
    if "S3" in which:
        for k in range(f.s3_fold.max() + 1):
            te = rows[f.s3_fold.values == k]
            bad = set(c.pid.values[te])
            tr = rows[(f.s3_fold.values != k) & ~c.pid.isin(bad).values]
            tr, va = _inner(tr, c.scaf.values, seed=k)
            out.append(dict(split="S3", fold=k, tr=tr, va=va, te=te))
    return out
