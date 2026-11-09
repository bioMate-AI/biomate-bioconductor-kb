"""Does EXTERNAL knowledge bridge an UNSEEN-GENE gap? (the GEARS regime — the decision point)

Every prior probe found no transfer advantage because all genes are measured. The literature's
knowledge-transfer win (GEARS) is specifically for UNSEEN entities: a GO/graph prior propagates signal
to genes with no data. This constructs that gap and tests the bridge with PURELY EXTERNAL knowledge.

Setup (feature-level, per-cell z-scored HVG xr, leave-one-tissue-out = hardest case):
  mask a random 30% of HVG genes -> "unseen" (zeroed in the raw features).
  raw_full     : all genes (upper bound)
  raw_masked   : unseen genes zeroed (lower bound = what you have without them)
  know_bridge  : raw_masked, but each unseen gene's slot filled by the mean of its SEEN gene-set
                 CO-MEMBERS (genes sharing >=1 GO/KEGG/Reactome/TF set) -- external knowledge only,
                 no coexpression, no data-derived graph, no test leak (membership is fixed a priori).
Question: does know_bridge recover toward raw_full from raw_masked? If yes, external knowledge bridges
unseen genes -> a real capability worth building (expiMap/graph program). If no, even the relational
knowledge bridge doesn't help here -> close the knowledge-for-transfer direction on this endpoint.

3 mask seeds for stability. Fixed C=0.01. CPU-only.
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
OUT = Path(AUD) / "unseen_gene_bridge_20261108"; OUT.mkdir(exist_ok=True)
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
xr = ((x - mu) / sd).astype(np.float32)
n_hvg = len(hvg)

# gene -> set of co-member gene indices (union over all gene sets it belongs to). External knowledge only.
bases = K.fit_bases(hvg, f"{WS}/fs_long/work")
comember = [set() for _ in range(n_hvg)]
for idx in (bases["pathways"] + bases["tf"]):
    il = idx.tolist()
    for g in il: comember[g].update(il)
for g in range(n_hvg): comember[g].discard(g)

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
    ap_full = float(average_precision_score(yt, fit_pred(xr, tr, te)))
    for ms in (0, 1, 2):
        rng = np.random.RandomState(ms)
        unseen = np.sort(rng.choice(n_hvg, size=int(0.30 * n_hvg), replace=False))
        seen = np.setdiff1d(np.arange(n_hvg), unseen)
        seen_set = set(seen.tolist())
        masked = xr.copy(); masked[:, unseen] = 0.0
        bridge = masked.copy(); n_bridged = 0
        for g in unseen:
            nb = [h for h in comember[g] if h in seen_set]   # seen co-members (external-knowledge neighbors)
            if nb:
                bridge[:, g] = xr[:, nb].mean(1); n_bridged += 1   # impute unseen gene from its seen co-members
        ap_mask = float(average_precision_score(yt, fit_pred(masked, tr, te)))
        ap_brdg = float(average_precision_score(yt, fit_pred(bridge, tr, te)))
        # recovery fraction: how much of the full-raw signal lost to masking does the bridge restore
        denom = (ap_full - ap_mask)
        rec = float((ap_brdg - ap_mask) / denom) if abs(denom) > 1e-6 else float("nan")
        rows.append(dict(tissue=T, mask_seed=ms, n_unseen=int(len(unseen)), n_bridged=int(n_bridged),
                         raw_full=ap_full, raw_masked=ap_mask, know_bridge=ap_brdg,
                         bridge_minus_masked=ap_brdg - ap_mask, lost_to_masking=ap_full - ap_mask,
                         recovery_frac=rec))
        print(json.dumps(rows[-1]), flush=True)

(OUT / "results.json").write_text(json.dumps(dict(protocol="unseen_gene_external_knowledge_bridge_leave_tissue_out",
    mask_frac=0.30, interpreter=sys.version, platform=platform.platform(), rows=rows), indent=2))
print("\n=== unseen-gene bridge (full labels, per-cell-norm, held-out tissue AUPRC; mean over 3 mask seeds) ===", flush=True)
for T in ["lung", "spleen"]:
    rs = [r for r in rows if r["tissue"] == T]
    full = rs[0]["raw_full"]; mask = np.mean([r["raw_masked"] for r in rs]); brdg = np.mean([r["know_bridge"] for r in rs])
    rec = np.nanmean([r["recovery_frac"] for r in rs])
    print(f" {T:8s} raw_full={full:.3f}  raw_masked={mask:.3f}  know_bridge={brdg:.3f}"
          f"   bridge-masked={brdg-mask:+.4f}  recovery={rec*100:+.0f}% of what masking lost", flush=True)
print("UNSEEN_GENE_BRIDGE_COMPLETE", flush=True)
