#!/bin/bash
# bake_cyclic_image.sh — build the cyclic-peptide stack into a PRE-BAKED AMI (lever #1: kill per-run cold
# install, ~10 min -> seconds). Installs the THREE envs the runners use, verbatim, so the runners become
# activate-only:
#   /opt/miniconda env `bg`   -> BoltzGen        (boltzgen_ourtarget.sh)
#   /opt/miniconda env `mmg`  -> MM-GBSA         (peptide_mmgbsa_run.sh)
#   /opt/pepglad-venv         -> PepGLAD / M2c   (pdl1_m2c_run.sh driver)
# Plus: clone BoltzGen repo, pre-cache HF weights, pre-stage CHARMM36 toppar. Does NOT self-terminate
# (the instance is snapshotted into an AMI afterward). Signals readiness to S3.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
BAKE_S3=${BAKE_S3:?}
BUCKET=knowledge-datasets-1759951976
mkdir -p /opt/bake/status
exec > >(tee -a /opt/bake/bake.log) 2>&1
sig(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > /opt/bake/status/status.json; aws s3 cp /opt/bake/status/status.json "$BAKE_S3/status/status.json" --only-show-errors || true; aws s3 cp /opt/bake/bake.log "$BAKE_S3/status/bake.log" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && sig "FAILED_rc_$rc"; aws s3 cp /opt/bake/bake.log "$BAKE_S3/status/bake.log" --only-show-errors || true; exit $rc' EXIT

sig installing_base
# DL GPU AMI (Ubuntu 22.04/py3.10) already has awscli, git, curl, python3-venv. Only ensure git/curl.
# NO build-essential/python3-dev: not needed on 22.04 (biopython 1.80 + torch-scatter install as cp310
# wheels), and they conflict with the AMI's held CUDA packages ("held broken packages" -> rc 100).
# apt-get update FIRST (stale lists were the other half of the failure); tolerate apt hiccups (|| true).
apt-get -o DPkg::Lock::Timeout=300 update -qq || true
command -v aws >/dev/null 2>&1 || { apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
command -v git >/dev/null 2>&1 || apt-get -o DPkg::Lock::Timeout=300 install -y -qq git || true
# python3-venv IS required (pepglad venv: `python3 -m venv` fails without it -> rc_1). The DL AMI's base
# python3 is 3.10; this pulls python3.10-venv. Unlike build-essential it does NOT conflict with CUDA holds.
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv

# ---- miniconda (shared) ----
sig miniconda
if [ ! -d /opt/miniconda ]; then
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
  bash /tmp/mc.sh -b -p /opt/miniconda
fi
source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

# ---- env `bg`: BoltzGen (matches boltzgen_ourtarget.sh) ----
sig env_bg
conda create -y -n bg -c conda-forge python=3.12
conda run -n bg pip install -q boltzgen gemmi numpy
git clone https://github.com/HannesStark/boltzgen /opt/boltzgen || (cd /opt/boltzgen && git pull || true)
export HF_HOME=/opt/boltzgen-hf; mkdir -p /opt/boltzgen-hf
conda run -n bg python -c "import boltzgen, torch, gemmi; print('bg ok; cuda', torch.cuda.is_available())"

# ---- env `mmg`: MM-GBSA (matches peptide_mmgbsa_run.sh) ----
sig env_mmg
conda create -y -n mmg -c conda-forge python=3.11 openmm psfgen parmed gemmi numpy
conda run -n mmg python -c "import openmm,parmed,psfgen,gemmi; print('mmg ok; platforms', [openmm.Platform.getPlatform(i).getName() for i in range(openmm.Platform.getNumPlatforms())])"

# ---- pepglad venv: PepGLAD/M2c (matches pdl1_m2c_run.sh driver) ----
sig env_pepglad
python3 -m venv /opt/pepglad-venv; source /opt/pepglad-venv/bin/activate
pip install -q --disable-pip-version-check 'pip==25.0.1'
pip install -q 'torch==2.5.1' --index-url https://download.pytorch.org/whl/cu121
pip install -q 'torch-scatter==2.1.2' --only-binary=:all: -f https://data.pyg.org/whl/torch-2.5.1+cu121.html
pip install -q 'numpy==1.26.4' 'biopython==1.80' 'scipy==1.13.1' 'rdkit==2024.9.6' 'PyYAML==6.0.2' \
            'tqdm==4.67.1' 'networkx==3.2.1' 'sympy==1.13.3' 'tensorboard==2.18.0' 'boto3>=1.36,<2'
python -c "import torch,torch_scatter,rdkit,networkx,sympy,Bio,scipy; print('pepglad ok; cuda', torch.cuda.is_available())"
deactivate

# ---- pre-stage CHARMM36 toppar (MM-GBSA reads these; our S3 cache) ----
sig toppar
mkdir -p /opt/toppar
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/charmm36_toppar/top_all36_prot.rtf" /opt/toppar/ --only-show-errors || true
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/charmm36_toppar/par_all36m_prot.prm" /opt/toppar/ --only-show-errors || true

# ---- manifest ----
sig manifest
{ echo "baked $(date -u +%FT%TZ)";
  echo "envs: /opt/miniconda {bg,mmg} ; /opt/pepglad-venv";
  echo "boltzgen repo: /opt/boltzgen ; HF_HOME=/opt/boltzgen-hf ; toppar: /opt/toppar";
  conda run -n bg python -c "import boltzgen;print('boltzgen',boltzgen.__version__)" 2>/dev/null || true;
  conda run -n mmg python -c "import openmm;print('openmm',openmm.__version__)" 2>/dev/null || true;
} > /opt/bake/MANIFEST.txt
cat /opt/bake/MANIFEST.txt
aws s3 cp /opt/bake/MANIFEST.txt "$BAKE_S3/MANIFEST.txt" --only-show-errors || true

sig READY
echo "=== BAKE COMPLETE — instance ready to snapshot into an AMI (does NOT self-terminate) ==="
