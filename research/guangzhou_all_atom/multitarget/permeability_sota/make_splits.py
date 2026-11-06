"""Step 2: deterministic split assignment (no labels used). Writes data/folds.csv with columns:
 s0_seed0..4 in {train,val,test}; s1_fold, s2_fold in 0..4; s2_cluster; s3_fold (source index for the 8 largest sources else -1)."""
import numpy as np, pandas as pd, json
from common import *

c = pd.read_csv(CLEAN)
N = len(c)
f = pd.DataFrame({"row": np.arange(N)})
# S0: random 80/10/10 row-level (as the published papers: row-level, duplicates NOT grouped), 5 seeds
for s in range(5):
    rng = np.random.default_rng(1000 + s); perm = rng.permutation(N)
    lab = np.empty(N, object); lab[perm[: int(.8 * N)]] = "train"; lab[perm[int(.8 * N): int(.9 * N)]] = "val"; lab[perm[int(.9 * N):]] = "test"
    f[f"s0_seed{s}"] = lab

def balanced_group_folds(groups, k=5, seed=0):
    ug, cnt = np.unique(groups, return_counts=True)
    rng = np.random.default_rng(seed); order = np.lexsort((rng.random(len(ug)), -cnt))   # big first, ties random
    load = np.zeros(k); asg = {}
    for i in order:
        j = int(np.argmin(load)); asg[ug[i]] = j; load[j] += cnt[i]
    return np.array([asg[g] for g in groups]), load

# S1: generic Bemis-Murcko scaffold groups
f["s1_fold"], l1 = balanced_group_folds(c.scaf.values, 5, 11)

# S2: monomer-composition clusters. Jaccard on the SET of distinct monomers; Butina-style leader clustering,
# distance cutoff 0.5 (similarity >= 0.5), deterministic (largest-neighbourhood first).
vocab = sorted(set(m for s in c.monomers for m in s.split("|")))
vi = {m: i for i, m in enumerate(vocab)}
X = np.zeros((N, len(vocab)), np.float32)
for r, s in enumerate(c.monomers):
    for m in set(s.split("|")): X[r, vi[m]] = 1
inter = X @ X.T; sz = X.sum(1); union = sz[:, None] + sz[None, :] - inter
sim = inter / union
nbr = sim >= 0.5
cl = -np.ones(N, int); unassigned = np.ones(N, bool); cid = 0
deg = nbr.sum(1)
while unassigned.any():
    cand = np.where(unassigned)[0]
    ctr = cand[np.argmax((nbr[cand][:, unassigned]).sum(1))]
    mem = np.where(nbr[ctr] & unassigned)[0]
    cl[mem] = cid; unassigned[mem] = False; cid += 1
f["s2_cluster"] = cl
f["s2_fold"], l2 = balanced_group_folds(cl, 5, 22)

# S3: leave-one-source-out for sources with >=100 clean rows
vc = c.source.value_counts(); big = list(vc[vc >= 100].index)
f["s3_fold"] = c.source.map({s: i for i, s in enumerate(big)}).fillna(-1).astype(int)
f.to_csv(FOLDS, index=False)
info = {"s1_fold_sizes": l1.tolist(), "s2_fold_sizes": l2.tolist(), "n_s2_clusters": int(cid),
        "s2_largest_clusters": sorted(np.bincount(cl).tolist(), reverse=True)[:8], "s3_sources": {str(i): [s, int(vc[s])] for i, s in enumerate(big)},
        "s3_rows_covered": int((f.s3_fold >= 0).sum())}
json.dump(info, open(os.path.join(HERE, "results/split_info.json"), "w"), indent=1); print(json.dumps(info, indent=1))
