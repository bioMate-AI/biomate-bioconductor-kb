#!/usr/bin/env python3
"""Verifier-quality check (amendment A2), run BEFORE any baseline tune/eval. EC2/Spark only.
For each fitted verifier: leave-one-source-out (LOSO) Spearman of its predictions against the within-source-z PAMPA labels, over the sources of ITS OWN fitting group
with >= 20 labelled peptides (fit on the group minus that source, predict that source). Also: the TRAIN verifier fitted on group A scored against each S and B source
(descriptive: cross-group skill), and the physics held-out (min polar SASA) vs measured z on a fixed sample of B peptides.
Pre-registered floors (A2, fixed before this ran): STOP and HELD-OUT permeability verifiers: mean LOSO Spearman >= 0.15 over >= 5 evaluable sources;
physics held-out: Spearman >= +0.10 on the fixed B sample. Below the floor => the verifier is declared 'too weak to rank' and its family contributes no
held-out/stop evidence (the gate needs both families, so the stage-1 outcome would be INCONCLUSIVE)."""
import json, os, sys, time
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
import verifiers_e as VE
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor

FLOOR_PERM, FLOOR_PHYS, MIN_SRC_EVAL = 0.15, 0.10, 5
ver = sys.argv[2] if len(sys.argv) > 2 else "v2"
out_path = sys.argv[1]
d = VE.load_labelled(VE.ANN_DEFAULT); groups = VE.source_groups(d, ver); d["g"] = d["Source"].map(groups)
X = {"A": VE.features(d["smiles"].tolist(), "A"), "S": VE.features(d["smiles"].tolist(), "S"), "bits": VE.features(d["smiles"].tolist(), "bits2048")}
y = d["z"].values
mk = {0: ("A", lambda: HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=0)),
      1: ("S", lambda: RandomForestRegressor(n_estimators=300, min_samples_leaf=2, n_jobs=-1, random_state=0)),
      2: ("bits", lambda: VE.TanimotoKRR(alpha=1.0))}
res = {"version": ver, "floors": dict(perm=FLOOR_PERM, phys=FLOOR_PHYS, min_sources=MIN_SRC_EVAL), "loso": {}, "cross": {}}
for g, (feat, factory) in mk.items():
    idx = np.where(d["g"].values == g)[0]; srcs = sorted(d.iloc[idx]["Source"].unique()); per = {}
    for s in srcs:
        te = idx[d.iloc[idx]["Source"].values == s]; tr = np.array([i for i in idx if i not in set(te)])
        if len(te) < 20 or len(tr) < 50:
            continue
        m = factory().fit(X[feat][tr], y[tr]); r = spearmanr(m.predict(X[feat][te]), y[te]).correlation
        per[s] = dict(n=int(len(te)), spearman=None if r != r else round(float(r), 4))
    vals = [v["spearman"] for v in per.values() if v["spearman"] is not None]
    res["loso"]["ASB"[g]] = dict(per_source=per, mean=round(float(np.mean(vals)), 4) if vals else None, median=round(float(np.median(vals)), 4) if vals else None,
                                 n_evaluable=len(vals), source_weighted_by_n=round(float(np.average(vals, weights=[v["n"] for v in per.values() if v["spearman"] is not None])), 4) if vals else None)
# cross-group skill of the TRAIN verifier (fit on A) on every S and B source
idxA = np.where(d["g"].values == 0)[0]; mA = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=0).fit(X["A"][idxA], y[idxA])
for g in (1, 2):
    idx = np.where(d["g"].values == g)[0]; per = {}
    for s in sorted(d.iloc[idx]["Source"].unique()):
        te = idx[d.iloc[idx]["Source"].values == s]
        if len(te) >= 20:
            r = spearmanr(mA.predict(X["A"][te]), y[te]).correlation; per[s] = dict(n=int(len(te)), spearman=None if r != r else round(float(r), 4))
    vals = [v["spearman"] for v in per.values() if v["spearman"] is not None]
    res["cross"]["train_A_on_" + "ASB"[g]] = dict(per_source=per, mean=round(float(np.mean(vals)), 4) if vals else None)
json.dump(res, open(out_path, "w"), indent=1)          # partial result (LOSO + cross) saved BEFORE the slow physics step
# physics held-out on a fixed B sample (parallel over all cores; per-molecule failures are skipped, counted)
rng = np.random.default_rng(2026); idxB = np.where(d["g"].values == 2)[0]; pick = rng.choice(idxB, size=min(120, len(idxB)), replace=False)
smi_pick = [d.iloc[i]["smiles"] for i in pick]


def _ps(smi):
    try:
        return VE.polar_sasa_min(smi, n_conf=4)
    except Exception:
        return None


t0 = time.time()
from multiprocessing import get_context
with get_context("fork").Pool(max(1, os.cpu_count() or 2)) as pool:
    vals = pool.map(_ps, smi_pick, chunksize=1)
ph = [-v for v in vals if v is not None]; vv = [pick[j] for j, v in enumerate(vals) if v is not None]
r = spearmanr(ph, y[vv]).correlation if len(ph) > 10 else float("nan")
res["physics_heldout"] = dict(n=len(ph), n_requested=len(smi_pick), spearman=None if r != r else round(float(r), 4), wall_s=round(time.time() - t0, 1))
# floors
f = {}
f["stop_S_perm"] = (res["loso"]["S"]["mean"] or -9) >= FLOOR_PERM and res["loso"]["S"]["n_evaluable"] >= MIN_SRC_EVAL
f["heldout_B_perm"] = (res["loso"]["B"]["mean"] or -9) >= FLOOR_PERM and res["loso"]["B"]["n_evaluable"] >= MIN_SRC_EVAL
f["heldout_physics"] = (res["physics_heldout"]["spearman"] or -9) >= FLOOR_PHYS
res["floor_met"] = f
json.dump(res, open(out_path, "w"), indent=1)
print(json.dumps({k: res[k] for k in ("floor_met", "physics_heldout")}, indent=1)); print({g: (v["mean"], v["n_evaluable"]) for g, v in res["loso"].items()})
