#!/bin/bash -ue
python3 << 'EOF'
import json
from datetime import datetime

meta_id    = "EGFR_kinase"
min_drug   = float("0.5")
warn_drug  = float("0.3")
min_vol    = float("300.0")

data       = json.load(open("EGFR_kinase_pockets.json"))
pockets    = data.get("pockets", [])

if pockets:
    # Pockets already sorted by druggability_score descending
    top = pockets[0]
    top_score  = float(top["druggability_score"])
    top_volume = float(top["volume_A3"])
    top_id     = top["pocket_id"]
else:
    top_score  = 0.0
    top_volume = 0.0
    top_id     = None

# Evidence-graded decision
if top_score >= min_drug and top_volume >= min_vol:
    status = "PASS"
elif top_score >= warn_drug:
    status = "WARN"
else:
    status = "FAIL"

result = {
    "target":               meta_id,
    "status":               status,
    "top_pocket_id":        top_id,
    "top_druggability_score": top_score,
    "top_volume":           top_volume,
    "threshold_score":      min_drug,
    "threshold_volume":     min_vol,
    "warn_threshold_score": warn_drug,
    "evidence_tier":        "BRONZE",
    "num_pockets_evaluated":len(pockets),
    "timestamp":            datetime.utcnow().isoformat() + "Z",
}

with open(f"{meta_id}_qc_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Druggability QC [{meta_id}]: {status}")
print(f"  top pocket id={top_id}  score={top_score}  volume={top_volume} A3")
print(f"  PASS requires score>={min_drug} AND volume>={min_vol}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "POCKET_DETECTION_DRUGGABILITY:DRUGGABILITY_QC_GATE":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        min_druggability: "0.5"
        warn_druggability: "0.3"
        min_volume: "300.0"
    END_VERSIONS
