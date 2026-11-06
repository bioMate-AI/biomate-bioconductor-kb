"""Build analysis M2 (PREREG A5): cross-target decoys matched on the memorisation shortcuts.
Same pair labels / families / eligibility as M (A2). In addition to stratum, size, charge and ring bin, each decoy must have
  |B3(decoy) - B3(positive)| <= TOL_B3   where B3 = max Tanimoto (Morgan r2/2048, chirality) to positives of OTHER-family targets,
                                         excluding the item's own flat structure (exactly the B3 baseline of 03_run_arms.py), and
  |depth(decoy) - depth(positive)| <= TOL_DEPTH   where depth = number of OTHER targets with any labelled pair for the compound.
Tolerance policy (registered): TOL_B3 = 0.05, TOL_DEPTH = 1; if the resulting family-mean AUROC of B3_nn_neg or B4_depth_neg exceeds 0.55
(or falls below 0.45) the tolerance is tightened once to 0.02 / 0 and the tighter set is used. The choice is made on baselines only.
Writes data/items_M2.csv.gz, data/M2_build_log.json, data/FROZEN_HASHES_M2.json. No arm is scored here."""
import os, json, hashlib, sys
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; SEED = 20261029; N_DECOY = 20; MIN_DECOY = 10; K = 150
sys.path.insert(0, HERE); import harness as H
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv")
fam = dict(zip(T.target_key, T.family)); elig = T[T.eligible_M].target_key.tolist()
pos = P[P.label == "pos"]
posfams = pos.assign(f=pos.target_key.map(fam)).groupby("compound_id").f.apply(set).to_dict()
depth_sets = P.groupby("compound_id").target_key.apply(set).to_dict()
pool = np.array(sorted(posfams)); N = len(pool); pidx = {c: i for i, c in enumerate(pool)}
gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
X = np.stack([np.array(list(gen.GetFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"]))), np.uint8) for c in pool]).astype(np.float32); xs = X.sum(1)
flat = pd.factorize(C.loc[pool, "flat_key"])[0]
# global top-K neighbours among pool positives (excluding self index)
nbr = np.zeros((N, K), np.int32); nsim = np.zeros((N, K), np.float32)
for a in range(0, N, 1000):
    inter = X[a:a + 1000] @ X.T; S = inter / (xs[a:a + 1000, None] + xs[None, :] - inter + 1e-9)
    for r in range(S.shape[0]): S[r, a + r] = -2.0
    top = np.argpartition(-S, K, axis=1)[:, :K]; ts = np.take_along_axis(S, top, 1); o = np.argsort(-ts, 1)
    nbr[a:a + 1000] = np.take_along_axis(top, o, 1); nsim[a:a + 1000] = np.take_along_axis(ts, o, 1)
fams = sorted(set(fam[t] for t in elig))
fam_pos_mask = {F: np.array([F in posfams[c] for c in pool]) for F in fams}
b3 = {}; fallback = 0
for F in fams:
    bad = fam_pos_mask[F][nbr] | (flat[nbr] == flat[:, None])            # neighbour is a positive of this family, or the item's own flat structure
    valid = ~bad; first = valid.argmax(1); has = valid.any(1)
    v = np.where(has, nsim[np.arange(N), first], np.nan)
    for i in np.where(~has)[0]:                                          # exhausted top-K: exact fallback
        inter = X[i] @ X.T; S = inter / (xs[i] + xs - inter + 1e-9); m = (~fam_pos_mask[F]) & (flat != flat[i]); v[i] = S[m].max() if m.any() else 0.0; fallback += 1
    b3[F] = v
dep = lambda c, t: len(depth_sets.get(c, set()) - {t})
rng = np.random.default_rng(SEED)


def build(tol_b3, tol_dep):
    items = []; dropped = 0
    cinfo = C.loc[pool]; rb = lambda r: 0 if r <= 12 else 1 if r <= 20 else 2
    prb = np.array([rb(r) for r in cinfo.ring.values]); pst = cinfo.stratum.values; phv = cinfo.heavy.values; pch = cinfo.charge.values; pflat = cinfo.flat_key.values
    pdepth_all = np.array([len(depth_sets.get(c, set())) for c in pool])
    for t in elig:
        F = fam[t]; g = pos[pos.target_key == t].drop_duplicates("flat_key"); pos_flat = set(g.flat_key)
        bad = np.array([(F in posfams[c]) or (pflat[i] in pos_flat) for i, c in enumerate(pool)])
        own = np.array([t in depth_sets.get(c, set()) for c in pool]); pdep = pdepth_all - own          # depth excluding this target
        used = set(); rows = []
        for _, p in g.iterrows():
            i = pidx[p.compound_id]; bp = b3[F][i]
            if np.isnan(bp): dropped += 1; continue
            tol = max(3, int(round(0.10 * phv[i])))
            ok = (~bad) & (pst == pst[i]) & (np.abs(phv - phv[i]) <= tol) & (np.abs(pch - pch[i]) <= 1) & (prb == prb[i]) & (np.abs(np.nan_to_num(b3[F], nan=9) - bp) <= tol_b3) & (np.abs(pdep - pdep[i]) <= tol_dep)
            cand = [j for j in np.where(ok)[0] if j not in used]
            k = min(N_DECOY, len(cand))
            if k < MIN_DECOY: dropped += 1; continue
            pick = list(rng.choice(cand, k, replace=False)); used.update(pick)
            rows.append((t, p.compound_id, 1, "positive")); rows += [(t, pool[j], 0, f"cross_target_M2|matched_to:{p.compound_id}") for j in pick]
        if sum(r[2] for r in rows) >= 5: items += rows
    return pd.DataFrame(items, columns=["target_key", "compound_id", "label", "decoy_type"]), dropped


def baseline_gap(IT):
    out = {}
    fm = lambda col: None
    scores = {"B3_nn_neg": [], "B4_depth_neg": [], "B3_nn_pos": [], "B4_depth_pos": []}
    for t, g in IT.groupby("target_key", sort=True):
        F = fam[t]; ids = [pidx[c] for c in g.compound_id]; y = g.label.values
        s3 = b3[F][ids]; sd = np.array([dep(c, t) for c in g.compound_id], float)
        for k, v in (("B3_nn_neg", -s3), ("B3_nn_pos", s3), ("B4_depth_neg", -sd), ("B4_depth_pos", sd)):
            scores[k].append((F, H.tie_aware_auc(y, v)))
    for k, v in scores.items():
        d = pd.DataFrame(v, columns=["f", "auc"]).dropna(); out[k] = float(d.groupby("f").auc.mean().mean())
    return out


log = {"fallback_exact_b3": fallback, "pool": N}
for tol_b3, tol_dep in ((0.05, 1), (0.02, 0)):
    IT, dropped = build(tol_b3, tol_dep); gap = baseline_gap(IT)
    log[f"try_tol{tol_b3}_{tol_dep}"] = dict(baselines=gap, items=len(IT), positives=int(IT.label.sum()), targets=int(IT.target_key.nunique()), positives_dropped=dropped)
    ok = all(0.45 <= gap[k] <= 0.55 for k in gap)
    if ok or (tol_b3, tol_dep) == (0.02, 0): break
log["chosen_tol"] = [tol_b3, tol_dep]; log["baseline_gap_ok_within_0.45_0.55"] = bool(ok); log["baselines_chosen"] = gap
log["families"] = int(pd.Series([fam[t] for t in IT.target_key.unique()]).nunique())
IT.to_csv(f"{DATA}/items_M2.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
Hh = {"items_M2.csv.gz": hashlib.sha256(open(f"{DATA}/items_M2.csv.gz", "rb").read()).hexdigest(), "04_build_M2.py": hashlib.sha256(open(__file__, "rb").read()).hexdigest()}
json.dump(Hh, open(f"{DATA}/FROZEN_HASHES_M2.json", "w"), indent=1); json.dump(log, open(f"{DATA}/M2_build_log.json", "w"), indent=1)
print(json.dumps(log, indent=1)); print(Hh)
