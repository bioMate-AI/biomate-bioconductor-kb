"""Fit the all-lab ruleset, run the leave-one-lab-out test of the rules and the shuffled-label negative control on CycPeptMPDB (workstream 4's
annotation + pair tables, read-only). Writes peptide_sar_rules_v1.json, lolo_per_lab.csv, lolo_summary.json, rulesets_lolo/<lab>.json."""
import os, sys, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "stratification"))
import common as C, peptide_sar_kb as P
d = C.load_labelled(); pairs = pd.read_csv(os.path.join(HERE, "..", "stratification", "data", "mmp_pairs_pampa.csv.gz"))
vc = d.Source.value_counts(); elig = sorted(vc[vc >= P.MIN_SRC_N].index)
d = d[d.Source.isin(elig)].copy(); pairs = pairs[pairs.source.isin(elig)].copy()
print("eligible labs", len(elig), "peptides", len(d), "pairs", len(pairs))
rs = P.fit(pairs, d, elig); rs.to_json(os.path.join(HERE, "peptide_sar_rules_v1.json"))
for k, v in rs.rules.items():
    print("%-34s %-24s %s" % (k, v["status"], {x: (round(v[x], 3) if isinstance(v[x], float) else v[x]) for x in ("weight", "ci", "effect_z", "ci_z", "frac_sources_same_sign", "validity_score", "n_sources", "n_pairs", "agrees_with_kb") if x in v}))
os.makedirs(os.path.join(HERE, "rulesets_lolo"), exist_ok=True)
for L in elig:
    P.fit(pairs, d, [s for s in elig if s != L]).to_json(os.path.join(HERE, "rulesets_lolo", "heldout_%s.json" % L))
res, summ = P.lolo_evaluate(pairs, d, elig); res.to_csv(os.path.join(HERE, "lolo_per_lab.csv"), index=False)
neg = []
for seed in range(10):
    _, s = P.lolo_evaluate(pairs, d, elig, shuffle_labels=True, seed=seed, B=200); neg.append({k: v["median"] for k, v in s.items()})
negdf = pd.DataFrame(neg); out = dict(heldout=summ, shuffled_negative_control_median_of_lab_medians=negdf.describe().loc[["mean", "std", "min", "max"]].to_dict(),
                                      n_labs=len(elig), labs=elig)
json.dump(out, open(os.path.join(HERE, "lolo_summary.json"), "w"), indent=1, default=float)
print("LOLO held-out (median within-lab Spearman across labs, 95% source-bootstrap CI):")
for k, v in summ.items(): print("  %-8s median %.3f CI [%.3f, %.3f]  labs>0: %d/%d" % (k, v["median"], v["ci95"][0], v["ci95"][1], v["n_pos"], v["n_labs"]))
print("shuffled-label negative control (10 shuffles):"); print(negdf.describe().loc[["mean", "std", "min", "max"]].round(3).to_string())
print(res.round(3).to_string(index=False))
