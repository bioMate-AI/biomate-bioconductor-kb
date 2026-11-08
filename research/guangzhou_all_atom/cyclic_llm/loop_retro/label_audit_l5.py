#!/usr/bin/env python3
"""Audit of the within-source label construction (PREREG_LOOP L3/L5). usage: label_audit_l5.py CycPeptMPDB.csv out.json
(1) hits per source after standardisation (is any source still dominant?); (2) transductive-leak sensitivity: the labels are standardised with each source's mean/sd over ALL peptides, including ones the loop has not yet
revealed. We re-estimate those statistics from a random 30 % of each source (what an online analyst could know) and measure how many hit labels change — an upper bound on what the all-label statistics could leak."""
import sys, json, os, collections
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_prior as K
recs = R.load(sys.argv[1]); y_raw = np.array([r["y"] for r in recs]); srcs = np.array([r["source"] for r in recs])
y = K.source_normalize(y_raw, srcs); thr = float(np.quantile(y, .9)); hit = y >= thr
cnt = collections.Counter(srcs.tolist()); grp = np.array([s if cnt[s] >= 20 else "__other__" for s in srcs.tolist()])
share = {g: int(hit[grp == g].sum()) for g in set(grp.tolist())}; tot = int(hit.sum())
top = sorted(share.items(), key=lambda kv: -kv[1])[:5]
out = dict(n=len(recs), n_hits=tot, threshold=round(thr, 3), n_groups=len(share), top_groups_hits=top, max_group_share=round(max(share.values()) / tot, 3),
           raw_pooled_top_source_share=None)
raw_thr = float(np.quantile(y_raw, .9)); rh = y_raw >= raw_thr; rs = {g: int(rh[grp == g].sum()) for g in set(grp.tolist())}; out["raw_pooled_max_group_share"] = round(max(rs.values()) / int(rh.sum()), 3)
rng = np.random.default_rng(0); flips = []; jac = []
for rep in range(50):
    ys = np.zeros(len(y))
    for g in set(grp.tolist()):
        m = np.where(grp == g)[0]; sub = rng.choice(m, max(5, int(0.3 * len(m))), replace=False); sd = y_raw[sub].std()
        ys[m] = (y_raw[m] - y_raw[sub].mean()) / (sd if sd > 0 else 1.0)
    h2 = ys >= float(np.quantile(ys, .9)); flips.append(int((h2 != hit).sum())); jac.append(float((h2 & hit).sum() / (h2 | hit).sum()))
out["stat_from_30pct_subsample"] = dict(mean_label_flips=round(float(np.mean(flips)), 1), of_n=len(recs), mean_hit_set_jaccard=round(float(np.mean(jac)), 3), min_jaccard=round(float(np.min(jac)), 3))
json.dump(out, open(sys.argv[2], "w"), indent=1); print(json.dumps(out, indent=1))
