"""Shared helpers: paths, HELM parsing, featurizers, metrics, cluster bootstrap. No label-dependent code here."""
import os, re, json, hashlib, numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "../../data/raw/CycPeptMPDB_Peptide_All.csv")
CLEAN = os.path.join(HERE, "data/clean.csv")
FOLDS = os.path.join(HERE, "data/folds.csv")
SCRATCH = "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad/perm"
os.makedirs(SCRATCH, exist_ok=True)
ASSAY_ORDER = ["PAMPA", "Caco2", "RRCK", "MDCK"]

_HELM_RE = re.compile(r"^PEPTIDE\d+\{(.*?)\}\$")

def parse_helm_monomers(helm: str):
    """HELM 'PEPTIDE1{[Abu].[Sar].V.[meL]}$...' -> ['Abu','Sar','V','meL']. Raises ValueError if unparsable."""
    m = _HELM_RE.match(helm.strip())
    if not m:
        raise ValueError(f"unparsable HELM: {helm[:60]}")
    out = []
    for tok in m.group(1).split("."):
        tok = tok.strip()
        if tok.startswith("[") and tok.endswith("]"):
            tok = tok[1:-1]
        if not tok:
            raise ValueError("empty monomer token")
        out.append(tok)
    return out

def is_nmethyl_monomer(name: str) -> bool:
    return bool(re.match(r"^(me[A-Z]|Me_|Sar$|Me[A-Z])", name))

def r2(y, p):
    y = np.asarray(y, float); p = np.asarray(p, float)
    return 1 - ((y - p) ** 2).sum() / ((y - y.mean()) ** 2).sum()

def rmse(y, p):
    return float(np.sqrt(np.mean((np.asarray(y) - np.asarray(p)) ** 2)))

def spearman(y, p):
    from scipy.stats import spearmanr
    return float(spearmanr(y, p)[0])

def metrics(y, p):
    return {"r2": float(r2(y, p)), "rmse": rmse(y, p), "spearman": spearman(y, p), "n": int(len(y))}

def cluster_bootstrap(y, preds: dict, groups, n_boot=1000, seed=0):
    """Cluster bootstrap over `groups` (resample whole groups with replacement). preds: name->array.
    Returns {name: {metric: (point, lo, hi)}} and paired differences vs every other model are computed by
    paired_diff() using the same resamples (same seed => same resamples)."""
    y = np.asarray(y); groups = np.asarray(groups)
    ug, inv = np.unique(groups, return_inverse=True)
    idx_by_g = [np.where(inv == i)[0] for i in range(len(ug))]
    rng = np.random.default_rng(seed)
    boots = {k: {"r2": [], "rmse": [], "spearman": []} for k in preds}
    for _ in range(n_boot):
        pick = rng.integers(0, len(ug), len(ug))
        ii = np.concatenate([idx_by_g[g] for g in pick])
        for k, p in preds.items():
            m = metrics(y[ii], np.asarray(p)[ii])
            for mk in boots[k]: boots[k][mk].append(m[mk])
    out = {}
    for k, p in preds.items():
        pt = metrics(y, p); out[k] = {}
        for mk in ["r2", "rmse", "spearman"]:
            a = np.array(boots[k][mk]); out[k][mk] = (pt[mk], float(np.percentile(a, 2.5)), float(np.percentile(a, 97.5)))
    return out

def paired_diff(y, pa, pb, groups, metric="r2", n_boot=1000, seed=0):
    """CI of metric(pa)-metric(pb) with the same group resamples. Returns (diff, lo, hi)."""
    y = np.asarray(y); groups = np.asarray(groups); pa = np.asarray(pa); pb = np.asarray(pb)
    ug, inv = np.unique(groups, return_inverse=True)
    idx_by_g = [np.where(inv == i)[0] for i in range(len(ug))]
    rng = np.random.default_rng(seed); d = []
    for _ in range(n_boot):
        pick = rng.integers(0, len(ug), len(ug))
        ii = np.concatenate([idx_by_g[g] for g in pick])
        d.append(metrics(y[ii], pa[ii])[metric] - metrics(y[ii], pb[ii])[metric])
    pt = metrics(y, pa)[metric] - metrics(y, pb)[metric]
    return float(pt), float(np.percentile(d, 2.5)), float(np.percentile(d, 97.5))
