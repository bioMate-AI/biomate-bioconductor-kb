"""Aggregator for the validity-gate positive control (docs/20261031_GATE_POSITIVE_CONTROL_PREREG.md, sections 2, 3, 5, 6).
usage: python3 gpc_agg.py [results/gpc_results.jsonl]  ->  results/gpc_summary.json and results/gpc_summary.md
Pure post-processing of the stored per-construction records; no gate is re-run. All proportions carry exact Clopper-Pearson 95 % intervals."""
import os, sys, json, collections
import numpy as np
from scipy.stats import beta

HERE = os.path.dirname(os.path.abspath(__file__)); OUT = f"{HERE}/results"
DELTAS = [0.03, 0.05, 0.10]
# mirrors gpc_lib.DETECTORS (prereg section 2); S-diffuse: C2 or any secondary
DETECTORS = {"S-tpsa": ["secondary:tpsa", "primary:C2_multiproxy_leave_fold_out"], "S-typ": ["primary:C1_atomlm_typicality", "primary:C2_multiproxy_leave_fold_out"],
             "S-cens": ["secondary:C4_censored_label"], "S-diffuse": ["primary:C2_multiproxy_leave_fold_out"]}
FAMS = ["S-tpsa", "S-typ", "S-cens", "S-diffuse"]; A_GRID = [0.55, 0.60, 0.65, 0.70]; F_GRID = [4, 6, 8, 10, 14, 20, 26, 47, 50, 85, 100, 150]; CERT_F = [14, 20, 26, 47, 85, 150]


def cp(k, n, alpha=0.05):
    if n == 0: return (float("nan"), float("nan"))
    lo = 0.0 if k == 0 else float(beta.ppf(alpha / 2, k, n - k + 1)); hi = 1.0 if k == n else float(beta.ppf(1 - alpha / 2, k + 1, n - k)); return (round(lo, 4), round(hi, 4))


def prop(k, n): return dict(k=int(k), n=int(n), p=round(k / n, 4) if n else None, ci=cp(k, n))


def status_at(rec, delta):
    """Same logic as validity_gate.assign_status, with the equivalence margin as a parameter (biased flags do not depend on delta)."""
    if rec["biased"]: return "NOT_VALID_BIASED"
    if rec["unverifiable"]: return "NOT_VALID_UNVERIFIABLE"
    for k, v in rec["primary"].items():
        if v is None or v["lo90"] is None or v["hi90"] is None: return "NOT_VALID_UNVERIFIABLE"
        if not (v["lo90"] >= 0.5 - delta and v["hi90"] <= 0.5 + delta): return "NOT_VALID_NOT_EQUIVALENT"
    return "VALID"


def knife_edge(rec, eps=1e-3):
    """True if shifting every stored control bound by +-eps could change the status at the registered margin (solver-noise sensitivity, amendment A2)."""
    base = rec["status"]
    for sgn in (-1, 1):
        r2 = json.loads(json.dumps(rec)); b = []
        for k, v in r2["primary"].items():
            if v is None: continue
            for x in ("lo", "hi", "lo90", "hi90"): v[x] = v[x] + sgn * eps
            if v["lo"] > 0.5 or v["hi"] < 0.5: b.append(k)
        for k, v in r2["secondary"].items():
            if v is None or v.get("lo") is None: continue
            v["lo"] += sgn * eps; v["hi"] += sgn * eps
            if v["lo"] > 0.5 or v["hi"] < 0.5: b.append(k)
        r2["biased"] = rec["biased"] if False else b
        if status_at(r2, 0.05) != base: return True
    return False


def detected(rec, fam):
    if rec["status"] != "NOT_VALID_BIASED": return False
    b = set(rec["biased"])
    if fam == "S-diffuse": return bool(b & set(DETECTORS[fam])) or any(x.startswith("secondary:") for x in b)
    return bool(b & set(DETECTORS[fam]))


def dist(recs, delta=0.05):
    c = collections.Counter(status_at(r, delta) for r in recs); n = len(recs)
    return {s: prop(c.get(s, 0), n) for s in ("VALID", "NOT_VALID_BIASED", "NOT_VALID_NOT_EQUIVALENT", "NOT_VALID_UNVERIFIABLE")}


def per_control(R):
    """Per primary control under a TRUE AUC of exactly 0.5 (planted-valid): P(biased flag), P(equivalence satisfied), median 90 % width, P(width > region width 0.10)."""
    out = {}
    for c in sorted({k for r in R for k in r["primary"]}):
        v = [r["primary"][c] for r in R if r["primary"].get(c) and r["primary"][c]["lo90"] is not None]
        if not v: continue
        w = np.array([x["hi90"] - x["lo90"] for x in v]); cen = np.array([(x["hi90"] + x["lo90"]) / 2 - 0.5 for x in v])
        nb = sum(("primary:" + c) in r["biased"] for r in R); ne = sum((x["lo90"] >= 0.45 and x["hi90"] <= 0.55) for x in v)
        out[c] = dict(P_biased=prop(nb, len(R)), P_equivalent=prop(ne, len(v)), median_width90=round(float(np.median(w)), 4), P_width90_gt_0p10=prop(int((w > 0.10).sum()), len(v)), mean_abs_centre_offset=round(float(np.abs(cen).mean()), 4))
    return out


def main(paths):
    recs = [json.loads(l) for p in paths for l in open(p)]; by = collections.defaultdict(list)
    for r in recs:
        key = r["kind"] if r["kind"] in ("VI", "VM2") else (f"{r['family']}|{r['a']}" if r["kind"] == "S" else f"CURVE|{r['F']}"); by[key].append(r)
    cal = json.load(open(f"{OUT}/calibration.json")) if os.path.exists(f"{OUT}/calibration.json") else {}
    S = dict(n_records=len(recs), counts={k: len(v) for k, v in sorted(by.items())})
    # consistency: stored status must equal the recomputed status at the registered margin
    S["status_consistency_mismatches"] = sum(status_at(r, 0.05) != r["status"] for r in recs)
    S["knife_edge_records_pm_1e-3"] = {k: prop(sum(knife_edge(r) for r in v), len(v)) for k, v in sorted(by.items())}
    # PASS-A (section 5)
    A = {}
    for k in ("VI", "VM2"):
        R = by.get(k, []); nb = sum(r["status"] == "NOT_VALID_BIASED" for r in R); d = prop(nb, len(R)); d["point_pass"] = bool(d["p"] is not None and d["p"] <= 0.10)
        d["label"] = ("PASS" if d["ci"][1] <= 0.10 else "point-pass only") if d["point_pass"] else "FAIL"; d["status_distribution"] = dist(R); A[k] = d
    S["PASS_A"] = A; S["PASS_A_overall"] = all(A[k]["point_pass"] for k in A)
    # PASS-B and power curve
    B = {}
    for fam in FAMS:
        B[fam] = {}
        for a in A_GRID:
            R = by.get(f"{fam}|{a}", []); feas = cal.get(f"{fam}|{a}", {}).get("feasible", True)
            if not R: B[fam][str(a)] = dict(feasible=bool(feas), n=0); continue
            nd = sum(detected(r, fam) for r in R); nbias = sum(r["status"] == "NOT_VALID_BIASED" for r in R); nv = sum(r["status"] == "VALID" for r in R)
            B[fam][str(a)] = dict(feasible=True, detection=prop(nd, len(R)), P_biased=prop(nbias, len(R)), P_not_valid=prop(len(R) - nv, len(R)))
        ok = [a for a in A_GRID if B[fam][str(a)].get("detection") and B[fam][str(a)]["detection"]["p"] >= 0.8]; B[fam]["smallest_a_detection_ge_0.8"] = ok[0] if ok else None
    S["detection"] = B
    S["PASS_B"] = {fam: (B[fam]["0.65"].get("detection", {}).get("p") is not None and B[fam]["0.65"]["detection"]["p"] >= 0.90) for fam in ("S-tpsa", "S-typ", "S-cens")}
    S["PASS_B_overall"] = all(S["PASS_B"].values()); S["CONTROL_PASSES"] = bool(S["PASS_A_overall"] and S["PASS_B_overall"])
    # margin sensitivity (section 6)
    M = {}
    for dlt in DELTAS:
        M[str(dlt)] = {"VI": dist(by.get("VI", []), dlt)["VALID"], "VM2": dist(by.get("VM2", []), dlt)["VALID"]}
        for fam in FAMS:
            for a in A_GRID:
                R = by.get(f"{fam}|{a}", [])
                if R: M[str(dlt)][f"{fam}|{a}"] = prop(sum(status_at(r, dlt) == "VALID" for r in R), len(R))
    S["margin_sensitivity_P_VALID"] = M
    # minimum-families curve (section 3)
    C = {}; first = None
    for F in F_GRID:
        R = by.get(f"CURVE|{F}", [])
        if not R: continue
        d = dist(R); fails = collections.Counter(c for r in R for c in r["not_equivalent"]); C[str(F)] = dict(n=len(R), dist=d, primary_fails_equivalence=dict(fails.most_common()))
        if first is None and d["VALID"]["p"] is not None and d["VALID"]["p"] >= 0.8: first = F
    S["curve"] = C; S["smallest_F_P_VALID_ge_0.8"] = first if first is not None else ">150"
    # A3: certifier rule PASS-C and per-control tables
    cert = {}
    for F in CERT_F:
        d = C.get(str(F), {}).get("dist", {}).get("VALID")
        if d and d["p"] is not None: cert[str(F)] = dict(P_VALID=d, certifier=bool(d["p"] >= 0.5), verdict=("certifier at F=%d" % F) if d["p"] >= 0.5 else ("CANNOT CERTIFY at F=%d (P(VALID) < 0.5)" % F))
    for k, F in (("VI", 26), ("VM2", 14)):
        if k in A and A[k]["status_distribution"]["VALID"]["p"] is not None: d = A[k]["status_distribution"]["VALID"]; cert[f"{k} (real F={F})"] = dict(P_VALID=d, certifier=bool(d["p"] >= 0.5), verdict=("certifier at F=%d" % F) if d["p"] >= 0.5 else ("CANNOT CERTIFY at F=%d (P(VALID) < 0.5)" % F))
    S["PASS_C_certifier"] = cert; S["PASS_C_at_real_F"] = {k: v["certifier"] for k, v in cert.items() if "real F" in k}; S["PASS_C_evaluated_real_F"] = sorted(S["PASS_C_at_real_F"])
    S["per_control_under_truth_0p5"] = {k: per_control(by[k]) for k in ("VI", "VM2") if k in by} | {f"CURVE|{F}": per_control(by[f"CURVE|{F}"]) for F in CERT_F if f"CURVE|{F}" in by}
    S["control_verdict_text"] = ("PASSES as bias detector AND certifier at the real F" if (S["PASS_A_overall"] and S["PASS_B_overall"] and len(S["PASS_C_at_real_F"]) == 2 and all(S["PASS_C_at_real_F"].values())) else "PASSES as bias detector but CANNOT CERTIFY at the real F (P(VALID) < 0.5)" if (S["PASS_A_overall"] and S["PASS_B_overall"]) else "FAILS (see PASS-A / PASS-B)")
    # generator agreement (reported either way): synthetic F=26 / 14 vs real-derived V-I (26 fam) / V-M2 (14 fam)
    def overlap(a, b): return not (a["ci"][1] < b["ci"][0] or b["ci"][1] < a["ci"][0])
    S["generator_check"] = {}
    for F, real in ((26, "VI"), (14, "VM2")):
        if str(F) in C and real in A:
            for st in ("VALID", "NOT_VALID_BIASED", "NOT_VALID_NOT_EQUIVALENT"):
                S["generator_check"][f"F{F}_vs_{real}_{st}"] = dict(synthetic=C[str(F)]["dist"][st], real=A[real]["status_distribution"][st], ci_overlap=overlap(C[str(F)]["dist"][st], A[real]["status_distribution"][st]))
    for real, F in (("VI", 26), ("VM2", 14)):
        if real in A: S[f"P_VALID_planted_valid_{real}"] = A[real]["status_distribution"]["VALID"]
    json.dump(S, open(f"{OUT}/gpc_summary.json", "w"), indent=1)
    L = ["# Gate positive control: summary (auto-generated by gpc_agg.py)", "", f"Records: {S['n_records']}; stored-vs-recomputed status mismatches: {S['status_consistency_mismatches']}", "",
         f"PASS-A (P(NOT_VALID_BIASED) <= 0.10 on planted-valid): VI {A.get('VI',{}).get('p')} {A.get('VI',{}).get('ci')} [{A.get('VI',{}).get('label')}], VM2 {A.get('VM2',{}).get('p')} {A.get('VM2',{}).get('ci')} [{A.get('VM2',{}).get('label')}] -> {S['PASS_A_overall']}",
         f"PASS-B (detection >= 0.90 at a=0.65): {S['PASS_B']} -> {S['PASS_B_overall']}", f"CONTROL PASSES (A and B): {S['CONTROL_PASSES']}", "VERDICT: " + S["control_verdict_text"], "CERTIFIER (P(VALID) >= 0.5): " + json.dumps({k: v["verdict"] for k, v in S["PASS_C_certifier"].items()}), "",
         "P(VALID | planted-valid): " + json.dumps({k: S.get(f'P_VALID_planted_valid_{k}') for k in ('VI', 'VM2')}), "", "Smallest F with P(VALID) >= 0.8: " + str(S["smallest_F_P_VALID_ge_0.8"])]
    open(f"{OUT}/gpc_summary.md", "w").write("\n".join(L) + "\n"); print("\n".join(L))


if __name__ == "__main__":
    main(sys.argv[1:] if len(sys.argv) > 1 else [f"{OUT}/gpc_results.jsonl"])
