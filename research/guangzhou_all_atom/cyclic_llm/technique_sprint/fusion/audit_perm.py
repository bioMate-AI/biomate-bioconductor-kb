"""PREREG 6.4 audit: independent brute-force (pure-python loops + RDKit BulkTanimoto) recomputation of analog estimate, reliability and fusions for 3 cells; compare to the pipeline's cells."""
import sys, os, zlib, math
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import perm_testbed as T, fusion as F
from rdkit import Chem, DataStructs
from scipy.stats import spearmanr
cells = pd.read_csv(f"{HERE}/results/perm_cells_smoke.csv")
d, dfull, pairs, elig = T.load(); GB = T.GB
def sp(a, b): return float(spearmanr(np.round(np.asarray(a, float), 10), b)[0])
def zz(v):
    m = sum(v) / len(v); s = math.sqrt(sum((x - m) ** 2 for x in v) / len(v)); return [0.0] * len(v) if s < 1e-12 else [(x - m) / s for x in v]
worst = 0.0
for L, k, s in [("2013_CHUGAI", 5, 0), ("2013_CHUGAI", 25, 3), ("2015_Ahlbach", 5, 1)]:
    dl = d[d.Source == L]; smi = dl.SMILES.tolist(); y = dl.y_raw.values; flat = dl.flat_smiles.tolist()
    rv = list(np.random.default_rng(zlib.crc32(f"{L}|{k}|{s}".encode())).choice(len(smi), k, replace=False)); fr = {flat[i] for i in rv}
    rest = [i for i in range(len(smi)) if i not in set(rv) and flat[i] not in fr]
    fps = [GB.GetFingerprint(Chem.MolFromSmiles(x)) for x in smi]                      # ExplicitBitVect (independent of the numpy path)
    ybar = sum(y[j] for j in rv) / k
    A = []
    for i in rest:
        sims = DataStructs.BulkTanimotoSimilarity(fps[i], [fps[j] for j in rv]); w = [x ** 4 for x in sims]
        A.append(sum(wj * (y[j] - ybar) for wj, j in zip(w, rv)) / (sum(w) + 0.05))
    # reliability (leave-one-out among revealed)
    W = [[0.0] * k for _ in range(k)]
    for a_, ja in enumerate(rv):
        sims = DataStructs.BulkTanimotoSimilarity(fps[ja], [fps[j] for j in rv])
        for b_ in range(k): W[a_][b_] = 0.0 if a_ == b_ else sims[b_] ** 4
    mass = [sum(r) for r in W]; ok = [m > 0.01 for m in mass]; m_ok = sum(ok)
    if k < 3: rr = 0.5
    elif m_ok < 3: rr = (0 + 3 * 0.5) / (m_ok + 3)
    else:
        Aloo = []; yy = []
        for j in range(k):
            if ok[j]:
                yb = (sum(y[i] for i in rv) - y[rv[j]]) / (k - 1); Aloo.append(sum(W[j][b_] * (y[rv[b_]] - yb) for b_ in range(k)) / (mass[j] + 0.05)); yy.append(y[rv[j]])
        rh = sp(Aloo, yy) if (np.std(Aloo) > 1e-12 and np.std(yy) > 1e-12) else 0.0; rh = 0.0 if not np.isfinite(rh) else min(max(rh, 0.0), 1.0); rr = (m_ok * rh + 3 * 0.5) / (m_ok + 3)
    rs = P_ = None
    import peptide_sar_kb as P
    rs = P.fit(pairs, d, [e for e in elig if e != L]); K = rs.channel(dl)["K_phys"].values; Kp = [K[i] for i in rest]
    w = 5 / (5 + k); F1 = [w * a + (1 - w) * b for a, b in zip(zz(Kp), zz(A))]; F2 = [w * a + (1 - w) * rr * b for a, b in zip(zz(Kp), zz(A))]
    yr = [y[i] for i in rest]; got = cells[(cells.lab == L) & (cells.k == k) & (cells.seed == s)].set_index("arm").spearman
    ref = {"K": sp(Kp, yr), "A": sp(A, yr), "F1_5": sp(F1, yr), "F2_5": sp(F2, yr)}
    for arm, v in ref.items():
        dif = abs(v - got[arm]); worst = max(worst, dif); print(f"{L} k={k} s={s} {arm:5s} indep={v:.9f} pipeline={got[arm]:.9f} |diff|={dif:.2e}")
    print("   r independent =", round(rr, 6), " pipeline r =", round(float(cells[(cells.lab == L) & (cells.k == k) & (cells.seed == s)].r_rel.iloc[0]), 6))
print("WORST |diff| =", worst, "PASS" if worst < 1e-6 else "FAIL")
