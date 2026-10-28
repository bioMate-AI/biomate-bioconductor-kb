"""T1 testbed 1: permeability leave-labs-out few-label (PREREG sec. 3 + A1). usage: python3 perm_testbed.py [--smoke] [--shuffle N] [--no-pt]
Writes results/perm_cells.csv (lab,k,seed,arm,spearman,n_eval,r_rel,...) or results/perm_shuffle_cells.csv."""
import sys, os, zlib, time, argparse
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); STRAT = os.path.abspath(f"{HERE}/../../stratification"); KB = os.path.abspath(f"{HERE}/../../kb_audit")
sys.path.insert(0, STRAT); sys.path.insert(0, KB); sys.path.insert(0, HERE)
import common as C, peptide_sar_kb as P, fusion as F
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import RandomForestRegressor, HistGradientBoostingRegressor
KS = [5, 10, 25]; SEEDS = range(5); N0S = [1, 2, 5, 10, 25]; N0 = 5.0; WGRID = [round(0.1 * i, 1) for i in range(11)]
GB = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
GC = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=1024, includeChirality=True)


def bits_of(smiles):
    from rdkit import Chem
    return np.stack([GB.GetFingerprintAsNumPy(Chem.MolFromSmiles(s)) for s in smiles]).astype(np.float32)


def counts_of(smiles):
    from rdkit import Chem
    return np.stack([np.log1p(GC.GetCountFingerprintAsNumPy(Chem.MolFromSmiles(s)).astype(np.float32)) for s in smiles])


def load(shuffle_seed=None):
    d = C.load_labelled(); pairs = pd.read_csv(f"{STRAT}/data/mmp_pairs_pampa.csv.gz"); dfull = d.copy()
    vc = d.Source.value_counts(); elig = sorted(vc[vc >= P.MIN_SRC_N].index); d = d[d.Source.isin(elig)].copy(); pairs = pairs[pairs.source.isin(elig)].copy()
    if shuffle_seed is not None:                                                    # same construction as kb_audit.lolo_evaluate(shuffle_labels=True)
        rng = np.random.default_rng(shuffle_seed)
        for s in d.Source.unique():
            m = (d.Source == s).values; d.loc[m, "y_raw"] = rng.permutation(d.loc[m, "y_raw"].values); d.loc[m, "y"] = rng.permutation(d.loc[m, "y"].values)
        ym = d["y_raw"].to_dict(); zm = d["y"].to_dict(); pairs["y_a"] = pairs.id_a.map(ym); pairs["y_b"] = pairs.id_b.map(ym); pairs["z_a"] = pairs.id_a.map(zm); pairs["z_b"] = pairs.id_b.map(zm)
    return d, dfull, pairs, elig


def cell_rng(L, k, s): return np.random.default_rng(zlib.crc32(f"{L}|{k}|{s}".encode()))


def eval_lab(L, d, dfull, pairs, elig, bitsD, cntD, descD, pt_pred, rows, arms_full=True, rs=None):
    dl = d[d.Source == L]; idx = dl.index.values; pos = {i: j for j, i in enumerate(idx)}
    rs = rs or P.fit(pairs, d, [s for s in elig if s != L]); Kall = rs.channel(dl)["K_phys"].values
    Bl = bitsD.loc[idx].values; y = dl.y_raw.values; flat = dl.flat_smiles.values
    for k in KS:
        if len(idx) - k < 20: continue                                          # cannot leave >= 20 evaluable items (eligibility rule)
        for s in SEEDS:
            rv = cell_rng(L, k, s).choice(len(idx), k, replace=False); fr = set(flat[rv])
            rest_all = np.setdiff1d(np.arange(len(idx)), rv); rest = np.array([i for i in rest_all if flat[i] not in fr])
            if len(rest) < 20 or np.std(y[rest]) < 1e-12: continue
            sim_r = F.tanimoto(Bl[rest], Bl[rv]); A = F.analog_perm(sim_r, y[rv]); r = F.reliability_perm(F.tanimoto(Bl[rv], Bl[rv]), y[rv]); Kp = Kall[rest]
            def add(arm, score, rr=rest): rows.append(dict(lab=L, k=k, seed=s, arm=arm, spearman=F.spearman(score, y[rr]), n_eval=len(rr), r_rel=r))
            add("K", Kp); add("A", A)
            for n0 in N0S: add(f"F1_{n0}", F.fuse(Kp, A, k, n0)); add(f"F2_{n0}", F.fuse2(Kp, A, k, r, n0))
            for w in WGRID: add(f"W_{w}", F.fuse(Kp, A, k, w=w))
            sim_a = F.tanimoto(Bl[rest_all], Bl[rv]); A_all = F.analog_perm(sim_a, y[rv]); K_all = Kall[rest_all]            # sibling-inclusive sensitivity
            add("K_sib", K_all, rest_all); add("A_sib", A_all, rest_all); add("F1_5_sib", F.fuse(K_all, A_all, k, N0), rest_all); add("F2_5_sib", F.fuse2(K_all, A_all, k, r, N0), rest_all)
            if arms_full:
                rf = RandomForestRegressor(n_estimators=200, random_state=s, n_jobs=-1).fit(Bl[rv], y[rv]); add("RF_rev", rf.predict(Bl[rest]))
                if pt_pred is not None:
                    pz_all = pt_pred[L]; mu, sd = pz_all[rest].mean(), pz_all[rest].std() or 1.0; pz = (pz_all[rest] - mu) / sd; pzr = (pz_all[rv] - mu) / sd
                    add("PT", pz); ysd = np.std(y[rv], ddof=1) if k > 1 and np.std(y[rv], ddof=1) > 1e-12 else 1.0; res = (y[rv] - y[rv].mean()) / ysd - pzr; W = sim_r ** 4
                    add("PTk", pz + (W @ res) / (W.sum(1) + 0.05))


def fit_pt(d, dfull, L):
    """HistGB on all labelled peptides outside lab L (flat-identical to L's peptides removed), within-source-z labels; chirality-aware count bits + physchem descriptors."""
    flat_L = set(d[d.Source == L].flat_smiles); tr = dfull[(dfull.Source != L) & ~dfull.flat_smiles.isin(flat_L)]
    return tr


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--smoke", action="store_true"); ap.add_argument("--shuffle", type=int, default=0); ap.add_argument("--no-pt", action="store_true"); a = ap.parse_args()
    t0 = time.time(); rows = []
    shuffles = [None] if not a.shuffle else list(range(a.shuffle))
    for sh in shuffles:
        d, dfull, pairs, elig = load(sh); labs = elig[:2] if a.smoke else elig
        print("shuffle", sh, "labs", len(labs), "peptides", len(d), flush=True)
        bitsD = pd.DataFrame(bits_of(d.SMILES.values), index=d.index); cntD = None; descD = None; pt_pred = {}
        if not a.no_pt and sh is None:
            Cf = C.fingerprints  # unused; keep import side effects minimal
            allcnt = pd.DataFrame(counts_of(dfull.SMILES.values), index=dfull.index); allde = C.desc_matrix(dfull, ["physchem"])[0]; desc_df = pd.DataFrame(allde, index=dfull.index)
            for L in labs:
                tr = fit_pt(d, dfull, L); Xtr = np.hstack([allcnt.loc[tr.index].values, desc_df.loc[tr.index].values]); m = HistGradientBoostingRegressor(max_iter=100, max_bins=31, learning_rate=0.1, random_state=0).fit(Xtr, tr.y.values)
                dl = d[d.Source == L]; pt_pred[L] = m.predict(np.hstack([allcnt.loc[dl.index].values, desc_df.loc[dl.index].values])); print("PT", L, round(time.time() - t0), flush=True)
        for L in labs:
            r0 = len(rows); eval_lab(L, d, dfull, pairs, elig, bitsD, cntD, descD, pt_pred if pt_pred else None, rows, arms_full=(sh is None and not a.no_pt))
            for x in rows[r0:]: x["shuffle"] = -1 if sh is None else sh
            print("done", L, len(rows) - r0, round(time.time() - t0), flush=True)
    out = "perm_shuffle_cells.csv" if a.shuffle else ("perm_cells_smoke.csv" if a.smoke else ("perm_cells_nopt.csv" if a.no_pt else "perm_cells.csv"))
    pd.DataFrame(rows).to_csv(f"{HERE}/results/{out}", index=False); print("wrote", out, len(rows))
