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


# --- verified signatures (constants confirmed from source; see benchmarks/.../FIELD_TOOL_CONSTANTS.md) ---
# CYT: cytolytic activity, geometric mean of GZMA & PRF1 (Rooney et al., Cell 2015, PMID 25594174).
CYT_GENES = ["GZMA", "PRF1"]

# IFN-gamma signatures (Ayers et al., JCI 2017, 10.1172/JCI91190):
IFNG6_GENES: List[str] = ["IDO1", "CXCL10", "CXCL9", "HLA-DRA", "STAT1", "IFNG"]  # Table 2 "IFN-gamma"
IFNG_GEP_GENES: List[str] = [  # final 18-gene T-cell-inflamed GEP (paper Fig.4; = canonical NanoString TIS)
    "TIGIT", "CD27", "CD8A", "PDCD1LG2", "LAG3", "CD274", "CXCR6", "CMKLR1", "NKG7",
    "CCL5", "PSMB10", "IDO1", "CXCL9", "HLA-DQA1", "CD276", "STAT1", "HLA-DRB1", "HLA-E",
]

# IMPRES (Auslander et al., Nat Med 2018, 10.1038/s41591-018-0157-9): 15 ordered pairs; feature =
# expr(A) > expr(B); score = count fulfilled, 0-15, higher = responder. Verified across 5 independent
# code encodings (easier, Sahni2024, et al.); A>B direction confirmed.
IMPRES_PAIRS: List[Tuple[str, str]] = [
    ("PDCD1", "TNFSF4"), ("CD27", "PDCD1"), ("CTLA4", "TNFSF4"), ("CD40", "CD28"),
    ("CD86", "TNFSF4"), ("CD28", "CD86"), ("CD80", "TNFSF9"), ("CD274", "C10orf54"),
    ("CD86", "HAVCR2"), ("CD40", "PDCD1"), ("CD86", "CD200"), ("CD40", "CD80"),
    ("CD28", "CD276"), ("CD40", "CD274"), ("TNFRSF14", "CD86"),
]
# symbol aliases so a pair gene resolves whichever symbol the matrix uses
_GENE_ALIASES = {"C10orf54": ["VSIR"], "VSIR": ["C10orf54"], "TNFSF4": ["OX40L"],
                 "TNFSF9": ["CD137L"], "HAVCR2": ["TIM3", "TIMD3"], "PDCD1LG2": ["PDL2", "CD273"]}


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


def _resolve_gene(index_set, gene):
    if gene in index_set:
        return gene
    for a in _GENE_ALIASES.get(gene, []):
        if a in index_set:
            return a
    return None


def impres_score(expr):
    """IMPRES = count of the 15 ordered pairs with expr(A) > expr(B) (0-15; higher = responder).
    Comparison is monotone-invariant so raw expression is fine. Pairs with a missing gene are
    skipped (not penalised); returns {sample: count}. Fail-soft."""
    idx = set(expr.index)
    resolved = [(_resolve_gene(idx, a), _resolve_gene(idx, b)) for a, b in IMPRES_PAIRS]
    usable = [(a, b) for a, b in resolved if a and b]
    if not usable:
        return {}
    out = {}
    for s in expr.columns:
        cnt = 0
        for a, b in usable:
            va, vb = expr.at[a, s], expr.at[b, s]
            if math.isfinite(va) and math.isfinite(vb) and va > vb:
                cnt += 1
        out[s] = float(cnt)
    return out


def tide_score(expr, cancer="Melanoma"):
    """TIDE (Jiang 2018) via the tidepy package (a TRAINED model — no gene-list reimplementation).
    Returns {sample: -TIDE} so higher = predicted responder (TIDE itself: higher = resistant), or {}
    with a note if tidepy is unavailable. NOT faked offline."""
    try:
        import pandas as pd  # noqa: F401
        from tidepy.pred import TIDE
    except Exception:
        return {}
    try:
        res = TIDE(expr, cancer=cancer, pretreat=False, vthres=0.0)
        col = "TIDE" if "TIDE" in getattr(res, "columns", []) else res.columns[0]
        return {str(s): -float(v) for s, v in res[col].items() if math.isfinite(float(v))}
    except Exception:
        return {}


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


_FIELD_SIGS = {
    "CYT": cyt_score,
    "IFNG_6": lambda e: signature_score(e, IFNG6_GENES, "zmean"),
    "IFNG_GEP_18": lambda e: signature_score(e, IFNG_GEP_GENES, "zmean"),
    "IMPRES": impres_score,
}


def _cohort_feature_frame(expr, meta):
    """Per-sample field-signature feature matrix (within-cohort z) + response labels."""
    import numpy as np
    import pandas as pd
    feats = {name: fn(expr) for name, fn in _FIELD_SIGS.items()}
    samples = [s for s in expr.columns if s in meta.index]
    rows = [[feats[name].get(s, np.nan) for name in _FIELD_SIGS] for s in samples]
    y = np.array([int(meta.loc[s, "response_binary"]) for s in samples])
    X = pd.DataFrame(rows, columns=list(_FIELD_SIGS), index=samples)
    X = (X - X.mean()) / X.std(ddof=0).replace(0, 1.0)      # within-cohort z so cohorts are comparable
    return X.fillna(0.0), y, samples


def leave_cohort_out_fusion(cohorts: Dict[str, Tuple[Any, Any]]) -> Dict[str, Any]:
    """The 'our-system' placeholder arm: a LOGISTIC fusion of the field signals, trained
    leave-cohort-out (held-out cohort never seen in training -> no circularity). Returns pooled +
    per-held-out response-AUROC. This is the learnable fusion the immune-FM responder head will later
    feed/replace as one more feature."""
    import numpy as np
    from sklearn.linear_model import LogisticRegression
    frames = {n: _cohort_feature_frame(e, m) for n, (e, m) in cohorts.items()}
    names = [n for n in frames if len(set(frames[n][1].tolist())) > 1]  # cohort must have both classes
    pooled_y, pooled_p, per = [], [], {}
    for held in names:
        Xtr = [frames[n][0].values for n in names if n != held]
        ytr = [frames[n][1] for n in names if n != held]
        if not Xtr:
            continue
        Xtr = np.vstack(Xtr); ytr = np.concatenate(ytr)
        if len(set(ytr.tolist())) < 2:
            continue
        clf = LogisticRegression(max_iter=1000).fit(Xtr, ytr)
        Xte, yte, _ = frames[held]
        p = clf.predict_proba(Xte.values)[:, 1]
        per[held] = {"auroc": _auroc(yte, p), "n": len(yte)}
        pooled_y.extend(yte.tolist()); pooled_p.extend(p.tolist())
    return {"per_cohort": per, "pooled_auroc": _auroc(pooled_y, pooled_p), "pooled_n": len(pooled_y),
            "model": "logistic(field-signal fusion)", "features": list(_FIELD_SIGS)}


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
    sigs = {
        "CYT": evaluate_signature(cohorts, cyt_score),
        "IFNG_6": evaluate_signature(cohorts, lambda e: signature_score(e, IFNG6_GENES, "zmean")),
        "IFNG_GEP_18": evaluate_signature(cohorts, lambda e: signature_score(e, IFNG_GEP_GENES, "zmean")),
        "IMPRES": evaluate_signature(cohorts, impres_score),
    }
    tide = evaluate_signature(cohorts, lambda e: tide_score(e))
    if tide["pooled_auroc"] is not None or any(v.get("n") for v in tide["per_cohort"].values()):
        sigs["TIDE"] = tide

    learned = leave_cohort_out_fusion(cohorts)                       # the 'our-system' placeholder arm
    best_field = max((v["pooled_auroc"] or 0.0) for v in sigs.values())
    best_field_name = max(sigs, key=lambda k: (sigs[k]["pooled_auroc"] or 0.0))
    learned_pooled = learned["pooled_auroc"] or 0.0
    return {
        "signatures": sigs,
        "learned_fusion": learned,
        "best_field_tool": {"name": best_field_name, "pooled_auroc": best_field},
        "learned_beats_best_field": bool(learned_pooled > best_field),
        "cohorts": {n: {"n": expr.shape[1]} for n, (expr, meta) in cohorts.items()},
        "note": ("Field-tool baselines (CYT/IFN-gamma-6/IFN-gamma-GEP-18/IMPRES/TIDE) vs a leave-cohort-out "
                 "LOGISTIC fusion of them (the 'our-system' placeholder). The immune-FM responder head (h_strat) "
                 "plugs in later as one more feature. Full predictive>prognostic (P2/P3) still needs a non-ICB "
                 "control cohort (TIGER is all-ICB)."),
    }
