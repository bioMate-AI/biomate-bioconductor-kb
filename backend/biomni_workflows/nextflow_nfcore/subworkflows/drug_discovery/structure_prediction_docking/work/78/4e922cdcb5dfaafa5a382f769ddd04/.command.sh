#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

meta_id       = "EGFR_kinase"
ligand        = "mock_aspirin.sdf"
pae_file      = "EGFR_kinase_pae.json"
exhaustiveness = int("4")
num_modes     = int("3")

# ---------------------------------------------------------------------------
# 1. Identify binding pocket centre from PAE matrix
#    Strategy: the residue with the lowest mean PAE to all neighbours
#    (most structurally confident) is likely in the protein core / active site.
# ---------------------------------------------------------------------------
try:
    pae_data = json.load(open(pae_file))
    pae      = pae_data.get("pae", [])
    N        = len(pae)

    if N > 0:
        row_means = [sum(row) / N for row in pae]
        anchor    = row_means.index(min(row_means))
        # Convert residue index to approximate Angstrom position (alpha-helix geometry)
        angle  = math.radians(anchor * 100.0)
        cx     = round(2.3 * math.cos(angle), 2)
        cy     = round(2.3 * math.sin(angle), 2)
        cz     = round(anchor * 1.5, 2)
    else:
        cx, cy, cz = 0.0, 0.0, 0.0
        anchor = 0
except Exception:
    cx, cy, cz = 0.0, 0.0, 0.0
    anchor = 0

box_size = 20.0  # Angstroms (standard docking grid)

# ---------------------------------------------------------------------------
# 2. Generate 9 synthetic binding modes (PDBQT format)
#    Energies: empirically best is ~-9 kcal/mol, tail ~-6 kcal/mol
# ---------------------------------------------------------------------------
energies = []
base_energy = -9.2
for i in range(num_modes):
    e = base_energy + i * 0.34 + random.gauss(0, 0.05)
    energies.append(round(e, 1))
energies.sort()   # most negative first (best binding first)

pdbqt_lines = []
for mode_idx, energy in enumerate(energies, 1):
    pdbqt_lines.append(f"MODEL        {mode_idx}")
    pdbqt_lines.append(f"REMARK VINA RESULT:   {energy:.1f}      0.000      0.000")
    # Minimal PDBQT atom block (aspirin-like, translated by pocket centre)
    atoms = [
        ("C1",  cx + 1.5,  cy + 0.0,  cz + 0.0,  "C"),
        ("C2",  cx + 0.7,  cy + 1.2,  cz + 0.0,  "C"),
        ("C3",  cx - 0.7,  cy + 1.2,  cz + 0.0,  "C"),
        ("C4",  cx - 1.4,  cy + 0.0,  cz + 0.0,  "C"),
        ("C5",  cx - 0.7,  cy - 1.2,  cz + 0.0,  "C"),
        ("C6",  cx + 0.7,  cy - 1.2,  cz + 0.0,  "C"),
        ("C7",  cx + 2.9,  cy + 0.0,  cz + 0.0,  "C"),
        ("O1",  cx + 3.7,  cy + 1.0,  cz + 0.0,  "OA"),
        ("O2",  cx + 3.7,  cy - 1.0,  cz + 0.0,  "OA"),
        ("C8",  cx + 5.1,  cy - 1.0,  cz + 0.0,  "C"),
        ("C9",  cx + 5.9,  cy + 0.0,  cz + 0.0,  "C"),
        ("O3",  cx + 7.3,  cy + 0.0,  cz + 0.0,  "OA"),
        ("O4",  cx + 5.1,  cy + 1.3,  cz + 0.0,  "OA"),
    ]
    # Rotate pose slightly per mode
    theta = math.radians(mode_idx * 10)
    for serial, (name, ax, ay, az, atype) in enumerate(atoms, 1):
        rx = ax * math.cos(theta) - ay * math.sin(theta)
        ry = ax * math.sin(theta) + ay * math.cos(theta)
        rz = az
        pdbqt_lines.append(
            f"ATOM  {serial:5d} {name:<4s} LIG A   1    "
            f"{rx:8.3f}{ry:8.3f}{rz:8.3f}  1.00  0.00    "
            f"    0.000 {atype}"
        )
    pdbqt_lines.append("ENDMDL")

with open(f"{meta_id}_vina_poses.pdbqt", "w") as f:
    f.write("\n".join(pdbqt_lines) + "\n")

# ---------------------------------------------------------------------------
# 3. Summary JSON
# ---------------------------------------------------------------------------
modes_summary = []
for mode_idx, energy in enumerate(energies, 1):
    modes_summary.append({
        "mode":           mode_idx,
        "affinity_kcal_mol": energy,
        "rmsd_lb":        round(random.uniform(0.0, 2.0), 3),
        "rmsd_ub":        round(random.uniform(2.0, 5.0), 3),
    })

summary = {
    "target":            meta_id,
    "ligand":            ligand,
    "tool":              "AutoDock Vina",
    "version":           "1.2.5",
    "pocket_centre_xyz": [cx, cy, cz],
    "pocket_anchor_residue": anchor,
    "box_size_angstrom": box_size,
    "exhaustiveness":    exhaustiveness,
    "num_modes":         num_modes,
    "best_affinity_kcal_mol": energies[0],
    "modes":             modes_summary,
    "timestamp":         datetime.utcnow().isoformat() + "Z",
    "mock_mode":         True,
}

with open(f"{meta_id}_vina_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"AutoDock Vina mock complete: {num_modes} binding modes")
print(f"  Pocket centre from PAE: ({cx}, {cy}, {cz}) A")
print(f"  Best affinity: {energies[0]} kcal/mol")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live AutoDock Vina
        # ---------------------------------------------------------------------------

        # 1. Extract pocket box from PAE
        python3 << 'PYEOF'
import json, math

pae_data = json.load(open("EGFR_kinase_pae.json"))
pae      = pae_data.get("pae", [])
N        = len(pae)

if N > 0:
    row_means = [sum(row) / N for row in pae]
    anchor    = row_means.index(min(row_means))
    angle     = math.radians(anchor * 100.0)
    cx        = round(2.3 * math.cos(angle), 3)
    cy        = round(2.3 * math.sin(angle), 3)
    cz        = round(anchor * 1.5, 3)
else:
    cx, cy, cz = 0.0, 0.0, 0.0

with open("pocket_params.json", "w") as f:
    json.dump({"center_x": cx, "center_y": cy, "center_z": cz, "size": 20.0}, f)
print(f"Pocket centre: ({cx}, {cy}, {cz})")
PYEOF

        CX=$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_x'])")
        CY=$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_y'])")
        CZ=$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_z'])")

        # 2. Prepare receptor PDBQT
        prepare_receptor4.py -r EGFR_kinase_structure.pdb -o receptor.pdbqt -A hydrogens

        # 3. Convert ligand SDF → PDBQT
        obabel mock_aspirin.sdf -O ligand.pdbqt --gen3d --partialcharge gasteiger

        # 4. Run Vina
        vina \
            --receptor receptor.pdbqt \
            --ligand   ligand.pdbqt \
            --center_x $CX \
            --center_y $CY \
            --center_z $CZ \
            --size_x   20 \
            --size_y   20 \
            --size_z   20 \
            --exhaustiveness 4 \
            --num_modes       3 \
            --out             EGFR_kinase_vina_poses.pdbqt \
            --log             vina.log

        # 5. Parse log → summary JSON
        python3 << 'PYEOF'
import json, re
from datetime import datetime

log_text = open("vina.log").read()
meta_id  = "EGFR_kinase"
modes    = []

for m in re.finditer(
        r'\s+(\d+)\s+([\-\d.]+)\s+([\-\d.]+)\s+([\-\d.]+)', log_text):
    modes.append({
        "mode":              int(m.group(1)),
        "affinity_kcal_mol": float(m.group(2)),
        "rmsd_lb":           float(m.group(3)),
        "rmsd_ub":           float(m.group(4)),
    })

pocket = json.load(open("pocket_params.json"))
summary = {
    "target":      meta_id,
    "ligand":      "mock_aspirin.sdf",
    "tool":        "AutoDock Vina",
    "pocket_centre_xyz": [pocket["center_x"], pocket["center_y"], pocket["center_z"]],
    "exhaustiveness": int("4"),
    "num_modes":   len(modes),
    "best_affinity_kcal_mol": modes[0]["affinity_kcal_mol"] if modes else None,
    "modes":       modes,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "mock_mode":   False,
}
with open(f"{meta_id}_vina_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(f"Vina live: {len(modes)} modes written.")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "STRUCTURE_PREDICTION_DOCKING:AUTODOCK_VINA_DOCKING":
        autodock_vina: "1.2.5"
        openbabel: $(obabel --version 2>&1 | head -1 | awk '{print $3}' || echo "N/A")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
    END_VERSIONS
