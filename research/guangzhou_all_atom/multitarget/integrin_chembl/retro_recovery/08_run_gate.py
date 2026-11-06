"""Apply the validity gate (PREREG A7) to a set of analyses; writes results/validity_gate_<name>.json."""
import sys, json, os
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; sys.path.insert(0, HERE)
import validity_gate as G
prox = G.load_proxies(); T = pd.read_csv(f"{DATA}/targets.csv"); tfam = T[["target_key", "family", "genes"]]; fo = pd.read_csv(f"{DATA}/folds_v1.csv"); folds = dict(zip(fo.family, fo.fold))
out = {}
for name in sys.argv[1:]:
    items = pd.read_csv(f"{DATA}/items_{name}.csv.gz"); r = G.run_gate(items, tfam, prox, folds); out[name] = r
    json.dump(r, open(f"{HERE}/results/validity_gate_{name}.json", "w"), indent=1)
    print(f"\n=== {name}: VALID={r['VALID']}  failed={r['failed_controls']}")
    for k, v in r["primary"].items(): print("  PRIMARY", k, v if isinstance(v, str) else f"{v['point']:.3f} [{v['lo']:.3f},{v['hi']:.3f}] fam={v['n_families']}")
    print("  secondary (adj level %.4f):" % r["secondary_level"], {k: f"{v['point']:.2f}[{v['lo']:.2f},{v['hi']:.2f}]" for k, v in r["secondary"].items() if isinstance(v, dict)})
