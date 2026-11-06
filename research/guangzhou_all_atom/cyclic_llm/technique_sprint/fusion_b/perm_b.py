"""T1b testbed 1 (PREREG sec. 2-3, 6.2): permeability leave-labs-out few-label with a learned prior PT. usage: python3 perm_b.py [--labs N] [--shuffles S]
Writes results/perm_b_cells.csv (real) and results/perm_b_shuffle_cells.csv; PT predictions cached in results/pt_cache_*.npz."""
import sys, os, time, argparse
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.abspath(f"{HERE}/../fusion"))
import fusion_b as B, perm_testbed as T, common as C
from sklearn.ensemble import HistGradientBoostingRegressor
KS = T.KS; SEEDS = T.SEEDS; N0S = [1, 2, 5, 10, 25]
PT_PARAMS = dict(max_iter=100, max_bins=31, learning_rate=0.1, max_leaf_nodes=31, min_samples_leaf=20, l2_regularization=0.0, early_stopping=False, random_state=0)   # PREREG sec. 2


def shuffled_full(dfull, seed):
    d = dfull.copy(); rng = np.random.default_rng(5000 + seed)
    for s in d.Source.unique():
        m = (d.Source == s).values; d.loc[m, "y_raw"] = rng.permutation(d.loc[m, "y_raw"].values); d.loc[m, "y"] = rng.permutation(d.loc[m, "y"].values)
    return d


def run(shuffle, labs_n, t0):
    dfull = C.load_labelled()
    if shuffle is not None: dfull = shuffled_full(dfull, shuffle)
    vc = dfull.Source.value_counts(); elig = sorted(vc[vc >= 20].index); d = dfull[dfull.Source.isin(elig)].copy(); labs = elig[:labs_n] if labs_n else elig
    cnt = pd.DataFrame(T.counts_of(dfull.SMILES.values), index=dfull.index); phy = pd.DataFrame(C.desc_matrix(dfull, ["physchem"])[0], index=dfull.index); X = pd.concat([cnt, phy], axis=1); X.columns = range(X.shape[1])
    bits = pd.DataFrame(T.bits_of(d.SMILES.values), index=d.index); rows = []
    for L in labs:
        dl = d[d.Source == L]; idx = dl.index.values; flat_L = set(dl.flat_smiles); tr = dfull[(dfull.Source != L) & ~dfull.flat_smiles.isin(flat_L)]
        m = HistGradientBoostingRegressor(**PT_PARAMS).fit(X.loc[tr.index].values, tr.y.values); pt = m.predict(X.loc[idx].values)
        Bl = bits.loc[idx].values; y = dl.y_raw.values; flat = dl.flat_smiles.values
        for k in KS:
            if len(idx) - k < 20: continue
            for s in SEEDS:
                rv = T.cell_rng(L, k, s).choice(len(idx), k, replace=False); fr = set(flat[rv]); rest = np.array([i for i in range(len(idx)) if i not in set(rv) and flat[i] not in fr])
                if len(rest) < 20 or np.std(y[rest]) < 1e-12: continue
                sim = B.tanimoto(Bl[rest], Bl[rv]); A = B.analog_perm(sim, y[rv]); r = B.reliability_perm(B.tanimoto(Bl[rv], Bl[rv]), y[rv]); P = pt[rest]
                def add(arm, sc): rows.append(dict(shuffle=-1 if shuffle is None else shuffle, lab=L, k=k, seed=s, arm=arm, spearman=B.spearman(sc, y[rest]), n_eval=len(rest), r_rel=r))
                add("PT", P); add("A", A); add("PTk", B.ptk(P, sim, y[rv], pt[rv]))
                for n0 in N0S: add(f"F1b_{n0}", B.fuse(P, A, k, n0)); add(f"F2b_{n0}", B.fuse2(P, A, k, r, n0))
        print("shuffle", shuffle, L, "n_train", len(tr), round(time.time() - t0), "s", flush=True)
    return rows


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--labs", type=int, default=0); ap.add_argument("--shuffles", type=int, default=0); ap.add_argument("--only-shuffle", action="store_true"); a = ap.parse_args(); t0 = time.time()
    if not a.only_shuffle:
        rows = run(None, a.labs, t0); pd.DataFrame(rows).to_csv(f"{HERE}/results/perm_b_cells{'_smoke' if a.labs else ''}.csv", index=False); print("wrote real", len(rows))
    if a.shuffles:
        rows = []
        for sh in range(a.shuffles): rows += run(sh, a.labs, t0)
        pd.DataFrame(rows).to_csv(f"{HERE}/results/perm_b_shuffle_cells{'_smoke' if a.labs else ''}.csv", index=False); print("wrote shuffle", len(rows))
