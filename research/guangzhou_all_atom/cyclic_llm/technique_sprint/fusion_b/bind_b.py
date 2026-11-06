"""T1b testbed 2 (PREREG sec. 2, 4, 6.2): binding few-label H4b on analysis I with PT as prior; frozen baselines re-implemented (parity-checked), analog-distance strata.
usage: python3 bind_b.py [--shuffle S]   -> results/bind_b_cells.csv | bind_b_shuffle_<S>_cells.csv ; score files results/bind_b_scores_*.csv (real only)"""
import sys, os, copy, importlib.util, time, argparse
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery"); sys.path.insert(0, RR); sys.path.insert(0, HERE)
ap = argparse.ArgumentParser(); ap.add_argument("--shuffle", type=int, default=None); a = ap.parse_args(); t0 = time.time()
spec = importlib.util.spec_from_file_location("h4brun", f"{RR}/11_h4b_run.py"); M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
import harness as H, validity_gate as G, fusion_b as B
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
N0S = [1, 2, 5, 10, 25]
if a.shuffle is not None:                                        # permute labels within target: items I, reveals R (via I mapping), and the training pair labels
    rng = np.random.default_rng(7000 + a.shuffle); newl = {}
    for t, g in M.I.groupby("target_key"): newl.update({(t, c): l for c, l in zip(g.compound_id.values, rng.permutation(g.label.values))})
    M.I["label"] = [newl[(t, c)] for t, c in zip(M.I.target_key, M.I.compound_id)]; M.R["label"] = [newl[(t, c)] for t, c in zip(M.R.target_key, M.R.compound_id)]
    for t in M.lab.target_key.unique(): m = (M.lab.target_key == t).values; M.lab.loc[m, "y"] = rng.permutation(M.lab.loc[m, "y"].values)
    PT = {}
    for f in sorted(set(M.I.target_key.map(M.fam).map(M.fold))):
        held = set(M.flat[c] for c in M.lab[M.lab.fold == f].compound_id); tr = M.lab[(M.lab.fold != f) & ~M.lab.compound_id.map(M.flat).isin(held)]
        X = np.stack([M.CNT[c] for c in tr.compound_id]); PT[f] = (LogisticRegression(C=0.05, max_iter=300).fit(X, tr.y.values), X, tr.y.values)
    M.PT = PT; print("shuffled world", a.shuffle, "PT refit", round(time.time() - t0), "s", flush=True)
PROX = ["heavy", "charge", "n_frac", "o_frac", "has_s", "has_halogen", "ncaa_frac", "n_arom", "tpsa", "logp", "hbd", "hba", "rotb", "fsp3", "ring", "n_rings", "n_alpha"]
prox = G.load_proxies()[PROX]; med = prox.median(); PBm = {}
for f in sorted(set(M.I.target_key.map(M.fam).map(M.fold))):
    held = set(M.flat[c] for c in M.lab[M.lab.fold == f].compound_id); tr = M.lab[(M.lab.fold != f) & ~M.lab.compound_id.map(M.flat).isin(held)]; tr = tr[tr.compound_id.isin(prox.index)]
    Xp = prox.loc[tr.compound_id].fillna(med).values; sc_ = StandardScaler().fit(Xp); PBm[f] = (sc_, LogisticRegression(C=0.5, max_iter=500).fit(sc_.transform(Xp), tr.y.values))
print("priors ready", round(time.time() - t0), "s", flush=True)


def met(y, v, near=None):
    kk = 10; order = np.argsort(-v, kind="stable"); vs = v[order]; yy = y[order]; cut = vs[kk - 1]; above = vs > cut; tie = vs == cut
    p10 = (yy[above].sum() + (yy[tie].sum() * (kk - above.sum()) / tie.sum() if tie.sum() else 0)) / kk; o = dict(auc=H.tie_aware_auc(y, v), ef5=H.tie_aware_ef(y, v), p10=float(p10))
    for nm, mk in (("near", near), ("far", None if near is None else ~near)):
        o["auc_" + nm] = np.nan
        if mk is not None and mk.sum() >= 6 and len(set(y[mk])) == 2 and min(y[mk].sum(), (1 - y[mk]).sum()) >= 3: o["auc_" + nm] = H.tie_aware_auc(y[mk], v[mk])
    return o


def one_target(t, sco):
    g = M.I[M.I.target_key == t]; f = M.fold[M.fam[t]]; lr0, Xtr, ytr = M.PT[f]; out = []; scb, lrb = PBm[f]
    for k in [0, 5, 10, 25]:
        for s in (M.SEEDS if k else [0]):
            if k:
                rv = M.R[(M.R.target_key == t) & (M.R.k == k) & (M.R.seed == s)]; fl = set(M.flat[c] for c in rv.compound_id)
                rest = g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(M.flat).isin(fl)]
                if not M.E[(M.E.target_key == t) & (M.E.k == k) & (M.E.seed == s)].eligible.iloc[0]: continue
            else: rv = M.R.iloc[:0]; rest = g
            cid = rest.compound_id.values; y = rest.label.values; Xr = np.stack([M.CNT[c] for c in cid]); sc = {}; near = None
            sc["R"] = np.random.default_rng(1000 * k + s + len(t)).random(len(cid)); sc["PT"] = lr0.decision_function(Xr); sc["PB"] = lrb.decision_function(scb.transform(prox.reindex(cid).fillna(med).values))
            r = np.nan
            if k:
                rcid = rv.compound_id.values; rl = rv.label.values; ii = np.array([M.bitm[c] for c in cid]); ir = np.array([M.bitm[c] for c in rcid]); rp = ir[rl == 1]; rn = ir[rl == 0]
                simR = M.tan(ii, ir); near = simR.max(1) >= np.median(simR.max(1))
                sp = M.tan(ii, rp).max(1) if len(rp) else np.zeros(len(cid)); sn = M.tan(ii, rn).max(1) if len(rn) else np.zeros(len(cid)); NN = sp - sn; sc["NN"] = NN
                if len(rp) and len(rn) and k >= 5: sc["FP-k"] = LogisticRegression(C=0.5, max_iter=300).fit(np.stack([M.CNT[c] for c in rcid]), rl).decision_function(Xr)
                else: sc["FP-k"] = np.zeros(len(cid))
                m = copy.deepcopy(lr0); m.set_params(warm_start=True, max_iter=2000)
                m.fit(np.vstack([Xtr, np.stack([M.CNT[c] for c in rcid])]), np.concatenate([ytr, rl]), sample_weight=np.concatenate([np.ones(len(ytr)), np.full(len(rcid), 20.0)])); sc["PT+k"] = m.decision_function(Xr)
                r = B.reliability_nn(M.tan(ir, ir), rl, H.tie_aware_auc)
                for pn in ("PT", "PB"):
                    for n0 in (N0S if pn == "PT" else [5]): sc[f"F1b_{pn}_{n0}"] = B.fuse(sc[pn], NN, k, n0); sc[f"F2b_{pn}_{n0}"] = B.fuse2(sc[pn], NN, k, r, n0)
            for arm, v in sc.items():
                out.append(dict(target_key=t, k=k, seed=s, arm=arm, n=len(y), n_pos=int(y.sum()), r_rel=r, **met(y, v, near)))
                if a.shuffle is None and arm in ("PT", "F1b_PT_5", "F2b_PT_5", "F2b_PT_10", "F2b_PB_5"): sco.setdefault((arm, k), []).append(pd.DataFrame(dict(target_key=t, compound_id=cid, score=v, seed=s)))
    return out


if __name__ == "__main__":
    rows = []; sco = {}; tg = sorted(M.I.target_key.unique())
    for i, t in enumerate(tg):
        rows += one_target(t, sco)
        if i % 10 == 0: print("target", i, len(tg), round(time.time() - t0), flush=True)
    D = pd.DataFrame(rows); D["shuffle"] = -1 if a.shuffle is None else a.shuffle
    fn = "bind_b_cells.csv" if a.shuffle is None else f"bind_b_shuffle_{a.shuffle}_cells.csv"; D.to_csv(f"{HERE}/results/{fn}", index=False)
    for (arm, k), parts in sco.items(): pd.concat(parts).to_csv(f"{HERE}/results/bind_b_scores_{arm}_k{k}.csv", index=False)
    print("wrote", fn, len(D), round(time.time() - t0), "s")
