#!/usr/bin/env python3
"""A3 replacement test, evaluation part. usage: bw_eval.py IN.jsonl OUT.json [4D.csv]. Rule fixed in A3.2 (committed before the run):
PASS = pooled Spearman(-bw_psa, z) >= +0.10 AND 95% source-cluster bootstrap lower bound > 0 (2000 resamples over B sources);
evaluable only if >= 600 peptides covering >= 7 of the 9 B sources, else VOID. Also reports per-source Spearman, min-PSA score, and the 4D reference."""
import json, sys
import numpy as np
from scipy.stats import spearmanr
rows = [json.loads(l) for l in open(sys.argv[1])]
ok = [r for r in rows if not r.get("failed") and r.get("bw_psa") is not None]
srcs = sorted({r["source"] for r in ok}); out = {"n_written": len(rows), "n_ok": len(ok), "n_failed": sum(1 for r in rows if r.get("failed")), "n_sources": len(srcs)}
evaluable = len(ok) >= 600 and len(srcs) >= 7
out["evaluable"] = bool(evaluable)
if ok:
    x = np.array([-r["bw_psa"] for r in ok]); xm = np.array([-r["min_psa"] for r in ok]); z = np.array([r["z"] for r in ok]); s = np.array([r["source"] for r in ok])
    out["spearman_bw"] = round(float(spearmanr(x, z).correlation), 4); out["spearman_min_psa"] = round(float(spearmanr(xm, z).correlation), 4)
    out["per_source"] = {u: dict(n=int((s == u).sum()), bw=round(float(spearmanr(x[s == u], z[s == u]).correlation), 4) if (s == u).sum() > 5 else None) for u in srcs}
    rng = np.random.default_rng(31); bs = []
    for _ in range(2000):
        pick = rng.choice(srcs, size=len(srcs), replace=True); idx = np.concatenate([np.where(s == u)[0] for u in pick])
        if len(idx) > 10:
            bs.append(spearmanr(x[idx], z[idx]).correlation)
    out["ci95_cluster_boot"] = [round(float(np.percentile(bs, 2.5)), 4), round(float(np.percentile(bs, 97.5)), 4)]
    out["median_neff"] = round(float(np.median([r["neff"] for r in ok])), 2)
    out["verdict"] = "VOID" if not evaluable else ("PASS" if (out["spearman_bw"] >= 0.10 and out["ci95_cluster_boot"][0] > 0) else "FAIL")
else:
    out["verdict"] = "VOID"
if len(sys.argv) > 3:
    try:
        import pandas as pd
        f4 = pd.read_csv(sys.argv[3])
        f4["CycPeptMPDB_ID"] = f4["CycPeptMPDB_ID"].astype(str); f4 = f4.set_index("CycPeptMPDB_ID")
        have = [r for r in ok if r["cid"] in f4.index]
        ref = {"n_joined": len(have)}
        if len(have) > 20:
            zz = np.array([r["z"] for r in have]); idx = [r["cid"] for r in have]
            for name, ser in (("Water_3D_PSA", f4.loc[idx, "Water_3D_PSA"]), ("Hexane_3D_PSA", f4.loc[idx, "Hexane_3D_PSA"]), ("dPSA_water_minus_hexane", f4.loc[idx, "Water_3D_PSA"] - f4.loc[idx, "Hexane_3D_PSA"])):
                v = ser.astype(float).values; m = np.isfinite(v)
                ref[name + "_neg_spearman_vs_z"] = round(float(spearmanr(-v[m], zz[m]).correlation), 4)
        out["ref_4D_reference_only"] = ref
    except Exception as e:
        out["ref_4D_reference_only"] = f"not computed: {type(e).__name__}: {e}"
json.dump(out, open(sys.argv[2], "w"), indent=1); print(json.dumps({k: v for k, v in out.items() if k != "per_source"}, indent=1))
