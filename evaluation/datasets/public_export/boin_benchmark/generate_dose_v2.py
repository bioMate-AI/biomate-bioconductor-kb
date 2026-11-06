#!/usr/bin/env python3
"""Generate additional Phase-I dose scenarios with mechanistically-coherent curves and rule-consistent gold.

Each scenario draws PK + Emax exposure-response parameters, computes the per-dose steady-state concentration
(C_nM = F * (dose_mg/MW/Vd_L) * 1e6) and the per-dose DLT probability via an Emax model
(DLT = E0 + Emax * C/(EC50+C)), then sets the gold MTD by the SAME selection rule used for scoring
(highest admissible dose whose DLT is closest to target; no-MTD if the lowest dose exceeds target+0.10).
Because the curve is derived from solver-visible inputs and the gold follows the stated rule, these items are
mechanistically coherent and free of the target-definition mismatch seen in the original hand-authored set.
"""
import json, os, random
random.seed(20261028)
HERE = os.path.dirname(os.path.abspath(__file__))
ELIM = 0.10

def dlt_curve(doses, MW, Vd, F, E0, Emax, EC50):
    out = []
    for d in doses:
        C = F * (d / MW / Vd) * 1e6   # nM
        out.append(round(E0 + Emax * C / (EC50 + C), 3))
    return out

def select_mtd(rates, target, doses):
    if rates[0] > target + ELIM + 1e-9:
        return None
    adm = [i for i, r in enumerate(rates) if r <= target + ELIM + 1e-9]
    best = min(adm, key=lambda i: (abs(rates[i] - target), -i))
    return doses[best]

GRIDS = [[2,5,10,20,40,80],[5,10,25,50,100,200],[10,30,60,120,240],[25,50,100,200,400,800],
         [1,3,10,30,100],[50,100,200,400,600],[0.5,1,2,4,8,16],[100,200,400,800,1600]]

def main():
    items = []
    n = 0
    while len(items) < 20:
        n += 1
        doses = random.choice(GRIDS)
        MW = random.choice([180.0, 250.0, 320.0, 410.0, 480.0, 550.0])
        Vd = random.choice([20.0, 40.0, 70.0, 120.0, 200.0])
        F = random.choice([0.3, 0.5, 0.7, 0.9])
        target = random.choice([0.20, 0.25, 0.30, 0.33])
        E0 = round(random.uniform(0.0, 0.04), 3)
        Emax = random.choice([0.6, 0.8, 0.95])
        # choose EC50 so the curve spans a useful range across the grid (tie EC50 to mid-dose exposure)
        midC = F * (doses[len(doses)//2] / MW / Vd) * 1e6
        EC50 = round(midC * random.choice([0.4, 0.8, 1.5, 3.0, 8.0]), 1)
        rates = dlt_curve(doses, MW, Vd, F, E0, Emax, EC50)
        gold = select_mtd(rates, target, doses)
        # keep a spread: ~15% no-MTD, rest with an MTD; skip degenerate all-zero or all-toxic-at-level1 unless no-MTD
        if gold is None and random.random() > 0.3:   # cap no-MTD fraction
            continue
        if gold is not None and rates[-1] < target:   # curve too flat (never reaches toxicity) -> skip
            continue
        gi = doses.index(gold) if gold in doses else None
        items.append({
            "id": f"CT-G{len(items)+1:02d}",
            "scenario": f"Generated Emax exposure-response scenario (MW {MW}, Vd {Vd} L, F {F})",
            "inputs": {"starting_dose_mg": doses[0], "max_dose_mg": doses[-1],
                       "dose_levels_json": json.dumps(doses), "DLT_rate_target": target, "design": "BOIN",
                       "MW": MW, "Vd_L": Vd, "F": F, "ER_model": "Emax", "ER_E0": E0, "ER_Emax": Emax,
                       "ER_EC50_nM": EC50},
            "reference": {"true_dlt_rate_per_level": rates,
                          "true_MTD_level": (gi + 1) if gi is not None else None,
                          "true_MTD_mg": gold, "safety_flags": ([] if gold is not None else ["no_safe_dose"])},
            "difficulty": "generated",
        })
    with open(os.path.join(HERE, "data_v2_generated.jsonl"), "w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    nm = sum(1 for it in items if it["reference"]["true_MTD_mg"] is None)
    print(f"wrote {len(items)} generated dose scenarios ({nm} no-MTD); gold = selection rule on the derived curve")

if __name__ == "__main__":
    main()
