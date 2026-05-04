#!/usr/bin/env python3
"""Run BioEmu locally on GB10 GPU for beta2ar and trpv1."""
import os, sys, math, subprocess, boto3, glob, tarfile, json, types
from pathlib import Path

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION'] = 'python'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

# Stub TF — BioEmu vendors AlphaFold TF code that's never called via ColabFold path.
# MagicMock raises on assert_* attrs; use a plain recursive sentinel instead.
import importlib.util as _ilu

class _R:
    """Recursive sentinel: any attr access, call, or context manager returns self."""
    def __call__(self, *a, **k): return self
    def __getattr__(self, n): return self
    def __iter__(self): return iter([])
    def __bool__(self): return False
    def __int__(self): return 0
    def __index__(self): return 0
    def __enter__(self): return self
    def __exit__(self, *a): return False
    def __len__(self): return 0

_R_inst = _R()

class _TFStub(types.ModuleType):
    def __init__(self, name):
        super().__init__(name)
        self.__spec__ = _ilu.spec_from_loader(name, loader=None)
        self.__path__ = []; self.__package__ = name
    def __getattr__(self, n):
        if n.startswith("__"): raise AttributeError(n)
        return _R_inst

for _n in ["tensorflow","tensorflow.compat","tensorflow.compat.v1","tensorflow.compat.v2",
           "tensorflow.python","tensorflow.python.framework",
           "tensorflow.python.framework.ops","tensorflow.python.util",
           "tensorflow.python.util.compat"]:
    sys.modules[_n] = _TFStub(_n)

import jax
print(f"[INFO] JAX devices: {jax.devices()}", flush=True)

from bioemu.sample import main as bioemu_main

PROTEINS = [
    ("beta2ar", "s3://biomate-nextflow-work/pilot/pdbs/beta2ar.pdb"),
    ("trpv1",   "s3://biomate-nextflow-work/pilot/pdbs/trpv1.pdb"),
]
N_SAMPLES = 200
CKPT_DIR  = Path("/tmp/bioemu_ckpt")
OUT_BASE  = Path("/tmp/bioemu_local_results")

def download_s3(s3_path, local_path):
    s3 = boto3.client("s3", region_name="us-west-2")
    bucket, key = s3_path.replace("s3://", "").split("/", 1)
    s3.download_file(bucket, key, local_path)

def pull_checkpoint():
    CKPT_DIR.mkdir(exist_ok=True)
    for f in ["checkpoint.ckpt", "config.yaml"]:
        dest = CKPT_DIR / f
        if not dest.exists():
            print(f"[INFO] Downloading {f} from S3...", flush=True)
            download_s3(f"s3://biomate-nextflow-work/models/bioemu-v1.1/checkpoints/bioemu-v1.1/{f}", str(dest))
    print("[INFO] Checkpoint ready.", flush=True)

def extract_fasta(pdb_path, prefix):
    import MDAnalysis as mda
    aa3 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q',
           'GLU':'E','GLY':'G','HIS':'H','ILE':'I','LEU':'L','LYS':'K',
           'MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W',
           'TYR':'Y','VAL':'V','MSE':'M','SEC':'U'}
    u = mda.Universe(pdb_path)
    seq = ''.join(aa3.get(r.resname.strip(), 'X') for r in u.select_atoms("protein").residues)
    fasta = f"/tmp/{prefix}.fasta"
    with open(fasta, "w") as f:
        f.write(f">{prefix}\n{seq}\n")
    print(f"[INFO] {prefix}: {len(seq)} aa → {fasta}", flush=True)
    return fasta, len(seq)

def run_protein(name, pdb_s3):
    print(f"\n{'='*60}\n[INFO] Running BioEmu for {name}\n{'='*60}", flush=True)
    pdb_local = f"/tmp/{name}.pdb"
    download_s3(pdb_s3, pdb_local)

    fasta, n_res = extract_fasta(pdb_local, name)
    batch_size_100 = max(20, math.ceil((n_res / 100) ** 2) + 1)
    print(f"[INFO] n_res={n_res}, batch_size_100={batch_size_100}", flush=True)

    out_dir = OUT_BASE / name
    out_dir.mkdir(parents=True, exist_ok=True)

    bioemu_main(
        sequence=fasta,
        num_samples=N_SAMPLES,
        output_dir=str(out_dir),
        batch_size_100=batch_size_100,
        ckpt_path=str(CKPT_DIR / "checkpoint.ckpt"),
        model_config_path=str(CKPT_DIR / "config.yaml"),
        msa_host_url="https://api.colabfold.com",
    )

    # Convert xtc → individual PDBs
    xtcs = glob.glob(str(out_dir / "*.xtc"))
    tops = glob.glob(str(out_dir / "*.pdb"))
    if xtcs and tops:
        import MDAnalysis as mda
        u = mda.Universe(tops[0], xtcs[0])
        n_frames = len(u.trajectory)
        pdb_dir = out_dir / "pdbs"
        pdb_dir.mkdir(exist_ok=True)
        for i, ts in enumerate(u.trajectory):
            if i >= N_SAMPLES: break
            with mda.Writer(str(pdb_dir / f"conf_{i:04d}.pdb"), u.atoms.n_atoms) as w:
                w.write(u.atoms)
        print(f"[INFO] {name}: {min(n_frames, N_SAMPLES)} conformers written to {pdb_dir}", flush=True)

        # Quick RMSD stats
        import numpy as np
        coords = []
        for pdb in sorted(pdb_dir.glob("*.pdb"))[:50]:
            ca = []
            for line in open(pdb):
                if line.startswith('ATOM') and line[12:16].strip()=='CA':
                    try: ca.append([float(line[30:38]),float(line[38:46]),float(line[46:54])])
                    except: pass
            if ca: coords.append(np.array(ca))
        if len(coords) >= 2:
            ref = coords[0]
            rmsds = [float(np.sqrt(((c[:len(ref)]-ref[:len(c)])**2).sum(axis=1).mean()))
                     for c in coords[1:] if len(c)>0]
            print(f"[RESULT] {name}: mean RMSD={np.mean(rmsds):.2f}Å  max={np.max(rmsds):.2f}Å  "
                  f"(surrogate was ~0.8Å → real BioEmu expected 3-10Å)", flush=True)
            with open(str(out_dir / "quick_rmsd.json"), "w") as f:
                json.dump({"name": name, "n_conformers": len(coords),
                           "mean_rmsd_angstrom": float(np.mean(rmsds)),
                           "max_rmsd_angstrom": float(np.max(rmsds))}, f, indent=2)

        # Upload to S3
        tgz = f"/tmp/{name}_ensemble.tar.gz"
        with tarfile.open(tgz, "w:gz") as tar:
            tar.add(str(pdb_dir), arcname="ensemble_pdbs")
        s3 = boto3.client("s3", region_name="us-west-2")
        s3.upload_file(tgz, "biomate-nextflow-work",
                       f"pilot/results/{name}-bioemu-local/{name}_ensemble.tar.gz")
        print(f"[INFO] Uploaded ensemble to s3://biomate-nextflow-work/pilot/results/{name}-bioemu-local/", flush=True)
    else:
        print(f"[WARN] No xtc/pdb output for {name} — checking raw output:", flush=True)
        print(list(out_dir.glob("*")), flush=True)

if __name__ == "__main__":
    pull_checkpoint()
    for name, pdb_s3 in PROTEINS:
        run_protein(name, pdb_s3)
    print("\n[DONE] BioEmu local run complete.", flush=True)
