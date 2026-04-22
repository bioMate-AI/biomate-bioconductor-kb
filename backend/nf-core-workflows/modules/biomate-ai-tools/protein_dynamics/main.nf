// Protein Dynamics — Conformational Ensemble Pipeline
// Tools: BioEmu-1 (sampling), fpocket / PocketMiner (cryptic pockets),
//        MDAnalysis (RMSD / Rg), umap-learn (visualisation)
//
// Processes
//   BIOEMU_SAMPLE          — GPU  — generate conformational ensemble
//   POCKET_MINER           — CPU  — detect cryptic binding pockets per state
//   CONFORMATIONAL_SUMMARY — low  — RMSD/Rg stats + UMAP plot + JSON report

nextflow.enable.dsl=2

// ─────────────────────────────────────────────────────────────────────────────
// BIOEMU_SAMPLE
// ─────────────────────────────────────────────────────────────────────────────
process BIOEMU_SAMPLE {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:latest'

    input:
    tuple val(meta), path(pdb_or_fasta)
    val  n_samples

    output:
    tuple val(meta), path("*_ensemble.tar.gz"), emit: ensemble
    path "versions.yml",                        emit: versions

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def n_samp   = n_samples ?: 100
    """
    set -euo pipefail

    # ── Detect input type ──────────────────────────────────────────────────────
    INPUT_FILE="${pdb_or_fasta}"
    EXTENSION="\${INPUT_FILE##*.}"

    if [[ "\$EXTENSION" == "fasta" || "\$EXTENSION" == "fa" ]]; then
        INPUT_TYPE="fasta"
    else
        INPUT_TYPE="pdb"
    fi

    echo "[BIOEMU_SAMPLE] Input: \$INPUT_FILE  type: \$INPUT_TYPE  n_samples: ${n_samp}"

    # ── Run BioEmu conformational sampling ────────────────────────────────────
    # BioEmu exposes both a Python API and the CLI entry point bioemu-sample.
    # We prefer the CLI so the process is self-contained.
    python3 << 'PYEOF'
import os
import sys
import subprocess
import glob

input_file   = "${pdb_or_fasta}"
prefix       = "${prefix}"
n_samples    = int("${n_samp}")
input_type   = "${INPUT_TYPE}"

# Attempt CLI first; fall back to Python API
cli_result = subprocess.run(
    ["bioemu-sample",
     "--input",     input_file,
     "--n_samples", str(n_samples),
     "--output_dir", "ensemble_pdbs"],
    capture_output=True, text=True
)

if cli_result.returncode != 0:
    print("[BIOEMU_SAMPLE] CLI attempt failed, trying Python API", flush=True)
    print(cli_result.stderr, flush=True)

    # Python API fallback
    try:
        from bioemu.sample import sample_conformations
        sample_conformations(
            input_path=input_file,
            n_samples=n_samples,
            output_dir="ensemble_pdbs",
        )
    except ImportError as e:
        print(f"[ERROR] bioemu not available: {e}", file=sys.stderr)
        sys.exit(1)
else:
    print(cli_result.stdout, flush=True)

# Verify output directory has PDBs
pdbs = sorted(glob.glob("ensemble_pdbs/*.pdb"))
if not pdbs:
    print("[ERROR] BioEmu produced no PDB files in ensemble_pdbs/", file=sys.stderr)
    sys.exit(1)

print(f"[BIOEMU_SAMPLE] Generated {len(pdbs)} conformers", flush=True)

# Write a manifest so downstream processes know the count
with open("ensemble_pdbs/MANIFEST.txt", "w") as fh:
    fh.write(f"n_conformers={len(pdbs)}\\n")
    for p in pdbs:
        fh.write(os.path.basename(p) + "\\n")
PYEOF

    # ── Pack ensemble into a single archive ───────────────────────────────────
    tar -czf "${prefix}_ensemble.tar.gz" -C ensemble_pdbs .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bioemu: \$(python3 -c "import bioemu; print(getattr(bioemu, '__version__', 'unknown'))" 2>/dev/null || echo "unknown")
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// POCKET_MINER
// ─────────────────────────────────────────────────────────────────────────────
process POCKET_MINER {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:latest'

    input:
    tuple val(meta), path(ensemble_tgz)

    output:
    tuple val(meta), path("*_pockets.json"),          emit: pockets
    tuple val(meta), path("*_pockets.pdb"), optional: true, emit: pocket_viz
    path "versions.yml",                              emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    set -euo pipefail

    # ── Unpack ensemble ────────────────────────────────────────────────────────
    mkdir -p ensemble_pdbs
    tar -xzf "${ensemble_tgz}" -C ensemble_pdbs

    # ── Select representative frames (every 10th, min 5, max 50) ──────────────
    python3 << 'PYEOF'
import os
import glob
import math
import json
import subprocess
import shutil
import sys

pdbs       = sorted(glob.glob("ensemble_pdbs/*.pdb"))
pdbs       = [p for p in pdbs if not p.endswith("MANIFEST.txt")]
n_total    = len(pdbs)
prefix     = "${prefix}"

# Stride: pick up to 50 representative frames
stride     = max(1, math.ceil(n_total / 50))
rep_pdbs   = pdbs[::stride]
print(f"[POCKET_MINER] {n_total} total conformers, analysing {len(rep_pdbs)} representatives (stride={stride})", flush=True)

os.makedirs("pocket_results", exist_ok=True)

all_pocket_data = []
combined_pdb_lines = []

for i, pdb in enumerate(rep_pdbs):
    frame_id = os.path.splitext(os.path.basename(pdb))[0]
    out_dir  = f"pocket_results/{frame_id}"
    os.makedirs(out_dir, exist_ok=True)

    pocket_info = {
        "frame_id":    frame_id,
        "frame_index": i,
        "pdb_path":    pdb,
        "method":      None,
        "pockets":     [],
    }

    # ── Strategy 1: PocketMiner ───────────────────────────────────────────────
    pm_ok = False
    try:
        pm_result = subprocess.run(
            ["python3", "-m", "pocketminer.predict",
             "--pdb", pdb,
             "--output", f"{out_dir}/pm_predictions.csv"],
            capture_output=True, text=True, timeout=120
        )
        if pm_result.returncode == 0:
            import csv
            with open(f"{out_dir}/pm_predictions.csv") as fh:
                reader = csv.DictReader(fh)
                for row in reader:
                    pocket_info["pockets"].append({
                        "type":  "pocketminer",
                        "score": float(row.get("pocket_score", 0.0)),
                        "residue": row.get("residue_id", ""),
                    })
            pocket_info["method"] = "pocketminer"
            pm_ok = True
        else:
            print(f"[POCKET_MINER] PocketMiner failed for {frame_id}: {pm_result.stderr[:200]}", flush=True)
    except Exception as ex:
        print(f"[POCKET_MINER] PocketMiner exception for {frame_id}: {ex}", flush=True)

    # ── Strategy 2: fpocket (fallback or supplement) ──────────────────────────
    if not pm_ok or True:   # always run fpocket for geometry-based scores
        try:
            fp_result = subprocess.run(
                ["fpocket", "-f", pdb, "-o", f"{out_dir}/fpocket"],
                capture_output=True, text=True, timeout=120
            )
            if fp_result.returncode == 0:
                # Parse fpocket _info.txt for pocket scores
                info_files = glob.glob(f"{out_dir}/fpocket/*_info.txt")
                for info_f in info_files[:10]:   # top 10 pockets max
                    with open(info_f) as fh:
                        lines = fh.readlines()
                    score_line = next((l for l in lines if "Druggability Score" in l), None)
                    drug_score = 0.0
                    if score_line:
                        try:
                            drug_score = float(score_line.split(":")[-1].strip())
                        except ValueError:
                            pass
                    pocket_info["pockets"].append({
                        "type":  "fpocket",
                        "score": drug_score,
                        "info_file": os.path.basename(info_f),
                    })
                if not pocket_info["method"]:
                    pocket_info["method"] = "fpocket"

                # Collect cavity PDB lines for visualisation
                pqt_files = glob.glob(f"{out_dir}/fpocket/*_atm.pdb")
                for pqt in pqt_files[:3]:
                    with open(pqt) as fh:
                        combined_pdb_lines.append(f"REMARK frame={frame_id}\\n")
                        combined_pdb_lines.extend(fh.readlines())
        except Exception as ex:
            print(f"[POCKET_MINER] fpocket exception for {frame_id}: {ex}", flush=True)

    if not pocket_info["method"]:
        pocket_info["method"] = "none"

    all_pocket_data.append(pocket_info)

# ── Write JSON summary ────────────────────────────────────────────────────────
summary = {
    "n_total_conformers":       n_total,
    "n_analysed_conformers":    len(rep_pdbs),
    "stride":                   stride,
    "frames":                   all_pocket_data,
}
with open(f"{prefix}_pockets.json", "w") as fh:
    json.dump(summary, fh, indent=2)

print(f"[POCKET_MINER] Pocket analysis complete. Results written to {prefix}_pockets.json", flush=True)

# ── Write combined pocket visualisation PDB ───────────────────────────────────
if combined_pdb_lines:
    with open(f"{prefix}_pockets.pdb", "w") as fh:
        fh.writelines(combined_pdb_lines)
    print(f"[POCKET_MINER] Combined pocket PDB written ({len(combined_pdb_lines)} lines)", flush=True)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fpocket: \$(fpocket --version 2>&1 | head -1 || echo "unknown")
        pocketminer: \$(python3 -c "import pocketminer; print(getattr(pocketminer, '__version__', 'unknown'))" 2>/dev/null || echo "unknown")
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFORMATIONAL_SUMMARY
// ─────────────────────────────────────────────────────────────────────────────
process CONFORMATIONAL_SUMMARY {
    tag "$meta.id"
    label 'process_low'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:latest'

    input:
    tuple val(meta), path(ensemble_tgz)
    tuple val(meta2), path(pockets_json)

    output:
    tuple val(meta), path("summary_report.json"),      emit: report
    tuple val(meta), path("conformational_umap.png"),  emit: umap
    path "versions.yml",                               emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    set -euo pipefail

    # ── Unpack ensemble ────────────────────────────────────────────────────────
    mkdir -p ensemble_pdbs
    tar -xzf "${ensemble_tgz}" -C ensemble_pdbs

    python3 << 'PYEOF'
import os
import sys
import json
import glob
import numpy as np

# ── MDAnalysis for RMSD / Rg ──────────────────────────────────────────────────
try:
    import MDAnalysis as mda
    from MDAnalysis.analysis import rms, align
    HAS_MDA = True
except ImportError:
    HAS_MDA = False
    print("[CONFORMATIONAL_SUMMARY] MDAnalysis not available — using Biopython fallback", flush=True)

# ── Fallback: Biopython RMSD ──────────────────────────────────────────────────
from Bio import PDB as bpdb
import warnings
warnings.filterwarnings("ignore")

pdbs = sorted(glob.glob("ensemble_pdbs/*.pdb"))
pdbs = [p for p in pdbs if not p.endswith("MANIFEST.txt")]
n    = len(pdbs)
prefix = "${prefix}"

if n == 0:
    print("[ERROR] No PDB files found in ensemble_pdbs/", file=sys.stderr)
    sys.exit(1)

print(f"[CONFORMATIONAL_SUMMARY] Processing {n} conformers", flush=True)

# ── Compute pairwise Cα RMSD matrix ──────────────────────────────────────────
def get_ca_coords(pdb_path):
    """Extract Cα coordinates from a PDB file using Biopython."""
    parser = bpdb.PDBParser(QUIET=True)
    structure = parser.get_structure("s", pdb_path)
    coords = []
    for model in structure:
        for chain in model:
            for residue in chain:
                if bpdb.is_aa(residue, standard=True):
                    try:
                        coords.append(residue["CA"].get_vector().get_array())
                    except KeyError:
                        pass
        break  # first model only
    return np.array(coords, dtype=np.float32)

def rmsd(a, b):
    """Compute RMSD between two Cα coordinate arrays (same length)."""
    min_len = min(len(a), len(b))
    if min_len == 0:
        return 0.0
    diff = a[:min_len] - b[:min_len]
    return float(np.sqrt((diff ** 2).sum(axis=1).mean()))

def radius_of_gyration(coords):
    """Mass-unweighted radius of gyration."""
    if len(coords) == 0:
        return 0.0
    centre = coords.mean(axis=0)
    return float(np.sqrt(((coords - centre) ** 2).sum(axis=1).mean()))

# Load all structures
print("[CONFORMATIONAL_SUMMARY] Loading Cα coordinates…", flush=True)
all_coords = []
for pdb in pdbs:
    ca = get_ca_coords(pdb)
    all_coords.append(ca)

# Reference = first conformer
ref_coords = all_coords[0]

rmsd_to_ref = [rmsd(ref_coords, c) for c in all_coords]
rg_values   = [radius_of_gyration(c) for c in all_coords]

rmsd_mean = float(np.mean(rmsd_to_ref))
rmsd_std  = float(np.std(rmsd_to_ref))
rmsd_min  = float(np.min(rmsd_to_ref))
rmsd_max  = float(np.max(rmsd_to_ref))
rg_mean   = float(np.mean(rg_values))
rg_std    = float(np.std(rg_values))

print(f"[CONFORMATIONAL_SUMMARY] RMSD to ref: mean={rmsd_mean:.3f} std={rmsd_std:.3f} Å", flush=True)
print(f"[CONFORMATIONAL_SUMMARY] Rg: mean={rg_mean:.3f} std={rg_std:.3f} Å", flush=True)

# ── Pocket statistics ─────────────────────────────────────────────────────────
with open("${pockets_json}") as fh:
    pocket_data = json.load(fh)

pocket_counts = []
druggability_scores = []
for frame in pocket_data.get("frames", []):
    pockets = frame.get("pockets", [])
    pocket_counts.append(len(pockets))
    scores = [p.get("score", 0.0) for p in pockets if p.get("type") == "fpocket"]
    if scores:
        druggability_scores.append(max(scores))

mean_pockets    = float(np.mean(pocket_counts))   if pocket_counts    else 0.0
max_drug_score  = float(max(druggability_scores))  if druggability_scores else 0.0
mean_drug_score = float(np.mean(druggability_scores)) if druggability_scores else 0.0

# ── Build pairwise RMSD matrix for UMAP ───────────────────────────────────────
# Limit to first 200 conformers to keep memory manageable
max_umap = min(n, 200)
print(f"[CONFORMATIONAL_SUMMARY] Computing pairwise RMSD for {max_umap} conformers…", flush=True)
rmsd_matrix = np.zeros((max_umap, max_umap), dtype=np.float32)
for i in range(max_umap):
    for j in range(i + 1, max_umap):
        d = rmsd(all_coords[i], all_coords[j])
        rmsd_matrix[i, j] = d
        rmsd_matrix[j, i] = d

# ── UMAP projection ───────────────────────────────────────────────────────────
try:
    import umap
    reducer = umap.UMAP(metric="precomputed", n_components=2, random_state=42,
                        n_neighbors=min(15, max_umap - 1))
    embedding = reducer.fit_transform(rmsd_matrix)
    umap_ok = True
except Exception as ex:
    print(f"[CONFORMATIONAL_SUMMARY] UMAP failed ({ex}), falling back to PCA", flush=True)
    from sklearn.decomposition import PCA
    reducer = PCA(n_components=2)
    embedding = reducer.fit_transform(rmsd_matrix)
    umap_ok = False

# ── Plot ──────────────────────────────────────────────────────────────────────
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns

fig, axes = plt.subplots(1, 3, figsize=(16, 5))
fig.suptitle(f"Conformational Ensemble — {prefix}  (n={n})", fontsize=13)

# Panel 1: UMAP / PCA coloured by RMSD to reference
sc = axes[0].scatter(embedding[:, 0], embedding[:, 1],
                     c=rmsd_to_ref[:max_umap], cmap="viridis", s=20, alpha=0.8)
plt.colorbar(sc, ax=axes[0], label="RMSD to ref (Å)")
axes[0].set_title("UMAP" if umap_ok else "PCA")
axes[0].set_xlabel("Component 1")
axes[0].set_ylabel("Component 2")

# Panel 2: RMSD distribution
axes[1].hist(rmsd_to_ref, bins=30, color="steelblue", edgecolor="white", alpha=0.85)
axes[1].axvline(rmsd_mean, color="red", linestyle="--", label=f"mean={rmsd_mean:.2f} Å")
axes[1].set_xlabel("RMSD to reference (Å)")
axes[1].set_ylabel("Count")
axes[1].set_title("RMSD Distribution")
axes[1].legend(fontsize=9)

# Panel 3: Radius of gyration distribution
axes[2].hist(rg_values, bins=30, color="coral", edgecolor="white", alpha=0.85)
axes[2].axvline(rg_mean, color="darkred", linestyle="--", label=f"mean={rg_mean:.2f} Å")
axes[2].set_xlabel("Radius of gyration (Å)")
axes[2].set_ylabel("Count")
axes[2].set_title("Radius of Gyration")
axes[2].legend(fontsize=9)

plt.tight_layout()
plt.savefig("conformational_umap.png", dpi=150, bbox_inches="tight")
plt.close()
print("[CONFORMATIONAL_SUMMARY] Plot saved to conformational_umap.png", flush=True)

# ── Write summary JSON ────────────────────────────────────────────────────────
summary = {
    "prefix":            prefix,
    "n_conformers":      n,
    "rmsd": {
        "mean_angstrom":  rmsd_mean,
        "std_angstrom":   rmsd_std,
        "min_angstrom":   rmsd_min,
        "max_angstrom":   rmsd_max,
        "reference":      os.path.basename(pdbs[0]),
    },
    "radius_of_gyration": {
        "mean_angstrom":  rg_mean,
        "std_angstrom":   rg_std,
    },
    "pocket_analysis": {
        "n_analysed_frames":    len(pocket_counts),
        "mean_pockets_per_frame": mean_pockets,
        "mean_druggability_score": mean_drug_score,
        "max_druggability_score":  max_drug_score,
    },
    "umap": {
        "method":       "umap" if umap_ok else "pca",
        "n_conformers_projected": max_umap,
        "plot":         "conformational_umap.png",
    },
}

with open("summary_report.json", "w") as fh:
    json.dump(summary, fh, indent=2)

print("[CONFORMATIONAL_SUMMARY] Summary report written to summary_report.json", flush=True)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mdanalysis: \$(python3 -c "import MDAnalysis; print(MDAnalysis.__version__)" 2>/dev/null || echo "n/a")
        umap_learn: \$(python3 -c "import umap; print(umap.__version__)" 2>/dev/null || echo "n/a")
        biopython: \$(python3 -c "import Bio; print(Bio.__version__)" 2>/dev/null || echo "n/a")
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}
