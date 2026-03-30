#!/bin/bash -ue
if [ "true" = "true" ] || [ "mock" = "mock" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

meta_id    = "EGFR_kinase"
target     = "EGFR kinase domain (mock)"

# ---------------------------------------------------------------------------
# 1. Generate a synthetic 100-residue alpha-helix PDB (CA trace + full backbone)
# ---------------------------------------------------------------------------
aa_one  = list("ACDEFGHIKLMNPQRSTVWYACDEFGHIKLMNPQRSTVWY" * 3)[:100]
aa_three = {
    'A':'ALA','C':'CYS','D':'ASP','E':'GLU','F':'PHE','G':'GLY','H':'HIS',
    'I':'ILE','K':'LYS','L':'LEU','M':'MET','N':'ASN','P':'PRO','Q':'GLN',
    'R':'ARG','S':'SER','T':'THR','V':'VAL','W':'TRP','Y':'TYR'
}

lines = [
    "REMARK  BioMate mock AlphaFold3 structure — synthetic alpha-helix",
    f"REMARK  Target: {target}",
    f"REMARK  Generated: {datetime.utcnow().isoformat()}Z",
    "REMARK  pTM=0.85  ipTM=0.82  ranking_score=0.87",
]
atom_idx = 1
for i, aa in enumerate(aa_one, 1):
    # Ideal alpha-helix geometry: rise=1.5 A/residue, radius=2.3 A, twist=100 deg/residue
    angle   = math.radians(i * 100.0)
    x_ca    = 2.3 * math.cos(angle)
    y_ca    = 2.3 * math.sin(angle)
    z_ca    = i * 1.5
    res3    = aa_three.get(aa, 'ALA')
    bfac    = round(random.uniform(10.0, 30.0), 2)

    # N  (approx offset from CA)
    x_n = x_ca - 0.50 * math.cos(angle + 0.5)
    y_n = y_ca - 0.50 * math.sin(angle + 0.5)
    z_n = z_ca - 0.85
    lines.append(
        f"ATOM  {atom_idx:5d}  N   {res3:3s} A{i:4d}    "
        f"{x_n:8.3f}{y_n:8.3f}{z_n:8.3f}  1.00 {bfac:5.2f}           N"
    )
    atom_idx += 1

    # CA
    lines.append(
        f"ATOM  {atom_idx:5d}  CA  {res3:3s} A{i:4d}    "
        f"{x_ca:8.3f}{y_ca:8.3f}{z_ca:8.3f}  1.00 {bfac:5.2f}           C"
    )
    atom_idx += 1

    # C
    x_c = x_ca + 0.48 * math.cos(angle - 0.4)
    y_c = y_ca + 0.48 * math.sin(angle - 0.4)
    z_c = z_ca + 0.85
    lines.append(
        f"ATOM  {atom_idx:5d}  C   {res3:3s} A{i:4d}    "
        f"{x_c:8.3f}{y_c:8.3f}{z_c:8.3f}  1.00 {bfac:5.2f}           C"
    )
    atom_idx += 1

    # O
    x_o = x_c + 1.22 * math.cos(angle + math.pi / 3)
    y_o = y_c + 1.22 * math.sin(angle + math.pi / 3)
    z_o = z_c
    lines.append(
        f"ATOM  {atom_idx:5d}  O   {res3:3s} A{i:4d}    "
        f"{x_o:8.3f}{y_o:8.3f}{z_o:8.3f}  1.00 {bfac:5.2f}           O"
    )
    atom_idx += 1

lines.append("END")

with open(f"{meta_id}_structure.pdb", "w") as f:
    f.write("\n".join(lines) + "\n")

# ---------------------------------------------------------------------------
# 2. Minimal mmCIF (PDBx format)
# ---------------------------------------------------------------------------
cif_lines = [
    f"data_{meta_id}",
    f"_entry.id {meta_id}",
    "_struct.title 'BioMate mock AlphaFold3 structure'",
    "# Coordinates omitted in mock mode — use PDB file for coordinates",
    "_ma_qa_metric_global.metric_id   1",
    "_ma_qa_metric_global.metric_value  0.85",
    "_ma_qa_metric_global.type        pTM",
    "# end",
]
with open(f"{meta_id}_structure.cif", "w") as f:
    f.write("\n".join(cif_lines) + "\n")

# ---------------------------------------------------------------------------
# 3. PAE matrix (100x100): low near diagonal, high off-diagonal
#    Typical AF3 output: values in Angstroms, max ~31.75 A
# ---------------------------------------------------------------------------
N = 100
pae = []
for i in range(N):
    row = []
    for j in range(N):
        dist    = abs(i - j)
        base    = min(dist * 0.25 + random.uniform(0, 0.5), 15.0)
        # add domain-like block structure (residues 0-49 / 50-99)
        if (i < 50) == (j < 50):
            base = max(base - 2.0, 0.1)
        row.append(round(base, 3))
    pae.append(row)

with open(f"{meta_id}_pae.json", "w") as f:
    json.dump({
        "pae": pae,
        "max_predicted_aligned_error": 31.75,
        "residue_count": N,
        "chain_breaks": []
    }, f)

# ---------------------------------------------------------------------------
# 4. Per-model confidence scores
# ---------------------------------------------------------------------------
scores = {
    "ptm":                0.85,
    "iptm":               0.82,
    "ranking_score":      0.87,
    "fraction_disordered":0.02,
    "has_clash":          False,
    "num_recycles":       10,
    "model_id":           f"{meta_id}_model_1",
    "mean_plddt":         84.7,
    "min_plddt":          52.3,
    "timestamp":          datetime.utcnow().isoformat() + "Z",
    "mock_mode":          True
}
with open(f"{meta_id}_af3_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

print(f"AlphaFold3 mock complete: {meta_id}_structure.pdb ({N} residues)")
print(f"  pTM={scores['ptm']}  ipTM={scores['iptm']}  ranking_score={scores['ranking_score']}")
EOF

    elif [ "mock" = "server" ]; then
        # ---------------------------------------------------------------------------
        # Live: AlphaFold3 server API
        # Requires AF3_API_TOKEN environment variable
        # ---------------------------------------------------------------------------
        SEQUENCE=$(grep -v '>' mock_EGFR_kinase.fasta | tr -d '\n')
        TOKEN=""
        if [ -z "$TOKEN" ]; then
            TOKEN="${AF3_API_TOKEN:-}"
        fi
        if [ -z "$TOKEN" ]; then
            echo "ERROR: AF3_API_TOKEN not set and params.af3_api_token not provided" >&2
            exit 1
        fi

        # Submit prediction job
        curl -sSf \
             -H "Authorization: Bearer $TOKEN" \
             -H "Content-Type: application/json" \
             -d "{
                   \"sequences\": [
                     {\"proteinChain\": {\"sequence\": \"$SEQUENCE\", \"count\": 1}}
                   ],
                   \"modelSeeds\": [42],
                   \"name\": \"EGFR_kinase\"
                 }" \
             https://alphafoldserver.com/api/prediction/create > af3_job.json

        JOB_NAME=$(python3 -c "import json,sys; print(json.load(open('af3_job.json'))['name'])")
        echo "Submitted AF3 job: $JOB_NAME"

        # Poll until state=SUCCEEDED (max 60 attempts × 30 s = 30 min)
        STATUS="PENDING"
        for ATTEMPT in $(seq 1 60); do
            sleep 30
            curl -sSf "https://alphafoldserver.com/api/prediction/$JOB_NAME" > af3_status.json
            STATUS=$(python3 -c "import json,sys; print(json.load(open('af3_status.json'))['state'])")
            echo "  Attempt $ATTEMPT/60 — status: $STATUS"
            if [ "$STATUS" = "SUCCEEDED" ]; then break; fi
            if [ "$STATUS" = "FAILED"    ]; then
                echo "AF3 job failed" >&2
                exit 1
            fi
        done

        # Download result files
        python3 << 'PYEOF'
import json, urllib.request, os

data  = json.load(open('af3_status.json'))
files = data.get('resultFiles', [])
meta_id = "EGFR_kinase"

for rf in files:
    name = rf.get('name', '')
    url  = rf.get('url', '')
    if not url:
        continue
    if '.cif' in name:
        urllib.request.urlretrieve(url, f'{meta_id}_structure.cif')
    elif 'pae' in name and name.endswith('.json'):
        urllib.request.urlretrieve(url, f'{meta_id}_pae.json')
    elif 'summary_confidences' in name:
        urllib.request.urlretrieve(url, f'{meta_id}_af3_scores.json')

# Convert CIF to minimal PDB if not already present
if os.path.exists(f'{meta_id}_structure.cif') and not os.path.exists(f'{meta_id}_structure.pdb'):
    # Minimal CIF→PDB stub; for production use gemmi or biopython
    with open(f'{meta_id}_structure.pdb', 'w') as f:
        f.write(f'REMARK converted from {meta_id}_structure.cif\n')
        f.write('END\n')

# Fallback: create empty JSON files if download failed
for fname in [f'{meta_id}_pae.json', f'{meta_id}_af3_scores.json']:
    if not os.path.exists(fname):
        with open(fname, 'w') as f:
            json.dump({}, f)

print('AF3 server results downloaded.')
PYEOF

    else
        # ---------------------------------------------------------------------------
        # Live: local AlphaFold3 model weights
        # ---------------------------------------------------------------------------
        python3 /opt/alphafold3/run_alphafold.py \
            --json_path mock_EGFR_kinase.fasta \
            --model_dir /opt/alphafold3/models \
            --output_dir af3_out/ \
            --num_recycles 10

        # Normalise output file names to BioMate convention
        python3 << 'PYEOF'
import os, shutil, glob, json

meta_id  = "EGFR_kinase"
af3_out  = "af3_out"

# AF3 local produces: *_cif, *_summary_confidences.json, *_full_data.json
for f in glob.glob(f"{af3_out}/**/*.cif", recursive=True):
    shutil.copy(f, f"{meta_id}_structure.cif")

for f in glob.glob(f"{af3_out}/**/*summary_confidences*.json", recursive=True):
    shutil.copy(f, f"{meta_id}_af3_scores.json")

for f in glob.glob(f"{af3_out}/**/*full_data*.json", recursive=True):
    # Extract PAE from full_data
    try:
        d = json.load(open(f))
        pae_data = {"pae": d.get("pae", []), "max_predicted_aligned_error": 31.75}
        with open(f"{meta_id}_pae.json", "w") as out:
            json.dump(pae_data, out)
    except Exception:
        pass

# Ensure PDB placeholder exists
if not os.path.exists(f"{meta_id}_structure.pdb"):
    with open(f"{meta_id}_structure.pdb", "w") as out:
        out.write(f"REMARK local AF3 — see {meta_id}_structure.cif for coordinates\nEND\n")

print("AF3 local outputs normalised.")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "STRUCTURE_PREDICTION_DOCKING:ALPHAFOLD3_STRUCTURE_PREDICTION":
        alphafold3: "3.0.0"
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        af3_mode: "mock"
        mock_mode: "true"
    END_VERSIONS
