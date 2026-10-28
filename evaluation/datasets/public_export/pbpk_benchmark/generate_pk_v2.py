#!/usr/bin/env python3
"""Generate additional PK exposure items with a transparent one-compartment reference.

Reference Cmax (uM) = F * (dose_mg / MW / Vd_L) * 1000  (mg/MW = mmol; /Vd_L = mM; *1000 = uM).
The solver must perform the molecular-weight and volume unit conversions correctly from the provided inputs;
the reference is explicitly MODELED (one-compartment), consistent with the benchmark's modeled-reference scope.
"""
import json, os, random
random.seed(20261028)
HERE = os.path.dirname(os.path.abspath(__file__))

def main():
    items = []
    for i in range(15):
        MW = round(random.uniform(180, 560), 2)
        Vd = round(random.uniform(15, 250), 1)
        F = round(random.choice([0.3, 0.45, 0.6, 0.75, 0.9]), 2)
        dose = random.choice([10, 25, 50, 100, 200, 300, 400, 500])
        logP = round(random.uniform(0.5, 4.5), 2)
        fu = round(random.uniform(0.01, 0.8), 3)
        CLint = random.choice([5, 20, 60, 120, 300, 600])
        cmax = round(F * (dose / MW / Vd) * 1000, 3)   # uM
        items.append({
            "id": f"PK-G{i+1:02d}",
            "name": f"Compound-{i+1}",
            "smiles": "",
            "dose_mg": dose, "route": "oral",
            "inputs": {"MW": MW, "logP": logP, "fu_plasma": fu, "CLint_uL_min_mg": CLint,
                       "Vd_L": Vd, "F": F},
            "reference": {"Cmax_uM": cmax},
            "difficulty": "generated", "target_endpoint": "Cmax_uM", "target_units": "uM",
        })
    with open(os.path.join(HERE, "data_v2_generated.jsonl"), "w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    print(f"wrote {len(items)} generated PK items; reference Cmax = one-compartment (F*dose/MW/Vd), modeled")

if __name__ == "__main__":
    main()
