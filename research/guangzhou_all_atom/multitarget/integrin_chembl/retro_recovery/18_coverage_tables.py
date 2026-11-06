"""Machine-readable coverage tables for the primary analyses (PREREG A10; requested by the manuscript writer). Writes results/coverage_*.csv + coverage_tables.json. Pure pandas + validity_gate's own eligibility logic."""
import os, sys, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import validity_gate as G
T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family)); fo = pd.read_csv(f"{DATA}/folds_v1.csv"); fold = dict(zip(fo.family, fo.fold)); prox = G.load_proxies()
sets = {"I": pd.read_csv(f"{DATA}/items_I.csv.gz"), "I_CD": pd.read_csv(f"{DATA}/items_I_CD.csv.gz"), "M2": pd.read_csv(f"{DATA}/items_M2.csv.gz")}
for k, d in sets.items(): d["family"] = d.target_key.map(fam); d["fold"] = d.family.map(fold)
# (1) per-fold and target->family map ------------------------------------------------------------------------------------------------
rows = []
for name, d in sets.items():
    for f, x in d.groupby("fold"):
        rows.append(dict(analysis=name, fold=int(f), families=int(x.family.nunique()), targets=int(x.target_key.nunique()), positives=int(x.label.sum()), inactives_or_decoys=int((x.label == 0).sum()), items=int(len(x))))
    rows.append(dict(analysis=name, fold="ALL", families=int(d.family.nunique()), targets=int(d.target_key.nunique()), positives=int(d.label.sum()), inactives_or_decoys=int((d.label == 0).sum()), items=int(len(d))))
pd.DataFrame(rows).to_csv(f"{RES}/coverage_per_fold.csv", index=False)
tm = T[["target_key", "genes", "family", "pfam", "n_pos_flat", "n_inactive_flat", "eligible_M", "eligible_I"]].copy(); tm["fold"] = tm.family.map(fold)
for name, d in sets.items():
    g = d.groupby("target_key"); tm[f"{name}_positives"] = tm.target_key.map(g.label.sum()).fillna(0).astype(int); tm[f"{name}_negatives"] = tm.target_key.map(g.label.apply(lambda s: int((s == 0).sum()))).fillna(0).astype(int)
tm.to_csv(f"{RES}/target_family_fold_map.csv", index=False)
# (2) per-family coverage of the no-target controls ---------------------------------------------------------------------------------
MULTI = G.MULTI; okp = prox[MULTI].astype(float).notna().all(axis=1); typ = prox.typicality.notna(); rows = []
for name, d in sets.items():
    # folds actually evaluated by the leave-fold-out controls (>= 50 training rows with both classes)
    ev = {int(f): (d[d.fold != f].label.nunique() == 2 and len(d[d.fold != f]) >= 50) for f in sorted(d.fold.unique())}
    d = d.assign(c1_ok=d.compound_id.map(typ).fillna(False), c2_ok=d.compound_id.map(okp).fillna(False) & d.fold.map(ev), c3_ok=d.fold.map(ev))
    for fm, x in d.groupby("family"):
        both = lambda y: int(y.groupby("target_key").label.nunique().eq(2).sum())
        rows.append(dict(analysis=name, family=fm, fold=int(x.fold.iloc[0]), targets=int(x.target_key.nunique()), items=int(len(x)), positives=int(x.label.sum()),
                         C1_items_used=int(x.c1_ok.sum()), C1_frac=round(float(x.c1_ok.mean()), 4), C1_targets_both_classes=both(x[x.c1_ok]),
                         C2_items_used=int(x.c2_ok.sum()), C2_frac=round(float(x.c2_ok.mean()), 4), C2_targets_both_classes=both(x[x.c2_ok]),
                         C3_items_used=int(x.c3_ok.sum()), C3_frac=round(float(x.c3_ok.mean()), 4), C3_targets_both_classes=both(x[x.c3_ok])))
pd.DataFrame(rows).to_csv(f"{RES}/coverage_controls_per_family.csv", index=False)
# (3) positives per regime / seed (H4b) ----------------------------------------------------------------------------------------------
out = {}
for suf, name in (("", "I"), ("_CD", "I_CD")):
    E = pd.read_csv(f"{DATA}/h4b_eligible{suf}.csv"); E["family"] = E.target_key.map(fam)
    g = E[E.eligible].groupby(["k", "seed"]).agg(targets=("target_key", "nunique"), families=("family", "nunique"), revealed_total=("n_revealed", "sum"), revealed_positives=("n_rev_pos", "sum"),
                                                    remaining_items=("n_remaining", "sum"), remaining_positives=("n_rem_pos", "sum")).reset_index(); g.insert(0, "analysis", name); out[name] = g
    z = sets[name]; out[name + "_zero_shot"] = dict(k=0, targets=int(z.target_key.nunique()), families=int(z.family.nunique()), positives=int(z.label.sum()), items=int(len(z)))
pd.concat([out["I"], out["I_CD"]]).to_csv(f"{RES}/coverage_h4b_per_k_seed.csv", index=False)
json.dump({"zero_shot": {k: v for k, v in out.items() if k.endswith("zero_shot")}, "note": "tables: coverage_per_fold.csv, target_family_fold_map.csv, coverage_controls_per_family.csv, coverage_h4b_per_k_seed.csv; regime for analyses I/M2 = single frozen list (no seeds); seeds apply to H4b reveal sets (5 seeds)"}, open(f"{RES}/coverage_tables.json", "w"), indent=1)
print(pd.read_csv(f"{RES}/coverage_per_fold.csv").to_string(index=False)); print(pd.read_csv(f"{RES}/coverage_h4b_per_k_seed.csv").groupby(["analysis", "k"]).mean(numeric_only=True).round(1).to_string())
c = pd.read_csv(f"{RES}/coverage_controls_per_family.csv"); print(c.groupby("analysis")[["C1_frac", "C2_frac", "C3_frac"]].agg(["min", "mean"]).round(3).to_string())
