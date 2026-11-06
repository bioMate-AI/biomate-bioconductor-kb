"""Fit the frozen calibration constants from the EXISTING null records (positive-control runs 1 and 2). Usage: python3 gcal_fit.py RESULTS_DIR OUT.json"""
import sys, json, os
import gcal_lib as L

def main(res_dir, out):
    files = [f"{res_dir}/gpc_results_run1.jsonl", f"{res_dir}/gpc_results_run2.jsonl"]
    recs = [r for f in files for r in L.read_jsonl(f)]
    by = {"I": [], "M": []}; used = {}
    for r in recs:
        if r["kind"] == "VI": by["I"].append(r); used["VI"] = used.get("VI", 0) + 1
        elif r["kind"] == "VM2": by["M"].append(r); used["VM2"] = used.get("VM2", 0) + 1
        elif r["kind"] == "CURVE" and (r["F"] or 0) >= 14: by["M"].append(r); used[f"CURVE{r['F']}"] = used.get(f"CURVE{r['F']}", 0) + 1
    for t in by:
        assert all(L.rec_type(r) == t for r in by[t]), f"type mismatch in {t}"
    cal = L.fit(by)
    cal["_meta"] = dict(inputs={f: L.sha256(f) for f in files}, used_records=used, sigma_fam=L.SIGMA_FAM, alpha=L.ALPHA, z90=L.Z90, seeds_max=max(r["seed"] for r in recs if r["kind"] in ("VI", "VM2", "CURVE")))
    json.dump(cal, open(out, "w"), indent=1)
    for t in ("I", "M"): print(t, "n_null", cal[t]["n_null"], "q", round(cal[t]["q"], 3), "untested", cal[t]["untested"], "T quantiles", {k: round(v, 2) for k, v in cal[t]["T_null_quantiles"].items()})
    print("kappa I:", {k: round(v, 2) for k, v in sorted(cal["I"]["kappa"].items())})
    print("kappa M:", {k: round(v, 2) for k, v in sorted(cal["M"]["kappa"].items())})

if __name__ == "__main__": main(sys.argv[1], sys.argv[2])
