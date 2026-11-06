"""Stage cv / strata / lso of Part A3. usage: python3 strat_perf.py STAGE   (OMP_NUM_THREADS=8)"""
import sys, os, json, time
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
from sklearn.ensemble import HistGradientBoostingRegressor as H
from sklearn.model_selection import GroupKFold, KFold
from scipy.stats import spearmanr, rankdata
HERE = C.HERE; stage = sys.argv[1]
d = C.load_labelled(); n = len(d); y = d.y.values
print("labelled", n, flush=True)
Xb = C.fingerprints(d.SMILES.values, False); Xc = C.fingerprints(d.SMILES.values, True)
Xd, dcols = C.desc_matrix(d)
def mk(): return H(max_iter=150, learning_rate=0.1, random_state=0)
MODELS = {"fp_blind": Xb, "fp_chiral": Xc, "desc": Xd}

def cv_preds(X, splitter, groups=None):
    p = np.zeros(n)
    for tr, te in (splitter.split(X, y, groups) if groups is not None else splitter.split(X)):
        p[te] = mk().fit(X[tr], y[tr]).predict(X[te])
    return p

if stage == "cv":
    out = pd.DataFrame({"sid": d.index, "y": y, "nme_rule": d.n_nme_final.values.astype(float)})
    schemes = {"grp_flat": (GroupKFold(5), d.flat_id.values), "grp_source": (GroupKFold(5), d.Source.astype("category").cat.codes.values), "random": (KFold(5, shuffle=True, random_state=0), None)}
    for sc, (sp, g) in schemes.items():
        for name, X in MODELS.items():
            t = time.time(); out[f"{name}__{sc}"] = cv_preds(X, sp, g); print(sc, name, "%.0fs" % (time.time() - t), "spearman %.3f" % spearmanr(out[f"{name}__{sc}"], y)[0], flush=True)
    out.to_csv(os.path.join(HERE, "data", "cv_preds.csv.gz"), index=False)

def boot_ci(pred, yy, groups, B=1000, rng=None, kind="spearman"):
    rng = rng or np.random.default_rng(0)
    ug, inv = np.unique(groups, return_inverse=True); idx_by = [np.where(inv == k)[0] for k in range(len(ug))]
    vals = []
    for _ in range(B):
        pick = rng.integers(0, len(ug), len(ug)); ii = np.concatenate([idx_by[k] for k in pick])
        if kind == "spearman":
            if np.std(pred[ii]) == 0 or np.std(yy[ii]) == 0: vals.append(0.0); continue
            vals.append(spearmanr(pred[ii], yy[ii])[0])
        else: vals.append(np.mean(np.abs(pred[ii] - yy[ii])))
    return float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))

if stage == "strata":
    P = pd.read_csv(os.path.join(HERE, "data", "cv_preds.csv.gz")); assert (P.sid.values == d.index.values).all()
    S = C.strata(d); rows = []; rng = np.random.default_rng(1)
    for sname, lv in S.items():
        for lname, m in lv.items():
            k = int(m.sum())
            for sc in ("grp_flat", "grp_source"):
                for model in ("fp_blind", "fp_chiral", "desc", "nme_rule"):
                    col = f"{model}__{sc}" if model != "nme_rule" else "nme_rule"
                    if model == "nme_rule" and sc == "grp_source": continue
                    if k < 5: continue
                    pr = P[col].values[m]; yy = y[m]
                    if np.std(pr) == 0: rho = 0.0; lo = hi = 0.0
                    else:
                        rho = spearmanr(pr, yy)[0]; lo, hi = boot_ci(pr, yy, d.flat_id.values[m], rng=rng)
                    mae = np.nan if model == "nme_rule" else float(np.mean(np.abs(pr - yy)))
                    rows.append(dict(stratifier=sname, level=lname, n=k, n_groups=int(len(np.unique(d.flat_id.values[m]))), scheme=sc, model=model, spearman=rho, lo=lo, hi=hi, mae=mae,
                                     near_zero=bool(lo <= 0 <= hi), small=bool(k < 30)))
        print("done", sname, flush=True)
    pd.DataFrame(rows).to_csv(os.path.join(HERE, "data", "strata_perf.csv"), index=False)

if stage == "lso":
    S = C.strata(d); targets = {"topology": None, "length": None, "n_D": None, "peptoid": ["yes"], "unknown_monomer": ["yes"], "year": None}
    rows = []; flat = d.flat_id.values
    for sname, keep in targets.items():
        for lname, m in S[sname].items():
            if keep and lname not in keep: continue
            if m.sum() < 30: continue
            bad_groups = set(flat[m]); tr = np.array([f not in bad_groups for f in flat]) & ~m          # drop train peptides sharing a flat group with the held-out stratum
            for name, X in MODELS.items():
                t = time.time(); pr = mk().fit(X[tr], y[tr]).predict(X[m]); rho = spearmanr(pr, y[m])[0]
                rows.append(dict(stratifier=sname, level=lname, n_test=int(m.sum()), n_train=int(tr.sum()), model=name, spearman_lso=rho, mae_lso=float(np.mean(np.abs(pr - y[m])))))
                print(sname, lname, name, "rho %.3f" % rho, "%.0fs" % (time.time() - t), flush=True)
            pd.DataFrame(rows).to_csv(os.path.join(HERE, "data", "lso_perf.csv"), index=False)
