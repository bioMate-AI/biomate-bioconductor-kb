#!/usr/bin/env python3
"""Few-shot adaptation to HELD-OUT studies: trained encoder embedding vs raw genes vs a linear compression of the genes.

Same cells, genes, labels and study split as the capped-subset transfer result (b2_train_encoder.load_b0_folds +
featurize, identical arguments to run_b2_seed_repeat_spot.sh). The encoder checkpoint is the final checkpoint of a
seed-repeat run (bottleneck arm 'free'). Protocol: from the held-out TEST cells, draw k labelled cells per cell type
(the adaptation set), fit the classifier on those cells only, and score macro-F1 on the remaining test cells.
Features, each with the same classifier (standardise + multinomial logistic regression, C=1, max_iter=500):
  z      encoder embedding (64-d)
  raw    the 2,000-gene input
  lin64  64-component PCA of the genes, fitted on TRAINING-study cells only
Five random draws per k. No hyper-parameter is tuned for any feature set.
"""
import os, sys, json, argparse, subprocess
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import b2_train_encoder as B2
import immune_hybrid_llm as H
from eval_protocols import within_study_fewshot
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

log = B2.log; B = B2.B


def fewshot(X, y, k, seed):
    rng = np.random.RandomState(seed); ad = []
    for c in np.unique(y):
        ix = np.flatnonzero(y == c); n = min(k, max(1, len(ix) // 2))
        ad.append(rng.choice(ix, n, replace=False))
    ad = np.concatenate(ad); rest = np.setdiff1d(np.arange(len(y)), ad)
    clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=500, n_jobs=-1)).fit(X[ad], y[ad])
    return float(f1_score(y[rest], clf.predict(X[rest]), average="macro"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="/opt/b2/work"); ap.add_argument("--cache-tag", default="v7_capT100_capVT800")
    ap.add_argument("--ckpt-seeds", default="1,2"); ap.add_argument("--ks", default="4,16,64,256"); ap.add_argument("--draws", type=int, default=5)
    ap.add_argument("--out-s3", required=True); ap.add_argument("--n-pathways", type=int, default=512)
    a = ap.parse_args(); os.makedirs(a.work, exist_ok=True)
    import torch, torch.nn as nn
    cg = os.path.join(a.work, "canon.txt"); B2.s3cp(f"{B}/harmonized/canonical_genes.txt", cg)
    canon = [l.strip() for l in open(cg) if l.strip()]
    folds, _ = B2.load_b0_folds(a.work, a.cache_tag, prefetch=12)
    ncanon = folds["train"]["X"].shape[1]; canon_idx = {g: i for i, g in enumerate(canon[:ncanon])}
    P_canon = B2.load_gmt_membership(a.work, canon_idx, ncanon, K=a.n_pathways)
    data, hvg_names, meta = B2.featurize(folds, canon, 2000, 64, 9, P_canon)          # identical to the transfer run
    gp = B2.genetics_prior_over_hvg(a.work, hvg_names)
    cfg = H.default_cfg()
    cfg.update({"d": 128, "bottle": 64, "seqlen": 64, "vocab": len(hvg_names), "n_genes": len(hvg_names),
                "chan_dim": data["chan"].shape[1], "n_celltypes": meta["n_celltypes"], "n_studies": meta["n_studies"],
                "n_programs": 1, "mod_dims": {"rna": len(hvg_names), "knowledge": data["chan"].shape[1]},
                "mod_dropout": 0.0, "hvg_names": hvg_names, "_genetics_prior": gp, "kn2_denovo": 8, "kn2_perpath": 2})
    cfg["loss_weights"] = dict(cfg["loss_weights"]); cfg["loss_weights"].update({"strat": 0.0, "biomk": 0.0})
    cfg["bottleneck_mode"] = "free"; cfg["backbone"] = "stub"; cfg["batch_defense"] = "on"; cfg["genetics_prior"] = torch.tensor(cfg["_genetics_prior"])
    tr, te = data["split_tr"], data["split_te"]; y = data["y"]; yte = y[te]
    log(f"test cells {len(te)} in {len(np.unique(data['study'][te]))} studies; classes {len(np.unique(yte))}")
    Xraw_te = np.asarray(data["expr"][te], dtype=np.float32)   # cache may hold float16
    pca = PCA(n_components=64, random_state=0).fit(np.asarray(data["expr"][tr], dtype=np.float32)); Xlin_te = pca.transform(Xraw_te)
    out = {"protocol": "k labelled cells per class drawn from held-out-study cells; classifier fitted on them; macro-F1 on the remaining held-out cells",
           "n_test_cells": int(len(te)), "n_test_studies": int(len(np.unique(data["study"][te]))), "ks": a.ks, "draws": a.draws, "ckpts": {}}
    for sd in [int(s) for s in a.ckpt_seeds.split(",")]:
        loc = os.path.join(a.work, f"ckpt_free_s{sd}_final.pt")
        B2.s3cp(f"{B}/immune_llm_models/B2_seed_repeat/seed{sd}/ckpt_free_s{sd}_final.pt", loc)
        model = H.build_model(cfg, torch, nn); model.load_state_dict(torch.load(loc, map_location="cpu")); model.eval()
        zs = []
        with torch.no_grad():
            for j in range(0, len(te), 512):
                b = H.slice_batch(data, te[j:j + 512], torch); mods, masks = H.build_mods(b, torch)
                zs.append(model(b["tokens"], mods, masks, b["expr"])["z"].cpu().numpy())
        Z = np.vstack(zs); log(f"ckpt seed {sd}: embedded {Z.shape}")
        # sanity: frozen-z probe from the TRAINING studies must be near the reported value (0.654 / 0.661)
        ztr = []
        sub = np.random.RandomState(0).choice(tr, min(100000, len(tr)), replace=False)
        with torch.no_grad():
            for j in range(0, len(sub), 512):
                b = H.slice_batch(data, sub[j:j + 512], torch); mods, masks = H.build_mods(b, torch)
                ztr.append(model(b["tokens"], mods, masks, b["expr"])["z"].cpu().numpy())
        clf = LogisticRegression(max_iter=500, n_jobs=-1).fit(np.vstack(ztr), y[sub])
        sanity = float(f1_score(yte, clf.predict(Z), average="macro")); log(f"SANITY zero-shot frozen-z probe (100k train cells, all test cells) = {sanity:.4f}")
        res = {"sanity_zero_shot_frozen_z": round(sanity, 4)}
        for k in [int(x) for x in a.ks.split(",")]:
            r = {}
            for name, X in (("z", Z), ("raw", Xraw_te), ("lin64", Xlin_te)):
                v = [fewshot(X, yte, k, s) for s in range(a.draws)]; r[name] = {"mean": round(float(np.mean(v)), 4), "sd": round(float(np.std(v)), 4)}
            r["within_study_v2"] = {
                name: [within_study_fewshot(X, yte, data["study"][te], k, draw) for draw in range(a.draws)]
                for name, X in (("z", Z), ("raw", Xraw_te), ("lin64", Xlin_te))}
            res[f"k{k}"] = r; log(f"seed {sd} k={k}: " + json.dumps(r))
        out["ckpts"][f"seed{sd}"] = res
    loc = os.path.join(a.work, "fewshot_baselines.json"); json.dump(out, open(loc, "w"), indent=1)
    subprocess.run(["aws", "s3", "cp", loc, a.out_s3 + "fewshot_baselines.json", "--quiet"], check=True)
    log("DONE")


if __name__ == "__main__":
    main()
