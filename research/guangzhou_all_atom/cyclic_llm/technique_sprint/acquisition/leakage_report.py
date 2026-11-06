#!/usr/bin/env python3
"""Pool-vs-initial-set leakage per regime (review finding 3; amendment A2). usage: leakage_report.py CSV OUT.json [--cache P] [--seeds 10]
Reports, per regime, the mean over seeds of: fraction of pool peptides with NN Tanimoto >= 0.9 / >= 0.8 to the initial set, median NN, same flat structure, same scaffold, pool size;
for regime L also the number of held-out labs per seed and their share of peptides, and the held-out-vs-all-training-lab NN statistics."""
import os, sys, json, collections
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import acq as A

if __name__ == "__main__":
    csv, out = sys.argv[1], sys.argv[2]; cache = sys.argv[sys.argv.index("--cache") + 1] if "--cache" in sys.argv else None; ns = int(sys.argv[sys.argv.index("--seeds") + 1]) if "--seeds" in sys.argv else 10
    D = A.prepare(csv, cache); rep = {}
    for g in ("A", "B", "B2", "C", "C2", "L"):
        rows = [A.leakage_stats(g, s, D) for s in range(ns)]; rep[g] = {k: float(np.mean([r[k] for r in rows])) for k in rows[0] if k not in ("regime", "seed")}; rep[g]["seeds"] = ns
        if g == "L":
            held = [A.setup_L(s, D["srcs"], 100)[3] for s in range(ns)]; tests = [A.setup_L(s, D["srcs"], 100)[2] for s in range(ns)]
            rep[g]["n_heldout_labs_per_seed"] = [len(h) for h in held]; rep[g]["heldout_share_of_peptides"] = [len(t) / len(D["srcs"]) for t in tests]
            nn = []
            for s in range(ns):
                init, pool, test = A.setup_L(s, D["srcs"], 100)[:3]; tr = np.array(pool + init); te = np.array(test)[:1500]
                inter = D["B"][te] @ D["B"][tr].T; union = D["Bn"][te][:, None] + D["Bn"][tr][None, :] - inter; nn.append((inter / np.maximum(union, 1.0)).max(1))
            nn = np.concatenate(nn); rep[g]["heldout_vs_training_labs"] = dict(nn_ge_0p9=float((nn >= .9).mean()), nn_ge_0p8=float((nn >= .8).mean()), median_nn=float(np.median(nn)))
        print(g, json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in rep[g].items()}), flush=True)
    json.dump(rep, open(out, "w"), indent=1)
