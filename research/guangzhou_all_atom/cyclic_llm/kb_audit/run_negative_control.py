"""Shuffled-label negative control with counts: how many shuffles activate any rule, false-rule rate per rule on REAL features with shuffled labels, and
the held-out Spearman of the channel when rules are active (expected ~0)."""
import os, sys, json, time
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "stratification"))
import common as C, peptide_sar_kb as P
d = C.load_labelled(); pairs = pd.read_csv(os.path.join(HERE, "..", "stratification", "data", "mmp_pairs_pampa.csv.gz"))
vc = d.Source.value_counts(); elig = sorted(vc[vc >= P.MIN_SRC_N].index); d = d[d.Source.isin(elig)].copy(); pairs = pairs[pairs.source.isin(elig)].copy()
N = int(sys.argv[1]) if len(sys.argv) > 1 else 30; t0 = time.time(); rows = []; act = {k: 0 for k in list(P.PHYS) + [P.NME_LABEL, P.DFLIP_LABEL]}
for seed in range(N):
    rng = np.random.default_rng(seed); ds = d.copy(); pr = pairs.copy()
    for s in elig:                                   # ONE permutation per lab applied to the label, y and y_raw stay consistent
        m = (ds.Source == s).values; idx = rng.permutation(np.where(m)[0]); ds.loc[ds.index[m], "y_raw"] = ds.y_raw.values[idx]; ds.loc[ds.index[m], "y"] = ds.y.values[idx]
    ymap = ds.y_raw.to_dict(); zmap = ds.y.to_dict(); pr["y_a"] = pr.id_a.map(ymap); pr["y_b"] = pr.id_b.map(ymap); pr["z_a"] = pr.id_a.map(zmap); pr["z_b"] = pr.id_b.map(zmap)
    rs = P.fit(pr, ds, elig)
    for k, v in rs.rules.items(): act[k] += v["status"] == "rule"
    res, summ = P.lolo_evaluate(pr, ds, elig, B=10)   # note: lolo_evaluate re-mines per held-out lab on the ALREADY shuffled data (shuffle_labels=False)
    rows.append({k: summ.get(k, {}).get("median", np.nan) for k in ("K_phys", "K_nme", "K_total")})
    print(seed, round(time.time() - t0), rows[-1], flush=True)
r = pd.DataFrame(rows)
out = dict(n_shuffles=N, rule_active_counts_all_lab_fit=act, held_out_median_spearman={k: dict(mean=float(r[k].mean()), sd=float(r[k].std()), n_finite=int(r[k].notna().sum())) for k in r})
json.dump(out, open(os.path.join(HERE, "negative_control.json"), "w"), indent=1); print(json.dumps(out, indent=1))
