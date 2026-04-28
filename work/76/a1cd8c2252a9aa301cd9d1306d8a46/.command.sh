#!/bin/bash -ue
python3 << 'EOF'
import json
from datetime import datetime

compound_id    = "CPND0004"
pass_max_steps = int("4")
pass_min_score = float("0.6")
warn_max_steps = int("6")

data   = json.load(open("CPND0004_routes.json"))
routes = data.get("routes", [])
smiles_valid = data.get("smiles_valid", True)

# ---------------------------------------------------------------------------
# QC gate logic:
#   PASS — at least one route with step_count ≤ pass_max_steps AND score ≥ pass_min_score
#   WARN — best route step_count ≤ warn_max_steps (but failed PASS criteria)
#   FAIL — no routes / all routes exceed warn_max_steps / invalid SMILES
# ---------------------------------------------------------------------------
if not smiles_valid or len(routes) == 0:
    qc_status = "FAIL"
    qc_reason = "invalid_smiles" if not smiles_valid else "no_routes_found"
    best_steps = None
    best_score = None
    best_sa    = None
else:
    # Routes are sorted by score descending; best route = index 0
    best = routes[0]
    best_steps = best["step_count"]
    best_score = best["score"]
    best_sa    = best.get("sa_score", None)

    # Check PASS: at least one route meets both thresholds
    pass_routes = [
        r for r in routes
        if r["step_count"] <= pass_max_steps and r["score"] >= pass_min_score
    ]

    if pass_routes:
        qc_status = "PASS"
        qc_reason = f"route_with_steps<={pass_max_steps}_and_score>={pass_min_score}_found"
    elif best_steps <= warn_max_steps:
        qc_status = "WARN"
        qc_reason = f"best_route_steps={best_steps}_score={best_score}_below_pass_threshold"
    else:
        qc_status = "FAIL"
        qc_reason = f"all_routes_exceed_{warn_max_steps}_steps"

# Annotate each route with feasibility tier
for r in routes:
    if r["step_count"] <= pass_max_steps and r["score"] >= pass_min_score:
        r["feasibility_tier"] = "EXCELLENT"
    elif r["step_count"] <= warn_max_steps:
        r["feasibility_tier"] = "MODERATE"
    else:
        r["feasibility_tier"] = "POOR"

filtered = {
    "compound_id":       compound_id,
    "smiles":            data.get("smiles", ""),
    "smiles_valid":      smiles_valid,
    "qc_status":         qc_status,
    "qc_reason":         qc_reason,
    "best_route_steps":  best_steps,
    "best_route_score":  best_score,
    "best_sa_score":     best_sa,
    "n_routes":          len(routes),
    "pass_max_steps":    pass_max_steps,
    "pass_min_score":    pass_min_score,
    "warn_max_steps":    warn_max_steps,
    "routes":            routes,
    "timestamp":         datetime.utcnow().isoformat() + "Z",
    "mock_mode":         data.get("mock_mode", False),
}

with open(f"{compound_id}_filtered.json", "w") as f:
    json.dump(filtered, f, indent=2)

with open(f"{compound_id}_filter.tsv", "w") as f:
    f.write("compound_id\tsmiles\tbest_route_steps\tbest_route_score\tbest_sa_score\tn_routes\tqc_status\tqc_reason\n")
    f.write(
        f"{compound_id}\t"
        f"{data.get('smiles', '')}\t"
        f"{best_steps if best_steps is not None else 'NA'}\t"
        f"{best_score if best_score is not None else 'NA'}\t"
        f"{best_sa if best_sa is not None else 'NA'}\t"
        f"{len(routes)}\t"
        f"{qc_status}\t"
        f"{qc_reason}\n"
    )

status_icon = {"PASS": "✓", "WARN": "~", "FAIL": "✗"}.get(qc_status, "?")
print(f"Retrosynthesis filter [{compound_id}]: {status_icon} {qc_status}  ({qc_reason})")
if best_steps is not None:
    print(f"  Best route: steps={best_steps}  score={best_score}  sa_score={best_sa}")
    print(f"  PASS threshold: steps<={pass_max_steps} AND score>={pass_min_score}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "AIZYNTHFINDER_RETROSYNTHESIS:RETROSYNTHESIS_FILTER":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        pass_max_steps: "4"
        pass_min_score: "0.6"
        warn_max_steps: "6"
    END_VERSIONS
