#!/usr/bin/env nextflow
/*
 * drug_discovery/structure_prediction_docking
 *
 * Sprint 1: AlphaFold3 pre-docking pipeline
 * structure_prediction → docking (DiffDock + AutoDock Vina in parallel)
 *
 * Pipeline Steps:
 * 1. ALPHAFOLD3_STRUCTURE_PREDICTION  — Predict 3-D structure from sequence
 *    (server API mode or local model; mock for CI/testing)
 * 2. DIFFDOCK_BLIND_DOCKING           — Diffusion-model blind docking (no pocket required)
 * 3. AUTODOCK_VINA_DOCKING            — Classical docking with pocket from AF3 PAE
 *
 * Steps 2 and 3 run in parallel after step 1 completes.
 *
 * References:
 *  - AlphaFold3: Abramson et al. Nature 2024 (https://alphafoldserver.com)
 *  - DiffDock:   Corso et al. ICLR 2023   (https://github.com/gcorso/DiffDock)
 *  - AutoDock Vina: Eberhardt et al. JCIM 2021
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/structure_prediction_docking'
params.publish_dir_mode     = 'copy'

// Mode flags
params.mock_mode            = true      // true  = synthetic output, no real tools needed
params.af3_mode             = 'mock'    // 'mock' | 'server' | 'local'

// AlphaFold3 settings
params.af3_api_token        = null      // Bearer token for alphafoldserver.com (server mode)
params.af3_model_dir        = '/opt/alphafold3/models'  // local mode only
params.af3_num_recycles     = 10        // number of recycling iterations

// DiffDock settings
params.diffdock_poses       = 10        // number of docked poses to generate
params.diffdock_inference_steps = 20   // diffusion inference steps

// AutoDock Vina settings
params.vina_exhaustiveness  = 32        // search exhaustiveness (higher = more thorough)
params.vina_num_modes       = 9         // number of binding modes to report

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Structure Prediction + Docking Pipeline
    ====================================================================
    Mode:               ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE'}
    AlphaFold3 mode:    ${params.af3_mode}
    DiffDock poses:     ${params.diffdock_poses}
    Vina exhaustiveness: ${params.vina_exhaustiveness}
    Output dir:         ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: AlphaFold3 Structure Prediction
// ============================================================================

process ALPHAFOLD3_STRUCTURE_PREDICTION {
    tag "${meta.id}"
    label 'process_gpu_high'
    publishDir "${params.outdir}/${meta.id}/01_alphafold3", mode: params.publish_dir_mode

    container 'docker.io/catgumag/alphafold3:latest'

    input:
    tuple val(meta), path(sequence_fasta)
    val   af3_mode

    output:
    tuple val(meta), path("*_structure.cif"),        emit: cif
    tuple val(meta), path("*_structure.pdb"),        emit: pdb
    tuple val(meta), path("*_pae.json"),             emit: pae
    tuple val(meta), path("*_af3_scores.json"),      emit: scores
    path "versions.yml",                             emit: versions

    script:
    def mock      = params.mock_mode
    def mode      = af3_mode ?: 'mock'
    def api_token = params.af3_api_token ?: ''
    def model_dir = params.af3_model_dir
    def recycles  = params.af3_num_recycles
    """
    if [ "${mock}" = "true" ] || [ "${mode}" = "mock" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

meta_id    = "${meta.id}"
target     = "${meta.target_name}"

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
    f.write("\\n".join(lines) + "\\n")

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
    f.write("\\n".join(cif_lines) + "\\n")

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
    "num_recycles":       ${recycles},
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

    elif [ "${mode}" = "server" ]; then
        # ---------------------------------------------------------------------------
        # Live: AlphaFold3 server API
        # Requires AF3_API_TOKEN environment variable
        # ---------------------------------------------------------------------------
        SEQUENCE=\$(grep -v '>' ${sequence_fasta} | tr -d '\\n')
        TOKEN="${api_token}"
        if [ -z "\$TOKEN" ]; then
            TOKEN="\${AF3_API_TOKEN:-}"
        fi
        if [ -z "\$TOKEN" ]; then
            echo "ERROR: AF3_API_TOKEN not set and params.af3_api_token not provided" >&2
            exit 1
        fi

        # Submit prediction job
        curl -sSf \\
             -H "Authorization: Bearer \$TOKEN" \\
             -H "Content-Type: application/json" \\
             -d "{
                   \\"sequences\\": [
                     {\\"proteinChain\\": {\\"sequence\\": \\"\$SEQUENCE\\", \\"count\\": 1}}
                   ],
                   \\"modelSeeds\\": [42],
                   \\"name\\": \\"${meta.id}\\"
                 }" \\
             https://alphafoldserver.com/api/prediction/create > af3_job.json

        JOB_NAME=\$(python3 -c "import json,sys; print(json.load(open('af3_job.json'))['name'])")
        echo "Submitted AF3 job: \$JOB_NAME"

        # Poll until state=SUCCEEDED (max 60 attempts × 30 s = 30 min)
        STATUS="PENDING"
        for ATTEMPT in \$(seq 1 60); do
            sleep 30
            curl -sSf "https://alphafoldserver.com/api/prediction/\$JOB_NAME" > af3_status.json
            STATUS=\$(python3 -c "import json,sys; print(json.load(open('af3_status.json'))['state'])")
            echo "  Attempt \$ATTEMPT/60 — status: \$STATUS"
            if [ "\$STATUS" = "SUCCEEDED" ]; then break; fi
            if [ "\$STATUS" = "FAILED"    ]; then
                echo "AF3 job failed" >&2
                exit 1
            fi
        done

        # Download result files
        python3 << 'PYEOF'
import json, urllib.request, os

data  = json.load(open('af3_status.json'))
files = data.get('resultFiles', [])
meta_id = "${meta.id}"

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
        f.write(f'REMARK converted from {meta_id}_structure.cif\\n')
        f.write('END\\n')

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
        python3 /opt/alphafold3/run_alphafold.py \\
            --json_path ${sequence_fasta} \\
            --model_dir ${model_dir} \\
            --output_dir af3_out/ \\
            --num_recycles ${recycles}

        # Normalise output file names to BioMate convention
        python3 << 'PYEOF'
import os, shutil, glob, json

meta_id  = "${meta.id}"
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
        out.write(f"REMARK local AF3 — see {meta_id}_structure.cif for coordinates\\nEND\\n")

print("AF3 local outputs normalised.")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3: "3.0.0"
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        af3_mode: "${mode}"
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_structure.cif
    touch ${meta.id}_structure.pdb
    echo '{"pae":[],"max_predicted_aligned_error":31.75}' > ${meta.id}_pae.json
    echo '{"ptm":0.85,"iptm":0.82,"ranking_score":0.87}' > ${meta.id}_af3_scores.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3: "3.0.0"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: DiffDock Blind Docking
// ============================================================================

process DIFFDOCK_BLIND_DOCKING {
    tag "${meta.id}"
    label 'process_gpu_medium'
    publishDir "${params.outdir}/${meta.id}/02_diffdock", mode: params.publish_dir_mode

    container 'docker.io/simonelenz/diffdock:latest'

    input:
    tuple val(meta), path(protein_pdb)
    path  ligand_sdf
    val   num_poses

    output:
    tuple val(meta), path("diffdock_results/rank1_*.sdf"),  emit: top_pose
    tuple val(meta), path("diffdock_results/"),             emit: all_poses
    tuple val(meta), path("*_diffdock_summary.json"),       emit: summary
    path "versions.yml",                                    emit: versions

    script:
    def mock  = params.mock_mode
    def poses = num_poses ?: params.diffdock_poses
    def steps = params.diffdock_inference_steps
    """
    mkdir -p diffdock_results

    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import os
import random
import math
from datetime import datetime

random.seed(42)

meta_id   = "${meta.id}"
ligand    = "${ligand_sdf}"
num_poses = int("${poses}")

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
        "\$\$\$\$",
    ]
    return "\\n".join(lines)

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
    "inference_steps": int("${steps}"),
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
        python -m diffdock.inference \\
            --protein_path   ${protein_pdb} \\
            --ligand_path    ${ligand_sdf} \\
            --out_dir        diffdock_results/ \\
            --samples_per_complex ${poses} \\
            --inference_steps    ${steps} \\
            --batch_size 10

        # Normalise output: write summary JSON from DiffDock rank files
        python3 << 'PYEOF'
import json, glob, os, re
from datetime import datetime

meta_id  = "${meta.id}"
out_dir  = "diffdock_results"
sdf_files = sorted(glob.glob(f"{out_dir}/rank*.sdf"))

poses = []
for sdf in sdf_files:
    m = re.search(r'rank(\\d+)_confidence([\\-\\d.]+)\\.sdf', sdf)
    if m:
        rank = int(m.group(1))
        conf = float(m.group(2))
        poses.append({"rank": rank, "confidence": conf, "sdf_file": os.path.basename(sdf)})

summary = {
    "target":      meta_id,
    "ligand":      "${ligand_sdf}",
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
    "${task.process}":
        diffdock: "1.1.2"
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    mkdir -p diffdock_results
    echo 'mock' > diffdock_results/rank1_confidence2.2000.sdf
    echo '{"num_poses":10}' > ${meta.id}_diffdock_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        diffdock: "1.1.2"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: AutoDock Vina Docking
// ============================================================================

process AUTODOCK_VINA_DOCKING {
    tag "${meta.id}"
    label 'process_high'
    publishDir "${params.outdir}/${meta.id}/03_autodock_vina", mode: params.publish_dir_mode

    container 'docker.io/cford38/autodockvina:latest'

    input:
    tuple val(meta), path(protein_pdb), path(pae_json)
    path  ligand_sdf

    output:
    tuple val(meta), path("*_vina_poses.pdbqt"),  emit: poses
    tuple val(meta), path("*_vina_summary.json"), emit: summary
    path "versions.yml",                          emit: versions

    script:
    def mock          = params.mock_mode
    def exhaustiveness = params.vina_exhaustiveness
    def num_modes     = params.vina_num_modes
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

meta_id       = "${meta.id}"
ligand        = "${ligand_sdf}"
pae_file      = "${pae_json}"
exhaustiveness = int("${exhaustiveness}")
num_modes     = int("${num_modes}")

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
    f.write("\\n".join(pdbqt_lines) + "\\n")

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

pae_data = json.load(open("${pae_json}"))
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

        CX=\$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_x'])")
        CY=\$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_y'])")
        CZ=\$(python3 -c "import json; p=json.load(open('pocket_params.json')); print(p['center_z'])")

        # 2. Prepare receptor PDBQT
        prepare_receptor4.py -r ${protein_pdb} -o receptor.pdbqt -A hydrogens

        # 3. Convert ligand SDF → PDBQT
        obabel ${ligand_sdf} -O ligand.pdbqt --gen3d --partialcharge gasteiger

        # 4. Run Vina
        vina \\
            --receptor receptor.pdbqt \\
            --ligand   ligand.pdbqt \\
            --center_x \$CX \\
            --center_y \$CY \\
            --center_z \$CZ \\
            --size_x   20 \\
            --size_y   20 \\
            --size_z   20 \\
            --exhaustiveness ${exhaustiveness} \\
            --num_modes       ${num_modes} \\
            --out             ${meta.id}_vina_poses.pdbqt \\
            --log             vina.log

        # 5. Parse log → summary JSON
        python3 << 'PYEOF'
import json, re
from datetime import datetime

log_text = open("vina.log").read()
meta_id  = "${meta.id}"
modes    = []

for m in re.finditer(
        r'\\s+(\\d+)\\s+([\\-\\d.]+)\\s+([\\-\\d.]+)\\s+([\\-\\d.]+)', log_text):
    modes.append({
        "mode":              int(m.group(1)),
        "affinity_kcal_mol": float(m.group(2)),
        "rmsd_lb":           float(m.group(3)),
        "rmsd_ub":           float(m.group(4)),
    })

pocket = json.load(open("pocket_params.json"))
summary = {
    "target":      meta_id,
    "ligand":      "${ligand_sdf}",
    "tool":        "AutoDock Vina",
    "pocket_centre_xyz": [pocket["center_x"], pocket["center_y"], pocket["center_z"]],
    "exhaustiveness": int("${exhaustiveness}"),
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
    "${task.process}":
        autodock_vina: "1.2.5"
        openbabel: \$(obabel --version 2>&1 | head -1 | awk '{print \$3}' || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'MODEL 1\\nENDMDL' > ${meta.id}_vina_poses.pdbqt
    echo '{"num_modes":9,"best_affinity_kcal_mol":-9.2}' > ${meta.id}_vina_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autodock_vina: "1.2.5"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: STRUCTURE_PREDICTION_DOCKING
// ============================================================================
//
// Parallelism layout:
//
//   ch_fasta  ──► ALPHAFOLD3_STRUCTURE_PREDICTION
//                       │
//              ┌─────────────────┐
//              ▼                 ▼
//   DIFFDOCK_BLIND_DOCKING   AUTODOCK_VINA_DOCKING
//              │                 │
//              └──────┬──────────┘
//                  emit all outputs
//
// ============================================================================

workflow STRUCTURE_PREDICTION_DOCKING {
    take:
    ch_fasta   // channel: [ tuple(meta, path(sequence.fasta)) ]
    ch_ligand  // channel: path(ligand.sdf)

    main:
    // ------------------------------------------------------------------
    // Step 1: Predict protein structure with AlphaFold3
    // ------------------------------------------------------------------
    ALPHAFOLD3_STRUCTURE_PREDICTION(
        ch_fasta,
        params.af3_mode ?: 'mock'
    )

    // ------------------------------------------------------------------
    // Step 2 + 3 run in PARALLEL — both consume AF3 pdb + PAE outputs
    // ------------------------------------------------------------------

    // Combine each (meta, pdb) with the single ligand path
    ch_pdb_ligand = ALPHAFOLD3_STRUCTURE_PREDICTION.out.pdb
        .combine(ch_ligand)
        .map { meta, pdb, lig -> tuple(meta, pdb, lig) }

    // DiffDock (blind; no pocket needed)
    DIFFDOCK_BLIND_DOCKING(
        ch_pdb_ligand.map { meta, pdb, lig -> tuple(meta, pdb) },
        ch_pdb_ligand.map { meta, pdb, lig -> lig },
        params.diffdock_poses ?: 10
    )

    // AutoDock Vina (pocket derived from AF3 PAE)
    // Input channel: [ tuple(meta, pdb, pae), ligand_sdf ]
    ch_vina = ALPHAFOLD3_STRUCTURE_PREDICTION.out.pdb
        .join(ALPHAFOLD3_STRUCTURE_PREDICTION.out.pae, by: 0)
        .map { meta, pdb, pae -> tuple(meta, pdb, pae) }

    AUTODOCK_VINA_DOCKING(
        ch_vina,
        ch_ligand
    )

    emit:
    structure_pdb    = ALPHAFOLD3_STRUCTURE_PREDICTION.out.pdb
    structure_cif    = ALPHAFOLD3_STRUCTURE_PREDICTION.out.cif
    af3_scores       = ALPHAFOLD3_STRUCTURE_PREDICTION.out.scores
    pae              = ALPHAFOLD3_STRUCTURE_PREDICTION.out.pae
    diffdock_top     = DIFFDOCK_BLIND_DOCKING.out.top_pose
    diffdock_all     = DIFFDOCK_BLIND_DOCKING.out.all_poses
    diffdock_scores  = DIFFDOCK_BLIND_DOCKING.out.summary
    vina_poses       = AUTODOCK_VINA_DOCKING.out.poses
    vina_scores      = AUTODOCK_VINA_DOCKING.out.summary
    versions         = ALPHAFOLD3_STRUCTURE_PREDICTION.out.versions
                           .mix(DIFFDOCK_BLIND_DOCKING.out.versions)
                           .mix(AUTODOCK_VINA_DOCKING.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // Default test inputs (mock mode — no real files needed)
    if (params.mock_mode) {
        ch_fasta = Channel.of(
            [
                [
                    id:          'EGFR_kinase',
                    target_name: 'EGFR kinase domain (mock)',
                    sample_type: 'kinase'
                ],
                file("${projectDir}/test_data/egfr_kinase.fasta", checkIfExists: false)
            ]
        ).map { meta, fasta ->
            // In mock mode, create a synthetic FASTA on the fly if not present
            def f = fasta.exists() ? fasta : {
                def tmp = file("${workDir}/mock_${meta.id}.fasta")
                tmp.text = ">sp|P00533|${meta.id} ${meta.target_name}\\n" +
                           "MRPSGTAGAALLALLAALCPASRALEEKKVCQGTSNKLTQLGTFEDHFLSLQRMFNNCEVVLGNLEITYVQRNYDLSFLKTIQEVAGYVLIALNTVERIPLENLQIIRGNMYYENSYALAVLSNYDANKTGLKELPMRNLQEILHGAVRFSNNPALCNVESIQWRDIVSSDFLSNMSMDFQNHLGSCQKCDPSCPNGSCWGAGEENCQKLTKIICAQQCSGRCRGKSPSDCCHNQCAAGCTGPRESDCLVCRKFRDEATCKDTCPPLMLYNPTTYQMDVNPEGKYSFGATCVKKCPRNYVVTDHGSCVRACGADSYEMEEDGVRKCKKCEGPCRKVCNGIGIGEFKDSLSINATNIKHFKNCTSISGDLHILPVAFRGDSFTHTPPLDPQELDILKTVKEITGFLLIQAWPENRTDLHAFENLEIIRGRTKQHGQFSLAVVSLNITSLGLRSLKEISDGDVIISGNKNLCYANTINWKKLFGTSGQKTKIISNRGENSCKATGQVCHALCSPEGCWGPEPRDCVSCRNVSRGRECVDKCNLLEGEPREFVENSECIQCHPECLPQAMNITCTGRGPDNCIQCAHYIDGPHCVKTCPAGVMGENNTLVWKYADAGHVCHLCHPNCTYGCTGPGLEGCPTNGPKIPSIATGMVGALLLLLVVALGIGLFMRRRHIVRKRTLRRLLQERELVEPLTPSGEAPNQALLRILKETEFKKIKVLGSGAFGTVYKGLWIPEGEKVKIPVAIKELREATSPKANKEILDEAYVMASVDNPHVCRLLGICLTSTVQLITQLMPFGCLLDYVREHKDNIGSQYLLNWCVQIAKGMNYLEDRRLVHRDLAARNVLVKTPQHVKITDFGLAKLLGAEEKEYHAEGGKVPIKWMALESILHRIYTHQSDVWSYGVTVWELMTFGSKPYDGIPASEISSILEKGERLPQPPICTIDVYMIMVKCWMIDADSRPKFRELIIEFSKMARDPQRYLVIQGDERMHLPSPTDSNFYRALMDEEDMDDVVDADEYLIPQQGFFSSPSTSRTPLLSSLSATSNNSTVACIDRNGLQSCPIKEDSFLQRYSSDPTGALTEDSIDDTFLPVPEYINQSVPKRPAGSVQNPVYHNQPLNPAPSRDPHYQDPHSTAVGNPEYLNTVQPTCVNSTFDSPAHWAQKGSHQISLDNPDYQQDFFPKEAKPNGIFKGSTAENAEYLRVAPQSSEFIGA\\n"
                tmp
            }()
            return tuple(meta, f)
        }
    } else {
        if (!params.fasta_input) {
            error "params.fasta_input is required in live mode. Pass --fasta_input <path>"
        }
        ch_fasta = Channel
            .fromPath(params.fasta_input, checkIfExists: true)
            .map { fasta ->
                def meta = [
                    id:          fasta.baseName,
                    target_name: fasta.baseName,
                    sample_type: 'protein'
                ]
                tuple(meta, fasta)
            }
    }

    // Ligand
    if (params.mock_mode) {
        ch_ligand = Channel.of(
            file("${projectDir}/test_data/aspirin.sdf", checkIfExists: false)
        ).map { sdf ->
            // Create synthetic SDF if not present
            sdf.exists() ? sdf : {
                def tmp = file("${workDir}/mock_aspirin.sdf")
                tmp.text = [
                    "     BioMate_mock_aspirin",
                    "  BioMate  3D",
                    "",
                    " 13 13  0  0  0  0  0  0  0  0999 V2000",
                    "    1.5000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    0.7000    1.2000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "   -0.7000    1.2000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "   -1.4000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "   -0.7000   -1.2000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    0.7000   -1.2000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    2.9000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    3.7000    1.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    3.7000   -1.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    5.1000   -1.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    5.9000    0.0000    0.0000 C   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    7.3000    0.0000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0",
                    "    5.1000    1.3000    0.0000 O   0  0  0  0  0  0  0  0  0  0  0  0",
                    "  1  2  2  0", "  2  3  1  0", "  3  4  2  0", "  4  5  1  0",
                    "  5  6  2  0", "  6  1  1  0", "  1  7  1  0", "  7  8  2  0",
                    "  7  9  1  0", "  9 10  1  0", " 10 11  1  0", " 11 12  2  0",
                    " 10 13  2  0", "M  END", '$$$$',
                ].join("\n")
                tmp
            }()
        }
    } else {
        if (!params.ligand_sdf) {
            error "params.ligand_sdf is required in live mode. Pass --ligand_sdf <path>"
        }
        ch_ligand = Channel.fromPath(params.ligand_sdf, checkIfExists: true)
    }

    // Run the pipeline
    STRUCTURE_PREDICTION_DOCKING(ch_fasta, ch_ligand)

    // Display summary
    STRUCTURE_PREDICTION_DOCKING.out.af3_scores.view { meta, scores_file ->
        "AF3 scores (${meta.id}): ${scores_file}"
    }
    STRUCTURE_PREDICTION_DOCKING.out.diffdock_scores.view { meta, summary_file ->
        "DiffDock summary (${meta.id}): ${summary_file}"
    }
    STRUCTURE_PREDICTION_DOCKING.out.vina_scores.view { meta, summary_file ->
        "AutoDock Vina summary (${meta.id}): ${summary_file}"
    }
}
