"""Activity-cliff and pair-ordering analysis by transformation type (Part A5). Uses PAMPA pairs (within source) and grouped-CV (flat-structure) predictions.
Ordering accuracy is reported (i) on pairs whose two members lie in the SAME held-out fold (neither partner label seen in training: clean) and
(ii) on pairs in different folds (partner label in training: SAR setting, optimistic reference). Ties count 0.5."""
import sys, os, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C, stats as S
from sklearn.model_selection import GroupKFold
d = C.load_labelled(); y = d.y.values; flat = d.flat_id.values
fold = np.zeros(len(d), int)
for k, (_, te) in enumerate(GroupKFold(5).split(np.zeros(len(d)), y, flat)): fold[te] = k
P = pd.read_csv(os.path.join(C.HERE, "data", "cv_preds.csv.gz")); assert (P.sid.values == d.index.values).all()
pos = {sid: i for i, sid in enumerate(d.index)}
pr = pd.read_csv(os.path.join(C.HERE, "data", "mmp_pairs_pampa.csv.gz")); pr = pr[pr.id_a.isin(pos) & pr.id_b.isin(pos)].copy()
ia = pr.id_a.map(pos).values; ib = pr.id_b.map(pos).values
pr["same_fold"] = fold[ia] == fold[ib]; pr["flat_a"] = flat[ia]; pr["abs_dz"] = pr["dz"].abs(); pr["cliff"] = pr["abs_dz"] > 1.0
models = {"fp_blind": "fp_blind__grp_flat", "fp_chiral": "fp_chiral__grp_flat", "desc": "desc__grp_flat"}
for m, col in models.items():
    p = P[col].values; dp = pr["sign"].values * (p[ib] - p[ia]); dy = pr["sign"].values * (y[ib] - y[ia])
    pr[f"acc_{m}"] = np.where(np.abs(dy) < 1e-9, np.nan, np.where(np.abs(dp) < 1e-9, 0.5, (np.sign(dp) == np.sign(dy)).astype(float)))
rows = []
for lab, sub in pr.groupby("label"):
    if len(sub) < 30: continue
    row = dict(transformation=lab, n_pairs=int(len(sub)), n_sources=int(sub.source.nunique()), n_cliffs=int(sub.cliff.sum()),
               cliff_rate=float(sub.cliff.mean()), cliff_lo=np.nan, cliff_hi=np.nan, n_same_fold=int(sub.same_fold.sum()), n_cross_fold=int((~sub.same_fold).sum()))
    _, lo, hi = S.cluster_boot(lambda i: sub.cliff.values[i].mean(), sub.flat_a.values, B=300); row["cliff_lo"], row["cliff_hi"] = lo, hi
    for m in models:
        for tag, ss in (("same_fold", sub[sub.same_fold]), ("cross_fold", sub[~sub.same_fold]), ("same_fold_cliffs", sub[sub.same_fold & sub.cliff])):
            v = ss[f"acc_{m}"].dropna()
            row[f"acc_{m}_{tag}"] = float(v.mean()) if len(v) >= 20 else np.nan; row[f"n_{m}_{tag}"] = int(len(v))
    rows.append(row)
out = pd.DataFrame(rows).sort_values("n_pairs", ascending=False); out.to_csv(os.path.join(C.HERE, "data", "cliffs_by_transformation.csv"), index=False)
pd.set_option("display.width", 300); pd.set_option("display.max_columns", 40)
print(out[["transformation", "n_pairs", "cliff_rate", "cliff_lo", "cliff_hi", "n_same_fold", "acc_fp_blind_same_fold", "acc_fp_chiral_same_fold", "acc_desc_same_fold", "acc_fp_blind_cross_fold", "acc_fp_chiral_cross_fold"]].round(3).to_string(index=False))
