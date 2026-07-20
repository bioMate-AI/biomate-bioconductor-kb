#!/usr/bin/env python3
"""Phase-B BASELINE GATE — do simple linear baselines already solve the task?
If yes, a fine-tuned single-cell foundation model adds nothing (Ahlmann-Eltze 2025).

Baselines on donor pseudobulk (patient-level split, no leakage):
  1. cross-disease classification (SLE/RA/IBD/MS/Healthy): PCA + logistic regression
  2. cross-disease classification: mean-expression nearest-centroid
  3. IFN type-I signature score alone: SLE-vs-Healthy AUC (the "B" regression proxy)

Usage: python3 baseline_gate.py --corpus autoimmune_sc_corpus.h5ad --out out/
"""
import argparse, json, os
import numpy as np, pandas as pd, scipy.sparse as sp

IFN_GENES = ["ISG15", "IFI6", "IFI44", "IFI44L", "IFIT1", "IFIT3", "MX1", "MX2",
             "OAS1", "OAS2", "OAS3", "RSAD2", "LY6E", "USP18", "IFI27", "SIGLEC1",
             "HERC5", "EPSTI1", "OASL", "STAT1"]


def pseudobulk(adata):
    donor = adata.obs["donor_id"].astype(str).to_numpy()
    donors, inv = np.unique(donor, return_inverse=True)
    n_d = len(donors)
    M = sp.csr_matrix((np.ones(len(inv)), (inv, np.arange(len(inv)))),
                      shape=(n_d, adata.n_obs))
    X = adata.X
    if not sp.issparse(X):
        X = sp.csr_matrix(X)
    summed = np.asarray((M @ X).todense())    # n_d x n_genes, dense 2D
    counts = np.asarray(M.sum(1)).ravel()
    mean = np.asarray(summed / counts[:, None])
    pb = pd.DataFrame(mean, index=donors, columns=[str(v) for v in adata.var_names])
    meta = (adata.obs.drop_duplicates("donor_id")
            .assign(donor_id=lambda d: d["donor_id"].astype(str))
            .set_index("donor_id")[["disease_group", "split"]])
    meta = meta.reindex(donors)
    return pb, meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", required=True)
    ap.add_argument("--out", default="out")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    import anndata as ad
    from sklearn.decomposition import PCA
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.metrics import f1_score, roc_auc_score

    adata = ad.read_h5ad(args.corpus)
    pb, meta = pseudobulk(adata)
    # cap Healthy donors to reduce extreme imbalance (6k Healthy vs ~150 SLE)
    is_h = (meta["disease_group"] == "Healthy").to_numpy()
    rng = np.random.default_rng(0)
    h_idx = np.where(is_h)[0]
    keep_h = (rng.choice(h_idx, size=min(500, len(h_idx)), replace=False)
              if len(h_idx) else h_idx)
    keep = np.sort(np.concatenate([np.where(~is_h)[0], keep_h]))
    pb, meta = pb.iloc[keep], meta.iloc[keep]
    y = meta["disease_group"].to_numpy()
    split = meta["split"].to_numpy()
    Xlog = np.log1p(pb.to_numpy())
    tr, te = split == "train", split == "test"

    res = {"n_donors": int(len(pb)), "n_genes": int(pb.shape[1]),
           "class_counts": pd.Series(y).value_counts().to_dict()}

    # 1. PCA + logistic regression
    sc_ = StandardScaler().fit(Xlog[tr])
    Z = sc_.transform(Xlog)
    pca = PCA(n_components=min(50, tr.sum() - 1)).fit(Z[tr])
    P = pca.transform(Z)
    lr = LogisticRegression(max_iter=2000, class_weight="balanced").fit(P[tr], y[tr])
    yp = lr.predict(P[te])
    res["pca_lr_macro_f1"] = float(f1_score(y[te], yp, average="macro"))
    res["pca_lr_per_class_f1"] = {c: float(v) for c, v in
        zip(sorted(set(y[te])), f1_score(y[te], yp, average=None,
                                         labels=sorted(set(y[te]))))}

    # 2. mean-expression nearest-centroid
    cents = {c: Xlog[tr][y[tr] == c].mean(0) for c in np.unique(y[tr])}
    C = np.stack([cents[c] for c in sorted(cents)])
    order = sorted(cents)
    d = np.linalg.norm(Xlog[te][:, None, :] - C[None, :, :], axis=2)
    yc = np.array(order)[d.argmin(1)]
    res["centroid_macro_f1"] = float(f1_score(y[te], yc, average="macro"))

    # 3. IFN score alone: SLE vs Healthy AUC (var_names are Ensembl -> map symbols)
    symbols = (adata.var["feature_name"].astype(str).to_numpy()
               if "feature_name" in adata.var.columns
               else np.array([str(v) for v in adata.var_names]))
    pos = [i for i, s in enumerate(symbols) if s in IFN_GENES]
    res["ifn_genes_found"] = [symbols[i] for i in pos]
    if pos:
        zc = StandardScaler().fit_transform(Xlog[:, pos])
        score = zc.mean(1)
        mask = np.isin(y, ["SLE", "Healthy"])
        yb = (y[mask] == "SLE").astype(int)
        res["ifn_SLE_vs_Healthy_auc"] = float(roc_auc_score(yb, score[mask]))
        res["ifn_score_by_group"] = {c: float(score[y == c].mean())
                                     for c in np.unique(y)}

    json.dump(res, open(os.path.join(args.out, "baseline_metrics.json"), "w"), indent=2)
    print(json.dumps(res, indent=2))
    # verdict hint
    print("\nGATE HINT: if pca_lr_macro_f1 is already high, an FM adds little to the "
          "categorical head; the FM must earn its keep on activity stratification.")


if __name__ == "__main__":
    main()
