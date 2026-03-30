#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json, math, random
from datetime import datetime

random.seed(42)
meta_id = "EGFR_kinase"

aa_one = list("ACDEFGHIKLMNPQRSTVWY" * 5)[:100]
aa_three = {'A':'ALA','C':'CYS','D':'ASP','E':'GLU','F':'PHE','G':'GLY','H':'HIS',
            'I':'ILE','K':'LYS','L':'LEU','M':'MET','N':'ASN','P':'PRO','Q':'GLN',
            'R':'ARG','S':'SER','T':'THR','V':'VAL','W':'TRP','Y':'TYR'}

lines = [
    "REMARK  BioMate mock Boltz-2 structure — synthetic alpha-helix",
    f"REMARK  Target: EGFR kinase domain (mock)",
    f"REMARK  Generated: {datetime.utcnow().isoformat()}Z",
    "REMARK  confidence=0.91  ptm=0.89  iptm=0.87",
]
atom_idx = 1
for i, aa in enumerate(aa_one, 1):
    angle = math.radians(i * 100.0)
    x_ca = 2.3 * math.cos(angle)
    y_ca = 2.3 * math.sin(angle)
    z_ca = i * 1.5
    res3 = aa_three.get(aa, 'ALA')
    bfac = round(random.uniform(8.0, 25.0), 2)
    lines.append(f"ATOM  {atom_idx:5d}  CA  {res3:3s} A{i:4d}    {x_ca:8.3f}{y_ca:8.3f}{z_ca:8.3f}  1.00 {bfac:5.2f}           C")
    atom_idx += 1
lines.append("END")

with open(f"{meta_id}_structure.pdb", "w") as f:
    f.write("\n".join(lines) + "\n")

cif_lines = [f"data_{meta_id}", f"_entry.id {meta_id}",
             "_struct.title 'BioMate mock Boltz-2 structure'",
             "_ma_qa_metric_global.metric_value 0.91",
             "_ma_qa_metric_global.type confidence"]
with open(f"{meta_id}_structure.cif", "w") as f:
    f.write("\n".join(cif_lines) + "\n")

N = 100
pae = [[round(min(abs(i-j)*0.22 + random.uniform(0,0.4), 14.0), 3) for j in range(N)] for i in range(N)]
with open(f"{meta_id}_pae.json", "w") as f:
    json.dump({"pae": pae, "max_predicted_aligned_error": 31.75, "residue_count": N}, f)

scores = {
    "confidence":         0.91,
    "ptm":                0.89,
    "iptm":               0.87,
    "complex_plddt":      88.3,
    "mean_plddt":         87.1,
    "model_id":           f"{meta_id}_boltz2_model_0",
    "boltz2_mode":        "local",
    "timestamp":          datetime.utcnow().isoformat() + "Z",
    "tool":               "boltz2",
    "mock_mode":          True,
}
with open(f"{meta_id}_boltz2_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

print(f"Boltz-2 mock complete: {meta_id}_structure.pdb (100 residues)")
print(f"  confidence={scores['confidence']}  ptm={scores['ptm']}")
EOF

    elif [ "local" = "nim_api" ]; then
        # ---------------------------------------------------------------------------
        # Live: NVIDIA NIM API for Boltz-2
        # ---------------------------------------------------------------------------
        API_KEY=""
        if [ -z "$API_KEY" ]; then API_KEY="${NVIDIA_NIM_API_KEY:-}"; fi
        if [ -z "$API_KEY" ]; then
            echo "ERROR: NVIDIA_NIM_API_KEY not set for Boltz-2 NIM mode" >&2
            exit 1
        fi
        SEQUENCE=$(grep -v '>' mock_EGFR_kinase.fasta | tr -d '\n')

        curl -sSf \
             -H "Authorization: Bearer $API_KEY" \
             -H "Content-Type: application/json" \
             -d "{"sequence": "$SEQUENCE", "num_samples": 1}" \
             https://health.api.nvidia.com/v1/biology/boltz/predict > boltz2_result.json

        python3 << 'PYEOF'
import json, os
from datetime import datetime

meta_id = "EGFR_kinase"
result  = json.load(open("boltz2_result.json"))

# Extract CIF / PDB from NIM response
cif_data = result.get("structure_cif", "")
with open(f"{meta_id}_structure.cif", "w") as f:
    f.write(cif_data if cif_data else f"data_{meta_id}\n_entry.id {meta_id}\n")

if not os.path.exists(f"{meta_id}_structure.pdb"):
    with open(f"{meta_id}_structure.pdb", "w") as f:
        f.write(f"REMARK NIM Boltz-2 — see {meta_id}_structure.cif\nEND\n")

pae_raw = result.get("pae", [])
with open(f"{meta_id}_pae.json", "w") as f:
    json.dump({"pae": pae_raw, "max_predicted_aligned_error": 31.75}, f)

scores = {
    "confidence":  result.get("confidence",   None),
    "ptm":         result.get("ptm",          None),
    "iptm":        result.get("iptm",         None),
    "model_id":    f"{meta_id}_boltz2_nim",
    "boltz2_mode": "nim_api",
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "tool":        "boltz2",
    "mock_mode":   False,
}
with open(f"{meta_id}_boltz2_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

print(f"Boltz-2 NIM API complete.")
PYEOF

    else
        # ---------------------------------------------------------------------------
        # Live: local Boltz-2 weights
        # ---------------------------------------------------------------------------
        boltz predict mock_EGFR_kinase.fasta \
            --out_dir boltz2_out \
            --checkpoint /opt/boltz2/weights \
            --use_msa_server

        python3 << 'PYEOF'
import json, glob, shutil, os
from datetime import datetime

meta_id  = "EGFR_kinase"
out_dir  = "boltz2_out"

for f in glob.glob(f"{out_dir}/**/*.cif", recursive=True):
    shutil.copy(f, f"{meta_id}_structure.cif")
    break

if not os.path.exists(f"{meta_id}_structure.pdb"):
    with open(f"{meta_id}_structure.pdb", "w") as fh:
        fh.write(f"REMARK local Boltz-2 — see {meta_id}_structure.cif\nEND\n")

# Load confidence JSON produced by boltz
conf_files = glob.glob(f"{out_dir}/**/*confidence*.json", recursive=True)
conf = json.load(open(conf_files[0])) if conf_files else {}

pae_files = glob.glob(f"{out_dir}/**/*pae*.npy", recursive=True)
pae_list = []
if pae_files:
    import numpy as np
    arr = np.load(pae_files[0])
    pae_list = arr.tolist()
with open(f"{meta_id}_pae.json", "w") as fh:
    json.dump({"pae": pae_list, "max_predicted_aligned_error": 31.75}, fh)

scores = {
    "confidence":  conf.get("confidence", None),
    "ptm":         conf.get("ptm",        None),
    "iptm":        conf.get("iptm",       None),
    "model_id":    f"{meta_id}_boltz2_local",
    "boltz2_mode": "local",
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "tool":        "boltz2",
    "mock_mode":   False,
}
with open(f"{meta_id}_boltz2_scores.json", "w") as fh:
    json.dump(scores, fh, indent=2)

print(f"Boltz-2 local complete.")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "STRUCTURE_PREDICTION_DOCKING:BOLTZ2_STRUCTURE_PREDICTION":
        boltz2: "2.0.0"
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        boltz2_mode: "local"
        mock_mode: "true"
    END_VERSIONS
