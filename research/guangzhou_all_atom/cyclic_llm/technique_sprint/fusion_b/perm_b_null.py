"""POST-HOC diagnostic (declared as such; added after the registered 3-world shuffle control failed by the letter, before reading real-data results):
PT is fit ONCE per held-out lab on the REAL labels of the other labs (it cannot see the held-out lab's labels), then the held-out lab's labels are permuted within the lab
S = 40 times and every cell/arm is evaluated. E[rho] = 0 exactly for any pipeline that does not leak the held-out lab's labels. Aggregation clusters on SHUFFLE realisations
(mean over labs per shuffle, then bootstrap over the 40 shuffles) and also reports the lab-cluster view. Writes results/perm_b_null40_cells.csv, perm_b_null40_summary.json."""
import sys, os, time, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.abspath(f"{HERE}/../fusion"))
import fusion_b as B, perm_testbed as T, common as C, perm_b as PB
from sklearn.ensemble import HistGradientBoostingRegressor
S = 40; t0 = time.time(); dfull = C.load_labelled(); vc = dfull.Source.value_counts(); elig = sorted(vc[vc >= 20].index); d = dfull[dfull.Source.isin(elig)].copy()
cnt = pd.DataFrame(T.counts_of(dfull.SMILES.values), index=dfull.index); phy = pd.DataFrame(C.desc_matrix(dfull, ["physchem"])[0], index=dfull.index); X = pd.concat([cnt, phy], axis=1); X.columns = range(X.shape[1]); bits = pd.DataFrame(T.bits_of(d.SMILES.values), index=d.index); rows = []
for L in elig:
    dl = d[d.Source == L]; idx = dl.index.values; tr = dfull[(dfull.Source != L) & ~dfull.flat_smiles.isin(set(dl.flat_smiles))]; pt = HistGradientBoostingRegressor(**PB.PT_PARAMS).fit(X.loc[tr.index].values, tr.y.values).predict(X.loc[idx].values)
    Bl = bits.loc[idx].values; flat = dl.flat_smiles.values; y0 = dl.y_raw.values
    for sh in range(S):
        y = np.random.default_rng(9000 + sh).permutation(y0)
        for k in T.KS:
            if len(idx) - k < 20: continue
            for s in T.SEEDS:
                rv = T.cell_rng(L, k, s).choice(len(idx), k, replace=False); fr = set(flat[rv]); rest = np.array([i for i in range(len(idx)) if i not in set(rv) and flat[i] not in fr])
                if len(rest) < 20 or np.std(y[rest]) < 1e-12: continue
                sim = B.tanimoto(Bl[rest], Bl[rv]); A = B.analog_perm(sim, y[rv]); r = B.reliability_perm(B.tanimoto(Bl[rv], Bl[rv]), y[rv]); P = pt[rest]
                for arm, sc in (("PT", P), ("A", A), ("PTk", B.ptk(P, sim, y[rv], pt[rv])), ("F1b_5", B.fuse(P, A, k, 5.0)), ("F2b_5", B.fuse2(P, A, k, r, 5.0))):
                    rows.append((sh, L, k, s, arm, B.spearman(sc, y[rest])))
    print("null40", L, round(time.time() - t0), "s", flush=True)
D = pd.DataFrame(rows, columns=["shuffle", "lab", "k", "seed", "arm", "spearman"]); D.to_csv(f"{HERE}/results/perm_b_null40_cells.csv", index=False)
pl = D.groupby(["shuffle", "k", "lab", "arm"]).spearman.mean().reset_index(); out = {}; ok = {}
rng = np.random.default_rng(1)
for arm in ("PT", "A", "PTk", "F1b_5", "F2b_5"):
    good = True
    for k in (5, 10, 25):
        g = pl[(pl.k == k) & (pl.arm == arm)]; per_sh = g.groupby("shuffle").spearman.mean().values; per_lab = g.groupby("lab").spearman.mean().values
        bs = per_sh[rng.integers(0, len(per_sh), (5000, len(per_sh)))].mean(1); bl = per_lab[rng.integers(0, len(per_lab), (5000, len(per_lab)))].mean(1)
        o = dict(mean=float(per_sh.mean()), ci95_shuffle_cluster=[float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))], ci95_lab_cluster=[float(np.percentile(bl, 2.5)), float(np.percentile(bl, 97.5))], n_shuffles=int(len(per_sh)), n_labs=int(len(per_lab)))
        out[f"k{k}_{arm}"] = o; good &= abs(o["mean"]) <= 0.03 and o["ci95_shuffle_cluster"][0] <= 0 <= o["ci95_shuffle_cluster"][1]
    ok[arm] = bool(good)
out["PASS_per_arm(|mean|<=0.03 and shuffle-cluster CI contains 0 at every k)"] = ok; json.dump(out, open(f"{HERE}/results/perm_b_null40_summary.json", "w"), indent=1)
for k in (5, 10, 25): print("k", k, {a: (round(out[f"k{k}_{a}"]["mean"], 4), [round(x, 3) for x in out[f"k{k}_{a}"]["ci95_shuffle_cluster"]], [round(x, 3) for x in out[f"k{k}_{a}"]["ci95_lab_cluster"]]) for a in ok})
print("PASS", ok)
