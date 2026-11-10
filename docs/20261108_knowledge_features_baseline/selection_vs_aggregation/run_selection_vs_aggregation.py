"""Gate 1b: is the cross-tissue transfer failure from gene SELECTION or from AGGREGATION?

Gate 1 showed per-cell-norm (offset removal) only partly helps -> offset is a minor cause. The refined
suspect: the MEAN collapses each gene set to one scalar, destroying within-set structure. This cleanly
separates two causes, all per-cell z-scored (xr), leave-one-tissue-out, full labels, fixed C=0.01:

  raw           : all 2000 HVG (per-cell-norm)                      baseline
  raw_knowgenes : ONLY genes that are members of >=1 gene set, UNGROUPED (per-cell-norm)
                  -> tests the SELECTION effect (does restricting to knowledge genes lose transfer?)
  know_pc       : per-set MEAN over members (per-cell-norm)         -> current aggregation
  know_rich     : per-set [mean, std, max] over members (per-cell-norm), 768*3-d
                  -> partially restores within-set structure

Decode:
  raw_knowgenes ~ raw  AND  know_pc << raw  -> AGGREGATION is the killer (gene-level resolution matters)
                                               => expiMap (learnable within-program weights) is justified.
  raw_knowgenes << raw                      -> SELECTION loses it (sets miss the transferable genes)
                                               => knowledge sets wrong for this endpoint; expiMap won't fix.
  know_rich recovers toward raw             -> corroborates aggregation-loss (richer summary transfers better).
CPU-only, feature-level (no encoder).
"""
import json, time, resource, warnings, sys, os, platform
from pathlib import Path
import numpy as np
import anndata as ad
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import average_precision_score
from sklearn.exceptions import ConvergenceWarning

WS = os.environ.get("WS", "/workspace"); AUD = os.environ.get("AUD", "/audit")
OUT = Path(AUD) / "selection_vs_aggregation_20261108"; OUT.mkdir(exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")
import knowledge_channel as K
K._s3 = lambda src, dst: Path(dst).is_file()
start = time.time()
def align_genes(names, X, hvg):
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32); have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)
sc = np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg = list(sc["hvg_names"].astype(str))
A = ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
counts = A.X.tocsr().astype(np.float64); lib = np.asarray(counts.sum(1)).ravel(); lib[lib == 0] = 1
norm = counts.multiply(1e4 / lib[:, None]).tocsr(); norm.data = np.log1p(norm.data)
x, ng = align_genes(list(A.var_names), norm, hvg)
y = (A.obs["stim"].astype(str).to_numpy() != "unstimulated").astype(int)
tissue = A.obs["tissue"].astype(str).to_numpy(); del A, counts, norm
mu = x.mean(1, keepdims=True); sd = x.std(1, keepdims=True); sd[sd == 0] = 1.0
xr = ((x - mu) / sd).astype(np.float32)                          # per-cell z-scored HVG
bases = K.fit_bases(hvg, f"{WS}/fs_long/work"); assert bases["n_know"] == 768
cols = bases["pathways"] + bases["tf"]
member = np.unique(np.concatenate(cols))                          # genes in >=1 set
def rich(X):                                                      # [mean,std,max] per set
    out = np.empty((X.shape[0], len(cols) * 3), np.float32)
    for j, idx in enumerate(cols):
        S = X[:, idx]; out[:, 3*j] = S.mean(1); out[:, 3*j+1] = S.std(1); out[:, 3*j+2] = S.max(1)
    return out
FEAT = {"raw": xr, "raw_knowgenes": xr[:, member], "know_pc": K.transform(xr, bases), "know_rich": rich(xr)}
print(f"member genes in >=1 set: {len(member)}/{len(hvg)}", flush=True)
def fit_pred(F, tr, te):
    scaler = StandardScaler().fit(F[tr]); aa = scaler.transform(F[tr]); bb = scaler.transform(F[te])
    clf = LogisticRegression(C=0.01, max_iter=8000, tol=1e-6, class_weight="balanced", solver="lbfgs")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always", ConvergenceWarning); clf.fit(aa, y[tr])
    if any(issubclass(v.category, ConvergenceWarning) for v in w) or int(clf.n_iter_.max()) >= 8000:
        raise RuntimeError("unconverged")
    return clf.predict_proba(bb)[:, 1]
rows = []
for T in ["lung", "spleen"]:
    te = np.where(tissue == T)[0]; tr = np.where(tissue != T)[0]; yt = y[te]
    ap = {a: float(average_precision_score(yt, fit_pred(F, tr, te))) for a, F in FEAT.items()}
    rows.append(dict(tissue=T, n_test=int(len(te)), n_pos=int(yt.sum()), **ap,
                     raw_knowgenes_minus_raw=ap["raw_knowgenes"] - ap["raw"],
                     know_pc_minus_raw=ap["know_pc"] - ap["raw"],
                     know_rich_minus_raw=ap["know_rich"] - ap["raw"]))
    print(json.dumps(rows[-1]), flush=True)
(OUT / "results.json").write_text(json.dumps(dict(protocol="selection_vs_aggregation_leave_tissue_out",
    n_member=int(len(member)), interpreter=sys.version, platform=platform.platform(), rows=rows), indent=2))
print("\n=== selection vs aggregation (full labels, per-cell-norm, held-out tissue AUPRC) ===", flush=True)
for r in rows:
    print(f" {r['tissue']:8s} raw={r['raw']:.3f}  raw_knowgenes={r['raw_knowgenes']:.3f}"
          f"({r['raw_knowgenes_minus_raw']:+.3f})  know_pc={r['know_pc']:.3f}({r['know_pc_minus_raw']:+.3f})"
          f"  know_rich={r['know_rich']:.3f}({r['know_rich_minus_raw']:+.3f})", flush=True)
print("SELECTION_VS_AGGREGATION_COMPLETE", flush=True)
