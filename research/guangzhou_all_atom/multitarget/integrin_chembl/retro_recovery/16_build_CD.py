"""Build the strict compound-disjoint list items_I_CD (PREREG A10 V-S) and the per-fold coverage tables. No scorer is run.
Rule: drop rows of items_I whose flat (stereo-free) structure is labelled (any label) on a target belonging to a DIFFERENT fold; keep targets with >= 5 positives and >= 20 inactives (A2 rule)."""
import os, json, hashlib
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"
T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family)); fo = pd.read_csv(f"{DATA}/folds_v1.csv"); fold = dict(zip(fo.family, fo.fold))
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); P["fold"] = P.target_key.map(lambda t: fold[fam[t]]); P["flat"] = P.compound_id.map(C.flat_key)
foldsets = P.groupby("flat").fold.apply(set)
I = pd.read_csv(f"{DATA}/items_I.csv.gz"); I["fold"] = I.target_key.map(lambda t: fold[fam[t]]); I["flat"] = I.compound_id.map(C.flat_key)
other = [len(foldsets[x] - {f}) > 0 for x, f in zip(I.flat, I.fold)]; keep = I[~pd.Series(other, index=I.index)]
cnt = keep.groupby("target_key").label.agg(pos="sum", n="count"); cnt["neg"] = cnt.n - cnt.pos; ok = cnt[(cnt.pos >= 5) & (cnt.neg >= 20)].index
CD = keep[keep.target_key.isin(ok)].drop(columns=["fold", "flat"]).reset_index(drop=True)
CD.to_csv(f"{DATA}/items_I_CD.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
h = {"items_I_CD.csv.gz": hashlib.sha256(open(f"{DATA}/items_I_CD.csv.gz", "rb").read()).hexdigest(), "16_build_CD.py": hashlib.sha256(open(__file__, "rb").read()).hexdigest()}
json.dump(h, open(f"{DATA}/FROZEN_HASHES_CD.json", "w"), indent=1)
def cov(df):
    d = df.assign(fold=df.target_key.map(lambda t: fold[fam[t]]), family=df.target_key.map(fam)); g = d.groupby("fold")
    return {int(f): dict(families=int(x.family.nunique()), targets=int(x.target_key.nunique()), positives=int(x.label.sum()), items=int(len(x))) for f, x in g}
M2 = pd.read_csv(f"{DATA}/items_M2.csv.gz")
out = dict(I_original=cov(I.drop(columns=["fold", "flat"])), I_CD=cov(CD), M2_original=cov(M2), rows_removed=int(sum(other)), rows_removed_frac=round(sum(other) / len(I), 4),
           targets_dropped_after_removal=sorted(set(I.target_key) - set(ok)), targets_original=int(I.target_key.nunique()), targets_CD=int(CD.target_key.nunique()), families_CD=int(CD.target_key.map(fam).nunique()),
           positives_original=int(I.label.sum()), positives_CD=int(CD.label.sum()), hashes=h)
json.dump(out, open(f"{HERE}/results/coverage_primary.json", "w"), indent=1)
print(json.dumps({k: v for k, v in out.items() if k not in ("I_original", "I_CD", "M2_original")}, indent=1)); print("per fold  [original -> CD] families/targets/positives/items")
for f in range(5): print(f, out["I_original"].get(f), "->", out["I_CD"].get(f), "| M2:", out["M2_original"].get(f))
