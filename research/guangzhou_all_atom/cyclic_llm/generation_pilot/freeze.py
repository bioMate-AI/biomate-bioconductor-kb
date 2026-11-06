#!/usr/bin/env python3
"""Freeze the DEV-tuned configurations (pre-registration section 5): best grid cell by DEV primary Y (mean over dev seeds 100-102). Controls inherit the config of the model they control.
usage: freeze.py DEV_DIR OUT.json a|b   (a = CPU generators, b = L-CHEMFM)"""
import sys, json, os
d, out, which = sys.argv[1], sys.argv[2], sys.argv[3]
names = ["S-EDIT", "S-LIB", "S-BRICS", "L-P0", "L-PCLM2"] if which == "a" else ["L-CHEMFM"]
cfg = {}; table = {}
for n in names:
    r = json.load(open(os.path.join(d, f"dev_{n}.json"))); p2 = os.path.join(d, f"dev2_{n}.json")
    if os.path.exists(p2): r2 = json.load(open(p2)); cfg[n] = r2["best"]; table[n] = r["grid"] + r2["ext_grid"]
    else: cfg[n] = r["best"]; table[n] = r["grid"]
if which == "a":
    cfg["C-COPY"] = {}; cfg["C-RANDINIT-P0"] = cfg["L-P0"]; cfg["C-RANDINIT-PCLM2"] = cfg["L-PCLM2"]; cfg["C-SHUF-PCLM2"] = cfg["L-PCLM2"]
cfg["_dev_grid"] = table
json.dump(cfg, open(out, "w"), indent=1, default=list); print(json.dumps({k: v for k, v in cfg.items() if k != "_dev_grid"}, default=list))
