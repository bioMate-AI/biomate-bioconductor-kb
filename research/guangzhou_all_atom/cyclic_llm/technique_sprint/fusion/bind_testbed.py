"""T1 testbed 2: binding few-label H4b on analysis I (PREREG sec. 4 + A1). Re-uses the frozen machinery of retro_recovery/11_h4b_run.py (imported read-only).
Writes results/bind_cells.csv (per target/k/seed/arm metrics), results/bind_scores_<arm>_k<k>.csv (plug-in score files) and results/bind_summary.json."""
import sys, os, json, importlib.util, time
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery"); sys.path.insert(0, RR); sys.path.insert(0, HERE)
t0 = time.time()
spec = importlib.util.spec_from_file_location("h4brun", f"{RR}/11_h4b_run.py"); M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
print("imported 11_h4b_run", round(time.time() - t0), "s", flush=True)
import harness as H, validity_gate as G, fusion as F
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
PROX = ["heavy", "charge", "n_frac", "o_frac", "has_s", "has_halogen", "ncaa_frac", "n_arom", "tpsa", "logp", "hbd", "hba", "rotb", "fsp3", "ring", "n_rings", "n_alpha"]   # typicality-free (no in_corpus, in_cycpeptmpdb, typicality)
prox = G.load_proxies()[PROX]; med = prox.median()
N0S = [1, 2, 5, 10, 25]; N0 = 5.0
# prior P_B per held-out fold: logistic regression on typicality-free proxies, other folds' labelled pairs, flat-siblings of held-out compounds removed (as PT)
PB = {}
for f in sorted(set(M.I.target_key.map(M.fam).map(M.fold))):
    held = set(M.flat[c] for c in M.lab[M.lab.fold == f].compound_id); tr = M.lab[(M.lab.fold != f) & ~M.lab.compound_id.map(M.flat).isin(held)]
    tr = tr[tr.compound_id.isin(prox.index)]; X = prox.loc[tr.compound_id].fillna(med).values; sc = StandardScaler().fit(X); lr = LogisticRegression(C=0.5, max_iter=500).fit(sc.transform(X), tr.y.values); PB[f] = (sc, lr)
print("P_B fitted", round(time.time() - t0), "s", flush=True)


def prior_B(f, cids):
    sc, lr = PB[f]; X = prox.reindex(cids).fillna(med).values; return lr.decision_function(sc.transform(X))


def metrics(y, v):
    kk = 10; order = np.argsort(-v, kind="stable"); vs = v[order]; yy = y[order]; cut = vs[kk - 1]; above = vs > cut; tie = vs == cut
    p10 = (yy[above].sum() + (yy[tie].sum() * (kk - above.sum()) / tie.sum() if tie.sum() else 0)) / kk
    return dict(auc=H.tie_aware_auc(y, v), ef5=H.tie_aware_ef(y, v), p10=float(p10))


def one_target(t, scores_out):
    g = M.I[M.I.target_key == t]; f = M.fold[M.fam[t]]; lr0 = M.PT[f][0]; out = []
    for k in [0, 5, 10, 25]:
        for s in (M.SEEDS if k else [0]):
            if k:
                rv = M.R[(M.R.target_key == t) & (M.R.k == k) & (M.R.seed == s)]; fl = set(M.flat[c] for c in rv.compound_id)
                rest = g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(M.flat).isin(fl)]
                if not M.E[(M.E.target_key == t) & (M.E.k == k) & (M.E.seed == s)].eligible.iloc[0]: continue
            else: rv = M.R.iloc[:0]; rest = g
            cid = rest.compound_id.values; y = rest.label.values; Xr = np.stack([M.CNT[c] for c in cid]); sc = {}
            sc["PT"] = lr0.decision_function(Xr); sc["PB"] = prior_B(f, cid)
            if k:
                rcid = rv.compound_id.values; rl = rv.label.values; ii = np.array([M.bitm[c] for c in cid]); ir = np.array([M.bitm[c] for c in rcid])
                rp = ir[rl == 1]; rn = ir[rl == 0]
                sp = M.tan(ii, rp).max(1) if len(rp) else np.zeros(len(cid)); sn = M.tan(ii, rn).max(1) if len(rn) else np.zeros(len(cid)); NN = sp - sn; sc["NN"] = NN
                r = F.reliability_nn(M.tan(ir, ir), rl, H.tie_aware_auc)
                for pn, Pv in (("PB", sc["PB"]), ("PT", sc["PT"])):
                    for n0 in N0S: sc[f"F1_{pn}_{n0}"] = F.fuse(Pv, NN, k, n0); sc[f"F2_{pn}_{n0}"] = F.fuse2(Pv, NN, k, r, n0)
            for arm, v in sc.items():
                out.append(dict(target_key=t, k=k, seed=s, arm=arm, n=len(y), n_pos=int(y.sum()), r_rel=(r if k else np.nan), **metrics(y, v)))
                if arm in ("PB", "PT", "F1_PB_5", "F2_PB_5", "F1_PT_5", "F2_PT_5"):
                    scores_out.setdefault((arm, k), []).append(pd.DataFrame(dict(target_key=t, compound_id=cid, score=v, seed=s)))
    return out


if __name__ == "__main__":
    tg = sorted(M.I.target_key.unique()); rows = []; sco = {}
    for i, t in enumerate(tg):
        rows += one_target(t, sco)
        if i % 10 == 0: print("target", i, len(tg), round(time.time() - t0), flush=True)
    D = pd.DataFrame(rows); D.to_csv(f"{HERE}/results/bind_cells.csv", index=False)
    for (arm, k), parts in sco.items(): pd.concat(parts).to_csv(f"{HERE}/results/bind_scores_{arm}_k{k}.csv", index=False)
    print("wrote bind_cells.csv", len(D), round(time.time() - t0), "s")
