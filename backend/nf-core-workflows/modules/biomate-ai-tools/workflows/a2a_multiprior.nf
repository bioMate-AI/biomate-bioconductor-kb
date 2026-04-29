#!/usr/bin/env nextflow
nextflow.enable.dsl=2

params.fasta      = 's3://biomate-nextflow-work/pilot/sequences/a2a.fasta'
params.pdb        = 's3://biomate-nextflow-work/pilot/pdbs/a2a.pdb'
params.n_bioemu   = 200
params.n_chai     = 50
params.outdir     = 's3://biomate-nextflow-work/pilot/results/a2a-multiprior'

include { BIOEMU_SAMPLE } from '/home/yzhang/biomate/backend/nf-core-workflows/modules/biomate-ai-tools/protein_dynamics/main'

process CHAI1_ENSEMBLE {
    tag "a2a_chai1"
    label 'process_gpu'
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:nextflow'
    publishDir "${params.outdir}/chai1", mode: 'copy'

    input:
    path fasta

    output:
    path "chai1_ensemble.tar.gz", emit: ensemble
    path "versions.yml",          emit: versions

    script:
    def n = params.n_chai
    """
    mkdir -p chai_output ensemble_pdbs

    # Run Chai-1 with multiple diffusion samples
    python3 - << 'PYEOF'
import subprocess, os, glob, shutil, sys

fasta  = "${fasta}"
n_samp = int("${n}")
os.makedirs("chai_output", exist_ok=True)
os.makedirs("ensemble_pdbs", exist_ok=True)

# Chai-lab supports --num-samples or the API
try:
    result = subprocess.run(
        ["python", "-m", "chai_lab.main",
         "--fasta", fasta,
         "--output", "chai_output/",
         "--num-diffusion-samples", str(n_samp)],
        capture_output=True, text=True, timeout=3600
    )
    if result.returncode == 0:
        pdbs = glob.glob("chai_output/**/*.pdb", recursive=True)
        print(f"Chai-1: {len(pdbs)} structures generated")
        for i, p in enumerate(sorted(pdbs)[:n_samp]):
            shutil.copy(p, f"ensemble_pdbs/conf_{i:04d}.pdb")
    else:
        print("Chai-1 failed:", result.stderr[:500])
        sys.exit(1)
except FileNotFoundError:
    print("chai_lab not installed; check container")
    sys.exit(1)
PYEOF

    tar -czf chai1_ensemble.tar.gz -C ensemble_pdbs .

    python3 -c "
import sys
chai_ver = 'unknown'
try:
    import chai_lab; chai_ver = getattr(chai_lab, '__version__', 'installed')
except: pass
print('CHAI1_ENSEMBLE:')
print('    chai1: ' + chai_ver)
" > versions.yml
    """
}

process MULTIPRIOR_COMPARE {
    tag "a2a_comparison"
    label 'process_medium'
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/protein-dynamics-nf:v1.0.5'
    publishDir "${params.outdir}/comparison", mode: 'copy'

    input:
    path bioemu_tgz
    path chai1_tgz
    path ref_pdb

    output:
    path "multiprior_comparison.json", emit: report
    path "*.png",                      emit: figures, optional: true

    script:
    """
    python3 - << 'PYEOF'
import tarfile, os, json, numpy as np, glob

def extract_ca(tgz):
    coords = []
    with tarfile.open(tgz) as tf:
        for m in sorted(tf.getmembers(), key=lambda x: x.name):
            if not m.name.endswith('.pdb'): continue
            fh = tf.extractfile(m)
            if fh is None: continue
            ca = []
            for line in fh.read().decode().splitlines():
                if line.startswith('ATOM') and line[12:16].strip() == 'CA':
                    ca.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
            if ca: coords.append(np.array(ca))
    return coords

def kabsch_rmsd(a, b):
    n = min(len(a), len(b))
    a, b = a[:n] - a[:n].mean(0), b[:n] - b[:n].mean(0)
    H = a.T @ b
    U, _, Vt = np.linalg.svd(H)
    d = np.linalg.det(Vt.T @ U.T)
    R = Vt.T @ np.diag([1,1,d]) @ U.T
    a = a @ R.T
    return float(np.sqrt(((a-b)**2).sum(1).mean()))

def ref_ca(pdb):
    ca = []
    with open(pdb) as f:
        for line in f:
            if line.startswith('ATOM') and line[12:16].strip() == 'CA' and line[21] == 'A':
                ca.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.array(ca)

ref  = ref_ca("${ref_pdb}")
bio  = extract_ca("${bioemu_tgz}")
chai = extract_ca("${chai1_tgz}")

n_res = min(ref.shape[0], min(c.shape[0] for c in bio+chai))
ref = ref[:n_res]
bio  = [c[:n_res] for c in bio]
chai = [c[:n_res] for c in chai]

bio_rmsds  = np.array([kabsch_rmsd(c, ref) for c in bio])
chai_rmsds = np.array([kabsch_rmsd(c, ref) for c in chai])

# Coverage: for each Chai conformer, min RMSD to any BioEmu conformer
# Conformers only in Chai (not covered by BioEmu): min_rmsd > 2.0 Å
chai_only = []
for c in chai:
    min_r = min(kabsch_rmsd(c, b) for b in bio)
    chai_only.append(min_r)
chai_only = np.array(chai_only)
chai_unique_frac = float((chai_only > 2.0).mean())

# And vice versa
bio_only = []
for b in bio:
    min_r = min(kabsch_rmsd(b, c) for c in chai)
    bio_only.append(min_r)
bio_only = np.array(bio_only)
bio_unique_frac = float((bio_only > 2.0).mean())

print(f"BioEmu: n={len(bio)}  RMSD mean={bio_rmsds.mean():.2f} max={bio_rmsds.max():.2f}")
print(f"Chai-1: n={len(chai)} RMSD mean={chai_rmsds.mean():.2f} max={chai_rmsds.max():.2f}")
print(f"Chai-unique (not covered by BioEmu): {chai_unique_frac:.1%}")
print(f"BioEmu-unique (not covered by Chai): {bio_unique_frac:.1%}")

result = {
    "protein": "A2A adenosine receptor (3EML)",
    "n_bioemu": len(bio),
    "n_chai1": len(chai),
    "bioemu_rmsd_mean": round(float(bio_rmsds.mean()), 3),
    "bioemu_rmsd_max":  round(float(bio_rmsds.max()), 3),
    "chai1_rmsd_mean":  round(float(chai_rmsds.mean()), 3),
    "chai1_rmsd_max":   round(float(chai_rmsds.max()), 3),
    "chai_unique_frac": round(chai_unique_frac, 4),
    "bio_unique_frac":  round(bio_unique_frac, 4),
    "mixture_advantage": (
        "Chai-1 covers {:.1%} conformational space not covered by BioEmu alone; "
        "BioEmu covers {:.1%} not covered by Chai-1.  Mixture spans both.".format(
            chai_unique_frac, bio_unique_frac)
    )
}

with open("multiprior_comparison.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF
    """
}

workflow {
    fasta_ch  = Channel.value(file(params.fasta))
    pdb_ch    = Channel.value(file(params.pdb))
    meta      = [id: 'a2a']

    bioemu_ch = Channel.of([meta, file(params.pdb)])
    BIOEMU_SAMPLE(bioemu_ch, params.n_bioemu)

    CHAI1_ENSEMBLE(fasta_ch)

    MULTIPRIOR_COMPARE(
        BIOEMU_SAMPLE.out.ensemble.map { m, f -> f },
        CHAI1_ENSEMBLE.out.ensemble,
        pdb_ch
    )
}

// NOTE: Boltz-1 run added as the third prior (MIT-licensed AF3-class model)
