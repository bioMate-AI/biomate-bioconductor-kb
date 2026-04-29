// Cryo-EM Conformational Heterogeneity Analysis
// Uses cryoDRGN (MIT VAE) to resolve continuous heterogeneity in cryo-EM particle stacks
// then scans reconstructed conformational states for druggable pockets via fpocket

nextflow.enable.dsl=2

// -----------------------------------------------------------------------------
// PROCESS 1: Train cryoDRGN VAE on particle stack
// -----------------------------------------------------------------------------
process CRYODRGN_TRAIN {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-heterogeneity-nf:latest'

    input:
    tuple val(meta), path(particles_mrcs)
    path ctf_pkl
    path poses_pkl
    val n_zdim
    val n_epochs

    output:
    tuple val(meta), path("cryodrgn_output/"), emit: model_dir
    path "versions.yml",                       emit: versions

    script:
    def prefix  = task.ext.prefix ?: "${meta.id}"
    def zdim    = n_zdim  ?: 8
    def epochs  = n_epochs ?: 20
    """
    echo "Starting cryoDRGN VAE training"
    echo "  Particles: ${particles_mrcs}"
    echo "  CTF:       ${ctf_pkl}"
    echo "  Poses:     ${poses_pkl}"
    echo "  z-dim:     ${zdim}   epochs: ${epochs}"

    # Reserialize CTF pkl for cross-version compatibility
    python3 - << 'PYEOF'
import pickle, numpy as np, os

# ctf: cryodrgn 4.x expects raw (N, 9) ndarray
with open("${ctf_pkl}", "rb") as fh:
    raw_ctf = pickle.load(fh)
ctf_arr = np.array(raw_ctf, dtype=np.float32)
with open("ctf_compat.pkl", "wb") as fh:
    pickle.dump(ctf_arr, fh)
print(f"ctf_compat.pkl: shape={ctf_arr.shape}")

# poses: reserialized only if provided
poses_file = "${poses_pkl}".strip()
if poses_file and os.path.isfile(poses_file):
    with open(poses_file, "rb") as fh:
        raw = pickle.load(fh)
    rots  = np.array(raw[0], dtype=np.float32)
    trans = np.array(raw[1], dtype=np.float32)
    with open("poses_compat.pkl", "wb") as fh:
        pickle.dump((rots, trans), fh)
    print(f"poses_compat.pkl: rots={rots.shape} trans={trans.shape}")
    open("HAS_POSES", "w").close()
else:
    print("No poses provided — will use abinit_het mode")
PYEOF

    if [ -f HAS_POSES ]; then
        echo "Training with poses (train_vae mode)"
        cryodrgn train_vae \\
            ${particles_mrcs} \\
            --ctf ctf_compat.pkl \\
            --poses poses_compat.pkl \\
            -n ${epochs} \\
            --zdim ${zdim} \\
            -o cryodrgn_output/ \\
            --no-amp \\
            --log-interval 5
    else
        echo "Training ab initio (abinit_het mode — no poses required)"
        cryodrgn abinit_het \\
            ${particles_mrcs} \\
            --ctf ctf_compat.pkl \\
            -n ${epochs} \\
            --zdim ${zdim} \\
            -o cryodrgn_output/ \\
            --log-interval 5
    fi

    echo "Training complete. Epochs saved in cryodrgn_output/"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cryodrgn: \$(python -c "import cryodrgn; print(cryodrgn.__version__)")
        torch: \$(python -c "import torch; print(torch.__version__)")
    END_VERSIONS
    """
}

// -----------------------------------------------------------------------------
// PROCESS 2: Analyze latent space — UMAP + k-means → representative volumes
// -----------------------------------------------------------------------------
process CRYODRGN_ANALYZE {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-heterogeneity-nf:latest'

    input:
    tuple val(meta), path(model_dir)
    path ctf_pkl
    val epoch
    val n_clusters

    output:
    tuple val(meta), path("cryodrgn_output/analyze.*"), emit: analysis_dir
    path "versions.yml",                                emit: versions

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def clusters = n_clusters ?: 10
    """
    # Determine the epoch to analyze (case avoids single-quote Groovy tokenizer issues)
    case "${epoch}" in
        [0-9]*) EPOCH="${epoch}";;
        *) EPOCH=\$(ls ${model_dir}/weights.*.pkl 2>/dev/null \\
                    | sort -V | tail -1 \\
                    | grep -oE [0-9]+[.] | grep -oE [0-9]+ || echo 4);;
    esac

    echo "Analyzing cryoDRGN output at epoch \${EPOCH} with ${clusters} clusters"

    # Patch the training config to point CTF to a local compat file.
    # cryodrgn analyze reads the CTF path from config.yaml — the original
    # path (from the TRAIN container) no longer exists in this container.
    python3 - << 'PYEOF'
import pickle, json, os, yaml
import numpy as np

# Convert ctf pkl to numpy array (handles both list-of-lists and old dict format)
with open("${ctf_pkl}", "rb") as fh:
    raw = pickle.load(fh)
if isinstance(raw, dict):
    ctf_arr = np.array(raw["ctf"], dtype=np.float32)
else:
    ctf_arr = np.array(raw, dtype=np.float32)
with open("ctf_compat.pkl", "wb") as fh:
    pickle.dump(ctf_arr, fh)
print(f"ctf_compat.pkl: shape={ctf_arr.shape}")

# Patch config.yaml inside model_dir so cryodrgn analyze finds the CTF
cfg_path = "${model_dir}/config.yaml"
if os.path.exists(cfg_path):
    with open(cfg_path) as fh:
        cfg = yaml.safe_load(fh)
    cfg.setdefault("dataset_args", {})["ctf"] = os.path.abspath("ctf_compat.pkl")
    with open(cfg_path, "w") as fh:
        yaml.dump(cfg, fh)
    print(f"Patched {cfg_path} -> ctf={os.path.abspath('ctf_compat.pkl')}")
else:
    print(f"WARNING: {cfg_path} not found; cryodrgn analyze may fail")
PYEOF

    cryodrgn analyze \\
        ${model_dir} \\
        \${EPOCH} \\
        --ksample ${clusters}

    echo "Analysis complete."
    echo "Output dir: ${model_dir}/analyze.\${EPOCH}/"

    # Verify analysis directory exists and volumes were generated
    ls "${model_dir}/analyze.\${EPOCH}/" || { echo "ERROR: analyze.\${EPOCH}/ directory not found"; exit 1; }
    NVOLS=\$(ls "${model_dir}/analyze.\${EPOCH}/kmeans"*/vol_*.mrc 2>/dev/null | wc -l)
    echo "Found \${NVOLS} reconstructed volumes"
    [ "\${NVOLS}" -gt 0 ] || { echo "ERROR: no vol_*.mrc found in analyze.\${EPOCH}/kmeans*/"; exit 1; }
    # umap.png is generated by the Jupyter notebook; non-fatal if absent
    ls "${model_dir}/analyze.\${EPOCH}/umap.png" 2>/dev/null && echo "UMAP plot present" || echo "INFO: umap.png not found (notebook may not have run)"

    python3 -c "
import cryodrgn, umap, sklearn
print('${task.process}:')
print('    cryodrgn: ' + cryodrgn.__version__)
print('    umap_learn: ' + umap.__version__)
print('    scikit_learn: ' + sklearn.__version__)
" > versions.yml
    """
}

// -----------------------------------------------------------------------------
// PROCESS 3: Scan conformational ensemble for druggable pockets
// -----------------------------------------------------------------------------
process POCKET_SCAN_ENSEMBLE {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-heterogeneity-nf:latest'

    input:
    tuple val(meta), path(analysis_dir)

    output:
    tuple val(meta), path("ensemble_pockets.json"), emit: pockets
    path "versions.yml",                            emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    python3 << 'PYEOF'
import os
import sys
import json
import glob
import subprocess
import tempfile
import traceback

try:
    import mrcfile
    import numpy as np
except ImportError as e:
    print(f"ERROR: missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

def mrc_density_to_pseudo_pdb(mrc_path, out_pdb, threshold_percentile=80):
    '''
    Convert MRC density map to a pseudo-PDB by placing C-alpha atoms at
    high-density voxel centres. fpocket requires a PDB input.
    '''
    with mrcfile.open(mrc_path, mode='r', permissive=True) as mrc:
        data = mrc.data.astype(np.float32)
        vsize = mrc.voxel_size          # Angstrom/voxel (Å)
        origin = np.array([mrc.header.origin.x,
                            mrc.header.origin.y,
                            mrc.header.origin.z], dtype=np.float32)

    threshold = np.percentile(data, threshold_percentile)
    zz, yy, xx = np.where(data > threshold)

    vx = float(vsize.x) if vsize.x != 0 else 1.0
    vy = float(vsize.y) if vsize.y != 0 else 1.0
    vz = float(vsize.z) if vsize.z != 0 else 1.0

    # Sub-sample to at most 2000 atoms so fpocket runs quickly
    if len(xx) > 2000:
        idx = np.random.choice(len(xx), 2000, replace=False)
        xx, yy, zz = xx[idx], yy[idx], zz[idx]

    coords_x = origin[0] + xx * vx
    coords_y = origin[1] + yy * vy
    coords_z = origin[2] + zz * vz

    lines = []
    for i, (cx, cy, cz) in enumerate(zip(coords_x, coords_y, coords_z), start=1):
        lines.append(
            f"ATOM  {i:5d}  CA  ALA A{i:4d}    "
            f"{cx:8.3f}{cy:8.3f}{cz:8.3f}  1.00  0.00           C"
        )
    lines.append("END")

    with open(out_pdb, 'w') as fh:
        fh.write("\\n".join(lines) + "\\n")
    return len(xx)

def run_fpocket(pdb_path):
    '''
    Run fpocket on a PDB file, parse output, return list of pocket dicts.
    Returns empty list if fpocket fails (non-fatal: density map may lack pockets).
    '''
    result = subprocess.run(
        ['fpocket', '-f', pdb_path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  fpocket warning (rc={result.returncode}): {result.stderr[:200]}")
        return []

    # fpocket writes results to <basename>_out/
    base = os.path.splitext(pdb_path)[0]
    out_dir = f"{base}_out"
    info_file = os.path.join(out_dir, os.path.basename(base) + "_info.txt")

    if not os.path.exists(info_file):
        return []

    pockets = []
    current = {}
    with open(info_file) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("Pocket"):
                if current:
                    pockets.append(current)
                pocket_id = line.split()[1].rstrip(':')
                current = {"pocket_id": int(pocket_id)}
            elif ':' in line and current:
                key, _, val = line.partition(':')
                key = key.strip().lower().replace(' ', '_').replace('(', '').replace(')', '')
                try:
                    current[key] = float(val.strip())
                except ValueError:
                    current[key] = val.strip()
    if current:
        pockets.append(current)

    return pockets

# -- Main loop ----------------------------------------------------------------
# Scan all kmeans cluster volumes in the staged analysis directory
vol_files = sorted(glob.glob("${analysis_dir}/kmeans*/vol_*.mrc"))
print(f"Found {len(vol_files)} volume(s) to scan in ${analysis_dir}")

ensemble_results = []
np.random.seed(42)

for vol_path in vol_files:
    # Build unique state_id: "kmeans2_vol_001" to distinguish across cluster dirs
    cluster_dir = os.path.basename(os.path.dirname(vol_path))
    vol_base    = os.path.splitext(os.path.basename(vol_path))[0]
    state_id    = f"{cluster_dir}_{vol_base}"
    print(f"  Processing {vol_path} ...")

    with tempfile.TemporaryDirectory() as tmpdir:
        pdb_path = os.path.join(tmpdir, f"{state_id}.pdb")
        try:
            n_atoms = mrc_density_to_pseudo_pdb(vol_path, pdb_path)
            print(f"    -> {n_atoms} pseudo-atoms written")

            pockets = run_fpocket(pdb_path)
            print(f"    -> {len(pockets)} pocket(s) detected")

            # Select top pocket by druggability score or volume
            top_pocket = None
            if pockets:
                scored = [p for p in pockets if 'druggability_score' in p]
                if scored:
                    top_pocket = max(scored, key=lambda p: p['druggability_score'])
                else:
                    # Fall back to largest pocket by volume
                    vol_key = next((k for k in pockets[0] if 'volume' in k), None)
                    if vol_key:
                        top_pocket = max(pockets, key=lambda p: p.get(vol_key, 0))
                    else:
                        top_pocket = pockets[0]

            ensemble_results.append({
                "state":           state_id,
                "volume_file":     vol_path,
                "n_pockets":       len(pockets),
                "top_pocket":      top_pocket,
                "all_pockets":     pockets[:5]   # store up to 5 pockets per state
            })

        except Exception as exc:
            print(f"    WARNING: failed to process {vol_path}: {exc}")
            traceback.print_exc()
            ensemble_results.append({
                "state":       state_id,
                "volume_file": vol_path,
                "n_pockets":   0,
                "top_pocket":  None,
                "all_pockets": [],
                "error":       str(exc)
            })

# Write JSON output
with open("ensemble_pockets.json", "w") as fh:
    json.dump({"ensemble": ensemble_results}, fh, indent=2, default=str)

print(f"\\nPocket scan complete. Results written to ensemble_pockets.json")
print(f"States with pockets: {sum(1 for r in ensemble_results if r['n_pockets'] > 0)}/{len(ensemble_results)}")
PYEOF

    python3 -c "
import mrcfile, numpy
import subprocess, sys
fp = subprocess.run(['fpocket','--version'],capture_output=True,text=True)
fp_ver = fp.stdout.strip() or fp.stderr.strip() or 'installed'
print('${task.process}:')
print('    mrcfile: ' + mrcfile.__version__)
print('    fpocket: ' + fp_ver.split()[0])
print('    numpy: ' + numpy.__version__)
" > versions.yml
    """
}

// -----------------------------------------------------------------------------
// PROCESS 4: Generate heterogeneity summary report
// -----------------------------------------------------------------------------
process HETEROGENEITY_REPORT {
    tag "$meta.id"
    label 'process_low'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-heterogeneity-nf:latest'

    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(analysis_dir)
    tuple val(meta2), path(pockets_json)

    output:
    tuple val(meta), path("heterogeneity_report.json"), emit: report
    path "versions.yml",                                emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    python3 << 'PYEOF'
import os
import sys
import json
import glob
import math

try:
    import numpy as np
except ImportError as e:
    print(f"ERROR: missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

# -- Load cryoDRGN analysis outputs --------------------------------------------
analysis_dir = "${analysis_dir}"

# Latent z-coordinates (N x zdim array)
z_path = os.path.join(analysis_dir, "z.pkl")
# Cluster assignments written by cryodrgn analyze --ksample
kmeans_dir = os.path.join(analysis_dir, "kmeans_10")   # default 10 clusters
labels_path  = os.path.join(kmeans_dir, "labels.pkl") if os.path.isdir(kmeans_dir) else None

population_fractions = []
n_states             = 0
conformational_entropy = 0.0
z_coords             = None

# Try to load latent coordinates
try:
    import pickle
    with open(z_path, 'rb') as fh:
        z_coords = pickle.load(fh)
    n_particles = len(z_coords)
    print(f"Loaded {n_particles} latent coordinates (shape: {np.array(z_coords).shape})")
except Exception as exc:
    print(f"WARNING: could not load z.pkl: {exc}")
    n_particles = 0

# Try to load k-means cluster labels
if labels_path and os.path.exists(labels_path):
    try:
        with open(labels_path, 'rb') as fh:
            labels = np.array(pickle.load(fh))
        unique_labels, counts = np.unique(labels, return_counts=True)
        n_states = len(unique_labels)
        fracs = counts / counts.sum()
        population_fractions = [
            {"state_index": int(lbl), "fraction": float(frac), "n_particles": int(cnt)}
            for lbl, frac, cnt in zip(unique_labels, fracs, counts)
        ]
        # Shannon entropy of conformational distribution
        conformational_entropy = float(-np.sum(fracs * np.log(fracs + 1e-12)))
        print(f"Loaded {n_states} conformational states from k-means labels")
    except Exception as exc:
        print(f"WARNING: could not load cluster labels: {exc}")
else:
    # Fall back: count vol_*.mrc files as proxy for n_states
    vol_files = glob.glob(os.path.join(analysis_dir, "vol_*.mrc"))
    n_states = len(vol_files)
    if n_states > 0:
        uniform_frac = 1.0 / n_states
        population_fractions = [
            {"state_index": i, "fraction": uniform_frac, "n_particles": None}
            for i in range(n_states)
        ]
        conformational_entropy = math.log(n_states)
    print(f"Used {n_states} volume files as conformational state proxy")

# -- Load pocket scan results --------------------------------------------------
with open("${pockets_json}") as fh:
    pocket_data = json.load(fh)

ensemble = pocket_data.get("ensemble", [])

# Find the most druggable state
best_state_index = None
best_druggability = 0.0

for item in ensemble:
    tp = item.get("top_pocket")
    if tp:
        score = tp.get("druggability_score", 0.0) or 0.0
        if score > best_druggability:
            best_druggability  = score
            best_state_index   = item["state"]

# Summary stats
states_with_pockets = sum(1 for s in ensemble if s["n_pockets"] > 0)
avg_pockets = (sum(s["n_pockets"] for s in ensemble) / len(ensemble)) if ensemble else 0.0

# -- Compose final report ------------------------------------------------------
report = {
    "sample_id":                "${meta.id}",
    "n_states":                 n_states,
    "n_particles":              int(n_particles) if n_particles else None,
    "population_fractions":     population_fractions,
    "conformational_entropy":   conformational_entropy,
    "pocket_scan": {
        "n_states_scanned":      len(ensemble),
        "states_with_pockets":   states_with_pockets,
        "avg_pockets_per_state": round(avg_pockets, 2),
        "top_druggable_state":   best_state_index,
        "top_druggability_score": round(best_druggability, 4),
    },
    "per_state_pockets": [
        {
            "state":            s["state"],
            "n_pockets":        s["n_pockets"],
            "top_druggability": (s["top_pocket"] or {}).get("druggability_score"),
            "top_pocket_volume": (s["top_pocket"] or {}).get(
                next((k for k in (s["top_pocket"] or {}) if "volume" in k), ""), None
            ),
        }
        for s in ensemble
    ],
    "analysis_dir": analysis_dir,
    "pipeline":     "cryo_em_heterogeneity v1.0",
}

with open("heterogeneity_report.json", "w") as fh:
    json.dump(report, fh, indent=2, default=str)

print("\\nHeterogeneity report written to heterogeneity_report.json")
print(f"  Conformational states:    {n_states}")
print(f"  Conformational entropy:   {conformational_entropy:.3f} nats")
print(f"  Top druggable state:      {best_state_index}  (score={best_druggability:.3f})")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        scipy: \$(python -c "import scipy; print(scipy.__version__)")
    END_VERSIONS
    """
}
