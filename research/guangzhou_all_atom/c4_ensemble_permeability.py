"""C4-forward: do EXPLICIT conformer-ENSEMBLE (chameleon-dynamics) features beat the
single-point 3D-PSA proxy (R2=0.301) and the static ECFP baseline (R2=0.237)?

Honest scope: RDKit ETKDGv3 gas-phase conformer ensembles (CPU, no GPU) — real multi-conformer
flexibility/shielding dynamics, but NOT explicit membrane-vs-water MD (that is the GPU next lever).
Same leak-free Murcko generic-scaffold folds + HistGBM as the C4 baseline, on an identical bounded
subset so ECFP / static-proxy / ensemble are apples-to-apples.

v2 (scale on spot): env-configurable subset/conformers/paths; the per-molecule conformer-generation
loop (the sole bottleneck) is PARALLELISED across all vCPUs (ProcessPoolExecutor, 1 embed thread
per worker) so a large subset finishes inside the spot self-terminate window. Env:
  C4_CSV   (default repo path)      C4_OUT   (default repo results path)
  C4_NMAX  (default 250)            C4_KCONF (default 20)
  C4_WORKERS (default cpu_count)    C4_EMBED_THREADS (default 1, per-mol)
"""
import csv, os, numpy as np, json, time, random
from concurrent.futures import ProcessPoolExecutor, as_completed
from rdkit import Chem
from rdkit.Chem import AllChem, rdFingerprintGenerator, Descriptors3D
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import r2_score, mean_absolute_error
from scipy.stats import spearmanr

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.environ.get("C4_CSV", os.path.join(HERE, "data/raw/CycPeptMPDB_Peptide_All.csv"))
OUT = os.environ.get("C4_OUT", os.path.join(HERE, "results/c4_ensemble_permeability.json"))
NMAX = int(os.environ.get("C4_NMAX", "250"))        # bounded subset (directional read; smaller n → wider CIs)
KCONF = int(os.environ.get("C4_KCONF", "20"))       # conformers per molecule
EMBED_THREADS = int(os.environ.get("C4_EMBED_THREADS", "1"))  # per-mol embed threads (1 → parallelise across mols)
N_WORKERS = int(os.environ.get("C4_WORKERS", str(os.cpu_count() or 4)))
random.seed(0)
FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def num(x):
    try: return float(x)
    except: return np.nan


def ihb_count(mol, conf):
    """intramolecular H-bonds: polar-H(on N/O) ... acceptor(N/O) < 2.5A, donor heavy != acceptor, not 1-2/1-3."""
    pos = conf.GetPositions()
    donorsH = []; acc = []
    for a in mol.GetAtoms():
        if a.GetSymbol() in ("N", "O"):
            for nb in a.GetNeighbors():
                if nb.GetSymbol() == "H": donorsH.append((nb.GetIdx(), a.GetIdx()))
            acc.append(a.GetIdx())
    n = 0
    for hidx, didx in donorsH:
        for aidx in acc:
            if aidx == didx: continue
            if mol.GetBondBetweenAtoms(didx, aidx) is not None: continue
            d = np.linalg.norm(pos[hidx] - pos[aidx])
            if d < 2.5: n += 1
    return n


def ens_feats(smi):
    m = Chem.MolFromSmiles(smi)
    if m is None: return None
    m = Chem.AddHs(m)
    p = AllChem.ETKDGv3(); p.randomSeed = 0; p.useRandomCoords = True; p.useMacrocycleTorsions = True
    p.maxIterations = 200; p.numThreads = EMBED_THREADS   # NO pruneRmsThresh (it collapsed macrocycles to 1 conf → ensemble lost)
    cids = AllChem.EmbedMultipleConfs(m, numConfs=KCONF, params=p)
    if len(cids) < 3: return None
    # MMFF skipped for speed: raw ETKDG ensemble already captures flexibility/shielding distribution
    rg = []; ihb = []; asph = []; npr1 = []; ecc = []
    for cid in cids:
        conf = m.GetConformer(cid)
        try:
            rg.append(Descriptors3D.RadiusOfGyration(m, confId=cid))
            asph.append(Descriptors3D.Asphericity(m, confId=cid))
            npr1.append(Descriptors3D.NPR1(m, confId=cid))
            ecc.append(Descriptors3D.Eccentricity(m, confId=cid))
        except: continue
        ihb.append(ihb_count(m, conf))
    if len(rg) < 3: return None
    rg = np.array(rg, float); ihb = np.array(ihb, float)
    # chameleon DYNAMICS: distribution stats across the ensemble
    return [rg.mean(), rg.std(), rg.max() - rg.min(),
            ihb.mean(), ihb.std(), ihb.max(), ihb.min(),
            float(np.mean(asph)), float(np.std(asph)),
            float(np.mean(npr1)), float(np.std(npr1)),
            float(np.mean(ecc)), len(cids)]


def _worker(arg):
    idx, smi = arg
    try:
        return idx, ens_feats(smi)
    except Exception:
        return idx, None


def main():
    # ---- load ----
    raw = []
    with open(CSV) as f:
        for r in csv.DictReader(f):
            smi = (r.get("SMILES") or "").strip()
            try: perm = float(r.get("Permeability", ""))
            except: continue
            if not smi: continue
            raw.append((smi, perm, r))
    random.shuffle(raw)
    raw = raw[:NMAX]
    print(f"subset requested={len(raw)} (from CycPeptMPDB), generating {KCONF} ETKDGv3 confs each; "
          f"workers={N_WORKERS} embed_threads={EMBED_THREADS}", flush=True)

    # ---- parallel conformer-ensemble feature generation (the only bottleneck) ----
    t0 = time.time()
    feats = [None] * len(raw)
    done = 0
    with ProcessPoolExecutor(max_workers=N_WORKERS) as ex:
        futs = {ex.submit(_worker, (i, raw[i][0])): i for i in range(len(raw))}
        for fut in as_completed(futs):
            idx, f = fut.result()
            feats[idx] = f
            done += 1
            if done % 100 == 0:
                kept = sum(1 for x in feats if x is not None)
                print(f"  {done}/{len(raw)} done, kept {kept}, {time.time()-t0:.0f}s", flush=True)
    rows = [(raw[i][0], raw[i][1], raw[i][2], feats[i]) for i in range(len(raw)) if feats[i] is not None]
    print(f"n with ensemble = {len(rows)}  ({time.time()-t0:.0f}s)", flush=True)

    y = np.array([p for _, p, _, _ in rows])
    mols = [Chem.MolFromSmiles(s) for s, _, _, _ in rows]
    X_ecfp = np.array([np.frombuffer(FP.GetFingerprint(m).ToBitString().encode(), 'u1') - 48 for m in mols], dtype=np.int8)

    def staticcham(r):
        c, h = num(r.get("CHCl3_3DPSA")), num(r.get("H2O_3DPSA"))
        return [c, h, h - c, (h - c) / (h + 1e-6), num(r.get("_3DPSA")), num(r.get("TPSA"))]
    X_static = np.array([staticcham(r) for _, _, r, _ in rows], dtype=float)
    X_ens = np.array([f for _, _, _, f in rows], dtype=float)

    # leak-free scaffold folds (same scheme as baseline)
    scaf = []
    for m in mols:
        try: scaf.append(MurckoScaffold.MurckoScaffoldSmiles(mol=MurckoScaffold.GetScaffoldForMol(m), includeChirality=False))
        except: scaf.append("")
    from collections import defaultdict
    g = defaultdict(list)
    for i, s in enumerate(scaf): g[s].append(i)
    folds = [[] for _ in range(5)]
    for j, idx in enumerate(sorted(g.values(), key=len, reverse=True)): folds[j % 5].extend(idx)
    fold = np.zeros(len(y), int)
    for k, idx in enumerate(folds):
        for i in idx: fold[i] = k

    def cv(X):
        oof = np.zeros(len(y))
        for k in range(5):
            te = fold == k; tr = ~te
            mdl = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=0)
            mdl.fit(X[tr], y[tr]); oof[te] = mdl.predict(X[te])
        return r2_score(y, oof), mean_absolute_error(y, oof), spearmanr(y, oof).correlation

    res = {}
    for name, X in [("ECFP (static baseline)", X_ecfp),
                    ("static 3D-PSA proxy", X_static),
                    ("ensemble-dynamics (ETKDG)", X_ens),
                    ("ECFP + static-proxy", np.hstack([X_ecfp, X_static])),
                    ("ECFP + ensemble-dynamics", np.hstack([X_ecfp, X_ens])),
                    ("ECFP + static + ensemble", np.hstack([X_ecfp, X_static, X_ens]))]:
        r2, mae, sp = cv(X); res[name] = {"scaffold_r2": round(r2, 3), "mae": round(mae, 3), "spearman": round(sp, 3)}
        print(f"{name:34s} R2={r2:.3f} MAE={mae:.3f} Spearman={sp:.3f}", flush=True)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"n": len(y), "n_scaffolds": len(g), "n_conf_target": KCONF, "subset": NMAX,
               "note": "RDKit ETKDGv3 gas-phase conformer ensembles (CPU); NOT explicit membrane MD; same leak-free scaffold folds; same-subset apples-to-apples",
               "ref_full8466": {"ECFP": 0.237, "ECFP+staticproxy": 0.301}, "results": res},
              open(OUT, "w"), indent=1)
    print(f"WROTE {OUT}", flush=True)


if __name__ == "__main__":
    main()
