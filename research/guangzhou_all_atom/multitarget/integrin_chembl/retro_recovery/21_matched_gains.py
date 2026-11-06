"""A11 item 5: matched zero-shot-vs-k gains. From per-target H4b metrics (k = 0 PT on all items; k > 0 arms and PT on the SAME remaining items of the k-eligible targets).
(i) matched = arm(k) - PT(k) on the same targets/items; (ii) common-target set = targets eligible at every k in {5,10,25}; (iii) the old unmatched figure (arm(k) vs PT(k=0) over all targets), labelled as such."""
import os, sys, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import harness as H
out = {}
for tag, per, tgt, fn in (("v1_I", "h4b_per_target.csv", "targets.csv", None), ("v1_I_CD", "h4b_per_target_CD.csv", "targets.csv", None), ("v2folds_I", "h4b_per_target_v2.csv", "targets_v2.csv", None)):
    p = f"{RES}/{per}"
    if not os.path.exists(p): out[tag] = "per-target file not available yet"; continue
    D = pd.read_csv(p); tf = pd.read_csv(f"{DATA}/{tgt}")[["target_key", "family"]]; res = {}
    pt = {k: D[D.k == k].groupby(["arm", "target_key"]).auc.mean().reset_index() for k in (0, 5, 10, 25)}
    common = set(pt[5].target_key) & set(pt[10].target_key) & set(pt[25].target_key); res["common_targets"] = len(common)
    zs = pt[0][pt[0].arm == "PT"].set_index("target_key").auc
    for k in (5, 10, 25):
        d = pt[k]; fm = lambda a, ts=None: d[(d.arm == a) & (d.target_key.isin(ts if ts is not None else set(d.target_key)))].merge(tf, on="target_key").groupby("family").auc.mean()
        r = {}
        for a in ("NN", "FP-k", "PT+k"):
            r[a] = dict(matched=H.boot_diff(fm(a), fm("PT"), B=2000), common_set=H.boot_diff(fm(a, common), fm("PT", common), B=2000),
                        unmatched_vs_k0_all_targets=H.boot_diff(fm(a), zs.reset_index().merge(tf, on="target_key").groupby("family").auc.mean(), B=2000))
        r["targets_k"] = int(d.target_key.nunique()); r["PT_zero_shot_same_items"] = H.boot_mean(fm("PT"), B=2000); r["PT_k0_all_targets"] = H.boot_mean(zs.reset_index().merge(tf, on="target_key").groupby("family").auc.mean(), B=2000)
        res[str(k)] = r
    out[tag] = res
json.dump(out, open(f"{RES}/h4b_matched_gains.json", "w"), indent=1)
for tag, res in out.items():
    if isinstance(res, str): print(tag, res); continue
    print(tag, "common targets", res["common_targets"])
    for k in ("5", "10", "25"):
        for a in ("NN", "FP-k", "PT+k"):
            x = res[k][a]; print(f"  k={k} {a:5s} matched {x['matched']['point']:+.3f} [{x['matched']['lo']:+.3f},{x['matched']['hi']:+.3f}] | common-set {x['common_set']['point']:+.3f} [{x['common_set']['lo']:+.3f},{x['common_set']['hi']:+.3f}] | UNMATCHED(old) {x['unmatched_vs_k0_all_targets']['point']:+.3f}")
