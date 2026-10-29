"""Evaluate the calibrated gate on the FRESH validation records against the FROZEN constants (docs/20261031_GATE_CALIBRATION_PREREG.md sections 4-6).
usage: python3 gcal_eval.py CAL.json VALIDATION.jsonl REAL.json OUT.json   (run on EC2; reads JSON only)"""
import sys, json, collections
import numpy as np
import gcal_lib as L


def cell_key(r):
    F = r["primary"]["C1_atomlm_typicality"]["n_families"] if r["primary"].get("C1_atomlm_typicality") else r.get("F")
    return (r["kind"], int(F), r.get("family"), r.get("a"))


def t_raw(rec):
    z, _ = L.zvals(rec); return max(abs(v) for v in z.values()) if z else float("nan")


def main(cal_p, val_p, real_p, out_p):
    cal = json.load(open(cal_p)); recs = L.read_jsonl(val_p); real = json.load(open(real_p))
    cells = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in recs:
        a = L.assess(r, cal); k = cell_key(r)
        cells[k]["cal_biased"].append(a["status"] == "BIASED"); cells[k]["cal_valid"].append(a["status"] == "VALID")
        cells[k]["reg_biased"].append(r["status"] == "NOT_VALID_BIASED"); cells[k]["reg_valid"].append(r["status"] == "VALID")
    table = {}
    for k, v in sorted(cells.items(), key=lambda kv: str(kv[0])):
        table["|".join(str(x) for x in k)] = {m: L.rate(vals) for m, vals in v.items()}
    # DEVIATION (recorded in the results section): the as-run evaluator looked up the V-I cell as ("VI", 26) but the records carry 25 evaluable
    # families (n_families of C1), so the cell was reported as None and the as-run outcome printed FAILURE. The lookup now finds the V-I cell by kind.
    vi_key = next((k for k in table if k.startswith("VI|")), None)
    A_cells = [tuple([vi_key.split("|")[0], int(vi_key.split("|")[1]), None, None])] if vi_key else []
    A_cells += [("V3", 20, None, None), ("V3", 26, None, None), ("V3", 47, None, None)]
    passA = {}
    for k in A_cells:
        t = table.get("|".join(str(x) for x in k)); 
        if t is None: passA["|".join(map(str, k))] = None; continue
        c = t["cal_biased"]; passA["|".join(map(str, k))] = dict(rate=c["p"], ci=c["ci"], passed=bool(c["p"] <= 0.10 and c["ci"][1] <= 0.15), reg_rate=t["reg_biased"]["p"], valid_rate=t["cal_valid"]["p"], valid_ci=t["cal_valid"]["ci"], reg_valid_rate=t["reg_valid"]["p"], n=c["n"])
    passB, passC = {}, {}
    for key, t in table.items():
        kind, F, fam, a = key.split("|")
        if kind not in ("S", "SS"): continue
        a = float(a); need = 0.80 if abs(a - 0.65) < 1e-9 else 0.90
        passB[key] = dict(detect=t["cal_biased"]["p"], ci=t["cal_biased"]["ci"], need=need, passed=bool(t["cal_biased"]["p"] >= need), reg_detect=t["reg_biased"]["p"], n=t["cal_biased"]["n"])
        if abs(a - 0.65) < 1e-9: passC[key] = dict(p_valid=t["cal_valid"]["p"], ci=t["cal_valid"]["ci"], passed=bool(t["cal_valid"]["p"] <= 0.05), reg_p_valid=t["reg_valid"]["p"])
    allA = all(v and v["passed"] for v in passA.values()); allB = all(v["passed"] for v in passB.values()); allC = all(v["passed"] for v in passC.values())
    outcome = "SUCCESS" if (allA and allB and allC) else "PARTIAL" if allA else "FAILURE"
    # real benchmarks
    nullI = [t_raw(r) for r in recs if r["kind"] == "VI"]; nullM = [t_raw(r) for r in recs if r["kind"] == "VM2"]; real_out = {}
    for name, rec, null in (("I", real["I"], nullI), ("M2", real["M2"], nullM)):
        a = L.assess(rec, cal); to = t_raw(rec); nn = [x for x in null if x == x]
        p = (1 + sum(x >= to for x in nn)) / (1 + len(nn)) if nn else float("nan")
        real_out[name] = dict(calibrated=a, registered_status=rec["status"], registered_biased=rec["biased"], T_raw_obs=to, perm_p=p, perm_n=len(nn), primary={k: rec["primary"][k] for k in L.PRIMARY if rec["primary"].get(k)})
    c4 = real["I"]["secondary"].get("C4_censored_label"); real_out["C4_independent"] = c4
    res = dict(constants_sha256=L.sha256(cal_p), validation_sha256=L.sha256(val_p), n_records=len(recs), outcome=outcome, passA=passA, passB=passB, passC=passC, cells=table, real=real_out)
    json.dump(res, open(out_p, "w"), indent=1)
    print("OUTCOME", outcome, "| A", allA, "B", allB, "C", allC)
    for k, v in passA.items(): print("A", k, v and (round(v["rate"], 3), [round(x, 3) for x in v["ci"]], v["passed"], "reg", round(v["reg_rate"], 3), "P(VALID)", round(v["valid_rate"], 3)))
    for k, v in passB.items(): print("B", k, round(v["detect"], 3), "need", v["need"], v["passed"], "reg", round(v["reg_detect"], 3))
    for k, v in passC.items(): print("C", k, round(v["p_valid"], 3), v["passed"])
    for n, v in real_out.items():
        if n != "C4_independent": print("REAL", n, v["calibrated"]["status"], "T", round(v["calibrated"]["T"], 2), "q", round(v["calibrated"]["q"], 2), "flagged", v["calibrated"]["flagged"], "reg", v["registered_status"], "perm_p", round(v["perm_p"], 4))

if __name__ == "__main__": main(*sys.argv[1:5])
