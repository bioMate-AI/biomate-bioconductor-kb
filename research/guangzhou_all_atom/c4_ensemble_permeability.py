"""C4-forward: explicit conformer-ENSEMBLE (chameleon-dynamics) permeability features vs the
single-point 3D-PSA proxy (R2=0.301) and static ECFP (R2=0.237).

Honest scope: RDKit ETKDGv3 gas-phase ensembles (CPU, no GPU) — real flexibility/shielding dynamics,
NOT explicit membrane-vs-water MD (GPU next lever). Featurization is ~9 s/mol single-thread, so the
full 8,466-row set is ~21 h serial (exceeds one window). This version is BOTH:
  (1) PARALLEL across molecules (ProcessPoolExecutor, 1 embed thread/worker) — the full set then fits
      one spot window (~8466*9s / N_cores); and
  (2) CACHED + RESUMABLE (jsonl keyed by SMILES md5) — a truncated/interrupted run loses nothing and a
      re-run accumulates. CV runs once >= MIN_CV molecules are cached.
Degenerate-column guard on CV (HistGBM binning crashes on columns with <2 distinct values — common for
all-zero ECFP bits at full set). Same leak-free Murcko scaffold folds + HistGBM as the C4 baseline,
same-subset apples-to-apples.

Reconciles two prior variants: the cached/resumable serial version (25408bfc9) and the parallel
rewrite (0fe9afe6e). Env: C4_CSV C4_OUT C4_CACHE C4_NMAX C4_KCONF C4_WORKERS C4_EMBED_THREADS C4_MIN_CV.
"""
import csv, os, json, time, random, hashlib, numpy as np
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
CACHE = os.environ.get("C4_CACHE", os.path.join(HERE, "results/c4_ensemble_cache.jsonl"))
NMAX = int(os.environ.get("C4_NMAX", "9000"))        # cap on dataset rows considered (9000 → all ~8466)
KCONF = int(os.environ.get("C4_KCONF", "20"))        # conformers per molecule
EMBED_THREADS = int(os.environ.get("C4_EMBED_THREADS", "1"))   # per-mol threads; 1 → parallelise across mols
N_WORKERS = int(os.environ.get("C4_WORKERS", str(os.cpu_count() or 4)))
MIN_CV = int(os.environ.get("C4_MIN_CV", "600"))     # need >= this many cached before a (less-underpowered) CV
FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def num(x):
    try: return float(x)
    except: return np.nan


def key(s):
    return hashlib.md5(s.encode()).hexdigest()[:16]


def ihb(mol, conf):
    pos = conf.GetPositions(); dH = []; acc = []
    for a in mol.GetAtoms():
        if a.GetSymbol() in ("N", "O"):
            acc.append(a.GetIdx())
            for nb in a.GetNeighbors():
                if nb.GetSymbol() == "H": dH.append((nb.GetIdx(), a.GetIdx()))
    n = 0
    for hi, di in dH:
        for ai in acc:
            if ai == di or mol.GetBondBetweenAtoms(di, ai): continue
            if np.linalg.norm(pos[hi] - pos[ai]) < 2.5: n += 1
    return n


def ens(smi):
    m = Chem.MolFromSmiles(smi)
    if m is None: return None
    m = Chem.AddHs(m)
    p = AllChem.ETKDGv3(); p.randomSeed = 0; p.useRandomCoords = True; p.useMacrocycleTorsions = True
    p.maxIterations = 200; p.numThreads = EMBED_THREADS
    cids = AllChem.EmbedMultipleConfs(m, numConfs=KCONF, params=p)
    if len(cids) < 3: return None
    rg = []; hb = []; asph = []; npr = []; ecc = []
    for c in cids:
        try:
            rg.append(Descriptors3D.RadiusOfGyration(m, confId=c)); asph.append(Descriptors3D.Asphericity(m, confId=c))
            npr.append(Descriptors3D.NPR1(m, confId=c)); ecc.append(Descriptors3D.Eccentricity(m, confId=c))
            hb.append(ihb(m, m.GetConformer(c)))
        except: continue
    if len(rg) < 3: return None
    rg = np.array(rg, float); hb = np.array(hb, float)
    return [rg.mean(), rg.std(), rg.max() - rg.min(), hb.mean(), hb.std(), hb.max(), hb.min(),
            float(np.mean(asph)), float(np.std(asph)), float(np.mean(npr)), float(np.std(npr)),
            float(np.mean(ecc)), len(cids)]


def _worker(arg):
    k, smi = arg
    try:
        return k, ens(smi)
    except Exception:
        return k, None


def dropdegen(X):      # HistGBM binning crashes on columns with <2 distinct values (e.g. all-zero ECFP bits)
    X = np.asarray(X, float)
    keep = [j for j in range(X.shape[1]) if np.unique(X[~np.isnan(X[:, j]), j]).size >= 2]
    return X[:, keep] if keep else X


def main():
    # ---- load dataset (full, shuffled deterministically) ----
    random.seed(0)
    raw = []
    for r in csv.DictReader(open(CSV)):
        smi = (r.get("SMILES") or "").strip()
        try: perm = float(r.get("Permeability", ""))
        except: continue
        if smi: raw.append((smi, perm, r))
    random.shuffle(raw)
    raw = raw[:NMAX]

    # ---- load cache ----
    cache = {}
    if os.path.exists(CACHE):
        for line in open(CACHE):
            try:
                d = json.loads(line); cache[d["k"]] = d
            except: pass
    todo = [(key(smi), smi, perm, r) for (smi, perm, r) in raw if key(smi) not in cache]
    print(f"dataset={len(raw)} cached={len(cache)} todo={len(todo)} workers={N_WORKERS} "
          f"embed_threads={EMBED_THREADS} kconf={KCONF}", flush=True)

    # row metadata (static-proxy inputs) for anything we featurize this run
    meta = {key(smi): r for (smi, perm, r) in raw}
    perm_by = {key(smi): perm for (smi, perm, r) in raw}
    smi_by = {k: smi for (k, smi, _, _) in todo}

    # ---- parallel conformer-ensemble featurization (resumable: append to cache as results arrive) ----
    t0 = time.time(); added = 0
    with open(CACHE, "a") as cf, ProcessPoolExecutor(max_workers=N_WORKERS) as ex:
        futs = {ex.submit(_worker, (k, smi)): k for (k, smi, _, _) in todo}
        for fut in as_completed(futs):
            k, f = fut.result()
            if f is None:
                continue
            r = meta[k]
            rec = {"k": k, "smi": smi_by[k], "perm": perm_by[k], "ens": f,
                   "stat": [num(r.get("CHCl3_3DPSA")), num(r.get("H2O_3DPSA")),
                            num(r.get("H2O_3DPSA")) - num(r.get("CHCl3_3DPSA")), num(r.get("_3DPSA")), num(r.get("TPSA"))]}
            cf.write(json.dumps(rec) + "\n"); cf.flush(); cache[k] = rec; added += 1
            if added % 100 == 0:
                print(f"  +{added} (total {len(cache)}) {time.time()-t0:.0f}s", flush=True)
    print(f"featurized +{added}, total cached={len(cache)} ({time.time()-t0:.0f}s)", flush=True)

    # ---- CV only when enough cached ----
    if len(cache) < MIN_CV:
        print(f"ACCUMULATING: {len(cache)}/{MIN_CV} cached — re-run to continue; CV deferred.", flush=True)
        return

    recs = list(cache.values())
    y = np.array([d["perm"] for d in recs])
    mols = [Chem.MolFromSmiles(d["smi"]) for d in recs]
    X_ecfp = np.array([np.frombuffer(FP.GetFingerprint(m).ToBitString().encode(), 'u1') - 48 for m in mols], dtype=np.int8)
    X_stat = np.array([d["stat"] for d in recs], float)
    X_ens = np.array([d["ens"] for d in recs], float)

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
        X = dropdegen(X); oof = np.zeros(len(y))
        for k in range(5):
            te = fold == k; tr = ~te
            md = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=0)
            md.fit(X[tr], y[tr]); oof[te] = md.predict(X[te])
        return r2_score(y, oof), mean_absolute_error(y, oof), spearmanr(y, oof).correlation

    res = {}
    for name, X in [("ECFP (static baseline)", X_ecfp), ("static 3D-PSA proxy", X_stat),
                    ("ensemble-dynamics (ETKDG)", X_ens), ("ECFP + static-proxy", np.hstack([X_ecfp, X_stat])),
                    ("ECFP + ensemble", np.hstack([X_ecfp, X_ens])), ("ECFP + static + ensemble", np.hstack([X_ecfp, X_stat, X_ens]))]:
        r2, mae, sp = cv(X); res[name] = {"scaffold_r2": round(r2, 3), "mae": round(mae, 3), "spearman": round(sp, 3)}
        print(f"{name:34s} R2={r2:.3f} Spearman={sp:.3f}", flush=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"n": len(y), "n_scaffolds": len(g), "kconf": KCONF,
               "note": "RDKit ETKDGv3 gas-phase ensembles (CPU); NOT membrane MD; leak-free scaffold folds; same-subset; parallel+resumable+degen-guard",
               "ref_full8466": {"ECFP": 0.237, "ECFP+staticproxy": 0.301}, "results": res},
              open(OUT, "w"), indent=1)
    print(f"WROTE {OUT}", flush=True)


if __name__ == "__main__":
    main()
