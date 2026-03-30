#!/bin/bash -ue
mkdir -p diffdock_results

    if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import os
import random
import math
from datetime import datetime

random.seed(42)

meta_id   = "EGFR_kinase"
ligand    = "mock_aspirin.sdf"
num_poses = int("10")

# ---------------------------------------------------------------------------
# Generate mock ranked SDF poses and confidence scores
# ---------------------------------------------------------------------------
# DiffDock confidence: log(P/(1-P)) in (-inf, +inf); higher = better
# Typical range: top pose ~+2.0 → +0.9, tail ~-1.0
confidence_scores = []
base = 2.2
for i in range(num_poses):
    c = base - i * 0.19 + random.gauss(0, 0.04)
    confidence_scores.append(round(c, 4))
confidence_scores.sort(reverse=True)

def mock_pose_sdf(rank, conf):
    # Generate minimal valid SDF for a ligand pose (aspirin-like)
    lines = [
        f"     BioMate_mock_pose_rank{rank}",
        "  DiffDock 3D",
        "",
        " 13 13  0  0  0  0  0  0  0  0999 V2000",
        # atom block: 13 atoms rotated by rank * 5 degrees
        f"    {1.5 + rank*0.1:.4f}    {0.0 + rank*0.05:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {0.7:.4f}    {1.2:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"   {-0.7:.4f}    {1.2:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"   {-1.4:.4f}    {0.0:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"   {-0.7:.4f}   {-1.2:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {0.7:.4f}   {-1.2:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {2.9:.4f}    {0.0:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {3.7:.4f}    {1.0:.4f}    {0.0:.4f} O   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {3.7:.4f}   {-1.0:.4f}    {0.0:.4f} O   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {5.1:.4f}   {-1.0:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {5.9:.4f}    {0.0:.4f}    {0.0:.4f} C   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {7.3:.4f}    {0.0:.4f}    {0.0:.4f} O   0  0  0  0  0  0  0  0  0  0  0  0",
        f"    {5.1:.4f}    {1.3:.4f}    {0.0:.4f} O   0  0  0  0  0  0  0  0  0  0  0  0",
        "  1  2  2  0  0  0  0",
        "  2  3  1  0  0  0  0",
        "  3  4  2  0  0  0  0",
        "  4  5  1  0  0  0  0",
        "  5  6  2  0  0  0  0",
        "  6  1  1  0  0  0  0",
        "  1  7  1  0  0  0  0",
        "  7  8  2  0  0  0  0",
        "  7  9  1  0  0  0  0",
        "  9 10  1  0  0  0  0",
        " 10 11  1  0  0  0  0",
        " 11 12  2  0  0  0  0",
        " 10 13  2  0  0  0  0",
        "M  END",
        f"> <DiffDock_confidence>",
        f"{conf}",
        "",
        "$$$$",
    ]
    return "\n".join(lines)

# Write all ranked poses
for rank, conf in enumerate(confidence_scores, 1):
    sdf_path = f"diffdock_results/rank{rank}_confidence{conf:.4f}.sdf"
    with open(sdf_path, "w") as f:
        f.write(mock_pose_sdf(rank, conf))

# Write rank1 with canonical name (required by output spec)
top_conf = confidence_scores[0]
top_path = f"diffdock_results/rank1_confidence{top_conf:.4f}.sdf"
if not os.path.exists(top_path):
    with open(top_path, "w") as f:
        f.write(mock_pose_sdf(1, top_conf))

# Summary JSON — mirrors DiffDock's actual output schema
poses_summary = []
for rank, conf in enumerate(confidence_scores, 1):
    poses_summary.append({
        "rank":            rank,
        "confidence":      conf,
        "sdf_file":        f"rank{rank}_confidence{conf:.4f}.sdf",
        "rmsd_to_ref":     None,   # unknown without reference
        "centroid":        [round(rank * 0.3, 3), round(rank * 0.1, 3), 0.0],
    })

summary = {
    "target":          meta_id,
    "ligand":          ligand,
    "tool":            "DiffDock",
    "version":         "1.1.2",
    "num_poses":       num_poses,
    "inference_steps": int("20"),
    "top_confidence":  confidence_scores[0],
    "poses":           poses_summary,
    "timestamp":       datetime.utcnow().isoformat() + "Z",
    "mock_mode":       True,
}

with open(f"{meta_id}_diffdock_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"DiffDock mock complete: {num_poses} poses")
print(f"  Top confidence: {confidence_scores[0]:.4f}")
print(f"  Poses directory: diffdock_results/")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live DiffDock inference
        # ---------------------------------------------------------------------------
        python -m diffdock.inference \
            --protein_path   EGFR_kinase_structure.pdb \
            --ligand_path    mock_aspirin.sdf \
            --out_dir        diffdock_results/ \
            --samples_per_complex 10 \
            --inference_steps    20 \
            --batch_size 10

        # Normalise output: write summary JSON from DiffDock rank files
        python3 << 'PYEOF'
import json, glob, os, re
from datetime import datetime

meta_id  = "EGFR_kinase"
out_dir  = "diffdock_results"
sdf_files = sorted(glob.glob(f"{out_dir}/rank*.sdf"))

poses = []
for sdf in sdf_files:
    m = re.search(r'rank(\d+)_confidence([\-\d.]+)\.sdf', sdf)
    if m:
        rank = int(m.group(1))
        conf = float(m.group(2))
        poses.append({"rank": rank, "confidence": conf, "sdf_file": os.path.basename(sdf)})

summary = {
    "target":      meta_id,
    "ligand":      "mock_aspirin.sdf",
    "tool":        "DiffDock",
    "num_poses":   len(poses),
    "poses":       sorted(poses, key=lambda x: x["rank"]),
    "top_confidence": poses[0]["confidence"] if poses else None,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "mock_mode":   False,
}
with open(f"{meta_id}_diffdock_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(f"DiffDock live: {len(poses)} poses written to {out_dir}/")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "STRUCTURE_PREDICTION_DOCKING:DIFFDOCK_BLIND_DOCKING":
        diffdock: "1.1.2"
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
    END_VERSIONS
