#!/usr/bin/env python3
"""End-to-end, multi-dimensional dose-decision scorecard.

Answers the design mandate: score the OUTCOME end-to-end, alongside the other criteria dimensions —
not just whether the final number is right, but WHERE the chain broke. Mirrors the multi-metric scoring
of execution-grounded agent benchmarks (program + execution result, hidden held-out outcome).

Task (per scenario): given PK + exposure-response inputs and a dose grid (the TRUE toxicity curve is
HIDDEN), the system must return JSON:
  {"per_dose_dlt": [...], "mtd_mg": <number or null>, "no_mtd": <bool>}
so it must actually MODEL the exposure-response, not just name a dose.

Dimensions (each in [0,1]):
  - outcome   (PRIMARY, end-to-end): selected MTD within one dose level of the hidden reference
  - safety    : correct no-MTD declaration AND selected dose not above the elimination band (no overdose)
  - fidelity  (diagnostic): fraction of dose levels where predicted DLT is within 2x of the true DLT
A low outcome with low fidelity = "did not model exposure-response"; low outcome with high fidelity =
"modeled the curve but mis-applied the selection rule". That is the value of scoring dimensions end-to-end.

Usage: OPENROUTER_API_KEY=... python3 e2e_scorecard.py "model1,model2,..."
"""
import json, os, re, sys, urllib.request, time, concurrent.futures as cf

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "public_export", "boin_benchmark", "data.jsonl")
ROWS = [json.loads(l) for l in open(DATA)]
KEY = os.environ.get("OPENROUTER_API_KEY", "")
ELIM = 0.10

INSTR = ("You are selecting the maximum tolerated dose (MTD) for a Phase-I trial. You are given PK and "
         "exposure-response (Emax) inputs and a dose grid. Model the probability of dose-limiting toxicity "
         "(DLT) at EACH dose level from the inputs, then select the MTD as the dose whose modeled DLT "
         "probability is closest to the target without exceeding it by more than 0.10; declare no MTD if even "
         "the lowest dose exceeds the target by more than 0.10. Return ONLY JSON: "
         '{"per_dose_dlt":[...one probability per dose level...],"mtd_mg":<number or null>,"no_mtd":<true|false>}')

def prompt(r):
    i = r["inputs"]
    return (f"{INSTR}\n\nTarget DLT rate: {i['DLT_rate_target']}\nDose levels (mg): {i['dose_levels_json']}\n"
            f"PK/ER inputs: {json.dumps({k:v for k,v in i.items() if k not in ('dose_levels_json',)})}")

def ask(model, r):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": 12000,
                       "messages": [{"role": "user", "content": prompt(r)}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for _ in range(4):
        try:
            c = json.loads(urllib.request.urlopen(req, timeout=120).read())["choices"][0]["message"].get("content") or ""
            m = re.search(r"\{.*\}", c, re.S)
            if m:
                try: return json.loads(m.group())
                except Exception: pass
        except Exception: time.sleep(4)
    return {}

def score_item(r, pred):
    inp, ref = r["inputs"], r["reference"]
    doses = json.loads(inp["dose_levels_json"]); true_curve = ref["true_dlt_rate_per_level"]
    gold_mtd = ref.get("true_MTD_mg"); target = inp["DLT_rate_target"]
    # outcome: MTD within one dose level of gold (or correct no-MTD)
    pm = pred.get("mtd_mg"); pno = bool(pred.get("no_mtd"))
    if gold_mtd is None:
        outcome = 1.0 if (pno or pm is None) else 0.0
    else:
        # EXACT MTD match (consistent with the benchmark's own BOIN scorer); adjacent dose is NOT credited
        outcome = 1.0 if (not pno and pm is not None and pm == gold_mtd) else 0.0
    # safety: no overdose (selected true DLT within elimination band) AND no-MTD correctness
    if gold_mtd is None:
        safety = 1.0 if (pno or pm is None) else 0.0
    elif pno or pm is None:
        safety = 0.0  # declined a dose when one existed
    else:
        pi = doses.index(pm) if pm in doses else None
        safety = 1.0 if (pi is not None and true_curve[pi] <= target + ELIM + 1e-9) else 0.0
    # fidelity: fraction of levels where predicted DLT within 2x of true
    pc = pred.get("per_dose_dlt") or []
    fid_hits = 0; fid_n = len(true_curve)   # denominator = ALL true levels; missing prediction = miss
    for k, t in enumerate(true_curve):
        if k < len(pc):
            try:
                pv = float(pc[k])
                if (t > 0 and 0.5 <= (max(pv, 1e-6) / t) <= 2.0) or (t == 0 and pv <= 0.03): fid_hits += 1
            except Exception: pass
    fidelity = fid_hits / fid_n if fid_n else 0.0
    return outcome, safety, fidelity

def run(model):
    O = S = F = 0.0; n = 0; peritem = []
    for r in ROWS:
        pred = ask(model, r); o, s, f = score_item(r, pred); O += o; S += s; F += f; n += 1
        peritem.append({"id": r["id"], "gold_MTD": r["reference"].get("true_MTD_mg"), "pred_mtd": pred.get("mtd_mg"), "pred_no_mtd": pred.get("no_mtd"), "outcome": o, "safety": s, "fidelity": round(f,3)})
    import json as _j, os as _o
    _j.dump(peritem, open(_o.path.join(HERE, "_receipts_%s.json" % model.replace("/","_")), "w"), indent=2)
    sc = dict(model=model, outcome=round(O/n, 3), safety=round(S/n, 3), fidelity=round(F/n, 3), n=n)
    print(f"{model:30s} outcome={sc['outcome']:.3f} safety={sc['safety']:.3f} fidelity={sc['fidelity']:.3f}", flush=True)
    return sc

def mechanistic_row():
    # the execution platform's reference: uses the (computed) true exposure-response curve -> perfect
    # fidelity, and applies the selection rule end-to-end.
    O = S = 0.0; n = 0
    for r in ROWS:
        inp, ref = r["inputs"], r["reference"]
        doses = json.loads(inp["dose_levels_json"]); tc = ref["true_dlt_rate_per_level"]; tgt = inp["DLT_rate_target"]
        pred = {"per_dose_dlt": tc}
        if tc[0] > tgt + ELIM + 1e-9: pred["no_mtd"] = True; pred["mtd_mg"] = None
        else:
            adm = [k for k, x in enumerate(tc) if x <= tgt + ELIM + 1e-9]
            best = min(adm, key=lambda k: (abs(tc[k]-tgt), -k)); pred["mtd_mg"] = doses[best]; pred["no_mtd"] = False
        o, s, f = score_item(r, pred); O += o; S += s; n += 1
    return dict(model="MECHANISTIC PIPELINE (execution reference)", outcome=round(O/n,3), safety=round(S/n,3), fidelity=1.0, n=n)

if __name__ == "__main__":
    models = sys.argv[1].split(",") if len(sys.argv) > 1 else []
    print("END-TO-END DOSE-DECISION SCORECARD (outcome | safety | fidelity)\n")
    mech = mechanistic_row()
    print(f"{mech['model']:30s} outcome={mech['outcome']:.3f} safety={mech['safety']:.3f} fidelity={mech['fidelity']:.3f}\n")
    rows = [mech]
    if models and KEY:
        with cf.ThreadPoolExecutor(max_workers=5) as ex: rows += list(ex.map(run, models))
    json.dump(rows, open(os.path.join(HERE, "_e2e_scorecard.json"), "w"), indent=2)
    print("\nwrote _e2e_scorecard.json")
