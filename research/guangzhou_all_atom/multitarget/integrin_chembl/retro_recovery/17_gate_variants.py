"""A10: gate on compound-disjoint variants; differences vs the registered numbers (results/validity_gate_{I,M2}.json are NOT overwritten).
V-T-items : committee variant, training rows sharing a flat structure with the held-out fold's ITEMS removed.
V-T-all   : training rows sharing a flat structure with ANY labelled pair of the held-out fold removed (registered scope).
V-S       : strict list items_I_CD (+V-T-all exclusion, which is then a no-op for items)."""
import os, sys, json
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; sys.path.insert(0, HERE)
import validity_gate as G
prox = G.load_proxies(); T = pd.read_csv(f"{DATA}/targets.csv"); tfam = T[["target_key", "family", "genes"]]; fam = dict(zip(T.target_key, T.family)); fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold))
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); flat = C.flat_key; P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); P["fold"] = P.target_key.map(lambda t: folds[fam[t]])
excl_all = {f: set(P[P.fold == f].compound_id.map(flat)) for f in range(5)}
def excl_items(it): d = it.assign(fold=it.target_key.map(lambda t: folds[fam[t]])); return {f: set(d[d.fold == f].compound_id.map(flat)) for f in range(5)}
out = {}
def fmt(r): return {k: (v if isinstance(v, str) else [round(v["point"], 4), round(v["lo"], 4), round(v["hi"], 4), v["n_families"]]) for k, v in r["primary"].items()}
for name, variants in (("I", ["V-T-items", "V-T-all", "V-S"]), ("M2", ["V-T-items", "V-T-all"])):
    base = pd.read_csv(f"{DATA}/items_{name}.csv.gz"); reg = json.load(open(f"{HERE}/results/validity_gate_{name}.json")); out[name] = {"registered": fmt(reg), "registered_failed": reg["failed_controls"]}
    for v in variants:
        it = pd.read_csv(f"{DATA}/items_I_CD.csv.gz") if v == "V-S" else base
        ex = excl_items(it) if v == "V-T-items" else excl_all
        r = G.run_gate(it, tfam, prox, folds, FP=G.fp_table(it.compound_id), flat=flat, excl=ex); out[name][v] = dict(primary=fmt(r), VALID=r["VALID"], failed=r["failed_controls"], n_targets=int(it.target_key.nunique()), secondary_failed=[k for k in r["failed_controls"] if k.startswith("secondary")])
        print(name, v, json.dumps(out[name][v]), flush=True)
json.dump(out, open(f"{HERE}/results/gate_variants_A10.json", "w"), indent=1)
