"""Build analysis M3 (PREREG A7): M2 hard constraints + propensity-style matching on ALL no-target proxies incl. atom-LM typicality.
Candidates / positives are restricted to compounds with an atom-LM typicality score (the scorer fails on very large compounds: median 233 heavy atoms; max scored 169).
Hard constraints (as M2): stratum, ring bin, |B3 diff| <= 0.02, depth diff == 0, not a positive of the target's family, not the same flat structure.
Matching: z-score the matching proxies over the pool; for each positive take the (<= 20) nearest candidates by Euclidean distance with distance <= CALIPER; >= 10 required.
Caliper policy (registered, decided ONLY on the gate and baseline band, never on any arm): try 4.0, 3.0, 2.0, 1.5 (loosest first); accept the first whose
  (a) validity gate has no failed control (primary C1-C3 at 95 %, secondary Bonferroni) AND (b) B3_nn_neg and B4_depth_neg family-mean AUROC in [0.45, 0.55].
If none passes, M3 is reported as not achievable at this data size and the tightest attempt is saved for transparency (NOT used to judge arms)."""
import os, sys, json, hashlib
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; sys.path.insert(0, HERE)
import harness as H, validity_gate as G
SEED = 20261031; N_DECOY = 20; MIN_DECOY = 10; K = 150; CALIPERS = [4.0, 3.0, 2.0, 1.5]
MATCH = ["heavy", "charge", "n_arom", "tpsa", "logp", "hbd", "hba", "rotb", "fsp3", "ring", "n_rings", "n_frac", "o_frac", "has_s", "has_halogen", "ncaa_frac", "n_alpha", "in_corpus", "typicality"]
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv"); prox = G.load_proxies()
fam = dict(zip(T.target_key, T.family)); elig = T[T.eligible_M].target_key.tolist(); pos = P[P.label == "pos"]
posfams = pos.assign(f=pos.target_key.map(fam)).groupby("compound_id").f.apply(set).to_dict(); depth_sets = P.groupby("compound_id").target_key.apply(set).to_dict()
pool = np.array(sorted(posfams)); N = len(pool); pidx = {c: i for i, c in enumerate(pool)}
# ---- B3 (identical definition to 04_build_M2 / 03_run_arms)
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*"); gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
X = np.stack([np.array(list(gen.GetFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"]))), np.uint8) for c in pool]).astype(np.float32); xs = X.sum(1); flat = pd.factorize(C.loc[pool, "flat_key"])[0]
nbr = np.zeros((N, K), np.int32); nsim = np.zeros((N, K), np.float32)
for a in range(0, N, 1000):
    inter = X[a:a + 1000] @ X.T; S = inter / (xs[a:a + 1000, None] + xs[None, :] - inter + 1e-9)
    for r in range(S.shape[0]): S[r, a + r] = -2.0
    top = np.argpartition(-S, K, axis=1)[:, :K]; ts = np.take_along_axis(S, top, 1); o = np.argsort(-ts, 1); nbr[a:a + 1000] = np.take_along_axis(top, o, 1); nsim[a:a + 1000] = np.take_along_axis(ts, o, 1)
fams = sorted(set(fam[t] for t in elig)); fam_pos_mask = {F: np.array([F in posfams[c] for c in pool]) for F in fams}; b3 = {}
for F in fams:
    bad = fam_pos_mask[F][nbr] | (flat[nbr] == flat[:, None]); valid = ~bad; first = valid.argmax(1); has = valid.any(1); v = np.where(has, nsim[np.arange(N), first], np.nan)
    for i in np.where(~has)[0]:
        inter = X[i] @ X.T; S = inter / (xs[i] + xs - inter + 1e-9); m = (~fam_pos_mask[F]) & (flat != flat[i]); v[i] = S[m].max() if m.any() else 0.0
    b3[F] = v
dep = lambda c, t: len(depth_sets.get(c, set()) - {t})
# ---- matching space
Z = prox.loc[pool, MATCH].astype(float); has_typ = Z.typicality.notna().values; mu = Z[has_typ].mean(); sd = Z[has_typ].std().replace(0, 1.0); Zs = ((Z - mu) / sd).values
cinfo = C.loc[pool]; rb = lambda r: 0 if r <= 12 else 1 if r <= 20 else 2; prb = np.array([rb(r) for r in cinfo.ring.values]); pst = cinfo.stratum.values; pflat = cinfo.flat_key.values
pdepth_all = np.array([len(depth_sets.get(c, set())) for c in pool])
fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold)); tfam = T[["target_key", "family", "genes"]]
FPtab = None


def build(caliper):
    rng = np.random.default_rng(SEED); items = []; dropped = 0; dist_log = []
    for t in elig:
        F = fam[t]; g = pos[pos.target_key == t].drop_duplicates("flat_key"); pos_flat = set(g.flat_key)
        bad = np.array([(F in posfams[c]) or (pflat[i] in pos_flat) for i, c in enumerate(pool)]); own = np.array([t in depth_sets.get(c, set()) for c in pool]); pdep = pdepth_all - own
        used = set(); rows = []
        for _, p in g.iterrows():
            i = pidx[p.compound_id]
            if not has_typ[i] or np.isnan(b3[F][i]): dropped += 1; continue
            ok = has_typ & (~bad) & (pst == pst[i]) & (prb == prb[i]) & (np.abs(np.nan_to_num(b3[F], nan=9) - b3[F][i]) <= 0.02) & (pdep == pdep[i])
            cand = np.array([j for j in np.where(ok)[0] if j not in used])
            if len(cand) < MIN_DECOY: dropped += 1; continue
            d = np.linalg.norm(Zs[cand] - Zs[i], axis=1); o = np.argsort(d, kind="stable"); cand, d = cand[o], d[o]; keep = d <= caliper; cand, d = cand[keep][:N_DECOY], d[keep][:N_DECOY]
            if len(cand) < MIN_DECOY: dropped += 1; continue
            used.update(cand.tolist()); dist_log.append(float(d.mean())); rows.append((t, p.compound_id, 1, "positive")); rows += [(t, pool[j], 0, f"cross_target_M3|matched_to:{p.compound_id}") for j in cand]
        if sum(r[2] for r in rows) >= 5: items += rows
    return pd.DataFrame(items, columns=["target_key", "compound_id", "label", "decoy_type"]), dropped, (float(np.mean(dist_log)) if dist_log else None)


def b_gap(IT):
    sc = {"B3_nn_neg": [], "B4_depth_neg": []}
    for t, g in IT.groupby("target_key", sort=True):
        F = fam[t]; ids = [pidx[c] for c in g.compound_id]; y = g.label.values
        sc["B3_nn_neg"].append((F, H.tie_aware_auc(y, -b3[F][ids]))); sc["B4_depth_neg"].append((F, H.tie_aware_auc(y, -np.array([dep(c, t) for c in g.compound_id], float))))
    return {k: float(pd.DataFrame(v, columns=["f", "auc"]).dropna().groupby("f").auc.mean().mean()) for k, v in sc.items()}


log = {"pool": N, "pool_with_typicality": int(has_typ.sum()), "caliper_schedule": CALIPERS, "attempts": {}}; accepted = None
for cal in CALIPERS:
    IT, dropped, md = build(cal)
    if IT.empty: log["attempts"][str(cal)] = "no items"; continue
    gap = b_gap(IT); gate = G.run_gate(IT, tfam, prox, folds, FP=G.fp_table(IT.compound_id))
    band = all(0.45 <= v <= 0.55 for v in gap.values())
    log["attempts"][str(cal)] = dict(items=len(IT), positives=int(IT.label.sum()), targets=int(IT.target_key.nunique()), families=int(IT.target_key.map(fam).nunique()), positives_dropped=dropped, mean_match_distance=md, baseline_gap=gap, band_ok=band,
                                     gate_VALID=gate["VALID"], gate_failed=gate["failed_controls"], gate_primary={k: (v if isinstance(v, str) else [round(v["point"], 3), round(v["lo"], 3), round(v["hi"], 3)]) for k, v in gate["primary"].items()})
    print(cal, json.dumps(log["attempts"][str(cal)]), flush=True)
    last = (cal, IT, gate)
    if gate["VALID"] and band: accepted = (cal, IT, gate); break
best = max((v for v in [(float(k), v) for k, v in log["attempts"].items() if isinstance(v, dict)]), key=lambda kv: kv[1]["positives"])[0] if not accepted else None
if not accepted:                       # none valid: keep the most-powered attempt as a DIAGNOSTIC-WITH-CONTROLS set (A7 rule), never as a validated benchmark
    IT, _, _ = build(best); gate = G.run_gate(IT, tfam, prox, folds, FP=G.fp_table(IT.compound_id)); last = (best, IT, gate)
use = accepted or last
cal, IT, gate = use; log["accepted"] = bool(accepted); log["caliper_used"] = cal
IT.to_csv(f"{DATA}/items_M3.csv.gz" if accepted else f"{DATA}/items_M3_NOT_VALID_do_not_use.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
fn = "items_M3.csv.gz" if accepted else "items_M3_NOT_VALID_do_not_use.csv.gz"
Hh = {fn: hashlib.sha256(open(f"{DATA}/{fn}", "rb").read()).hexdigest(), "09_build_M3.py": hashlib.sha256(open(__file__, "rb").read()).hexdigest(), "proxies.csv.gz": hashlib.sha256(open(f"{DATA}/proxies.csv.gz", "rb").read()).hexdigest(),
      "typicality_atomlm.csv.gz": hashlib.sha256(open(f"{DATA}/typicality_atomlm.csv.gz", "rb").read()).hexdigest()}
json.dump(Hh, open(f"{DATA}/FROZEN_HASHES_M3.json", "w"), indent=1); json.dump(log, open(f"{DATA}/M3_build_log.json", "w"), indent=1)
json.dump(gate, open(f"{HERE}/results/validity_gate_M3.json", "w"), indent=1); print(json.dumps({k: v for k, v in log.items() if k != "attempts"}), Hh)
