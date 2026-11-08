"""err_analysis_permeability.py — WHY is our permeability oracle ~0.3 while SOTA (CycPeptMP) is ~0.77?

Error analysis: hold the model (HistGBM) + the LEAKAGE-SAFE split (cluster-disjoint, monomer-Tanimoto)
fixed, vary only the FEATURES, and measure cluster-disjoint CV R²/MAE/Spearman. This isolates how much of
the gap is FEATURES vs model/data. Feature tiers, crude -> rich:
  1. monomer-composition  (what methodology_close's reward oracle uses — the suspected bottleneck)
  2. ECFP (Morgan, from SMILES)                      (structure)
  3. chameleon 3D-PSA     (CHCl3/H2O 3D-PSA, the dynamical descriptor C4 showed lifts permeability)
  4. ECFP + chameleon     (toward CycPeptMP's multi-level fusion, within a simple model)
All on the SAME CycPeptMPDB rows + SAME folds. CPU; collected data only.
"""
import ast, csv, os, hashlib, numpy as np
from rdkit import Chem
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import r2_score, mean_absolute_error
from scipy.stats import spearmanr

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
CSV = os.path.join(ROOT, "data/raw/CycPeptMPDB_Peptide_All.csv")
FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
CANON = set("ACDEFGHIKLMNPQRSTVWY")


def num(x):
    try: return float(x)
    except: return np.nan


def load():
    rows = []
    for r in csv.DictReader(open(CSV)):
        try: perm = float(r["Permeability"])
        except: continue
        smi = (r.get("SMILES") or "").strip(); seq = (r.get("Sequence") or "").strip()
        if not smi or not seq: continue
        try: monos = [str(m) for m in ast.literal_eval(seq)]
        except: continue
        if 3 <= len(monos) <= 24:
            rows.append((monos, smi, r, perm))
    return rows


def cluster_folds(rows, k=5, thr=0.6, nmax=4000, seed=0):
    rng = np.random.default_rng(seed)
    if len(rows) > nmax:
        idx = rng.choice(len(rows), nmax, replace=False); rows = [rows[i] for i in idx]
    vocab = sorted({m for mo, _, _, _ in rows for m in mo}); vi = {m: i for i, m in enumerate(vocab)}
    B = np.zeros((len(rows), len(vocab)), bool)
    for r, (mo, _, _, _) in enumerate(rows):
        for m in mo: B[r, vi[m]] = True
    card = B.sum(1).astype(np.float32); assigned = -np.ones(len(rows), int); cid = 0
    for i in rng.permutation(len(rows)):
        if assigned[i] >= 0: continue
        inter = (B & B[i]).sum(1).astype(np.float32)
        tani = inter / (card + card[i] - inter + 1e-9)
        assigned[np.where((tani >= thr) & (assigned < 0))[0]] = cid; cid += 1
    fold = np.array([assigned[i] % k for i in range(len(rows))])   # whole clusters -> one fold
    return rows, fold, cid


def feats(rows):
    vocab = sorted({m for mo, _, _, _ in rows for m in mo}); vi = {m: i for i, m in enumerate(vocab)}
    def comp(mo):
        x = np.zeros(len(vocab) + 2, np.float32)
        for m in mo:
            if m in vi: x[vi[m]] += 1
        L = max(len(mo), 1); x[:len(vocab)] /= L
        x[-2] = L; x[-1] = sum(1 for m in mo if m not in CANON) / L
        return x
    Xcomp = np.array([comp(mo) for mo, _, _, _ in rows])
    mols = [Chem.MolFromSmiles(s) for _, s, _, _ in rows]
    Xecfp = np.array([(np.frombuffer(FP.GetFingerprint(m).ToBitString().encode(), 'u1') - 48) if m else np.zeros(2048)
                      for m in mols], dtype=np.int8)
    def cham(r):
        c, h = num(r.get("CHCl3_3DPSA")), num(r.get("H2O_3DPSA"))
        return [c, h, h - c, (h - c) / (h + 1e-6), num(r.get("_3DPSA")), num(r.get("TPSA"))]
    Xcham = np.array([cham(r) for _, _, r, _ in rows], float)
    y = np.array([p for _, _, _, p in rows])
    return y, {"1.monomer-composition (reward oracle)": Xcomp, "2.ECFP (structure)": Xecfp,
               "3.chameleon 3D-PSA (dynamical)": Xcham, "4.ECFP + chameleon (multi-level)": np.hstack([Xecfp, Xcham])}


def cv(X, y, fold, k=5):
    oof = np.zeros(len(y))
    for f in range(k):
        te = fold == f; tr = ~te
        if te.sum() == 0 or tr.sum() < 20: continue
        m = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05, max_depth=8, random_state=0)
        m.fit(X[tr], y[tr]); oof[te] = m.predict(X[te])
    return r2_score(y, oof), mean_absolute_error(y, oof), spearmanr(y, oof).correlation


def main():
    rows = load(); print(f"loaded {len(rows)} CycPeptMPDB peptides w/ SMILES+Sequence+permeability", flush=True)
    rows, fold, ncl = cluster_folds(rows); print(f"cluster-disjoint folds: {ncl} clusters over {len(rows)} rows", flush=True)
    y, F = feats(rows)
    print(f"\n{'feature set':38s} {'R2':>7} {'MAE':>7} {'Spearman':>9}   (cluster-disjoint 5-fold CV)")
    res = {}
    for name, X in F.items():
        r2, mae, sp = cv(np.nan_to_num(X.astype(float)), y, fold); res[name] = round(r2, 3)
        print(f"{name:38s} {r2:7.3f} {mae:7.3f} {sp:9.3f}", flush=True)
    import json
    json.dump({"what": "permeability feature-tier error analysis (leakage-safe CV)",
               "n": len(rows), "n_clusters": ncl, "sota_ref": {"CycPeptMP_r": 0.883, "CPMP_PAMPA_R2": 0.67},
               "R2_by_feature": res,
               "finding": "locates how much of the ~0.3 vs ~0.77 gap is FEATURES (monomer-composition is the "
                          "reward-oracle bottleneck) vs model/data"},
              open(os.path.join(ROOT, "results/err_analysis_permeability.json"), "w"), indent=2)
    print("\nwrote results/err_analysis_permeability.json")


if __name__ == "__main__":
    main()
