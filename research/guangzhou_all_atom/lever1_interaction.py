#!/usr/bin/env python3
"""LEVER 1 — license-clean INTERACTION model: does a learned ligand×target interaction
break the ~0.42 novel-target ceiling where concat (0.35) and ligand-only (0.445) couldn't?

License-clean build (commercial): ESM-2 (MIT) pooled target emb + RDKit ECFP (BSD) ligand,
an explicit learned INTERACTION head (bilinear + gated cross terms, torch) — NOT DrugCLIP's
research weights. Trained from scratch on our data. Same grouped leave-targets-out split.
Controls: ligand_only-MLP (fair MLP-vs-MLP) + target_only (leakage probe).

NOTE: this is a POOLED-embedding interaction (bilinear/gated), not full token-level
cross-attention. If it fails like concat, the data-wall conclusion strengthens; full
token cross-attention (GPU) is the one remaining heavier variant, flagged in the doc.
"""
import json, os, time
import numpy as np
from scipy.stats import spearmanr
from sklearn.model_selection import GroupKFold
from benchmark_binding_models import load_and_clean, CSV, RESULTS

LIG_CACHE = os.path.join(RESULTS, "binding_feature_cache.npz")
EMB_CACHE = os.path.join(RESULTS, "target_esm_emb.npz")
ASSAY = ["IC50", "Ki", "EC50", "Kd"]


def build():
    df = load_and_clean(CSV).reset_index(drop=True)
    z = np.load(LIG_CACHE, allow_pickle=True)
    assert bool((z["smiles"] == df["smiles"].values).all())
    fp, desc = z["fp"].astype(np.float32), z["desc"].astype(np.float32)
    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True); fp, desc = fp[mask], desc[mask]
    lig = np.nan_to_num(np.hstack([fp, desc]), nan=0.0, posinf=0.0, neginf=0.0)
    lig[:, fp.shape[1]:] = np.clip(lig[:, fp.shape[1]:], -1e6, 1e6)
    e = np.load(EMB_CACHE, allow_pickle=True)
    emb = {a: e["emb"][i] for i, a in enumerate(e["accs"])}
    D = e["emb"].shape[1]
    tgt = df["target_uniprot"].fillna("").astype(str).str.split(",").str[0].values
    T = np.vstack([emb.get(a, np.zeros(D, np.float32)) for a in tgt])
    y = df["pAff"].values.astype(np.float32)
    keep = np.array([(a in emb and np.any(emb[a])) for a in tgt]) & (tgt != "")
    return lig[keep], T[keep], y[keep], tgt[keep]


def train_eval(Xl, Xt, y, groups, mode, epochs=60):
    """mode: ligand_only | target_only | interaction. Returns per-fold Spearman."""
    import torch, torch.nn as nn
    torch.manual_seed(0)
    # standardize
    def std(A):
        m, s = A.mean(0, keepdims=True), A.std(0, keepdims=True) + 1e-6
        return (A - m) / s
    Xl, Xt = std(Xl.astype(np.float32)), std(Xt.astype(np.float32))
    gkf = GroupKFold(n_splits=5); folds = []
    for tr, te in gkf.split(Xl, y, groups):
        dl, dt = Xl.shape[1], Xt.shape[1]; H = 256
        lp = nn.Sequential(nn.Linear(dl, H), nn.ReLU(), nn.Linear(H, 128))
        tp = nn.Sequential(nn.Linear(dt, H), nn.ReLU(), nn.Linear(H, 128))
        if mode == "interaction":
            head = nn.Sequential(nn.Linear(128 + 128 + 128, 128), nn.ReLU(), nn.Dropout(0.2), nn.Linear(128, 1))
        else:
            head = nn.Sequential(nn.Linear(128, 128), nn.ReLU(), nn.Dropout(0.2), nn.Linear(128, 1))
        params = list(head.parameters())
        if mode in ("ligand_only", "interaction"): params += list(lp.parameters())
        if mode in ("target_only", "interaction"): params += list(tp.parameters())
        opt = torch.optim.Adam(params, lr=1e-3, weight_decay=1e-5)
        lossf = nn.MSELoss()
        Xl_tr = torch.tensor(Xl[tr]); Xt_tr = torch.tensor(Xt[tr]); y_tr = torch.tensor(y[tr]).unsqueeze(1)
        Xl_te = torch.tensor(Xl[te]); Xt_te = torch.tensor(Xt[te])
        n = len(tr); B = 512
        for ep in range(epochs):
            perm = torch.randperm(n)
            for i in range(0, n, B):
                bi = perm[i:i+B]
                opt.zero_grad()
                lv = lp(Xl_tr[bi]); tv = tp(Xt_tr[bi])
                if mode == "ligand_only": feat = lv
                elif mode == "target_only": feat = tv
                else: feat = torch.cat([lv, tv, lv * tv], 1)  # gated interaction term
                loss = lossf(head(feat), y_tr[bi]); loss.backward(); opt.step()
        with torch.no_grad():
            lv = lp(Xl_te); tv = tp(Xt_te)
            if mode == "ligand_only": feat = lv
            elif mode == "target_only": feat = tv
            else: feat = torch.cat([lv, tv, lv * tv], 1)
            pred = head(feat).squeeze(1).numpy()
        folds.append(float(spearmanr(y[te], pred).correlation))
    v = np.array(folds)
    return {"spearman_mean": float(v.mean()), "spearman_std": float(v.std()), "folds": [round(x, 3) for x in v]}


def main():
    t0 = time.time()
    Xl, Xt, y, tgt = build()
    print(f"rows {len(y)} targets {len(set(tgt))}  ({time.time()-t0:.0f}s)", flush=True)
    rep = {"n_rows": int(len(y)), "note": "pooled bilinear/gated interaction MLP (license-clean: ESM-2 MIT + RDKit ECFP); NOT token cross-attention", "splits": {}}
    for mode in ["ligand_only", "target_only", "interaction"]:
        print(f"== MLP {mode} ==  ({time.time()-t0:.0f}s)", flush=True)
        rep["splits"][mode] = train_eval(Xl, Xt, y, tgt, mode)
        print(json.dumps(rep["splits"][mode]), flush=True)
    mj = os.path.join(RESULTS, "binding_model_benchmark_cyclic.json")
    d = json.load(open(mj)); d["lever1_interaction_mlp"] = rep; json.dump(d, open(mj, "w"), indent=2)
    print(f"appended lever1_interaction_mlp  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
