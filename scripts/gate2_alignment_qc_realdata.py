"""Gate-2: reproduce the Gate-1 over-correction result on REAL single-cell data with a
REAL batch-correction method (Harmony), swept from correct to over-corrected.

Gate-1 (scripts/gate1_alignment_qc_overcorrection.py) showed IN SIMULATION that batch-only
metrics (iLISI/kBET) are fooled by over-correction while biology-conservation (ARI/cLISI)
catches it. Gate-2 asks: does that hold on real cells + real Harmony?

Mechanism: Harmony's `theta` controls batch-mixing aggressiveness. Sweep theta upward — at
some point Harmony stops removing only batch and starts merging biologically-distinct cell
types (over-correction). A trustworthy QC panel must flag that; a batch-only metric will keep
reporting "better mixed."

Deps: scanpy/anndata (already in the biomate notebook image) + harmonypy (one pip add) +
numpy + scikit-learn. NO scib needed — the metric panel is hand-rolled (same defs as Gate-1),
so there is no extra image dependency to validate.

Run (in a scanpy+harmonypy env, e.g. BioMate notebook/Batch):
  python gate2_alignment_qc_realdata.py --adata pancreas.h5ad \
      --batch-key tech --label-key celltype --thetas 0,0.5,1,2,4,8,16 --out gate2_results.json
"""
import argparse, json
import numpy as np

# ---- metric panel: identical definitions to Gate-1 (kNN-based), computed on an embedding ----
def _knn(emb, k):
    from sklearn.neighbors import NearestNeighbors
    nn = NearestNeighbors(n_neighbors=k + 1).fit(emb)
    return nn.kneighbors(emb, return_distance=False)[:, 1:]  # drop self

def lisi(labels, nn):
    labels = np.asarray(labels); out = np.empty(nn.shape[0])
    for i in range(nn.shape[0]):
        _, cnt = np.unique(labels[nn[i]], return_counts=True)
        p = cnt / cnt.sum(); out[i] = 1.0 / (p @ p)
    return float(out.mean())

def kbet_accept(batch, nn, tol=0.15):
    batch = np.asarray(batch); B = np.unique(batch)
    g = np.array([(batch == b).mean() for b in B]); ok = 0
    for i in range(nn.shape[0]):
        loc = np.array([(batch[nn[i]] == b).mean() for b in B])
        if np.abs(loc - g).max() <= tol: ok += 1
    return ok / nn.shape[0]

def ari(a, b):
    a = np.asarray(a); b = np.asarray(b); ua = np.unique(a); ub = np.unique(b)
    tab = np.array([[((a == i) & (b == j)).sum() for j in ub] for i in ua], float)
    comb = lambda n: n * (n - 1) / 2
    idx = comb(tab).sum(); ai = comb(tab.sum(1)).sum(); bj = comb(tab.sum(0)).sum()
    n = len(a); exp = ai * bj / comb(n); mx = (ai + bj) / 2
    return 0.0 if mx == exp else float((idx - exp) / (mx - exp))

def bio_ari(emb, labels):
    from sklearn.cluster import KMeans
    K = len(np.unique(labels))
    lab = KMeans(n_clusters=K, n_init=10, random_state=0).fit_predict(emb)
    return ari(labels, lab)

def score(emb, batch, celltype, k=30, subsample=4000, seed=0):
    rng = np.random.RandomState(seed)
    idx = np.arange(emb.shape[0])
    if emb.shape[0] > subsample: idx = rng.choice(idx, subsample, replace=False)
    e, b, c = emb[idx], np.asarray(batch)[idx], np.asarray(celltype)[idx]
    nn = _knn(e, k)
    return {"iLISI": lisi(b, nn), "cLISI": lisi(c, nn), "kBET": kbet_accept(b, nn),
            "ARI": bio_ari(e, c), "n_batch": int(len(np.unique(b))), "n_type": int(len(np.unique(c)))}

def harmony_embed(pca, meta, batch_key, theta):
    import harmonypy
    ho = harmonypy.run_harmony(pca, meta, [batch_key], theta=theta, max_iter_harmony=20)
    return ho.Z_corr.T  # cells x dims

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adata", required=True)
    ap.add_argument("--batch-key", required=True)
    ap.add_argument("--label-key", required=True)
    ap.add_argument("--thetas", default="0,0.5,1,2,4,8,16")
    ap.add_argument("--n-hvg", type=int, default=2000)
    ap.add_argument("--n-pcs", type=int, default=30)
    ap.add_argument("--out", default="gate2_results.json")
    a = ap.parse_args()
    import scanpy as sc
    thetas = [float(x) for x in a.thetas.split(",")]

    ad = sc.read_h5ad(a.adata)
    batch = ad.obs[a.batch_key].astype(str).values
    celltype = ad.obs[a.label_key].astype(str).values
    # standard preprocessing → PCA (the uncorrected embedding).
    # DEFENSIVE: some benchmark h5ads (e.g. scIB *_norm_*) already hold log-normalized .X —
    # re-normalizing would double-log. Prefer a raw 'counts' layer; else detect raw-vs-norm.
    import numpy as _np
    if "counts" in ad.layers:
        ad.X = ad.layers["counts"].copy()
        sc.pp.normalize_total(ad, target_sum=1e4); sc.pp.log1p(ad)
        print("[prep] used 'counts' layer → normalize+log1p")
    else:
        xmax = float(ad.X.max())
        looks_raw = xmax > 50 and float(_np.abs(ad.X[:50].toarray() % 1).sum()
                                        if hasattr(ad.X, "toarray") else _np.abs(ad.X[:50] % 1).sum()) == 0
        if looks_raw:
            sc.pp.normalize_total(ad, target_sum=1e4); sc.pp.log1p(ad)
            print(f"[prep] .X looks like raw counts (max={xmax:.0f}) → normalize+log1p")
        else:
            print(f"[prep] .X already normalized (max={xmax:.2f}) → skip normalize/log1p")
    sc.pp.highly_variable_genes(ad, n_top_genes=a.n_hvg, subset=True)
    sc.pp.scale(ad, max_value=10); sc.tl.pca(ad, n_comps=a.n_pcs)
    pca = ad.obsm["X_pca"]
    meta = ad.obs[[a.batch_key]].copy()

    rows = [{"stage": "uncorrected", "theta": None, **score(pca, batch, celltype)}]
    for th in thetas:
        emb = harmony_embed(pca, meta, a.batch_key, th)
        rows.append({"stage": f"harmony_theta_{th}", "theta": th,
                     **score(emb, batch, celltype)})

    # the verdict test: does a batch-only metric keep improving while biology collapses?
    best_bio = max(r["ARI"] for r in rows)
    for r in rows:
        r["biology_ok"] = r["ARI"] >= 0.9 * best_bio  # within 10% of best bio conservation
    print(f"{'stage':22} {'iLISI↑':>8} {'cLISI↓':>8} {'kBET↑':>8} {'ARI↑':>8} {'bio_ok':>7}")
    for r in rows:
        print(f"{r['stage']:22} {r['iLISI']:8.3f} {r['cLISI']:8.3f} {r['kBET']:8.3f} "
              f"{r['ARI']:8.3f} {str(r['biology_ok']):>7}")
    # over-correction = high batch-mixing but biology NOT ok
    over = [r for r in rows if r["theta"] and r["kBET"] >= 0.8 and not r["biology_ok"]]
    print(f"\nOVER-CORRECTED configs (batch-mixed but biology erased): "
          f"{[r['stage'] for r in over] or 'none'}")
    print("→ a batch-only gate would PASS these; the panel (ARI/cLISI) FLAGS them."
          if over else "→ no over-correction reached in this theta range.")
    with open(a.out, "w") as f: json.dump(rows, f, indent=2)
    print(f"wrote {a.out}")

if __name__ == "__main__":
    main()
