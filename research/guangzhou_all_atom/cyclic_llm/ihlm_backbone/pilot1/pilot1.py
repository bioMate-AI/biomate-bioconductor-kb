"""Pilot 1 (docs/20261031_IHLM_HYPOTHESIS_V2_PILOT_GATE.md, A1 + A2): backbone embeddings + analog retrieval vs the strongest simple baselines,
permeability, few-label (k = 5/10/25), leave-labs-out, hard stratum primary.
Reuses (read-only): technique_sprint/fusion + fusion_b (cells, reveal RNG, analog_perm, ptk, spearman), loop_retro/loop_models.GP (Tanimoto-kernel GP, hyperparameters
fixed there), stratification/common (data). Modes:
  regress  baselines only (PT, A, PTk) on all labs; must equal technique_sprint/fusion_b/results/perm_b_cells.csv to 1e-9; no embedding score is computed
  dev      dev-half labs (sha256(source) mod 2 == 0): all candidate configurations + baselines -> results/dev_cells.pkl, results/selection_<size>.json
  test     test-half labs (== 1): baselines + the frozen selected configuration only; refuses to run without selection_<size>.json
  control  planted / shuffled labels, all labs, selected configuration (see A2)
usage: python3 pilot1.py MODE --emb EMB.npz [--size small|base] [--label real|shuffle|plant_emb|plant_fp]"""
import sys, os, zlib, hashlib, json, time, pickle, argparse
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); CL = os.path.abspath(f"{HERE}/../..")
for p in ("stratification", "kb_audit", "technique_sprint/fusion", "technique_sprint/fusion_b", "loop_retro"): sys.path.insert(0, f"{CL}/{p}")
import common as C, fusion_b as B, perm_testbed as T
from loop_models import GP
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.linear_model import Ridge
from rdkit import Chem
from rdkit.Chem import rdFingerprintGenerator

KS = T.KS; SEEDS = list(T.SEEDS); BOOT = 2000; MIN_ITEMS = 8; MIN_LABS = 5; MARGIN = 0.03
PT_PARAMS = dict(max_iter=100, max_bins=31, learning_rate=0.1, max_leaf_nodes=31, min_samples_leaf=20, l2_regularization=0.0, early_stopping=False, random_state=0)   # fusion_b/perm_b.py
RIDGE_A = (10.0, 100.0); GAMMA = (1.0, 2.0, 4.0); ALPHA = (0.25, 0.5, 0.75); GAMMA_C = (1.0, 2.0)
GC2048 = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
RES = f"{HERE}/results"; os.makedirs(RES, exist_ok=True)


def half(source): return int(hashlib.sha256(str(source).encode()).hexdigest(), 16) % 2          # 0 = dev, 1 = test (A2)


def raw_counts(smiles): return np.stack([GC2048.GetCountFingerprintAsNumPy(Chem.MolFromSmiles(s)) for s in smiles]).astype(np.float64)


def load(label_mode, emb_path):
    dfull = C.load_labelled()
    E = np.load(emb_path); assert (E["index"] == dfull.index.values).all(), "embedding index != labelled index"; Eall = E["E"].astype(np.float64)
    if label_mode == "shuffle":
        d2 = dfull.copy(); rng = np.random.default_rng(20261031)
        for s in d2.Source.unique():
            m = (d2.Source == s).values; perm = rng.permutation(m.sum()); d2.loc[m, "y_raw"] = d2.loc[m, "y_raw"].values[perm]; d2.loc[m, "y"] = d2.loc[m, "y"].values[perm]
        dfull = d2
    elif label_mode in ("plant_emb", "plant_fp"):
        rng = np.random.default_rng(20261031)
        if label_mode == "plant_emb": F = Eall - Eall.mean(0)
        else: F = np.log1p(raw_counts(dfull.SMILES.values)); F = F - F.mean(0)
        U, S, Vt = np.linalg.svd(F[rng.choice(len(F), 3000, replace=False)], full_matrices=False); pcs = F @ Vt[:5].T
        w = rng.normal(size=5); s = pcs @ w; s = (s - s.mean()) / s.std(); y = s + 0.3 * rng.normal(size=len(s))
        d2 = dfull.copy(); d2["y_raw"] = y; d2["y"] = y; dfull = d2
    return dfull, Eall


def unit(X):
    n = np.linalg.norm(X, axis=1, keepdims=True); return X / np.where(n > 0, n, 1.0)


def run_labs(labs, dfull, Eall, mode, selected=None, baselines_only=False):
    """Returns list of cell dicts: lab,k,seed,y,simmax,scores{arm: array over candidates}."""
    vc = dfull.Source.value_counts(); elig = sorted(vc[vc >= 20].index); d = dfull[dfull.Source.isin(elig)].copy()
    cnt = pd.DataFrame(T.counts_of(dfull.SMILES.values), index=dfull.index); phy = pd.DataFrame(C.desc_matrix(dfull, ["physchem"])[0], index=dfull.index); X = pd.concat([cnt, phy], axis=1); X.columns = [str(c) for c in X.columns]
    bits = pd.DataFrame(T.bits_of(d.SMILES.values), index=d.index); rawc = pd.DataFrame(raw_counts(d.SMILES.values), index=d.index)
    Edf = pd.DataFrame(Eall, index=dfull.index); cells = []; t0 = time.time()
    for L in labs:
        dl = d[d.Source == L]; idx = dl.index.values; flat_L = set(dl.flat_smiles); tr = dfull[(dfull.Source != L) & ~dfull.flat_smiles.isin(flat_L)]
        pt = HistGradientBoostingRegressor(**PT_PARAMS).fit(X.loc[tr.index].values, tr.y.values).predict(X.loc[idx].values)
        Bl = bits.loc[idx].values; y = dl.y_raw.values; flat = dl.flat_smiles.values; Xc = rawc.loc[idx].values; gp = GP(Xc)
        if not baselines_only:
            Etr = Edf.loc[tr.index].values; mu = Etr.mean(0); esd = Etr.std(0) + 1e-6; Eh = unit(Edf.loc[idx].values - mu); Estd_tr = (Etr - mu) / esd; Estd_l = (Edf.loc[idx].values - mu) / esd
            ptE = {a: Ridge(alpha=a).fit(Estd_tr, tr.y.values).predict(Estd_l) for a in RIDGE_A}
        for k in KS:
            if len(idx) - k < 20: continue
            for s in SEEDS:
                rv = T.cell_rng(L, k, s).choice(len(idx), k, replace=False); fr = set(flat[rv]); rvs = set(rv.tolist())
                rest = np.array([i for i in range(len(idx)) if i not in rvs and flat[i] not in fr])
                if len(rest) < 20 or np.std(y[rest]) < 1e-12: continue
                sim = B.tanimoto(Bl[rest], Bl[rv]); yr = y[rv]; P = pt[rest]; sc_ = {}
                sc_["A"] = B.analog_perm(sim, yr); sc_["PT"] = P; sc_["PTk"] = B.ptk(P, sim, yr, pt[rv]); sc_["NN1"] = yr[np.argmax(sim, 1)]
                st = gp.fit(None, rv, yr, 0, 0); sc_["GP_fp"] = gp.predict(st, rest)
                if not baselines_only:
                    cos = Eh[rest] @ Eh[rv].T; se = np.clip(cos, 0, None)
                    for a in RIDGE_A:
                        sc_[f"EPT_r{int(a)}"] = ptE[a][rest]; sc_[f"EPTk_r{int(a)}"] = B.ptk(ptE[a][rest], sim, yr, ptE[a][rv])
                    for g in GAMMA: sc_[f"EA_g{g:g}"] = B.analog_perm(se ** g, yr)
                    for a in RIDGE_A:
                        for al in ALPHA:
                            for g in GAMMA_C:
                                simc = al * sim + (1 - al) * se ** g; sc_[f"ECPTk_r{int(a)}_a{al:g}_g{g:g}"] = B.ptk(ptE[a][rest], simc, yr, ptE[a][rv])
                    Kt = gp._K(rest, rv); Kl = Eh[rest] @ Eh[rv].T; Kr = 0.5 * gp._K(rv, rv) + 0.5 * (Eh[rv] @ Eh[rv].T); a_ = max(float(yr.var()), 1e-6); s2 = 0.3 * a_
                    Lc = np.linalg.cholesky(a_ * Kr + s2 * np.eye(k) + 1e-8 * np.eye(k)); al_ = np.linalg.solve(Lc.T, np.linalg.solve(Lc, yr - yr.mean())); sc_["GP_fpemb"] = yr.mean() + a_ * (0.5 * Kt + 0.5 * Kl) @ al_
                cells.append(dict(lab=L, k=k, seed=s, y=y[rest], simmax=sim.max(1), scores=sc_))
        print(mode, L, "n", len(idx), round(time.time() - t0), "s", flush=True)
    return cells


def lab_values(cells, labs, k, arm, hard, theta=None):
    """Per-lab mean (over seeds) Spearman of arm on (hard stratum | all candidates); returns dict lab -> value (labs with no valid cell omitted)."""
    out = {}
    for L in labs:
        v = []
        for c in cells:
            if c["lab"] != L or c["k"] != k: continue
            m = (c["simmax"] <= theta) if hard else np.ones(len(c["y"]), bool)
            if m.sum() < MIN_ITEMS: continue
            r = B.spearman(c["scores"][arm][m], c["y"][m])
            if np.isfinite(r): v.append(r)
        if v: out[L] = float(np.mean(v))
    return out


def theta_of(cells, labs, k): return float(np.percentile(np.concatenate([c["simmax"] for c in cells if c["lab"] in labs and c["k"] == k]), 100 / 3))


def boot_diff(a, b, seed=20261031):
    labs = sorted(set(a) & set(b)); x = np.array([a[l] - b[l] for l in labs]); rng = np.random.default_rng(seed)
    bs = [x[rng.integers(0, len(x), len(x))].mean() for _ in range(BOOT)]
    return dict(n_labs=len(labs), diff=float(x.mean()), lo=float(np.percentile(bs, 2.5)), hi=float(np.percentile(bs, 97.5)))


BASE = ["A", "NN1", "PT", "PTk", "GP_fp"]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("mode"); ap.add_argument("--emb"); ap.add_argument("--size", default="small"); ap.add_argument("--label", default="real"); ap.add_argument("--ann", default=None); a = ap.parse_args()
    if a.mode == "regress":
        dfull = C.load_labelled(a.ann); vc = dfull.Source.value_counts(); labs = sorted(vc[vc >= 20].index)
        dummy = np.zeros((len(dfull), 2)); cells = run_labs(labs, dfull, dummy, "regress", baselines_only=True)
        old = pd.read_csv(f"{CL}/technique_sprint/fusion_b/results/perm_b_cells.csv"); old = old[old.arm.isin(["PT", "A", "PTk"])]
        mism = 0; n = 0; mx = 0.0
        for c in cells:
            for arm in ("PT", "A", "PTk"):
                row = old[(old.lab == c["lab"]) & (old.k == c["k"]) & (old.seed == c["seed"]) & (old.arm == arm)]
                if len(row) != 1: mism += 1; continue
                new = B.spearman(c["scores"][arm], c["y"]); n += 1; diff = abs(new - float(row.spearman.iloc[0])); mx = max(mx, diff)
                if diff > 1e-9: mism += 1
        agg = {}
        for k in KS:
            for arm in ("PT", "A", "PTk"):
                lv = lab_values(cells, labs, k, arm, False); agg[f"{arm}_k{k}"] = (round(float(np.mean(list(lv.values()))), 4), len(lv))
        out = dict(cells_compared=n, mismatches=mism, max_abs_diff=mx, lab_first_means=agg, n_cells_new=len(cells), n_cells_old=int(old.groupby(["lab", "k", "seed"]).ngroups))
        json.dump(dict(out, annotations=(a.ann or "current (post source fix)")), open(f"{RES}/regression{'_prefix' if a.ann else ''}.json", "w"), indent=1); print(json.dumps(out, indent=1)); return
    dfull, Eall = load(a.label, a.emb); vc = dfull.Source.value_counts(); elig = sorted(vc[vc >= 20].index)
    if a.mode == "dev":
        labs = [l for l in elig if half(l) == 0]; cells = run_labs(labs, dfull, Eall, "dev"); pickle.dump(cells, open(f"{RES}/dev_cells_{a.size}.pkl", "wb"))
        cand = sorted({arm for c in cells for arm in c["scores"] if arm not in BASE}); tab = {}
        for arm in cand + BASE:
            per = []
            for k in KS:
                th = theta_of(cells, labs, k); lv = lab_values(cells, labs, k, arm, True, th)
                if lv: per.append(float(np.mean(list(lv.values()))))
            tab[arm] = float(np.mean(per)) if per else float("nan")
        best = max(cand, key=lambda x: tab[x] if np.isfinite(tab[x]) else -9)
        json.dump(dict(size=a.size, selected=best, dev_hard_mean_over_budgets=tab, dev_labs=labs, rule="argmax over candidate configurations of the dev-half hard-stratum Spearman (mean over labs, then over budgets)"), open(f"{RES}/selection_{a.size}.json", "w"), indent=1)
        print("selected", best, round(tab[best], 4), "| best dev baseline", max(BASE, key=lambda x: tab[x]), round(max(tab[x] for x in BASE), 4)); return
    sel = json.load(open(f"{RES}/selection_{a.size}.json"))["selected"] if os.path.exists(f"{RES}/selection_{a.size}.json") else None
    if sel is None: sys.exit("refusing: selection file missing (dev must run first and be committed)")
    if a.mode == "test":
        labs = [l for l in elig if half(l) == 1]; cells = run_labs(labs, dfull, Eall, "test"); pickle.dump(cells, open(f"{RES}/test_cells_{a.size}.pkl", "wb"))
        res = dict(size=a.size, selected=sel, test_labs=labs, budgets={})
        for k in KS:
            th = theta_of(cells, labs, k); arms = BASE + [sel, "GP_fpemb"]; hv = {arm: lab_values(cells, labs, k, arm, True, th) for arm in arms}; av = {arm: lab_values(cells, labs, k, arm, False) for arm in arms}
            nl = len(hv[sel]); bestb = max(BASE, key=lambda x: np.mean(list(hv[x].values())) if hv[x] else -9)
            row = dict(theta=th, n_labs_hard=nl, best_baseline_hard=bestb, hard_means={x: (float(np.mean(list(hv[x].values()))) if hv[x] else None) for x in arms}, overall_means={x: (float(np.mean(list(av[x].values()))) if av[x] else None) for x in arms})
            for cand in (sel, "GP_fpemb"):
                bd = boot_diff(hv[cand], hv[bestb]); bd["underpowered"] = nl < MIN_LABS; bd["passes"] = (not bd["underpowered"]) and bd["diff"] >= MARGIN and bd["lo"] > 0; row[f"hard_{cand}_minus_{bestb}"] = bd
                row[f"overall_{cand}_minus_best_overall_baseline"] = boot_diff(av[cand], av[max(BASE, key=lambda x: np.mean(list(av[x].values())) if av[x] else -9)])
            res["budgets"][str(k)] = row
        npass = sum(res["budgets"][str(k)][f"hard_{sel}_minus_{res['budgets'][str(k)]['best_baseline_hard']}"]["passes"] for k in KS)
        res["gate_selected"] = "PASS" if npass >= 2 else ("UNDERPOWERED" if sum(res["budgets"][str(k)][f"hard_{sel}_minus_{res['budgets'][str(k)]['best_baseline_hard']}"]["underpowered"] for k in KS) >= 2 else "FAIL")
        json.dump(res, open(f"{RES}/test_{a.size}_{a.label}.json", "w"), indent=1); print(json.dumps(res, indent=1)); return
    if a.mode == "control":
        labs = elig; cells = run_labs(labs, dfull, Eall, "control"); res = dict(size=a.size, label=a.label, selected=sel, budgets={})
        for k in KS:
            th = theta_of(cells, labs, k)
            res["budgets"][str(k)] = {arm: dict(hard=(float(np.mean(list(lab_values(cells, labs, k, arm, True, th).values()))) if lab_values(cells, labs, k, arm, True, th) else None),
                                                overall=(float(np.mean(list(lab_values(cells, labs, k, arm, False).values()))) if lab_values(cells, labs, k, arm, False) else None))
                                      for arm in ["A", "GP_fp", "PTk", sel, "EA_g1", "EA_g2", "GP_fpemb"] if arm in cells[0]["scores"]}
        json.dump(res, open(f"{RES}/control_{a.size}_{a.label}.json", "w"), indent=1); print(json.dumps(res, indent=1)); return


if __name__ == "__main__": main()
