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

# ── PyTorch CPU-only ───────────────────────────────────────────────────────
# Install CPU-only PyTorch BEFORE admet-ai so pip doesn't pull the full
# CUDA wheel (~2 GB). ADMET prediction is purely inference on small molecule
# batches — GPU is not needed and adds no throughput benefit here.
# CPU wheel: ~250 MB vs CUDA wheel: ~2 GB.
RUN pip install --no-cache-dir \
    torch \
    --index-url https://download.pytorch.org/whl/cpu

# ── scikit-learn + matplotlib (lightweight, needed for fallback models) ────
RUN pip install --no-cache-dir \
    scikit-learn \
    matplotlib

# ── mordred (1826 molecular descriptors) ──────────────────────────────────
RUN pip install --no-cache-dir "mordred==1.2.0"

# ── PyTDC (TDC benchmark datasets + splits) ───────────────────────────────
RUN pip install --no-cache-dir PyTDC

# ── ChEMBL REST API client ─────────────────────────────────────────────────
RUN pip install --no-cache-dir chembl_webresource_client

# ── ADMET-AI (Chemprop-backed, bundled pre-trained models) ────────────────
# admet-ai requires torch>=2.8.0 — already satisfied by CPU wheel above.
# Chemprop will reuse the existing torch install, not pull a new one.
RUN pip install --no-cache-dir admet-ai

# ── Package verification (pip show only — no import/execution) ───────────────
# C extensions (RDKit, mordred, PyTorch/Chemprop) segfault under QEMU x86_64
# emulation used by buildx cross-compilation. Verify via pip metadata only;
# all imports and inference are tested when the container runs on real hardware.
RUN pip show admet-ai mordred PyTDC chembl_webresource_client scikit-learn | \
    grep -E "^Name:|^Version:" && \
    aws --version && \
    echo "biomni-admet package verification passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate ADMET Container Ready')"]
