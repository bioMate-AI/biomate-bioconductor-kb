"""Feature-family analysis (Part A4). usage: OMP_NUM_THREADS=4 python3 feat_analysis.py  -> data/feat_*.csv, data/feat_summary.json"""
import sys, os, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C, stats as S
from sklearn.ensemble import HistGradientBoostingRegressor as H
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupKFold
from sklearn.preprocessing import StandardScaler
from scipy.stats import spearmanr

d = C.load_labelled(); y = d.y.values; n = len(d); flat = d.flat_id.values
fam = list(C.FAMILIES); mk = lambda: H(max_iter=150, learning_rate=0.1, random_state=0)
folds = list(GroupKFold(5).split(np.zeros(n), y, flat))
strat = C.strata(d); STR = {k: strat[k] for k in ("topology", "length", "n_D", "n_methyl")}

def cvpred(cols):
    X = d[cols].astype(float).values; p = np.zeros(n)
    for tr, te in folds: p[te] = mk().fit(X[tr], y[tr]).predict(X[te])
    return p

def rho_ci(p, mask=None, B=300):
    idx = np.where(mask)[0] if mask is not None else np.arange(n)
    pt, lo, hi = S.cluster_boot(lambda i: spearmanr(p[idx][i], y[idx][i])[0] if np.std(p[idx][i]) > 0 else 0.0, flat[idx], B=B)
    return pt, lo, hi

def strata_rho(p):
    out = {}
    for sn, lv in STR.items():
        for ln, m in lv.items():
            if m.sum() >= 30: out[f"{sn}:{ln}"] = (int(m.sum()), float(spearmanr(p[m], y[m])[0]) if np.std(p[m]) > 0 else 0.0)
    return out

rows = []
full_cols = [c for f in fam for c in C.FAMILIES[f]]
models = {"full": full_cols}
for f in fam: models["only:" + f] = C.FAMILIES[f]
for f in fam: models["without:" + f] = [c for g in fam if g != f for c in C.FAMILIES[g]]
preds = {}
for name, cols in models.items():
    p = cvpred(cols); preds[name] = p; pt, lo, hi = rho_ci(p)
    rows.append(dict(model=name, n_features=len(cols), spearman=pt, lo=lo, hi=hi, **{("rho_" + k): v[1] for k, v in strata_rho(p).items()}))
    print(name, "%.3f [%.3f, %.3f]" % (pt, lo, hi), flush=True)
fam_df = pd.DataFrame(rows); fam_df.to_csv(os.path.join(C.HERE, "data", "feat_family_models.csv"), index=False)
sn = {f"{sn}:{ln}": int(m.sum()) for sn, lv in STR.items() for ln, m in lv.items() if m.sum() >= 30}
json.dump(sn, open(os.path.join(C.HERE, "data", "feat_stratum_n.json"), "w"), indent=1)

# permutation importance by family (joint permutation of the family's columns within held-out folds, 30 repetitions)
rng = np.random.default_rng(0); R = 30; imp = {f: [] for f in fam}; imp_str = {f: {k: [] for k in sn} for f in fam}
base = preds["full"]; Xall = d[full_cols].astype(float).values; col_idx = {f: [full_cols.index(c) for c in C.FAMILIES[f]] for f in fam}
for rep in range(R):
    perm_p = {f: np.zeros(n) for f in fam}
    for tr, te in folds:
        model = mk().fit(Xall[tr], y[tr])
        for f in fam:
            Xt = Xall[te].copy(); pi = rng.permutation(len(te)); Xt[:, col_idx[f]] = Xt[pi][:, col_idx[f]]; perm_p[f][te] = model.predict(Xt)
    for f in fam:
        imp[f].append(spearmanr(base, y)[0] - spearmanr(perm_p[f], y)[0])
        for k in sn:
            sname, lname = k.split(":", 1); m = STR[sname][lname]
            imp_str[f][k].append(spearmanr(base[m], y[m])[0] - (spearmanr(perm_p[f][m], y[m])[0] if np.std(perm_p[f][m]) > 0 else 0.0))
    if rep % 5 == 0: print("perm rep", rep, flush=True)
pi_rows = []
for f in fam:
    v = np.array(imp[f]); pi_rows.append(dict(family=f, stratum="ALL", n=n, mean_drop=float(v.mean()), lo=float(np.percentile(v, 2.5)), hi=float(np.percentile(v, 97.5))))
    for k in sn:
        v = np.array(imp_str[f][k]); pi_rows.append(dict(family=f, stratum=k, n=sn[k], mean_drop=float(v.mean()), lo=float(np.percentile(v, 2.5)), hi=float(np.percentile(v, 97.5))))
pd.DataFrame(pi_rows).to_csv(os.path.join(C.HERE, "data", "feat_perm_importance.csv"), index=False)

# interactions: N-methyl x D grid and additive vs interaction models
nb = pd.cut(d.n_nme_final, [-1, 0, 2, 4, 100], labels=["0", "1-2", "3-4", ">=5"]); db = pd.cut(d.n_D, [-1, 0, 2, 100], labels=["0", "1-2", ">=3"])
grid = []
for a in nb.cat.categories:
    for b in db.cat.categories:
        m = ((nb == a) & (db == b)).values
        if m.sum() >= 5:
            pt, lo, hi = S.cluster_boot(lambda i: y[m][i].mean(), flat[m], B=300) if m.sum() >= 10 else (float(y[m].mean()), np.nan, np.nan)
            grid.append(dict(n_methyl=a, n_D=b, n=int(m.sum()), mean_z=pt, lo=lo, hi=hi))
pd.DataFrame(grid).to_csv(os.path.join(C.HERE, "data", "feat_interaction_grid.csv"), index=False)
def ridge_cv(X):
    p = np.zeros(n)
    for tr, te in folds:
        sc = StandardScaler().fit(X[tr]); p[te] = Ridge(alpha=1.0).fit(sc.transform(X[tr]), y[tr]).predict(sc.transform(X[te]))
    return p
a_, b_ = d.n_nme_final.values.astype(float), d.n_D.values.astype(float)
inter = {"ridge_additive(nMe,nD)": ridge_cv(np.c_[a_, b_]), "ridge_with_product": ridge_cv(np.c_[a_, b_, a_ * b_]), "gbm(nMe,nD)": cvpred(["n_nme_final", "n_D"])}
inter_rows = []
for k, p in inter.items(): pt, lo, hi = rho_ci(p); inter_rows.append(dict(model=k, spearman=pt, lo=lo, hi=hi))
pd.DataFrame(inter_rows).to_csv(os.path.join(C.HERE, "data", "feat_interaction_models.csv"), index=False)

# source confound: eta^2 between sources and pooled vs within-source correlation with the raw label
src = d.Source.values; yraw = d.y_raw.values; us = np.unique(src)
def eta2(v):
    """between-source share of variance (SSB / SST)."""
    tot = ((v - v.mean()) ** 2).sum()
    if tot == 0: return np.nan
    ssb = sum((src == s).sum() * (v[src == s].mean() - v.mean()) ** 2 for s in us)
    return float(ssb / tot)
sc_rows = []; big = [s for s in us if (src == s).sum() >= 30]
for c in full_cols:
    v = d[c].astype(float).values
    if np.std(v) == 0: continue
    pooled = spearmanr(v, yraw)[0]; zs = []; vs = []
    for s in big:
        m = src == s
        if np.std(v[m]) > 0: r = spearmanr(v[m], yraw[m])[0]; zs.append(np.arctanh(np.clip(r, -0.999, 0.999))); vs.append(1 / (m.sum() - 3))
    mt = S.dl_meta(zs, vs); within = float(np.tanh(mt["pooled"])) if mt["k"] else np.nan
    sc_rows.append(dict(feature=c, eta2_between_source=eta2(v), pooled_rho=pooled, within_source_rho=within, within_k=mt["k"], I2=mt["I2"],
                        confounded=bool(np.isfinite(within) and (np.sign(pooled) != np.sign(within) or abs(pooled - within) > 0.15))))
pd.DataFrame(sc_rows).to_csv(os.path.join(C.HERE, "data", "feat_source_confound.csv"), index=False)
json.dump(dict(label_eta2_between_source_raw=eta2(yraw), n=n, n_sources=int(len(us)), n_sources_ge30=len(big)), open(os.path.join(C.HERE, "data", "feat_summary.json"), "w"), indent=1)
print("done", flush=True)
