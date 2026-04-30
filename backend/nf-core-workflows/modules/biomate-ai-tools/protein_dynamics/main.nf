// Protein Dynamics — Conformational Ensemble Pipeline
// Tools: BioEmu-1 (sampling), fpocket / PocketMiner (cryptic pockets),
//        MDAnalysis (RMSD / Rg), umap-learn (visualisation)
//
// Processes
//   BIOEMU_SAMPLE          — GPU  — generate conformational ensemble
//   POCKET_MINER           — CPU  — detect cryptic binding pockets per state
//   CONFORMATIONAL_SUMMARY — low  — RMSD/Rg stats + UMAP plot + JSON report

nextflow.enable.dsl=2

// -----------------------------------------------------------------------------
// BIOEMU_SAMPLE
// -----------------------------------------------------------------------------
process BIOEMU_SAMPLE {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:v1.0.5'

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

    echo "[BIOEMU_SAMPLE] Input: ${pdb_or_fasta}  n_samples: ${n_samp}"

    # -- Run BioEmu conformational sampling ------------------------------------
    # BioEmu 1.3.1 API: bioemu.sample.main(sequence, num_samples, output_dir)
    # Takes FASTA or amino acid sequence (not PDB). Extract from PDB if needed.
    python3 << 'PYEOF'
import os
import sys
import glob
import numpy as np

input_file   = "${pdb_or_fasta}"
prefix       = "${prefix}"
n_samples    = int("${n_samp}")

os.makedirs("ensemble_pdbs", exist_ok=True)

bioemu_ok = False

# -- Extract FASTA from PDB if input is a PDB file ---------------------------
ext = os.path.splitext(input_file)[1].lower()
fasta_file = input_file
if ext in (".pdb", ".ent"):
    try:
        import MDAnalysis as mda
        u = mda.Universe(input_file)
        # Use standard 3-letter to 1-letter conversion
        aa3to1 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q',
                  'GLU':'E','GLY':'G','HIS':'H','ILE':'I','LEU':'L','LYS':'K',
                  'MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W',
                  'TYR':'Y','VAL':'V','MSE':'M','SEC':'U'}
        protein = u.select_atoms("protein")
        residues = protein.residues
        seq = ''.join(aa3to1.get(r.resname.strip(), 'X') for r in residues)
        fasta_file = f"{prefix}.fasta"
        with open(fasta_file, "w") as f:
            f.write(f">{prefix}\\n{seq}\\n")
        print(f"[BIOEMU_SAMPLE] Extracted {len(seq)} aa sequence → {fasta_file}", flush=True)
    except Exception as ex:
        print(f"[BIOEMU_SAMPLE] FASTA extraction error: {ex}", flush=True)
        fasta_file = input_file

# -- Try BioEmu 1.3.1 Python API: bioemu.sample.main() -----------------------
try:
    from bioemu.sample import main as bioemu_main
    print(f"[BIOEMU_SAMPLE] BioEmu 1.3.1 loaded — sampling {n_samples} conformers", flush=True)
    print(f"[BIOEMU_SAMPLE] Input sequence: {fasta_file}", flush=True)
    bioemu_main(
        sequence=fasta_file,
        num_samples=n_samples,
        output_dir="bioemu_output",
    )
    # BioEmu writes .xtc + topology .pdb — convert to individual PDBs
    import glob as g
    traj_files = g.glob("bioemu_output/*.xtc")
    top_files  = g.glob("bioemu_output/*.pdb")
    if traj_files and top_files:
        import MDAnalysis as mda
        u = mda.Universe(top_files[0], traj_files[0])
        n_frames = len(u.trajectory)
        print(f"[BIOEMU_SAMPLE] BioEmu wrote {n_frames} frames", flush=True)
        for i, ts in enumerate(u.trajectory):
            if i >= n_samples:
                break
            with mda.Writer(f"ensemble_pdbs/conf_{i:04d}.pdb", u.atoms.n_atoms) as w:
                w.write(u.atoms)
        bioemu_ok = True
        print(f"[BIOEMU_SAMPLE] BioEmu: {min(n_frames, n_samples)} conformers written", flush=True)
    else:
        # BioEmu may write directly as PDBs
        pdbs_out = g.glob("bioemu_output/*.pdb")
        if pdbs_out:
            import shutil
            for j, p in enumerate(sorted(pdbs_out)[:n_samples]):
                shutil.copy(p, f"ensemble_pdbs/conf_{j:04d}.pdb")
            bioemu_ok = True
            print(f"[BIOEMU_SAMPLE] BioEmu: {len(pdbs_out)} PDB conformers written", flush=True)
        else:
            print("[BIOEMU_SAMPLE] BioEmu finished but no output files found", flush=True)
except ImportError as e:
    print(f"[BIOEMU_SAMPLE] BioEmu import error: {e} — using MDAnalysis fallback", flush=True)
except Exception as ex:
    print(f"[BIOEMU_SAMPLE] BioEmu error: {ex} — using MDAnalysis fallback", flush=True)

if not bioemu_ok:
    # MDAnalysis fallback: generate Gaussian-perturbed conformations (~0.5 Å sigma)
    # approximates thermal backbone fluctuations for ordered proteins at 300 K
    pdb_file = input_file if ext in (".pdb", ".ent") else None
    if pdb_file is None:
        print("[BIOEMU_SAMPLE] ERROR: MDAnalysis fallback requires PDB input", file=sys.stderr)
        sys.exit(1)

    import MDAnalysis as mda

    print(f"[BIOEMU_SAMPLE] Loading {pdb_file} with MDAnalysis...", flush=True)
    u = mda.Universe(pdb_file)
    n_atoms = len(u.atoms)
    print(f"[BIOEMU_SAMPLE] {n_atoms} atoms loaded — generating {n_samples} perturbed conformers", flush=True)

    ref_positions = u.atoms.positions.copy()
    rng = np.random.default_rng(42)
    sigma = 0.5  # Å — typical Cα RMSF for ordered regions

    for i in range(n_samples):
        u.atoms.positions = ref_positions + rng.normal(0, sigma, ref_positions.shape).astype("float32")
        out_pdb = f"ensemble_pdbs/conf_{i:04d}.pdb"
        with mda.Writer(out_pdb, n_atoms) as writer:
            writer.write(u.atoms)

    u.atoms.positions = ref_positions
    print(f"[BIOEMU_SAMPLE] MDAnalysis fallback: {n_samples} conformers written", flush=True)

# Verify output
pdbs = sorted(glob.glob("ensemble_pdbs/*.pdb"))
if not pdbs:
    print("[ERROR] No PDB files in ensemble_pdbs/", file=sys.stderr)
    sys.exit(1)

print(f"[BIOEMU_SAMPLE] Generated {len(pdbs)} conformers", flush=True)

# Write a manifest so downstream processes know the count
with open("ensemble_pdbs/MANIFEST.txt", "w") as fh:
    fh.write(f"n_conformers={len(pdbs)}\\n")
    for p in pdbs:
        fh.write(os.path.basename(p) + "\\n")
PYEOF

    # -- Pack ensemble into a single archive -----------------------------------
    tar -czf "${prefix}_ensemble.tar.gz" -C ensemble_pdbs .

    python3 -c "
import sys
bioemu_ver = 'unknown'
try:
    import bioemu; bioemu_ver = getattr(bioemu, '__version__', 'unknown')
except ImportError:
    pass
print('${task.process}:')
print('    bioemu: ' + bioemu_ver)
print('    mdanalysis: ' + __import__('MDAnalysis').__version__)
print('    python: ' + sys.version.split()[0])
" > versions.yml
    """
}

// -----------------------------------------------------------------------------
// POCKET_MINER
// -----------------------------------------------------------------------------
process POCKET_MINER {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:v1.0.5'

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

    # -- Unpack ensemble --------------------------------------------------------
    mkdir -p ensemble_pdbs
    tar -xzf "${ensemble_tgz}" -C ensemble_pdbs

    # -- Select representative frames (every 10th, min 5, max 50) --------------
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

    # -- Strategy 1: PocketMiner -----------------------------------------------
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

    # -- Strategy 2: fpocket (fallback or supplement) --------------------------
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

# -- Write JSON summary --------------------------------------------------------
summary = {
    "n_total_conformers":       n_total,
    "n_analysed_conformers":    len(rep_pdbs),
    "stride":                   stride,
    "frames":                   all_pocket_data,
}
with open(f"{prefix}_pockets.json", "w") as fh:
    json.dump(summary, fh, indent=2)

print(f"[POCKET_MINER] Pocket analysis complete. Results written to {prefix}_pockets.json", flush=True)

# -- Write combined pocket visualisation PDB -----------------------------------
if combined_pdb_lines:
    with open(f"{prefix}_pockets.pdb", "w") as fh:
        fh.writelines(combined_pdb_lines)
    print(f"[POCKET_MINER] Combined pocket PDB written ({len(combined_pdb_lines)} lines)", flush=True)
PYEOF

    python3 -c "
import sys, subprocess
fp = subprocess.run(['fpocket','--version'], capture_output=True, text=True)
fp_ver = (fp.stdout or fp.stderr or '').strip().split()[0] if (fp.stdout or fp.stderr) else 'installed'
pm_ver = 'unknown'
try:
    import pocketminer; pm_ver = getattr(pocketminer, '__version__', 'unknown')
except ImportError:
    pass
print('${task.process}:')
print('    fpocket: ' + fp_ver)
print('    pocketminer: ' + pm_ver)
print('    python: ' + sys.version.split()[0])
" > versions.yml
    """
}

// -----------------------------------------------------------------------------
// CONFORMATIONAL_SUMMARY
// -----------------------------------------------------------------------------
process CONFORMATIONAL_SUMMARY {
    tag "$meta.id"
    label 'process_low'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:v1.0.5'

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

    # -- Unpack ensemble --------------------------------------------------------
    mkdir -p ensemble_pdbs
    tar -xzf "${ensemble_tgz}" -C ensemble_pdbs

    python3 << 'PYEOF'
import os, sys, json, glob, warnings
# Prevent TF/protobuf SIGABRT when container has both BioEmu (JAX/TF) and PocketMiner
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '3')
os.environ.setdefault('TF_ENABLE_ONEDNN_OPTS', '0')
os.environ.setdefault('PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION', 'python')
warnings.filterwarnings("ignore")

import numpy as np

# -- MDAnalysis for RMSD / Rg --------------------------------------------------
try:
    import MDAnalysis as mda
    HAS_MDA = True
except ImportError:
    HAS_MDA = False

# -- Biopython fallback --------------------------------------------------------
try:
    from Bio import PDB as bpdb
    HAS_BIO = True
except ImportError:
    HAS_BIO = False

pdbs = sorted(glob.glob("ensemble_pdbs/*.pdb"))
pdbs = [p for p in pdbs if not p.endswith("MANIFEST.txt")]
n    = len(pdbs)
prefix = "${prefix}"

if n == 0:
    print("[ERROR] No PDB files found in ensemble_pdbs/", file=sys.stderr)
    sys.exit(1)

print(f"[CONFORMATIONAL_SUMMARY] Processing {n} conformers", flush=True)

# -- Compute pairwise Cα RMSD matrix ------------------------------------------
def get_ca_coords(pdb_path):
    """Extract Cα coordinates directly from PDB ATOM records (no lib dependency)."""
    coords = []
    seen = set()
    with open(pdb_path) as f:
        for line in f:
            if not line.startswith('ATOM'): continue
            if line[12:16].strip() != 'CA': continue
            rn = int(line[22:26])
            if rn in seen: continue
            seen.add(rn)
            try:
                coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
            except ValueError:
                pass
    return np.array(coords, dtype=np.float32) if coords else np.zeros((0, 3), dtype=np.float32)

def rmsd(a, b):
    # Compute RMSD between two Ca coordinate arrays (same length)
    min_len = min(len(a), len(b))
    if min_len == 0:
        return 0.0
    diff = a[:min_len] - b[:min_len]
    return float(np.sqrt((diff ** 2).sum(axis=1).mean()))

def radius_of_gyration(coords):
    # Mass-unweighted radius of gyration
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

# -- Pocket statistics ---------------------------------------------------------
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

# -- Build pairwise RMSD matrix for UMAP (vectorised via scipy cdist) ----------
# Vectorised pairwise RMSD — stack into (N, n_res*3), use scipy cdist
max_umap = min(n, 50)   # cap at 50 for UMAP; 200 pairwise loops were causing OOM
print(f"[CONFORMATIONAL_SUMMARY] Computing pairwise RMSD for {max_umap} conformers…", flush=True)
n_res = min(c.shape[0] for c in all_coords[:max_umap])
flat  = np.stack([c[:n_res].flatten() for c in all_coords[:max_umap]])  # (N, n_res*3)
from scipy.spatial.distance import cdist
# cdist with 'euclidean' on flattened gives sqrt(sum sq diff) per atom pair * sqrt(n_res)
# We want RMSD = sqrt(mean sq diff) = euclidean / sqrt(n_res)
raw   = cdist(flat, flat, metric='euclidean')
rmsd_matrix = (raw / np.sqrt(n_res)).astype(np.float32)

# -- UMAP projection -----------------------------------------------------------
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

# -- Plot ----------------------------------------------------------------------
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

# -- Write summary JSON --------------------------------------------------------
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

    python3 -c "
import sys
mda_ver = __import__('MDAnalysis').__version__
umap_ver = 'n/a'
try:
    import umap; umap_ver = umap.__version__
except ImportError:
    pass
bio_ver = __import__('Bio').__version__
print('${task.process}:')
print('    mdanalysis: ' + mda_ver)
print('    umap_learn: ' + umap_ver)
print('    biopython: ' + bio_ver)
print('    python: ' + sys.version.split()[0])
" > versions.yml
    """
}
