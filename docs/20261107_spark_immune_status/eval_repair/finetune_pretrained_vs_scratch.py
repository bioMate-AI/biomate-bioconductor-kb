#!/usr/bin/env python3
"""Does PRETRAINING help fine-tuning on external immune datasets? Same architecture, same data, same splits,
same head and hyperparameters; only the initialisation differs (pretrained checkpoint vs random).

Arms:  pretrained (all weights fine-tuned) | scratch (random init, identical architecture) |
       pretrained_frozen (encoder frozen, only the new head is trained)
Inputs: rna (the model's 2,000 genes, aligned by symbol; missing genes = 0)  or  rna_protein (adds the antibodies of
        the external panel that map onto the model's 35-antibody panel; other slots = 0). Knowledge/clinical/bulk/
        genetics inputs are not supplied (absent), identically for all arms.
Tasks (same labels and held-out units as the earlier per-dataset analyses):
  gse261278 : stimulated (flu/SARS) vs unstimulated, held-out CELL TYPES
  papalexi  : knockout of an IFN-gamma / PD-L1 regulator vs other perturbed cells, held-out GENES
Label budget: fraction of the training-fold cells used for fine-tuning (class-stratified).
Metrics: pooled out-of-fold AUROC and AUPRC; run over several seeds.
"""
import os, re, sys, json, time, argparse, subprocess
import numpy as np
import anndata as ad
import torch, torch.nn as nn
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score, average_precision_score
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import immune_hybrid_llm as H
from eval_protocols import fold_standardize, validate_checkpoint_parameters

REG = {"STAT1", "STAT2", "JAK1", "JAK2", "IRF1", "IRF2", "IRF7", "NFKBIA", "SPI1", "MYC", "IFNGR1", "IFNGR2", "B2M", "TAP1", "TAP2",
       "TAPBP", "NLRC5", "CMTM6", "CD274", "PDCD1LG2", "SOCS1", "BRD4", "ETV7"}
CTRL = {"NT", "CONTROL", "NTC", "SAFE", "NONTARGET", "NON-TARGETING", "NEG"}
log = lambda m: print(f"[ft] {time.strftime('%H:%M:%S')} {m}", flush=True)


def load_ckpt(path):
    local = path
    if path.startswith("s3://"):
        local = "/tmp/_ckpt_%d.pt" % abs(hash(path)); subprocess.run(["aws", "s3", "cp", path, local, "--quiet"], check=True)
    return torch.load(local, map_location="cpu", weights_only=False)


def build(ck, pretrained, seed):
    """Rebuild the checkpoint's architecture from its own saved config and tensor shapes; weights loaded only if pretrained."""
    sd, m = ck["trainable_state_dict"], ck["cfg_meta"]
    cfg = H.default_cfg()
    for k in ("n_genes", "chan_dim", "n_celltypes", "n_studies", "mod_dims", "d", "bottle", "concept_perpath", "n_programs"):
        if k in m: cfg[k] = m[k]
    cfg["hvg_names"] = m["hvg_names"]; cfg["backbone"] = ck["backbone"]; cfg["bottleneck_mode"] = ck["bottleneck_mode"]
    cfg["pep_dim"] = int(sd["pep_enc.0.weight"].shape[1]) if "pep_enc.0.weight" in sd else cfg["pep_dim"]
    cfg["n_programs"] = int(sd["h_biomk.weight"].shape[0]) if "h_biomk.weight" in sd else cfg["n_programs"]   # head width from the ckpt itself
    cfg["genetics_prior"] = torch.zeros(cfg["n_genes"]); cfg["mod_dropout"] = 0.0
    if "backbone.proto.weight" in sd: cfg["proto_init"] = torch.zeros_like(sd["backbone.proto.weight"])
    torch.manual_seed(seed)
    model = H.build_model(cfg, torch, nn)
    if pretrained:
        validate_checkpoint_parameters(model, sd)
        r = model.load_state_dict(sd, strict=False)
        if r.unexpected_keys: raise ValueError(f"Unexpected checkpoint keys: {r.unexpected_keys[:20]}")
    return model, cfg


class Clf(nn.Module):
    def __init__(s, model, cfg, use_protein):
        super().__init__(); s.m = model; s.cfg = cfg; s.use_protein = use_protein
        s.head = nn.Linear(cfg["bottle"], 1)
    def forward(s, xr, xp=None):
        B = xr.shape[0]; mods = {"rna": xr}; masks = {"rna": torch.ones(B, 1, device=xr.device)}
        if s.use_protein and xp is not None: mods["protein"] = xp; masks["protein"] = torch.ones(B, 1, device=xr.device)
        out = s.m(torch.zeros(B, s.cfg["seqlen"], dtype=torch.long, device=xr.device), mods, masks, xr)
        return s.head(out["z"]).squeeze(-1)


def align_genes(names, X, hvg):
    idx = {str(g).upper(): i for i, g in enumerate(names)}
    cols = [idx.get(str(g).upper(), -1) for g in hvg]
    out = np.zeros((X.shape[0], len(hvg)), np.float32)
    have = [j for j, c in enumerate(cols) if c >= 0]
    Xs = X[:, [cols[j] for j in have]]
    out[:, have] = np.asarray(Xs.todense() if hasattr(Xs, "todense") else Xs, np.float32)
    return out, len(have)


def clr(P):
    X = np.log1p(np.clip(P, 0, None)); return (X - X.mean(1, keepdims=True)).astype(np.float32)


def data_gse261278(path, hvg, panel):
    A = ad.read_h5ad(path)
    stim = A.obs["stim"].astype(str).str.lower().values
    y = np.array([0 if ("unstim" in s or "none" in s or "ctrl" in s) else 1 for s in stim], int)
    grp = A.obs["cell_type"].astype(str).values
    Xr, ng = align_genes(list(A.var_names), A.X, hvg); Xr = np.log1p(np.clip(Xr, 0, None)).astype(np.float32)
    names = list(A.uns["protein_names"]); P = np.asarray(A.obsm["protein_expression"], np.float32)
    slots = {m: i for i, m in enumerate(panel["model_panel"])}; match = panel["GSE261278"]["matched"]
    Xp = np.zeros((P.shape[0], len(slots)), np.float32); use = [(names.index(n), slots[m]) for n, m in match.items()]
    C = clr(P[:, [a for a, _ in use]])
    for k, (_, b) in enumerate(use): Xp[:, b] = C[:, k]
    log(f"gse261278: N={len(y)} stim+={int(y.sum())} genes aligned {ng}/{len(hvg)} | antibodies mapped {len(use)}/{len(slots)} | cell types {len(set(grp))}")
    return Xr, Xp, y, grp


def data_papalexi(path, hvg):
    A = ad.read_h5ad(path)
    gene = np.array([re.sub(r"[gG]\d+$", "", str(p)).upper() for p in A.obs["perturbation"].astype(str).values])
    keep = ~np.isin(gene, list(CTRL)); y = np.isin(gene, list(REG))[keep].astype(int); grp = gene[keep]
    Xr, ng = align_genes(list(A.var_names), A.X[keep] if hasattr(A.X, "tocsr") else np.asarray(A.X)[keep], hvg); Xr = np.log1p(np.clip(Xr, 0, None)).astype(np.float32)
    log(f"papalexi: N={len(y)} regulator+={int(y.sum())} genes aligned {ng}/{len(hvg)} | KO genes {len(set(grp))}")
    return Xr, None, y, grp


def fit_predict(clf, arm, Xtr, Ptr, ytr, Xte, Pte, epochs, lr, seed, device="cpu"):
    clf = clf.to(device)
    torch.manual_seed(seed); rng = np.random.RandomState(seed)
    params = list(clf.head.parameters()) if arm == "pretrained_frozen" else list(clf.parameters())
    if arm == "pretrained_frozen":
        for p in clf.m.parameters(): p.requires_grad_(False)
    opt = torch.optim.AdamW(params, lr=lr, weight_decay=1e-4)
    pw = torch.tensor([(ytr == 0).sum() / max(1, (ytr == 1).sum())], dtype=torch.float32, device=device); lossf = nn.BCEWithLogitsLoss(pos_weight=pw)
    Xt = torch.from_numpy(Xtr); Pt = torch.from_numpy(Ptr) if Ptr is not None else None; yt = torch.from_numpy(ytr.astype(np.float32))
    clf.train()
    if arm == "pretrained_frozen": clf.m.eval()
    for ep in range(epochs):
        perm = rng.permutation(len(ytr))
        for i in range(0, len(perm), 256):
            b = perm[i:i + 256]
            if len(b) < 4: continue
            opt.zero_grad(); loss = lossf(clf(Xt[b].to(device), Pt[b].to(device) if Pt is not None else None), yt[b].to(device)); 
            if not torch.isfinite(loss): raise ValueError("Nonfinite training loss")
            loss.backward(); opt.step()
    clf.eval(); out = []
    with torch.no_grad():
        Xe = torch.from_numpy(Xte); Pe = torch.from_numpy(Pte) if Pte is not None else None
        for i in range(0, len(Xe), 1024): out.append(torch.sigmoid(clf(Xe[i:i + 1024].to(device), Pe[i:i + 1024].to(device) if Pe is not None else None)).cpu().numpy())
    return np.concatenate(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True, choices=["gse261278", "papalexi"]); ap.add_argument("--data", required=True)
    ap.add_argument("--ckpt", required=True); ap.add_argument("--panel", default=os.path.join(os.path.dirname(__file__), "panel_overlap.json"))
    ap.add_argument("--seeds", default="0,1,2"); ap.add_argument("--budgets", default="0.01,0.1,1.0")
    ap.add_argument("--arms", default="pretrained,scratch,pretrained_frozen"); ap.add_argument("--inputs", default="rna,rna_protein")
    ap.add_argument("--epochs", type=int, default=12); ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--folds", type=int, default=5); ap.add_argument("--max-cells", type=int, default=0, help="subsample for smoke tests")
    ap.add_argument("--save-oof", default="", help="npz path: out-of-fold predictions + labels + groups for group-level bootstrap")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    ap.add_argument("--out", required=True); a = ap.parse_args()
    torch.set_num_threads(max(1, a.threads))
    ck = load_ckpt(a.ckpt); hvg = ck["cfg_meta"]["hvg_names"]; panel = json.load(open(a.panel))
    Xr, Xp, y, grp = data_gse261278(a.data, hvg, panel) if a.dataset == "gse261278" else data_papalexi(a.data, hvg)
    if a.max_cells and len(y) > a.max_cells:
        sel = np.sort(np.random.RandomState(0).choice(len(y), a.max_cells, replace=False)); Xr, y, grp = Xr[sel], y[sel], grp[sel]; Xp = Xp[sel] if Xp is not None else None
    inputs = [i for i in a.inputs.split(",") if (i == "rna" or Xp is not None)]
    res = []; oofs = {}; folds = list(GroupKFold(n_splits=min(a.folds, len(set(grp)))).split(Xr, y, grp))
    for inp in inputs:
        for arm in a.arms.split(","):
            for bud in [float(b) for b in a.budgets.split(",")]:
                for seed in [int(s) for s in a.seeds.split(",")]:
                    oof = np.full(len(y), np.nan)
                    for (tr, te) in folds:
                        if len(np.unique(y[tr])) < 2: continue
                        rng = np.random.RandomState(seed); sub = []
                        for c in (0, 1):
                            idc = tr[y[tr] == c]; k = max(2, int(round(bud * len(idc)))); sub.append(rng.choice(idc, min(k, len(idc)), replace=False))
                        sub = np.concatenate(sub)
                        model, cfg = build(ck, pretrained=(arm != "scratch"), seed=seed)
                        clf = Clf(model, cfg, use_protein=(inp == "rna_protein"))
                        Rtr, Rte = fold_standardize(Xr[sub], Xr[te])
                        Ptr, Pte = fold_standardize(Xp[sub], Xp[te]) if inp == "rna_protein" else (None, None)
                        oof[te] = fit_predict(clf, arm, Rtr, Ptr, y[sub], Rte, Pte, a.epochs, a.lr, seed, a.device)
                    m = np.isfinite(oof); oofs[f"{inp}|{arm}|{bud}|{seed}"] = oof.copy()
                    r = {"input": inp, "arm": arm, "budget": bud, "seed": seed, "auroc": round(float(roc_auc_score(y[m], oof[m])), 4), "auprc": round(float(average_precision_score(y[m], oof[m])), 4)}
                    res.append(r); log(json.dumps(r))
                    json.dump({"protocol": "labelled-train-only-scaling-v2", "device": a.device, "dataset": a.dataset, "ckpt": a.ckpt, "n_cells": int(len(y)), "epochs": a.epochs, "lr": a.lr, "results": res}, open(a.out, "w"), indent=1)
                    if a.save_oof: np.savez_compressed(a.save_oof, y=y, grp=grp.astype(str), **{k.replace("|", "__"): v for k, v in oofs.items()})


if __name__ == "__main__":
    main()
