"""A7 gate on the H4b remaining-item sets (seed 0 reveals), k in {5,10,25}: C1/C2/C3 + secondary on the items that arms are ranked on."""
import os, sys, json
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; sys.path.insert(0, HERE)
import validity_gate as G
prox = G.load_proxies(); T = pd.read_csv(f"{DATA}/targets.csv"); tfam = T[["target_key", "family", "genes"]]; fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold))
I = pd.read_csv(f"{DATA}/items_I.csv.gz"); C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); R = pd.read_csv(f"{DATA}/h4b_reveals.csv.gz"); E = pd.read_csv(f"{DATA}/h4b_eligible.csv"); out = {}
for k in (5, 10, 25):
    parts = []
    for t, g in I.groupby("target_key"):
        e = E[(E.target_key == t) & (E.k == k) & (E.seed == 0)]
        if not len(e) or not e.eligible.iloc[0]: continue
        rv = R[(R.target_key == t) & (R.k == k) & (R.seed == 0)]; fl = set(rv.compound_id.map(C.flat_key)); parts.append(g[~g.compound_id.isin(rv.compound_id) & ~g.compound_id.map(C.flat_key).isin(fl)])
    it = pd.concat(parts); r = G.run_gate(it, tfam, prox, folds, FP=G.fp_table(it.compound_id)); out[str(k)] = r
    print("k", k, "targets", it.target_key.nunique(), "VALID", r["VALID"], "failed", r["failed_controls"], {a: (v if isinstance(v, str) else [round(v["point"], 3), round(v["lo"], 3), round(v["hi"], 3)]) for a, v in r["primary"].items()}, flush=True)
json.dump(out, open(f"{HERE}/results/validity_gate_h4b.json", "w"), indent=1)
