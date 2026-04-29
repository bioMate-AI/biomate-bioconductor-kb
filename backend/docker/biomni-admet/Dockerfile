# BioMate ADMET Prediction Container (biomni-admet)
#
# Dedicated container for ADMET property prediction workflows.
# Starts from biomate-nextflow-base (NOT biomni-tools) to stay lean.
#
# Base provides: Python 3.11, AWS CLI v2, numpy, scipy, pandas, biopython, rdkit
#
# Adds:
#   admet-ai     : Chemprop-backed ADMET predictor; bundled pre-trained models
#                  for 41 TDC ADMET endpoints (Swanson et al. 2023, Bioinformatics)
#                  Best AUROC on TDC leaderboard: >0.85 on 20/31 classification tasks
#   mordred      : 1826 molecular descriptors for PK property prediction
#   PyTDC        : TDC benchmark datasets + official train/test splits
#   chembl_webresource_client : ChEMBL REST API for bioactivity queries
#   scikit-learn : Random forest / logistic regression fallback models
#   matplotlib   : Plotting for ADMET profile reports
#
# NOT included (those live in biomni-tools):
#   ViennaRNA, AutoDock Vina, Meeko, openbabel, codon-tools, seaborn, plotly
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:x86 \
#     --push -f backend/docker/biomni-admet/Dockerfile .
#
# Local:
#   docker build -t biomate/biomni-admet:latest \
#     -f backend/docker/biomni-admet/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL version="1.0.0"
LABEL description="biomni-admet: ADMET-AI (Chemprop), mordred, PyTDC, ChEMBL client — dedicated ADMET prediction"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── System deps needed by admet-ai / mordred ───────────────────────────────
# libgomp1: OpenMP required by Chemprop's C extensions
# libxrender1 + libxext6: RDKit 2D rendering (already in base but be explicit)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# ── scikit-learn + matplotlib (lightweight, needed for fallback models) ────
RUN pip install --no-cache-dir \
    scikit-learn \
    matplotlib

# ── mordred (1826 molecular descriptors) ──────────────────────────────────
# Pin 1.2.1 — stable, rdkit-compatible
RUN pip install --no-cache-dir "mordred==1.2.1"

# ── PyTDC (TDC benchmark datasets + splits) ───────────────────────────────
RUN pip install --no-cache-dir PyTDC

# ── ChEMBL REST API client ─────────────────────────────────────────────────
RUN pip install --no-cache-dir chembl_webresource_client

# ── ADMET-AI (Chemprop-backed, bundled pre-trained models) ────────────────
# This is the primary ADMET predictor. Replaces DeepPurpose.
# admet-ai ships with Chemprop as a dependency — no separate install needed.
# Models are bundled in the package; no download required on first use.
RUN pip install --no-cache-dir admet-ai

# ── Smoke tests ────────────────────────────────────────────────────────────
RUN python3 -c "\
from admet_ai import ADMETModel; \
model = ADMETModel(); \
df = model.predict(smiles=['CC(=O)Oc1ccccc1C(=O)O']); \
cols = list(df.columns); \
print('ADMET-AI OK  n_endpoints={} hERG={:.3f}'.format(len(cols), df['hERG'].iloc[0]))" && \
    python3 -c "\
from mordred import Calculator, descriptors; \
calc = Calculator(descriptors, ignore_3D=True); \
print('mordred OK  n_descriptors={}'.format(len(calc.descriptors)))" && \
    python3 -c "from tdc.single_pred import ADMET; print('PyTDC OK')" && \
    python3 -c "from chembl_webresource_client.new_client import new_client; print('ChEMBL client OK')" && \
    python3 -c "from rdkit import Chem; print('RDKit OK (from base)')" && \
    aws --version && \
    echo "All biomni-admet checks passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate ADMET Container Ready')"]
