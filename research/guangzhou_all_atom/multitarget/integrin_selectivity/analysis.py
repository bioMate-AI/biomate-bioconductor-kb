"""Runs the pre-registered tasks (see README sections 1). Hyper-parameters are fixed constants below; nothing is tuned."""
import json, warnings
import numpy as np, pandas as pd
from scipy.stats import spearmanr, pearsonr
from rdkit import Chem
from rdkit.Chem import rdFingerprintGenerator
from sklearn.linear_model import Ridge
from pathlib import Path
import integrin_seq
warnings.filterwarnings("ignore")
HERE = Path(__file__).parent
INT = ["avb3", "avb5", "avb6", "avb8", "a5b1"]
RNG = np.random.default_rng(20261025)
NBOOT = 2000
RIDGE_ALPHA, GP_LAMBDA, SOFTMAX_T, LOIO_LAMBDA, FLOOR = 1.0, 0.1, 0.05, 0.1, 0.3

# ------------------------------------------------------------------ data
mx = pd.read_csv(HERE / "matrix.csv")
kp = mx[mx.source == "kapp2017"]
lig_names = list(dict.fromkeys(kp.ligand_id))
Y = np.full((len(lig_names), 5), np.nan); C = np.zeros_like(Y, bool)
for r in kp.itertuples():
    if r.integrin in INT:
        i, j = lig_names.index(r.ligand_id), INT.index(r.integrin)
        Y[i, j] = r.pIC50; C[i, j] = r.censor == ">"
assert not np.isnan(Y).any()
NL = len(lig_names)
lg = pd.read_csv(HERE / "ligands.csv").fillna("")
smi = {r.ligand_id: (r.smiles, r.tier) for r in lg.itertuples() if r.source == "kapp2017"}
S_all = [i for i, n in enumerate(lig_names) if smi[n][0]]
S_A = [i for i in S_all if smi[lig_names[i]][1] == "A"]
gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
FP = {i: np.log1p(gen.GetCountFingerprintAsNumPy(Chem.MolFromSmiles(smi[lig_names[i]][0])).astype(float)) for i in S_all}
RAW = {i: gen.GetCountFingerprintAsNumPy(Chem.MolFromSmiles(smi[lig_names[i]][0])).astype(float) for i in S_all}


def tanimoto_minmax(a, b):
    return np.minimum(a, b).sum() / max(np.maximum(a, b).sum(), 1e-9)

# ------------------------------------------------------------------ models (LOLO)
def lolo_predict(model, subset):
    """Hold out each ligand in `subset` (whole ligand); training = subset minus that ligand."""
    P = np.full((NL, 5), np.nan)
    for i in subset:
        tr = [t for t in subset if t != i]
        P[i] = model(tr, i)
    return P

def n_mean(tr, i): return Y[tr].mean(0)
def n_median(tr, i): return np.median(Y[tr], 0)
def mk_n_mean_all(subset):  # same null but trained on ALL other 34 ligands (stronger, more data)
    return lambda tr, i: Y[[t for t in range(NL) if t != i]].mean(0)
def m1_ridge(tr, i):
    X = np.array([FP[t] for t in tr]); mdl = Ridge(alpha=RIDGE_ALPHA).fit(X, Y[tr])
    return mdl.predict(FP[i][None])[0]
def m2_gp(tr, i):
    X = [RAW[t] for t in tr]; K = np.array([[tanimoto_minmax(a, b) for b in X] for a in X])
    mu = Y[tr].mean(0); a = np.linalg.solve(K + GP_LAMBDA * np.eye(len(tr)), Y[tr] - mu)
    k = np.array([tanimoto_minmax(RAW[i], b) for b in X]); return mu + k @ a
def m3_rr(tr, i):
    X = np.array([FP[t] for t in tr]); mdl = Ridge(alpha=RIDGE_ALPHA).fit(X, Y[tr])
    F = mdl.predict(X); mu = F.mean(0); _, _, Vt = np.linalg.svd(F - mu, full_matrices=False); v = Vt[0]
    p = mdl.predict(FP[i][None])[0]; return mu + (p - mu) @ np.outer(v, v)

# ------------------------------------------------------------------ metrics
def sp(a, b):
    if len(a) < 4 or np.ptp(a) == 0 or np.ptp(b) == 0: return 0.0  # constant predictions -> 0 by convention
    return float(spearmanr(a, b)[0])
def rmse(a, b): return float(np.sqrt(np.mean((a - b) ** 2)))

def cell_table(P, subset, floor_all=False):
    rows = [(i, j, Y[i, j], C[i, j], P[i, j]) for i in subset for j in range(5)]
    return pd.DataFrame(rows, columns=["lig", "j", "y", "cens", "p"])

def lolo_metrics(df, idx_lig):
    """df rows for the ligands in idx_lig (list with repeats allowed)."""
    d = pd.concat([G[l] for l in idx_lig]) if False else None
    return d

def metrics_for(df_by_lig, ligs):
    d = pd.concat([df_by_lig[l] for l in ligs], ignore_index=True)
    u = d[~d.cens]; out = {"rmse_pooled_unc": rmse(u.y.values, u.p.values),
                           "rmse_pooled_floor": rmse(d.y.values, d.p.values)}
    per = []
    for j in range(5):
        uj = u[u.j == j]
        out[f"rmse_{INT[j]}"] = rmse(uj.y.values, uj.p.values) if len(uj) else np.nan
        out[f"rho_{INT[j]}"] = sp(uj.y.values, uj.p.values) if len(uj) else np.nan
        per.append(out[f"rho_{INT[j]}"])
    out["rho_mean_per_integrin"] = float(np.nanmean(per))
    out["pearson_pooled_unc"] = float(pearsonr(u.y, u.p)[0]) if u.p.std() > 0 else 0.0
    return out

def boot(fn, ligs, nb=NBOOT):
    ligs = np.array(ligs); res = []
    for _ in range(nb):
        res.append(fn(list(RNG.choice(ligs, len(ligs), replace=True))))
    return res

def ci(vals):
    v = np.array(vals, float); v = v[~np.isnan(v)]
    return [float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))] if len(v) else [np.nan, np.nan]

def summarize(preds, subset, primary_key, better="lower"):
    """preds: dict name -> P. Returns point metrics, bootstrap CIs, paired diffs vs each null."""
    dfl = {name: {l: cell_table(P, [l]) for l in subset} for name, P in preds.items()}
    pt = {n: metrics_for(dfl[n], subset) for n in preds}
    bs = {n: [] for n in preds}
    idxs = [list(RNG.choice(subset, len(subset), replace=True)) for _ in range(NBOOT)]
    for ligs in idxs:
        for n in preds: bs[n].append(metrics_for(dfl[n], ligs))
    out = {}
    for n in preds:
        out[n] = {"point": pt[n], "ci": {k: ci([b[k] for b in bs[n]]) for k in pt[n]}}
    out["_boot_idx_hash"] = None
    return out, bs, pt

def paired(bs, pt, model, null, key):
    d = [m[key] - n[key] for m, n in zip(bs[model], bs[null])]
    return {"model": model, "null": null, "key": key, "point_diff": pt[model][key] - pt[null][key], "ci": ci(d)}

def vs_const(bs, pt, model, key, const):
    d = [m[key] - const for m in bs[model]]
    return {"model": model, "null": f"chance={const}", "key": key, "point_diff": pt[model][key] - const, "ci": ci(d)}

def verdict(diff, lower_better):
    lo, hi = diff["ci"]
    if lower_better: return "POSITIVE" if hi < 0 else ("NEGATIVE" if lo > 0 else "NULL")
    return "POSITIVE" if lo > 0 else ("NEGATIVE" if hi < 0 else "NULL")

R = {"meta": dict(n_ligands=NL, integrins=INT, n_cells=int(Y.size), n_censored=int(C.sum()), n_uncensored_per_integrin={INT[j]: int((~C[:, j]).sum()) for j in range(5)},
                  n_structure_ligands=len(S_all), n_tierA=len(S_A), hyper=dict(ridge_alpha=RIDGE_ALPHA, gp_lambda=GP_LAMBDA, softmax_T=SOFTMAX_T, loio_lambda=LOIO_LAMBDA, floor=FLOOR, nboot=NBOOT))}

# ================================================================== (a) LOLO
ALL = list(range(NL))
lolo = {}
for nm, model in [("N1_mean", n_mean), ("N2_median", n_median)]:
    lolo[nm] = lolo_predict(model, ALL)
res_all, bs_all, pt_all = summarize(lolo, ALL, "rmse_pooled_unc")
R["a_LOLO_all34_structure_blind"] = res_all

sub_preds = {"N1_mean(S-only train)": lolo_predict(n_mean, S_all), "N1_mean(train all 34)": lolo_predict(mk_n_mean_all(S_all), S_all),
             "N2_median(S-only train)": lolo_predict(n_median, S_all),
             "M1_ridge_morgan": lolo_predict(m1_ridge, S_all), "M2_tanimoto_gp": lolo_predict(m2_gp, S_all), "M3_reduced_rank1": lolo_predict(m3_rr, S_all)}
res_s, bs_s, pt_s = summarize(sub_preds, S_all, "rmse_pooled_unc")
R["a_LOLO_structure_subset16"] = res_s
best_null = min(["N1_mean(S-only train)", "N1_mean(train all 34)", "N2_median(S-only train)"], key=lambda n: pt_s[n]["rmse_pooled_unc"])
R["a_LOLO_structure_subset16"]["_best_null"] = best_null
R["a_LOLO_structure_subset16"]["paired_vs_best_null"] = {}
for m in ["M1_ridge_morgan", "M2_tanimoto_gp", "M3_reduced_rank1"]:
    for key, lb in [("rmse_pooled_unc", True), ("rho_mean_per_integrin", False)]:
        dd = paired(bs_s, pt_s, m, best_null, key) if key.startswith("rmse") else vs_const(bs_s, pt_s, m, key, 0.0)
        dd["verdict"] = verdict(dd, lb)
        R["a_LOLO_structure_subset16"]["paired_vs_best_null"][f"{m}|{key}"] = dd
# sensitivity: tier-A only (n=7)
subA = {"N1_mean": lolo_predict(n_mean, S_A), "M1_ridge_morgan": lolo_predict(m1_ridge, S_A), "M2_tanimoto_gp": lolo_predict(m2_gp, S_A)}
rA, bA, pA = summarize(subA, S_A, "rmse_pooled_unc"); R["a_LOLO_sensitivity_tierA_only_n7"] = rA

# ================================================================== (a2) cell masking
def svd1_complete(M, mask_missing, iters=300):
    X = M.copy(); cm = np.nanmean(np.where(mask_missing, np.nan, M), 0)
    for j in range(M.shape[1]): X[mask_missing[:, j], j] = cm[j]
    for _ in range(iters):
        mu = X.mean(0); U, s, Vt = np.linalg.svd(X - mu, full_matrices=False)
        R1 = mu + s[0] * np.outer(U[:, 0], Vt[0])
        X = np.where(mask_missing, R1, M)
    return R1
P_n1, P_n3, P_n4 = (np.full((NL, 5), np.nan) for _ in range(3))
for i in range(NL):
    for j in range(5):
        keep = [k for k in range(5) if k != j]
        P_n3[i, j] = Y[i, keep].mean()
        P_n1[i, j] = np.delete(Y[:, j], i).mean()
        m = np.zeros_like(Y, bool); m[i, j] = True
        P_n4[i, j] = svd1_complete(Y, m)[i, j]
a2 = {"N1_mean": P_n1, "N3_promiscuity": P_n3, "N4_rank1_svd": P_n4}
r2, b2, p2 = summarize(a2, ALL, "rmse_pooled_unc")
r2["paired"] = {}
for nul in ["N1_mean", "N3_promiscuity"]:
    for key, lb in [("rmse_pooled_unc", True), ("rho_mean_per_integrin", False)]:
        dd = paired(b2, p2, "N4_rank1_svd", nul, key) if key.startswith("rmse") else vs_const(b2, p2, "N4_rank1_svd", key, 0.0)
        if key.startswith("rmse") or nul == "N1_mean": r2["paired"][f"N4_vs_{nul}|{key}"] = dd
        dd["verdict"] = verdict(dd, lb)
dd = paired(b2, p2, "N3_promiscuity", "N1_mean", "rmse_pooled_unc"); dd["verdict"] = verdict(dd, True); r2["paired"]["N3_vs_N1|rmse"] = dd
for m_ in ["N3_promiscuity", "N4_rank1_svd"]:
    dd = vs_const(b2, p2, m_, "rho_mean_per_integrin", 0.0); dd["verdict"] = verdict(dd, False); r2["paired"][f"{m_}|rho_vs_zero"] = dd
dd = paired(b2, p2, "N4_rank1_svd", "N3_promiscuity", "rmse_pooled_unc"); dd["verdict"] = verdict(dd, True); r2["paired"]["N4_vs_N3|rmse"] = dd
R["a2_cell_masking"] = r2

# ================================================================== (b) LOIO
Kint, parts = integrin_seq.kernel(INT)
R["integrin_kernel"] = dict(names=INT, K=np.round(Kint, 4).tolist(), parts={f"{a}|{b}": [round(x, 4) for x in v] for (a, b), v in parts.items()})
def loio_preds(subset):
    out = {"N3_promiscuity": np.full((NL, 5), np.nan), "N5_const_other_cols": np.full((NL, 5), np.nan), "M5_seq_kernel": np.full((NL, 5), np.nan), "M5b_product_gp": np.full((NL, 5), np.nan)}
    for j in range(5):
        oth = [k for k in range(5) if k != j]
        w = np.exp(Kint[j, oth] / SOFTMAX_T); w /= w.sum()
        colmu = Y[:, oth].mean(0)
        for i in range(NL):
            out["N3_promiscuity"][i, j] = Y[i, oth].mean()
            out["N5_const_other_cols"][i, j] = Y[:, oth].mean()
            out["M5_seq_kernel"][i, j] = w @ (Y[i, oth] - colmu) + colmu.mean()
        # product-kernel GP on structure subset; training = all cells of other integrins
        cells = [(i, k) for i in S_all for k in oth]
        Kl = np.array([[tanimoto_minmax(RAW[a], RAW[b]) for b in S_all] for a in S_all]); pos = {l: n for n, l in enumerate(S_all)}
        Kc = np.array([[Kl[pos[a], pos[b]] * Kint[k1, k2] for (b, k2) in cells] for (a, k1) in cells])
        yv = np.array([Y[i, k] for i, k in cells]); mu = yv.mean()
        alpha = np.linalg.solve(Kc + LOIO_LAMBDA * np.eye(len(cells)), yv - mu)
        for i in S_all:
            ks = np.array([Kl[pos[i], pos[b]] * Kint[j, k2] for (b, k2) in cells]); out["M5b_product_gp"][i, j] = mu + ks @ alpha
    return out
lo = loio_preds(S_all)
def loio_summary(preds, subset):
    sub_idx = subset
    def met(ligs, P):
        o = {}
        for j in range(5):
            idx = [l for l in ligs]; y = np.array([Y[l, j] for l in idx]); p = np.array([P[l, j] for l in idx]); c = np.array([C[l, j] for l in idx])
            u = ~c; o[f"rho_{INT[j]}"] = sp(y[u], p[u]) if u.sum() >= 4 else np.nan
            o[f"rmse_{INT[j]}"] = rmse(y[u], p[u]) if u.sum() else np.nan
            o[f"rho_floor_{INT[j]}"] = sp(y, p)
        o["rho_mean"] = float(np.nanmean([o[f"rho_{INT[j]}"] for j in range(5)]))
        o["rho_floor_mean"] = float(np.nanmean([o[f"rho_floor_{INT[j]}"] for j in range(5)]))
        return o
    pt = {n: met(subset, P) for n, P in preds.items()}
    idxs = [list(RNG.choice(subset, len(subset), replace=True)) for _ in range(NBOOT)]
    bs = {n: [met(l, P) for l in idxs] for n, P in preds.items()}
    out = {n: {"point": pt[n], "ci": {k: ci([b[k] for b in bs[n]]) for k in pt[n]}} for n in preds}
    return out, bs, pt
rb_all, bb_all, pb_all = loio_summary({k: lo[k] for k in ["N3_promiscuity", "N5_const_other_cols", "M5_seq_kernel"]}, ALL)
rb_all["paired"] = {}
for key in ["rho_mean", "rho_floor_mean"]:
    dd = paired(bb_all, pb_all, "M5_seq_kernel", "N3_promiscuity", key); dd["verdict"] = verdict(dd, False); rb_all["paired"][f"M5_vs_N3|{key}"] = dd
R["b_LOIO_all34"] = rb_all
rb_s, bb_s, pb_s = loio_summary({k: lo[k] for k in ["N3_promiscuity", "M5_seq_kernel", "M5b_product_gp"]}, S_all)
rb_s["paired"] = {}
for m in ["M5_seq_kernel", "M5b_product_gp"]:
    dd = paired(bb_s, pb_s, m, "N3_promiscuity", "rho_mean"); dd["verdict"] = verdict(dd, False); rb_s["paired"][f"{m}_vs_N3|rho_mean"] = dd
R["b_LOIO_structure_subset16"] = rb_s

# ================================================================== (c) selectivity (LOLO)
OTH = [j for j in range(5) if INT[j] != "avb6"]; J6 = INT.index("avb6")
def sel_table(P, subset):
    rows = []
    for i in subset:
        for j in OTH:
            if not C[i, J6] and not C[i, j]:
                rows.append((i, j, Y[i, J6] - Y[i, j], P[i, J6] - P[i, j]))
    return pd.DataFrame(rows, columns=["lig", "j", "y", "p"])
def sel_met(tabs, ligs):
    d = pd.concat([tabs[l] for l in ligs if len(tabs[l])], ignore_index=True)
    o = {"rmse": rmse(d.y.values, d.p.values), "rho": sp(d.y.values, d.p.values),
         "sign_acc": float(np.mean(np.where(d.p == 0, .5, (np.sign(d.p) == np.sign(d.y)).astype(float)))), "n": len(d)}
    for j in OTH:
        dj = d[d.j == j]; o[f"rmse_{INT[j]}"] = rmse(dj.y.values, dj.p.values) if len(dj) else np.nan
        o[f"rho_{INT[j]}"] = sp(dj.y.values, dj.p.values) if len(dj) >= 4 else np.nan
        o[f"n_{INT[j]}"] = len(dj)
    return o
def sel_run(preds, subset):
    tabs = {n: {l: sel_table(P, [l]) for l in subset} for n, P in preds.items()}
    pt = {n: sel_met(tabs[n], subset) for n in preds}
    idxs = [list(RNG.choice(subset, len(subset), replace=True)) for _ in range(NBOOT)]
    bs = {n: [sel_met(tabs[n], l) for l in idxs] for n in preds}
    return {n: {"point": pt[n], "ci": {k: ci([b[k] for b in bs[n]]) for k in pt[n]}} for n in preds}, bs, pt
rc, bc, pc_ = sel_run(lolo, ALL); R["c_selectivity_all34_structure_blind"] = rc
rc2, bc2, pc2 = sel_run(sub_preds, S_all)
bn = min(["N1_mean(S-only train)", "N1_mean(train all 34)"], key=lambda n: pc2[n]["rmse"])
rc2["_best_null"] = bn; rc2["paired"] = {}
for m in ["M1_ridge_morgan", "M2_tanimoto_gp", "M3_reduced_rank1"]:
    for key, lb in [("rmse", True), ("sign_acc", False)]:
        dd = paired(bc2, pc2, m, bn, key); dd["verdict"] = verdict(dd, lb); rc2["paired"][f"{m}|{key}"] = dd
    dd = paired(bc2, pc2, m, bn, "rho"); dd["verdict"] = verdict(dd, False); rc2["paired"][f"{m}|rho"] = dd
R["c_selectivity_structure_subset16"] = rc2

# ================================================================== (d) pairwise concordance
def pairs_d1(subset):
    out = []
    for j in range(5):
        for a in subset:
            for b in subset:
                if a == b: continue
                ya, yb, ca, cb = Y[a, j], Y[b, j], C[a, j], C[b, j]
                if ca and cb: continue
                if abs(ya - yb) >= FLOOR and ya > yb: out.append((j, a, b))   # a truly more potent than b (censored side has y=5.0 bound; need 0.3 margin)
    return out
def conc_d1(P, prs, cnt):
    num = den = 0.0
    for j, a, b in prs:
        w = cnt[a] * cnt[b]
        if w == 0: continue
        s = 1.0 if P[a, j] > P[b, j] else (0.5 if P[a, j] == P[b, j] else 0.0)
        num += w * s; den += w
    return num / den if den else np.nan
def pairs_d2(subset):
    out = []
    for i in subset:
        for j in range(5):
            for k in range(5):
                if j == k: continue
                if C[i, j] and C[i, k]: continue
                if Y[i, j] - Y[i, k] >= FLOOR: out.append((i, j, k))
    return out
def conc_d2(P, prs, cnt):
    num = den = 0.0
    for i, j, k in prs:
        w = cnt[i]
        if w == 0: continue
        s = 1.0 if P[i, j] > P[i, k] else (0.5 if P[i, j] == P[i, k] else 0.0)
        num += w * s; den += w
    return num / den if den else np.nan
def pair_run(preds, subset):
    p1, p2 = pairs_d1(subset), pairs_d2(subset); out = {"n_pairs_d1": len(p1), "n_pairs_d2": len(p2)}
    res = {}
    cnts = []
    for _ in range(NBOOT):
        c = np.zeros(NL); np.add.at(c, RNG.choice(subset, len(subset), replace=True), 1); cnts.append(c)
    one = np.zeros(NL); one[subset] = 1
    for n, P in preds.items():
        d1 = conc_d1(P, p1, one); d2 = conc_d2(P, p2, one)
        b1 = [conc_d1(P, p1, c) for c in cnts]; b2 = [conc_d2(P, p2, c) for c in cnts]
        per = {INT[j]: conc_d1(P, [q for q in p1 if q[0] == j], one) for j in range(5)}
        res[n] = {"d1": d1, "d1_ci": ci(b1), "d2": d2, "d2_ci": ci(b2), "d1_per_integrin": per, "_b1": b1, "_b2": b2}
    return out, res
o_all, d_all = pair_run(lolo, ALL)
o_s, d_s = pair_run(sub_preds, S_all)
def strip(res): return {n: {k: v for k, v in r.items() if not k.startswith("_b")} for n, r in res.items()}
R["d_pairwise_all34"] = {**o_all, "results": strip(d_all)}
dd = {}
bn = best_null
for m in ["M1_ridge_morgan", "M2_tanimoto_gp", "M3_reduced_rank1"]:
    for key, bk in [("d1", "_b1"), ("d2", "_b2")]:
        ref, refname = (0.5, "chance0.5") if key == "d1" else (None, "N1_all34")   # d1: LOO-mean null is an artifact (reverses order) -> chance; d2: N1 is a legitimate null
        if ref is not None:
            diff = [x - 0.5 for x in d_s[m][bk]]; pdiff = d_s[m][key] - 0.5
        else:
            diff = [x - y for x, y in zip(d_s[m][bk], d_s["N1_mean(train all 34)"][bk])]; pdiff = d_s[m][key] - d_s["N1_mean(train all 34)"][key]
        dc = {"point_diff": pdiff, "ci": ci(diff)}; dc["verdict"] = verdict(dc, False); dd[f"{m}|{key}_vs_{refname}"] = dc
R["d_pairwise_structure_subset16"] = {**o_s, "results": strip(d_s), "paired": dd}

# ================================================================== X cross-lab consistency (descriptive)
def mget(lig, src, ig):
    r = mx[(mx.ligand_id == lig) & (mx.source == src) & (mx.integrin == ig)]
    return None if r.empty else (float(r.ic50_nM.iloc[0]), r.censor.iloc[0])
xl = []
for kl, ol, src in [("c(FRGDLAFp(NMe)K)", "Quigley_FF", "quigley2023"), ("Cilengitide", "Cilengitide@tomassi2021", "tomassi2021"), ("RTDLDSLRT", "RTDLDSLRT@tomassi2021", "tomassi2021")]:
    for ig in ["avb3", "avb6", "avb8", "a5b1"]:
        a, b = mget(kl, "kapp2017", ig), mget(ol, src, ig)
        if a and b and a[1] == "=" and b[1] == "=":
            xl.append(dict(compound=kl, other=ol, integrin=ig, kapp_nM=a[0], other_nM=b[0], log10_ratio_other_over_kapp=round(float(np.log10(b[0] / a[0])), 3)))
R["X_crosslab"] = xl
R["X_crosslab_summary"] = dict(n=len(xl), mean_abs_log10=float(np.mean([abs(x["log10_ratio_other_over_kapp"]) for x in xl])), max_abs_log10=float(max(abs(x["log10_ratio_other_over_kapp"]) for x in xl)),
                               note="Assumes Quigley FF = Kapp c(FRGDLAFp(NMe)K) (same scaffold; NOT verified in the paper text) ")
# descriptive selectivity of extra series
sel = []
for src in ["quigley2023", "tomassi2021"]:
    sub = mx[mx.source == src]
    for lig in dict.fromkeys(sub.ligand_id):
        s6 = sub[(sub.ligand_id == lig) & (sub.integrin == "avb6")]
        for ig in ["avb3", "avb8", "a5b1"]:
            s = sub[(sub.ligand_id == lig) & (sub.integrin == ig)]
            if len(s6) and len(s):
                sel.append(dict(ligand=lig, vs=ig, log10_IC50_ratio_over_avb6=round(float(np.log10(s.ic50_nM.iloc[0] / s6.ic50_nM.iloc[0])), 3),
                                censored=bool(s.censor.iloc[0] == ">" or s6.censor.iloc[0] == ">")))
R["X_extra_series_selectivity"] = sel

def clean(o):
    if isinstance(o, dict): return {str(k): clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)): return None if np.isnan(o) else float(o)
    if isinstance(o, np.integer): return int(o)
    return o
json.dump(clean(R), open(HERE / "results.json", "w"), indent=1)
print("done")
