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
# Build (amd64 for AWS Batch):
#   docker build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:x86 \
#     -f backend/docker/biomni-admet/Dockerfile .
#
# Build (arm64 for Graviton on-prem — requires biomate/nextflow-base:arm64 in ECR):
#   docker build --platform linux/arm64 \
#     --build-arg TARGETARCH=arm64 --build-arg BASE_TAG=arm64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:arm64 \
#     -f backend/docker/biomni-admet/Dockerfile .

# BASE_TAG selects the arch-specific nextflow-base image.
# amd64 builds use :latest (= :x86); arm64 CI passes BASE_TAG=arm64.
ARG BASE_TAG=latest
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/nextflow-base:${BASE_TAG}

# TARGETARCH controls arch-specific install paths (e.g. torch wheel index).
ARG TARGETARCH=amd64

LABEL maintainer="BioMate Team"
LABEL version="1.0.0"
LABEL description="biomni-admet: ADMET-AI (Chemprop), mordred, PyTDC, ChEMBL client — dedicated ADMET prediction"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── System deps needed by admet-ai / mordred ───────────────────────────────
# libgomp1: OpenMP required by Chemprop's C extensions
# libxrender1 + libxext6: RDKit 2D rendering (already in base but be explicit)
# git: needed by PyTDC/mordred setup.py when building from source on arm64
#      (no pre-built arm64 wheel for some pinned versions)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libxrender1 \
    libxext6 \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── Reproducible dependency lock ───────────────────────────────────────────
# requirements.lock is a pip CONSTRAINTS file (full pip freeze, 170 pkgs) captured
# from a VERIFIED build (ADMET-AI predict() → 98 endpoints, no crash / no RDKit
# fallback). Passing it as `-c` to EVERY install pins the WHOLE transitive graph, so
# a rebuild can't silently drift. This closes the entire "dependency drift broke
# inference" bug class that produced, one at a time:
#   • "cat() received ... (NoneType, dim=int)"  — chemprop/torch/admet-ai drift
#   • "too many indices for array ..."           — numpy 2.x (chemprop 1.6.1 needs <2)
# To bump versions deliberately: edit the constraint, rebuild, and let the CI smoke
# (ADMETModel.predict) gate the change; then regenerate the lock from the new freeze.
COPY backend/docker/biomni-admet/requirements.lock /tmp/biomni-admet.lock

# CPU-only PyTorch (~250 MB vs CUDA ~2 GB; ADMET is small-batch inference).
# amd64: the +cpu wheel index carries torch==2.3.1+cpu (matches the lock pin).
# arm64: standard PyPI has aarch64 CPU wheels as plain torch==2.3.1 (no +cpu suffix);
#        the lock pin torch==2.3.1+cpu would fail on arm64, so we skip -c for torch only.
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      pip install --no-cache-dir torch; \
    else \
      pip install --no-cache-dir -c /tmp/biomni-admet.lock \
        torch --index-url https://download.pytorch.org/whl/cpu; \
    fi

# Everything else — versions come from the lock (numpy 1.26.4, chemprop 1.6.1,
# descriptastorus 2.8.0, admet-ai 1.3.1, mordred, PyTDC, sklearn, matplotlib,
# chembl client + all transitive deps).
RUN pip install --no-cache-dir -c /tmp/biomni-admet.lock \
    numpy scikit-learn matplotlib mordred PyTDC chembl_webresource_client descriptastorus

RUN pip install --no-cache-dir -c /tmp/biomni-admet.lock \
    chemprop admet-ai

# ── Package verification ──────────────────────────────────────────────────────
# CI builds use native runners (amd64 on ubuntu-latest, arm64 on ubuntu-24.04-arm),
# so the full smoke test (ADMETModel.predict) runs natively inside the built image.
# No QEMU, no C-extension segfaults during build or smoke.
RUN pip show admet-ai mordred PyTDC chembl_webresource_client scikit-learn | \
    grep -E "^Name:|^Version:" && \
    aws --version && \
    echo "biomni-admet package verification passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate ADMET Container Ready')"]
