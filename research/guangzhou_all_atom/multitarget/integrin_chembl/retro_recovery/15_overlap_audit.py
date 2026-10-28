"""Independent audit of compound overlap across targets / families / folds (PREREG A10). Pure pandas, no code shared with ext_check_gate.py or validity_gate.py.
Identity levels: compound_id (isomeric SMILES hash) and flat_key (stereo-free canonical SMILES). Scopes: the analysis's own items, and ALL labelled pairs (pair_labels, any label)."""
import os, json
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"
T = pd.read_csv(f"{DATA}/targets.csv"); fam = dict(zip(T.target_key, T.family)); fo = pd.read_csv(f"{DATA}/folds_v1.csv"); fold = dict(zip(fo.family, fo.fold))
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz")
tf = lambda t: fold[fam[t]]
P["fam"] = P.target_key.map(fam); P["fold"] = P.target_key.map(tf); P["flat"] = P.compound_id.map(C.flat_key)
out = {}
for name in ("I", "M2", "M"):
    it = pd.read_csv(f"{DATA}/items_{name}.csv.gz"); it["fam"] = it.target_key.map(fam); it["fold"] = it.target_key.map(tf); it["flat"] = it.compound_id.map(C.flat_key); r = {"rows": len(it), "targets": int(it.target_key.nunique())}
    for ident in ("compound_id", "flat"):
        g = it.groupby(ident); nt = g.target_key.nunique(); nf = g.fam.nunique(); nfo = g.fold.nunique()
        r[ident] = dict(distinct=int(it[ident].nunique()), in_gt1_target=int((nt > 1).sum()), in_gt1_family=int((nf > 1).sum()), in_gt1_fold=int((nfo > 1).sum()),
                        rows_with_item_in_other_fold=int(it[ident].isin(set()).sum()))
        other = it.groupby(ident).fold.apply(set)
        r[ident]["rows_with_same_identity_in_another_fold"] = int(sum(len(other[x] - {f}) > 0 for x, f in zip(it[ident], it.fold)))
        r[ident]["rows_frac"] = round(r[ident]["rows_with_same_identity_in_another_fold"] / len(it), 4)
        pf = P.groupby(ident).fold.apply(set)                                       # scope: ALL labelled pairs
        r[ident]["rows_with_same_identity_labelled_in_another_fold_ALLPAIRS"] = int(sum(len(pf[x] - {f}) > 0 for x, f in zip(it[ident], it.fold)))
        r[ident]["rows_frac_ALLPAIRS"] = round(r[ident]["rows_with_same_identity_labelled_in_another_fold_ALLPAIRS"] / len(it), 4)
        # positives only
        pos = it[it.label == 1]; r[ident]["positive_rows_in_another_fold_items"] = int(sum(len(other[x] - {f}) > 0 for x, f in zip(pos[ident], pos.fold))); r[ident]["positive_rows"] = len(pos)
    out[name] = r
json.dump(out, open(f"{HERE}/results/overlap_audit.json", "w"), indent=1)
for n, r in out.items(): print(n, json.dumps({k: v for k, v in r.items()}, indent=None)[:900])
