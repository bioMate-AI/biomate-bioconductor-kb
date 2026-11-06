"""Secondary analysis (PREREG sec. 2): n0 chosen from the grid by nested inner leave-one-training-lab-out CV (rules re-mined excluding both the outer and inner lab; 2 seeds;
k in {5,10,25}; objective = mean Spearman of F1 over inner cells), then applied to the outer held-out lab. Writes results/perm_nested_n0_cells.csv."""
import sys, os, numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import perm_testbed as T, fusion as F, peptide_sar_kb as P
d, dfull, pairs, elig = T.load(); bits = pd.DataFrame(T.bits_of(d.SMILES.values), index=d.index); GRID = T.N0S; rows = []; chosen = {}
def cells(L, K, k, seeds):
    dl = d[d.Source == L]; idx = dl.index.values; Bl = bits.loc[idx].values; y = dl.y_raw.values; flat = dl.flat_smiles.values
    if len(idx) - k < 20: return
    for s in seeds:
        rv = T.cell_rng(L, k, s).choice(len(idx), k, replace=False); fr = set(flat[rv]); rest = np.array([i for i in range(len(idx)) if i not in set(rv) and flat[i] not in fr])
        if len(rest) < 20 or np.std(y[rest]) < 1e-12: continue
        A = F.analog_perm(F.tanimoto(Bl[rest], Bl[rv]), y[rv]); r = F.reliability_perm(F.tanimoto(Bl[rv], Bl[rv]), y[rv]); yield s, rest, A, r, y[rest], K[rest]
for L in elig:
    inner = [t for t in elig if t != L and (d.Source == t).sum() >= 45]; score = {n0: [] for n0 in GRID}
    for Tn in inner:
        rs = P.fit(pairs, d, [e for e in elig if e not in (L, Tn)]); KT = rs.channel(d[d.Source == Tn])["K_phys"].values
        for k in T.KS:
            for s, rest, A, r, yr, Kp in cells(Tn, KT, k, (0, 1)):
                for n0 in GRID: score[n0].append(F.spearman(F.fuse(Kp, A, k, n0), yr))
    m = {n0: (np.nanmean(v) if len(v) else np.nan) for n0, v in score.items()}; best = max(GRID, key=lambda n: m[n] if np.isfinite(m[n]) else -9); chosen[L] = best
    rs = P.fit(pairs, d, [e for e in elig if e != L]); K = rs.channel(d[d.Source == L])["K_phys"].values
    for k in T.KS:
        for s, rest, A, r, yr, Kp in cells(L, K, k, T.SEEDS):
            rows.append(dict(lab=L, k=k, seed=s, n0_cv=best, F1_cv=F.spearman(F.fuse(Kp, A, k, best), yr), F2_cv=F.spearman(F.fuse2(Kp, A, k, r, best), yr), K=F.spearman(Kp, yr), A=F.spearman(A, yr)))
    print(L, "n0*", best, {n: round(v, 3) for n, v in m.items()}, flush=True)
pd.DataFrame(rows).to_csv(f"{HERE}/results/perm_nested_n0_cells.csv", index=False); print("chosen n0:", chosen)
