"""[COMPOUND-DISJOINT COPY of 10_h4b_reveals.py for A10: only file names differ] H4b step 1 (PREREG A8): build and freeze the reveal sets BEFORE any scoring. Writes data/h4b_reveals_CD.csv.gz and data/h4b_eligible_CD.csv (target,k,eligible,...)."""
import os, hashlib, json, zlib
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; KS = [5, 10, 25]; SEEDS = range(5)
I = pd.read_csv(f"{DATA}/items_I_CD.csv.gz"); C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); I["flat"] = I.compound_id.map(C.flat_key)
rev = []; elig = []
for t, g in I.groupby("target_key", sort=True):
    pos = g[g.label == 1]; neg = g[g.label == 0]
    for k in KS:
        for s in SEEDS:
            rng = np.random.default_rng(zlib.crc32(f"{t}|{k}|{s}".encode()))
            npos = min(int(np.ceil(k / 2)), len(pos)); nneg = min(k // 2, len(neg)); npos = min(k - nneg, len(pos)) if nneg < k // 2 else npos
            rp = pos.sample(npos, random_state=int(rng.integers(1 << 30))) if npos else pos.iloc[:0]; rn = neg.sample(nneg, random_state=int(rng.integers(1 << 30))) if nneg else neg.iloc[:0]
            R = pd.concat([rp, rn]); flats = set(R.flat); rest = g[~g.compound_id.isin(R.compound_id) & ~g.flat.isin(flats)]
            ok = len(rest) >= 20 and rest.label.sum() >= 3 and (rest.label == 0).sum() >= 3
            elig.append(dict(target_key=t, k=k, seed=s, n_revealed=len(R), n_rev_pos=int(R.label.sum()), n_remaining=len(rest), n_rem_pos=int(rest.label.sum()), eligible=bool(ok)))
            rev += [(t, k, s, c, int(l)) for c, l in zip(R.compound_id, R.label)]
pd.DataFrame(rev, columns=["target_key", "k", "seed", "compound_id", "label"]).to_csv(f"{DATA}/h4b_reveals_CD.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
E = pd.DataFrame(elig); E.to_csv(f"{DATA}/h4b_eligible_CD.csv", index=False)
h = {"h4b_reveals_CD.csv.gz": hashlib.sha256(open(f"{DATA}/h4b_reveals_CD.csv.gz", "rb").read()).hexdigest(), "h4b_eligible_CD.csv": hashlib.sha256(open(f"{DATA}/h4b_eligible_CD.csv", "rb").read()).hexdigest(), "script": hashlib.sha256(open(__file__, "rb").read()).hexdigest()}
json.dump(h, open(f"{DATA}/FROZEN_HASHES_H4B_CD.json", "w"), indent=1)
T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family)); E["family"] = E.target_key.map(fam)
print(E[E.eligible].groupby("k").agg(targets=("target_key", "nunique"), families=("family", "nunique")).to_string()); print("targets total", I.target_key.nunique(), h)
