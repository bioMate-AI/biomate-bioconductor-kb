"""H4b analog-distance strata (PREREG A9). Re-scores the frozen reveal cells with the SAME arms as 11_h4b_run.py (imported, no changes) and aggregates AUROC by
nearest-revealed-analog similarity bin. Writes results/h4b_strata.json and results/h4b_strata_items_summary.csv."""
import os, sys, json, copy, warnings, importlib.util
import numpy as np, pandas as pd
warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("h4b", f"{HERE}/11_h4b_run.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
import harness as H
from sklearn.linear_model import LogisticRegression
BINS = [("close>=0.70", 0.70, 9), ("medium0.50-0.70", 0.50, 0.70), ("remote0.30-0.50", 0.30, 0.50), ("very_remote<0.30", -1, 0.30)]
BINS[0] = ("close>=0.70", 0.70, 9.0)
ARMS = ["R", "NN", "FP-k", "PT+k", "PT"]


def cells(t):
    g = m.I[m.I.target_key == t]; f = m.fold[m.fam[t]]; lr0, Xtr, ytr = m.PT[f]; out = []; n_sib = 0
    for k in (5, 10, 25):
        for s in m.SEEDS:
            if not m.E[(m.E.target_key == t) & (m.E.k == k) & (m.E.seed == s)].eligible.iloc[0]: continue
            rv = m.R[(m.R.target_key == t) & (m.R.k == k) & (m.R.seed == s)]; fl = set(m.flat[c] for c in rv.compound_id)
            rest = g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(m.flat).isin(fl)]; n_sib += int((g.compound_id.map(m.flat).isin(fl) & ~g.compound_id.isin(rv.compound_id)).sum())
            cid = rest.compound_id.values; Xr = np.stack([m.CNT[c] for c in cid]); ii = np.array([m.bitm[c] for c in cid]); allr = np.array([m.bitm[c] for c in rv.compound_id])
            sim = m.tan(ii, allr).max(1)
            rp = [c for c, l in zip(rv.compound_id, rv.label) if l == 1]; rn = [c for c, l in zip(rv.compound_id, rv.label) if l == 0]
            sp = m.tan(ii, np.array([m.bitm[c] for c in rp])).max(1) if rp else np.zeros(len(cid)); sn = m.tan(ii, np.array([m.bitm[c] for c in rn])).max(1) if rn else np.zeros(len(cid))
            sc = {"R": np.random.default_rng(1000 * k + s + len(t)).random(len(cid)), "PT": lr0.decision_function(Xr), "NN": sp - sn}
            if len(rp) and len(rn): sc["FP-k"] = LogisticRegression(C=0.5, max_iter=300).fit(np.stack([m.CNT[c] for c in rv.compound_id]), rv.label.values).decision_function(Xr)
            else: sc["FP-k"] = np.zeros(len(cid))
            mm = copy.deepcopy(lr0); mm.set_params(warm_start=True, max_iter=2000)
            mm.fit(np.vstack([Xtr, np.stack([m.CNT[c] for c in rv.compound_id])]), np.concatenate([ytr, rv.label.values]), sample_weight=np.concatenate([np.ones(len(ytr)), np.full(len(rv), 20.0)])); sc["PT+k"] = mm.decision_function(Xr)
            y = rest.label.values
            for bn, lo, hi in BINS:
                sel = (sim >= lo) & (sim < hi); n = int(sel.sum())
                rec = dict(target_key=t, k=k, seed=s, bin=bn, n_items=n, n_remaining=len(cid), n_pos=int(y[sel].sum()) if n else 0)
                ok = n >= 10 and y[sel].sum() >= 3 and (1 - y[sel]).sum() >= 3
                for a in ARMS: rec[a] = H.tie_aware_auc(y[sel], sc[a][sel]) if ok else np.nan
                out.append(rec)
    return out, n_sib


if __name__ == "__main__":
    import multiprocessing as mp
    tg = sorted(m.I.target_key.unique())
    with mp.get_context("fork").Pool(int(os.environ.get("PROCS", "4"))) as p: res = p.map(cells, tg)
    D = pd.DataFrame([r for x, _ in res for r in x]); n_sib = sum(s for _, s in res); D.to_csv(f"{m.RES}/h4b_strata_items_summary.csv", index=False)
    tf = m.T[["target_key", "family"]]; out = {"stereosibling_items_removed_total": int(n_sib), "bins": {}}
    for k in (5, 10, 25):
        out["bins"][str(k)] = {}
        for bn, _, _ in BINS:
            d = D[(D.k == k) & (D["bin"] == bn)]; tot = D[D.k == k].groupby("target_key").n_remaining.mean().sum()
            share = float(d.groupby(["target_key", "seed"]).n_items.mean().groupby("target_key").mean().sum() / tot) if len(d) else 0.0
            pt = d.groupby("target_key")[ARMS].mean().dropna(subset=["PT"]).reset_index().merge(tf, on="target_key"); r = dict(share_of_remaining_items=round(share, 3), targets=int(len(pt)), families=int(pt.family.nunique()))
            if r["families"] >= 3:
                fm = {a: pt.groupby("family")[a].mean() for a in ARMS}; r["auc"] = {a: H.boot_mean(fm[a], B=2000) for a in ARMS}
                r["transferable_gain_vs_PT"] = {a: H.boot_diff(fm[a], fm["PT"], B=2000) for a in ("FP-k", "PT+k")}; r["gain_vs_NN"] = {a: H.boot_diff(fm[a], fm["NN"], B=2000) for a in ("FP-k", "PT+k")}
            out["bins"][str(k)][bn] = r
    json.dump(out, open(f"{m.RES}/h4b_strata.json", "w"), indent=1)
    for k, v in out["bins"].items():
        for bn, r in v.items():
            if "auc" in r: print(f"k={k} {bn:18s} share {r['share_of_remaining_items']:.2f} tg {r['targets']} fam {r['families']} | " + " ".join(f"{a}:{r['auc'][a]['point']:.3f}" for a in ARMS) + f" | transf FP-k {r['transferable_gain_vs_PT']['FP-k']['point']:+.3f}[{r['transferable_gain_vs_PT']['FP-k']['lo']:+.3f},{r['transferable_gain_vs_PT']['FP-k']['hi']:+.3f}] PT+k {r['transferable_gain_vs_PT']['PT+k']['point']:+.3f}[{r['transferable_gain_vs_PT']['PT+k']['lo']:+.3f},{r['transferable_gain_vs_PT']['PT+k']['hi']:+.3f}]")
            else: print(f"k={k} {bn:18s} share {r['share_of_remaining_items']:.2f} tg {r['targets']} fam {r['families']} (too few families)")
