#!/usr/bin/env python3
"""D1-a / D1-f of docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md (amendment D1, committed before running).
Data-derived inputs (lab sizes, within-lab SD, measurement noise, tau-hat) and the retrospective anchor-panel census (set cover).
usage: design_census.py CycPeptMPDB.csv anchor_data.npz anchor_data_anchors.json OUT.json"""
import ast, collections, json, sys
import numpy as np, pandas as pd
CSV, NPZ, ANC, OUT = sys.argv[1:5]
d = pd.read_csv(CSV, low_memory=False)
z = np.load(NPZ, allow_pickle=True); y = z["y"].astype(float); src = z["src"].astype(str)
anch = json.load(open(ANC)); rng = np.random.default_rng(0)
res = {}
# ---- D1-a (i)(ii): lab sizes and within-lab SD of raw PAMPA
cnt = collections.Counter(src); big = {s: c for s, c in cnt.items() if c >= 30}
sd = {s: float(y[src == s].std()) for s in cnt if cnt[s] >= 5}
res["lab_sizes_all"] = sorted(cnt.values(), reverse=True); res["n_labs"] = len(cnt); res["n_labs_ge30"] = len(big)
res["within_lab_sd_median_ge30"] = float(np.median([sd[s] for s in big])); res["within_lab_sd_iqr_ge30"] = [float(np.percentile([sd[s] for s in big], q)) for q in (25, 75)]
res["lab_means_sd_ge30"] = float(np.std([y[src == s].mean() for s in big]))   # confounded with chemistry; NOT used as tau
# ---- D1-a (iii): sigma_m = pooled SD of repeated PAMPA measurements of the same peptide in the SAME source
num = den = 0.0; ngroups = 0
for _, r in d.iterrows():
    if not isinstance(r.Same_Peptides_Source, str): continue
    try: srcs = ast.literal_eval(r.Same_Peptides_Source); perm = ast.literal_eval(r.Same_Peptides_Permeability); asy = ast.literal_eval(r.Same_Peptides_Assay)
    except Exception: continue
    for s, pv, av in zip(srcs, perm, asy):
        v = [float(x) for x, a in zip(pv, av) if a == "PAMPA" and float(x) > -9.99]
        if len(v) >= 2: num += (len(v) - 1) * np.var(v, ddof=1); den += len(v) - 1; ngroups += 1
# also duplicate rows with the same Structurally_Unique_ID inside one source in the loader set
g = d[d["PAMPA"].notna() & (d["PAMPA"] > -9.99)].groupby(["Source", "Structurally_Unique_ID"])["PAMPA"]
for _, v in g:
    if len(v) >= 2: num += (len(v) - 1) * np.var(v.values, ddof=1); den += len(v) - 1; ngroups += 1
res["sigma_m"] = float(np.sqrt(num / den)) if den else None; res["sigma_m_n_repeat_groups"] = ngroups; res["sigma_m_df"] = float(den)
# ---- D1-a (iv): tau-hat from the real anchors (method of moments), bootstrap CI
dd = np.array([a["y_self"] - a["y_others"] for a in anch]); m = np.array([len(a["other_sources"]) for a in anch]); mbar = float(m.mean())
sm = res["sigma_m"] or 0.0
def tau2(dv, mv): return max(0.0, float(np.var(dv)) - sm ** 2 * (1 + 1 / float(np.mean(mv))))
def tau2_alt(dv, mv): return max(0.0, float(np.var(dv)) / (1 + 1 / float(np.mean(mv))) - sm ** 2)
bs = [tau2(dd[i], m[i]) for i in (rng.integers(0, len(dd), len(dd)) for _ in range(2000))]
res["tau_hat_registered"] = float(np.sqrt(tau2(dd, m))); res["tau_hat_ci95"] = [float(np.sqrt(np.percentile(bs, 2.5))), float(np.sqrt(np.percentile(bs, 97.5)))]
res["tau_hat_alt_formula"] = float(np.sqrt(tau2_alt(dd, m))); res["anchor_d_mean"] = float(dd.mean()); res["anchor_d_sd"] = float(dd.std()); res["n_anchors"] = int(len(dd)); res["mean_partners"] = mbar
res["tau_note"] = "weakly identified (57 anchors in 8 sources); includes compound-class-dependent inter-lab differences, so it is an upper-leaning estimate of a constant lab shift"
# ---- D1-f census: peptide clusters via Same_Peptides_ID, sources measuring each cluster with PAMPA values
ids = d["ID"].astype(int).tolist(); pos = {i: k for k, i in enumerate(ids)}; parent = list(range(len(ids)))
def find(x):
    while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
    return x
for k, r in d.iterrows():
    if isinstance(r.Same_Peptides_ID, str):
        try: lst = ast.literal_eval(r.Same_Peptides_ID)
        except Exception: continue
        for j in lst:
            if j in pos: parent[find(k)] = find(pos[j])
clus = collections.defaultdict(lambda: dict(pampa=set(), anyassay=set()))
for k, r in d.iterrows():
    c = find(k); clus[c]["anyassay"].add(r.Source)
    if pd.notna(r.PAMPA) and r.PAMPA > -9.99: clus[c]["pampa"].add(r.Source)
    if isinstance(r.Same_Peptides_Source, str):
        try: srcs = ast.literal_eval(r.Same_Peptides_Source); asy = ast.literal_eval(r.Same_Peptides_Assay); perm = ast.literal_eval(r.Same_Peptides_Permeability)
        except Exception: continue
        for s, av, pv in zip(srcs, asy, perm):
            clus[c]["anyassay"].add(s)
            if any(a == "PAMPA" and float(x) > -9.99 for a, x in zip(av, pv)): clus[c]["pampa"].add(s)
census = {}
for key in ("pampa", "anyassay"):
    ns = np.array([len(v[key]) for v in clus.values()]); census[key] = {f">={k}_sources": int((ns >= k).sum()) for k in (1, 2, 3, 4)}
res["census_peptide_clusters"] = census; res["n_peptide_clusters"] = len(clus)
# greedy set cover on PAMPA-measured panel members: choose P clusters maximising number of labs with >= k members
labs_all = sorted(set(src)); lab_rows = {s: int(cnt[s]) for s in labs_all}; eligible = sorted(big)
def greedy(P, k):
    chosen, cover = [], collections.Counter()
    cands = [(c, v["pampa"]) for c, v in clus.items() if len(v["pampa"]) >= 2]
    for _ in range(P):
        best, bg = None, -1
        for c, ss in cands:
            if c in chosen: continue
            gain = sum(1 for s in ss if cover[s] == k - 1) + 1e-3 * sum(1 for s in ss if cover[s] < k)
            if gain > bg: best, bg = (c, ss), gain
        if best is None: break
        chosen.append(best[0]); [cover.update([s]) for s in best[1]]
    covered = [s for s in labs_all if cover[s] >= k]
    return dict(P=len(chosen), labs_covered=len(covered), labs_covered_eligible_ge30=len([s for s in covered if s in big]), rows_share=float(sum(lab_rows[s] for s in covered) / len(src)), covered=covered)
res["greedy_cover"] = {f"k{k}": {str(P): {a: b for a, b in greedy(P, k).items() if a != "covered"} for P in (3, 5, 10, 20, 40, 80)} for k in (3, 5)}
res["greedy_cover_covered_labs_P40_k3"] = greedy(40, 3)["covered"]
json.dump(res, open(OUT, "w"), indent=1); print(json.dumps({k: v for k, v in res.items() if k not in ("lab_sizes_all",)}, indent=1)[:5000])
