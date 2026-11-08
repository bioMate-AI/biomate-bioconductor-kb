#!/usr/bin/env python3
"""Committee-2 follow-up checks on the validity gate (analysis I). Read-only on repo data; writes ext_check_gate.json next to this file.
(1) Label-permutation null: permute labels within each target (class counts preserved), rerun the gate; C1/C2/C3 must be compatible with 0.5.
(2) Compound-disjoint controls: for each held-out fold, drop from the training rows every compound that also appears in the held-out fold's rows
    (a compound that is in >1 target/family would otherwise be in both train and test of the no-target classifier). Compare with the registered gate.
Neither check changes any reported number; they test whether the registered gate numbers are artefacts of (a) pipeline bias or (b) compound overlap across folds."""
import os, sys, json
import numpy as np, pandas as pd
RR = "/Users/kky/biomate-review/research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery"
sys.path.insert(0, RR); os.chdir(RR)
import validity_gate as G
import harness as H
from validity_gate import _family_ci
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

DATA = f"{RR}/data"
prox = G.load_proxies(); T = pd.read_csv(f"{DATA}/targets.csv"); tfam = T[["target_key", "family", "genes"]]
fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold))
items = pd.read_csv(f"{DATA}/items_I.csv.gz")
FP = G.fp_table(items.compound_id)
fam_of = tfam.set_index("target_key").family


def per_target_auc(items, scored):
    rows = []
    for t, g in scored.groupby("target_key"):
        m = items[items.target_key == t].merge(g, on=["target_key", "compound_id"])
        rows.append(dict(target_key=t, auc=H.tie_aware_auc(m.label.values, m.score.values)))
    return _family_ci(pd.DataFrame(rows), tfam, 0.95)


def scores_disjoint(items, kind):
    it = items.copy(); it["fold"] = it.target_key.map(fam_of).map(folds)
    if kind == "C2":
        X = prox[G.MULTI].astype(float); ok = X.notna().all(axis=1); it = it[it.compound_id.isin(ok[ok].index)]
    out = []
    for f in sorted(it.fold.unique()):
        te = it[it.fold == f]; tr = it[(it.fold != f) & (~it.compound_id.isin(set(te.compound_id)))]       # compound-disjoint training rows
        if tr.label.nunique() < 2 or len(tr) < 50: continue
        if kind == "C2":
            sc = StandardScaler().fit(X.loc[tr.compound_id].values)
            lr = LogisticRegression(C=0.1, max_iter=1000, class_weight="balanced").fit(sc.transform(X.loc[tr.compound_id].values), tr.label.values)
            s = lr.decision_function(sc.transform(X.loc[te.compound_id].values))
        else:
            Xtr = np.log1p(FP.loc[tr.compound_id].values); Xte = np.log1p(FP.loc[te.compound_id].values)
            lr = LogisticRegression(C=0.05, max_iter=1000, class_weight="balanced").fit(Xtr, tr.label.values); s = lr.decision_function(Xte)
        out.append(te[["target_key", "compound_id"]].assign(score=s))
    return pd.concat(out)


res = {}
base = G.run_gate(items, tfam, prox, folds, FP=FP)
res["registered_gate"] = {k: (v if isinstance(v, str) else {kk: round(float(vv), 4) if isinstance(vv, float) else vv for kk, vv in v.items()}) for k, v in base["primary"].items()}
it_f = items.assign(fold=items.target_key.map(fam_of).map(folds))
overlap = {int(f): int(it_f[it_f.fold == f].compound_id.isin(set(it_f[it_f.fold != f].compound_id)).sum()) for f in sorted(it_f.fold.unique())}
res["train_test_compound_overlap_rows_per_fold"] = overlap
res["rows_total"] = int(len(items))
res["compound_disjoint"] = {"C2": per_target_auc(items, scores_disjoint(items, "C2")), "C3": per_target_auc(items, scores_disjoint(items, "C3"))}
perm = []
for seed in range(5):
    rng = np.random.default_rng(1000 + seed); it = items.copy()
    it["label"] = it.groupby("target_key").label.transform(lambda s: rng.permutation(s.values))
    r = G.run_gate(it, tfam, prox, folds, FP=FP)
    perm.append({k: round(float(v["point"]), 4) for k, v in r["primary"].items() if isinstance(v, dict)})
res["label_permutation_null_5_runs"] = perm
res["label_permutation_null_mean"] = {k: round(float(np.mean([p[k] for p in perm if k in p])), 4) for k in perm[0]}
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ext_check_gate.json"), "w"), indent=1, default=float)
print(json.dumps(res, indent=1, default=float))
