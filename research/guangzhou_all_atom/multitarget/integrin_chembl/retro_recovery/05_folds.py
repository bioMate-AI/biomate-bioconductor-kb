"""Deterministic 5-fold FAMILY-grouped assignment for model training/evaluation (PREREG A6).
Unit = frozen family (A2: Pfam-Jaccard>=0.67 components). Weight = number of DISTINCT compounds with a labelled (pos/inactive) pair on any target of the family.
Longest-processing-time bin-packing: families sorted by (-weight, family_id), each assigned to the currently lightest fold (ties -> lowest fold index).
No randomness. Writes data/folds_v1.csv and data/folds_v1.json (stats + sha256)."""
import os, json, hashlib
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; K = 5
P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family))
P["family"] = P.target_key.map(fam)
w = P.groupby("family").compound_id.nunique(); nt = T.groupby("family").size()
order = sorted(w.index, key=lambda f: (-w[f], f)); load = [0] * K; assign = {}
for f in order:
    k = min(range(K), key=lambda i: (load[i], i)); assign[f] = k; load[k] += int(w[f])
F = pd.DataFrame(dict(family=order, fold=[assign[f] for f in order], n_targets=[int(nt[f]) for f in order], n_compounds=[int(w[f]) for f in order]))
F.to_csv(f"{DATA}/folds_v1.csv", index=False)
T["fold"] = T.family.map(assign); stats = dict(fold_compounds_assigned=load, fold_targets=T.groupby("fold").size().to_dict(), fold_families=F.groupby("fold").size().to_dict(),
                                              largest_family=dict(family=order[0], n_targets=int(nt[order[0]]), n_compounds=int(w[order[0]]), fold=assign[order[0]], share_of_all_compound_pairs=round(float(w[order[0]] / w.sum()), 3)))
for name in ("I", "M2", "M"):
    it = pd.read_csv(f"{DATA}/items_{name}.csv.gz"); it["fold"] = it.target_key.map(fam).map(assign)
    stats[f"items_{name}"] = dict(positives_per_fold=it[it.label == 1].groupby("fold").size().reindex(range(K), fill_value=0).to_dict(), items_per_fold=it.groupby("fold").size().reindex(range(K), fill_value=0).to_dict(),
                                  families_per_fold=it.assign(f=it.target_key.map(fam)).groupby("fold").f.nunique().reindex(range(K), fill_value=0).to_dict(), targets_per_fold=it.groupby("fold").target_key.nunique().reindex(range(K), fill_value=0).to_dict())
h = hashlib.sha256(open(f"{DATA}/folds_v1.csv", "rb").read()).hexdigest(); stats["folds_v1.csv_sha256"] = h; stats["script_sha256"] = hashlib.sha256(open(__file__, "rb").read()).hexdigest()
json.dump(stats, open(f"{DATA}/folds_v1.json", "w"), indent=1); print(json.dumps(stats, indent=1))
