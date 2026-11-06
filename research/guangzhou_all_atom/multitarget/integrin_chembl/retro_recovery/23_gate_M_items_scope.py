"""Reproduce the external reviewer's M4 number: gate on M with training rows removed when their flat structure occurs among the held-out fold's ITEMS (items scope; A10 V-T-items). Output results/gate_A11_M_v1_Titems.json."""
import os, sys, json
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import validity_gate as G
prox = G.load_proxies(); T = pd.read_csv(f"{DATA}/targets.csv"); tfam = T[["target_key", "family", "genes"]]; fam = dict(zip(T.target_key, T.family)); fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold))
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); flat = C.flat_key; it = pd.read_csv(f"{DATA}/items_M.csv.gz"); d = it.assign(fold=it.target_key.map(lambda t: folds[fam[t]]))
ex = {f: set(d[d.fold == f].compound_id.map(flat)) for f in range(5)}
r = G.run_gate(it, tfam, prox, folds, FP=G.fp_table(it.compound_id), flat=flat, excl=ex); json.dump(r, open(f"{RES}/gate_A11_M_v1_Titems.json", "w"), indent=1, default=float)
print({k: (round(v["point"], 4), round(v["lo95"], 4), round(v["hi95"], 4), v["n_families"]) for k, v in r["primary"].items()}, r["status"])
