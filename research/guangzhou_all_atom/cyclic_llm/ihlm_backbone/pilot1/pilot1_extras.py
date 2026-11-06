"""Pilot 1 addendum A3 analyses on cached cells (dev_cells_<size>.pkl + test_cells_<size>.pkl): (1) MDE, (2) 50 repeated source splits, (3) noise-ceiling scale.
usage: python3 pilot1_extras.py small|base"""
import sys, os, json, pickle, ast
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import pilot1 as P
P.BOOT = 1000
size = sys.argv[1]; RES = P.RES; KS = P.KS; BASE = P.BASE
cells = pickle.load(open(f"{RES}/dev_cells_{size}.pkl", "rb")) + pickle.load(open(f"{RES}/test_cells_{size}.pkl", "rb"))
labs_all = sorted({c["lab"] for c in cells}); cand = sorted({a for c in cells for a in c["scores"] if a not in BASE})
sel_primary = json.load(open(f"{RES}/selection_{size}.json"))["selected"]; test_primary = json.load(open(f"{RES}/test_{size}_real.json"))
dev_labs = [l for l in labs_all if P.half(l) == 0]; test_labs = [l for l in labs_all if P.half(l) == 1]


def best_baseline(hv):
    return max(BASE, key=lambda x: np.mean(list(hv[x].values())) if hv[x] else -9)


def run_split(devl, testl, boot_seed):
    tab = {}
    for arm in cand:
        per = []
        for k in KS:
            th = P.theta_of(cells, devl, k); lv = P.lab_values(cells, devl, k, arm, True, th)
            if lv: per.append(float(np.mean(list(lv.values()))))
        tab[arm] = float(np.mean(per)) if per else -9.0
    sel = max(cand, key=lambda x: tab[x]); out = dict(selected=sel, budgets={})
    for k in KS:
        th = P.theta_of(cells, testl, k); hv = {a: P.lab_values(cells, testl, k, a, True, th) for a in BASE + [sel]}; bb = best_baseline(hv)
        bd = P.boot_diff(hv[sel], hv[bb], seed=boot_seed); bd["underpowered"] = bd["n_labs"] < P.MIN_LABS; bd["passes"] = (not bd["underpowered"]) and bd["diff"] >= P.MARGIN and bd["lo"] > 0; bd["best_baseline"] = bb; out["budgets"][str(k)] = bd
    out["pass"] = sum(out["budgets"][str(k)]["passes"] for k in KS) >= 2; out["n_under"] = sum(out["budgets"][str(k)]["underpowered"] for k in KS)
    return out


res = dict(size=size)
# ---- (1) MDE ---------------------------------------------------------------------------------------------------------------------------------------------------
mde = {}
for k in KS:
    row = {}
    for name, labs_ in (("dev", dev_labs), ("test_posthoc", test_labs), ("all_posthoc", labs_all)):
        th = P.theta_of(cells, labs_, k); hv = {a: P.lab_values(cells, labs_, k, a, True, th) for a in BASE + [sel_primary]}; bb = best_baseline(hv)
        labs_ok = sorted(set(hv[sel_primary]) & set(hv[bb])); dd = np.array([hv[sel_primary][l] - hv[bb][l] for l in labs_ok])
        row[name] = dict(n_labs=len(labs_ok), sd_d=float(dd.std(ddof=1)) if len(dd) > 1 else None, best_baseline=bb)
    n_test = test_primary["budgets"][str(k)]["n_labs_hard"]
    for name in row: row[name]["mde80_for_n_test_labs"] = float(2.8 * row[name]["sd_d"] / np.sqrt(n_test)) if row[name]["sd_d"] else None
    row["n_test_labs_hard"] = n_test; row["margin"] = P.MARGIN; row["mde_prereg_dev_gt_margin"] = (row["dev"]["mde80_for_n_test_labs"] or 9) > P.MARGIN; mde[str(k)] = row
res["mde"] = mde
# ---- (2) 50 repeated splits ------------------------------------------------------------------------------------------------------------------------------------
rng = np.random.default_rng(20261031); splits = []
for i in range(50):
    perm = list(rng.permutation(labs_all)); devl, testl = perm[:len(perm) // 2], perm[len(perm) // 2:]; r = run_split(devl, testl, 20261031 + i); r["split"] = i; splits.append(r); print("split", i, r["selected"], r["pass"], flush=True)
dist = {}
for k in KS:
    dd = np.array([s["budgets"][str(k)]["diff"] for s in splits if np.isfinite(s["budgets"][str(k)]["diff"])]); un = np.mean([s["budgets"][str(k)]["underpowered"] for s in splits])
    dist[str(k)] = dict(n=len(dd), median=float(np.median(dd)), q25=float(np.percentile(dd, 25)), q75=float(np.percentile(dd, 75)), p5=float(np.percentile(dd, 5)), p95=float(np.percentile(dd, 95)), frac_diff_ge_margin=float(np.mean(dd >= P.MARGIN)),
                        frac_underpowered=float(un), frac_budget_passes=float(np.mean([s["budgets"][str(k)]["passes"] for s in splits])))
sel_counts = pd.Series([s["selected"] for s in splits]).value_counts().to_dict()
res["repeated_splits"] = dict(n_splits=50, frac_splits_pass=float(np.mean([s["pass"] for s in splits])), per_budget=dist, selected_counts=sel_counts, splits=splits)
# ---- (3) noise ceiling -----------------------------------------------------------------------------------------------------------------------------------------
raw = pd.read_csv(f"{P.CL}/../data/raw/CycPeptMPDB_Peptide_All.csv", low_memory=False)
raw = raw[raw["PAMPA"].notna() & (raw["PAMPA"] > -9.99) & raw["SMILES"].notna()]; rows = []
for _, r in raw.iterrows():
    if not isinstance(r.Same_Peptides_Source, str): continue
    try: srcs = ast.literal_eval(r.Same_Peptides_Source); perm_ = ast.literal_eval(r.Same_Peptides_Permeability); assay = ast.literal_eval(r.Same_Peptides_Assay)
    except Exception: continue
    ov = [np.mean([float(x) for x, a in zip(pv, av) if a == "PAMPA" and float(x) > -9.99]) for s, pv, av in zip(srcs, perm_, assay) if s != r.Source and any(a == "PAMPA" and float(x) > -9.99 for x, a in zip(pv, av))]
    if ov: rows.append((r.Structurally_Unique_ID, float(r.PAMPA), float(np.mean(ov))))
an = pd.DataFrame(rows, columns=["peptide", "y_self", "y_others"]); peps = an.peptide.unique()
rx = P.B.spearman(an.y_self.values, an.y_others.values); rb = np.random.default_rng(1); bs = []
for _ in range(2000):
    pick = rb.choice(peps, len(peps)); sub = pd.concat([an[an.peptide == p] for p in pick]); v = P.B.spearman(sub.y_self.values, sub.y_others.values)
    if np.isfinite(v): bs.append(v)
rxlo, rxhi = np.percentile(bs, [2.5, 97.5]); ceil = float(np.sqrt(max(rx, 0))); ceil_lo, ceil_hi = float(np.sqrt(max(rxlo, 0))), float(np.sqrt(max(rxhi, 0)))
frac = {}
for k in KS:
    b = test_primary["budgets"][str(k)]; bb = b["best_baseline_hard"]; frac[str(k)] = {nm: dict(hard_mean=b["hard_means"][nm], overall_mean=b["overall_means"][nm], hard_frac_of_ceiling=(b["hard_means"][nm] / ceil if b["hard_means"][nm] is not None and ceil > 0 else None),
                                                                                    overall_frac_of_ceiling=(b["overall_means"][nm] / ceil if b["overall_means"][nm] is not None and ceil > 0 else None)) for nm in (sel_primary, bb)}
res["noise_ceiling"] = dict(n_anchor_rows=len(an), n_peptides=len(peps), r_cross_lab=float(rx), r_ci95=[float(rxlo), float(rxhi)], ceiling_sqrt_r=ceil, ceiling_ci95=[ceil_lo, ceil_hi], skill_fraction_point=frac, note="approximate: sqrt(r_x) assumes equal noise in both measurements; y_others is the mean of the other laboratories' values; CI of the fractions not propagated (ceiling CI shown)")
json.dump(res, open(f"{RES}/extras_{size}.json", "w"), indent=1)
print(json.dumps({k: v for k, v in res.items() if k != "repeated_splits"}, indent=1)); print("splits pass", res["repeated_splits"]["frac_splits_pass"], json.dumps(res["repeated_splits"]["per_budget"], indent=1), sel_counts)
