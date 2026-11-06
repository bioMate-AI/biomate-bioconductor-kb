"""PREREG 6.3: independent brute-force (python loops + RDKit BulkTanimoto) recomputation of PT+k, F1b, F2b and r for 3 permeability cells; shared input = the PT predictions (refit with the registered settings)."""
import sys, os, zlib, math
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.abspath(f"{HERE}/../fusion"))
import perm_b as PB, perm_testbed as T, common as C
from rdkit import Chem, DataStructs
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor
cells = pd.read_csv(f"{HERE}/results/perm_b_cells_smoke.csv"); dfull = C.load_labelled(); vc = dfull.Source.value_counts(); elig = sorted(vc[vc >= 20].index); d = dfull[dfull.Source.isin(elig)]
L = elig[0]; dl = d[d.Source == L]; idx = dl.index.values
cnt = pd.DataFrame(T.counts_of(dfull.SMILES.values), index=dfull.index); phy = pd.DataFrame(C.desc_matrix(dfull, ["physchem"])[0], index=dfull.index); X = pd.concat([cnt, phy], axis=1); X.columns = range(X.shape[1])
tr = dfull[(dfull.Source != L) & ~dfull.flat_smiles.isin(set(dl.flat_smiles))]; pt = HistGradientBoostingRegressor(**PB.PT_PARAMS).fit(X.loc[tr.index].values, tr.y.values).predict(X.loc[idx].values)
smi = dl.SMILES.tolist(); y = dl.y_raw.values; flat = dl.flat_smiles.tolist(); fps = [T.GB.GetFingerprint(Chem.MolFromSmiles(s)) for s in smi]
def sp(a, b): return float(spearmanr(np.round(np.asarray(a, float), 10), b)[0])
def zz(v):
    m = sum(v) / len(v); s = math.sqrt(sum((x - m) ** 2 for x in v) / len(v)); return [0.0] * len(v) if s < 1e-12 else [(x - m) / s for x in v]
worst = 0.0
for k, s in [(5, 0), (10, 2), (25, 4)]:
    rv = list(T.cell_rng(L, k, s).choice(len(smi), k, replace=False)); fr = {flat[i] for i in rv}; rest = [i for i in range(len(smi)) if i not in set(rv) and flat[i] not in fr]
    ybar = sum(y[j] for j in rv) / k; A = []; corr = []
    mu = sum(pt[i] for i in rest) / len(rest); sd = math.sqrt(sum((pt[i] - mu) ** 2 for i in rest) / len(rest)); pz = lambda v: (v - mu) / sd
    ysd = math.sqrt(sum((y[j] - ybar) ** 2 for j in rv) / (k - 1)); res = [(y[j] - ybar) / ysd - pz(pt[j]) for j in rv]
    for i in rest:
        sims = DataStructs.BulkTanimotoSimilarity(fps[i], [fps[j] for j in rv]); w = [x ** 4 for x in sims]
        A.append(sum(wj * (y[j] - ybar) for wj, j in zip(w, rv)) / (sum(w) + 0.05)); corr.append(pz(pt[i]) + sum(wj * r_ for wj, r_ in zip(w, res)) / (sum(w) + 0.05))
    W = [[0.0] * k for _ in range(k)]
    for a_, ja in enumerate(rv):
        sims = DataStructs.BulkTanimotoSimilarity(fps[ja], [fps[j] for j in rv])
        for b_ in range(k): W[a_][b_] = 0.0 if a_ == b_ else sims[b_] ** 4
    mass = [sum(r_) for r_ in W]; ok = [m > 0.01 for m in mass]; m_ok = sum(ok)
    if k < 3: rr = 0.5
    elif m_ok < 3: rr = 3 * 0.5 / (m_ok + 3)
    else:
        Aloo = []; yy = []
        for j in range(k):
            if ok[j]:
                yb = (sum(y[i] for i in rv) - y[rv[j]]) / (k - 1); Aloo.append(sum(W[j][b_] * (y[rv[b_]] - yb) for b_ in range(k)) / (mass[j] + 0.05)); yy.append(y[rv[j]])
        rh = sp(Aloo, yy) if (np.std(Aloo) > 1e-12 and np.std(yy) > 1e-12) else 0.0; rh = 0.0 if not np.isfinite(rh) else min(max(rh, 0.0), 1.0); rr = (m_ok * rh + 1.5) / (m_ok + 3)
    P = [pt[i] for i in rest]; w5 = 5 / (5 + k); F1 = [w5 * a + (1 - w5) * b for a, b in zip(zz(P), zz(A))]; F2 = [w5 * a + (1 - w5) * rr * b for a, b in zip(zz(P), zz(A))]; yr = [y[i] for i in rest]
    got = cells[(cells.lab == L) & (cells.k == k) & (cells.seed == s)].set_index("arm").spearman
    for arm, v in {"PT": sp(P, yr), "A": sp(A, yr), "PTk": sp(corr, yr), "F1b_5": sp(F1, yr), "F2b_5": sp(F2, yr)}.items():
        dif = abs(v - got[arm]); worst = max(worst, dif); print(f"{L} k={k} s={s} {arm:6s} indep={v:.9f} pipeline={got[arm]:.9f} |diff|={dif:.2e}")
print("WORST |diff| =", worst, "PASS" if worst < 1e-6 else "FAIL")
