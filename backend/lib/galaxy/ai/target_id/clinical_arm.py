"""Clinical arm of the demonstration — ICB-response on the TIGER bulk cohorts (protocol §3 CL gate).

Scores each sample for predicted ICB response with gene-expression signatures and reports
response-AUROC per cohort + pooled (the baselines our system must beat). TIGER cohort format
(verified 2026-10-20): expr CSV = GENE_SYMBOL x sample columns; meta CSV columns
sample_id,response_raw,response_binary,cohort,cancer,os_time,os_event,surv_type.

HONESTY: only signatures whose EXACT gene definition is verified ship here. CYT (cytolytic
activity = geometric mean of GZMA, PRF1; Rooney et al. Cell 2015) is unambiguous and included.
IFN-gamma GEP (Ayers 2017) and IMPRES (Auslander 2018) and TIDE are framework slots — their exact
constants must be loaded from the cited source (NOT guessed); add_signature()/load_pairs_signature()
are the seams. The learned "our-system" arm + the predictive>prognostic (P2/P3) interaction need a
non-ICB control cohort (TIGER is all-ICB) — documented, not faked. 3.9-safe; numpy/pandas/sklearn.
"""
import math
import os
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple


# --- verified signatures only -------------------------------------------------------------
# CYT: cytolytic activity, geometric mean of GZMA & PRF1 (Rooney et al., Cell 2015, PMID 25594174).
CYT_GENES = ["GZMA", "PRF1"]

# Framework slots — fill from the cited source before use; left empty so nothing is fabricated.
# Ayers 2017 (JCI 10.1172/JCI91190) 18-gene T-cell-inflamed GEP; Auslander 2018 (Nat Med
# 10.1038/s41591-018-0157-9) 15 ordered gene pairs.
IFNG_GEP_GENES: List[str] = []          # TODO: populate verbatim from Ayers 2017 (unverified this session)
IMPRES_PAIRS: List[Tuple[str, str]] = []  # TODO: populate the 15 ordered (A>B) pairs from Auslander 2018


def load_tiger_cohort(expr_path: str, meta_path: str):
    """Return (expr DataFrame genes x samples, meta DataFrame indexed by sample_id)."""
    import pandas as pd
    expr = pd.read_csv(expr_path, index_col=0)
    expr.index = [str(g).upper() for g in expr.index]
    meta = pd.read_csv(meta_path)
    meta = meta.set_index("sample_id")
    # keep only samples present in both + with a response label
    common = [s for s in expr.columns if s in meta.index and meta.loc[s, "response_binary"] in (0, 1, 0.0, 1.0)]
    return expr[common], meta.loc[common]


def signature_score(expr, genes: Sequence[str], method: str = "zmean"):
    """Per-sample score for a gene-set signature. method: 'zmean' (mean of per-gene z across samples)
    or 'geomean' (geometric mean of raw expression). Returns {sample: score}. Missing genes dropped."""
    import numpy as np
    present = [g for g in (str(x).upper() for x in genes) if g in expr.index]
    if not present:
        return {}
    sub = expr.loc[present]
    X = np.nan_to_num(sub.values.astype(float), nan=0.0)   # real bulk matrices carry NaN -> treat as 0
    if method == "geomean":
        score = np.expm1(np.log1p(np.clip(X, 0, None)).mean(axis=0))
    else:  # zmean: z-score each gene across samples, then average
        m = X.mean(axis=1, keepdims=True)
        sd = X.std(axis=1, keepdims=True)
        sd[sd < 1e-9] = 1.0
        score = ((X - m) / sd).mean(axis=0)
    return {s: float(v) for s, v in zip(sub.columns, score) if math.isfinite(float(v))}


def cyt_score(expr):
    return signature_score(expr, CYT_GENES, method="geomean")


def _auroc(labels: Sequence[int], scores: Sequence[float]) -> Optional[float]:
    import numpy as np
    from sklearn.metrics import roc_auc_score
    y = np.asarray(labels, dtype=int)
    if y.sum() == 0 or y.sum() == len(y):
        return None
    return round(float(roc_auc_score(y, np.asarray(scores, dtype=float))), 4)


def evaluate_signature(cohorts: Dict[str, Tuple[Any, Any]], score_fn: Callable[[Any], Dict[str, float]]
                       ) -> Dict[str, Any]:
    """Per-cohort + pooled response-AUROC for a FIXED signature (no training -> no leave-cohort-out
    needed; pooled z-normalizes per cohort before combining). Returns {per_cohort, pooled}."""
    import numpy as np
    per_cohort = {}
    pooled_y, pooled_s = [], []
    for name, (expr, meta) in cohorts.items():
        sc = score_fn(expr)
        samples = [s for s in sc if s in meta.index]
        if not samples:
            per_cohort[name] = {"auroc": None, "n": 0}
            continue
        y = [int(meta.loc[s, "response_binary"]) for s in samples]
        s = [sc[s] for s in samples]
        per_cohort[name] = {"auroc": _auroc(y, s), "n": len(samples), "n_resp": int(sum(y))}
        sv = np.asarray(s, float)
        if sv.std() > 1e-9:
            sv = (sv - sv.mean()) / sv.std()               # per-cohort z so cohorts are comparable when pooled
        pooled_y.extend(y); pooled_s.extend(sv.tolist())
    return {"per_cohort": per_cohort, "pooled_auroc": _auroc(pooled_y, pooled_s),
            "pooled_n": len(pooled_y), "pooled_n_resp": int(sum(pooled_y))}


def load_cohorts(local_dir: str, cohort_names: Optional[Sequence[str]] = None) -> Dict[str, Tuple[Any, Any]]:
    """Load all <name>.expr.csv/<name>.meta.csv pairs under local_dir (already fetched from S3)."""
    out = {}
    names = cohort_names
    if names is None:
        names = sorted({f[:-len(".expr.csv")] for f in os.listdir(local_dir) if f.endswith(".expr.csv")})
    for n in names:
        ep = os.path.join(local_dir, n + ".expr.csv")
        mp = os.path.join(local_dir, n + ".meta.csv")
        if os.path.exists(ep) and os.path.exists(mp):
            try:
                out[n] = load_tiger_cohort(ep, mp)
            except Exception:
                pass
    return out


def run_clinical_demonstration(local_dir: str, cohort_names: Optional[Sequence[str]] = None) -> Dict[str, Any]:
    """Run the verified field-signature baselines on TIGER cohorts under local_dir.
    Returns {signatures: {name: {per_cohort, pooled_auroc}}, note}. Add our-system + IFN-gamma/IMPRES/
    TIDE arms once (a) their exact constants are verified and (b) a learned predictor + control arm exist.
    """
    cohorts = load_cohorts(local_dir, cohort_names)
    if not cohorts:
        return {"error": "no cohorts loaded from %s" % local_dir}
    sigs = {"CYT": evaluate_signature(cohorts, cyt_score)}
    if IFNG_GEP_GENES:
        sigs["IFNG_GEP"] = evaluate_signature(cohorts, lambda e: signature_score(e, IFNG_GEP_GENES, "zmean"))
    return {
        "signatures": sigs,
        "cohorts": {n: {"n": expr.shape[1]} for n, (expr, meta) in cohorts.items()},
        "note": ("CYT (Rooney 2015) is the only VERIFIED-constant field signature wired. IFN-gamma GEP "
                 "(Ayers 2017) / IMPRES (Auslander 2018) / TIDE require their exact constants + are "
                 "framework slots. predictive>prognostic (P2/P3) needs a non-ICB control cohort."),
    }
