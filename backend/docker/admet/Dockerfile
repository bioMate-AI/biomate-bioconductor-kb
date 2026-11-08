# BioMate ADMET Prediction Container (admet)
#
# Dedicated container for ADMET property prediction workflows.
# Starts from biomate-nextflow-base (NOT workflow-tools) to stay lean.
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
# NOT included (those live in workflow-tools):
#   ViennaRNA, AutoDock Vina, Meeko, openbabel, codon-tools, seaborn, plotly
#
# Build (amd64 for AWS Batch):
#   docker build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/admet:x86 \
#     -f backend/docker/admet/Dockerfile .
#
# Build (arm64 for Graviton on-prem — requires biomate/nextflow-base:arm64 in ECR):
#   docker build --platform linux/arm64 \
#     --build-arg TARGETARCH=arm64 --build-arg BASE_TAG=arm64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/admet:arm64 \
#     -f backend/docker/admet/Dockerfile .

# BASE_TAG selects the arch-specific nextflow-base image.
# amd64 builds use :latest (= :x86); arm64 CI passes BASE_TAG=arm64.
ARG BASE_TAG=latest
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/nextflow-base:${BASE_TAG}

# TARGETARCH controls arch-specific install paths (e.g. torch wheel index).
ARG TARGETARCH=amd64

LABEL maintainer="BioMate Team"
LABEL version="1.0.0"
LABEL description="admet: ADMET-AI (Chemprop), mordred, PyTDC, ChEMBL client — dedicated ADMET prediction"

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
COPY backend/docker/admet/requirements.lock /tmp/admet.lock

# On arm64: strip the "+cpu" local-version suffix from the torch constraint line.
# That suffix only exists in the amd64-specific download.pytorch.org/whl/cpu index;
# standard PyPI carries plain torch==2.3.1 wheels for aarch64.  Leaving +cpu in the
# constraint causes a ResolutionImpossible when pip resolves PyTDC→accelerate→torch
# and finds the installed plain 2.3.1 doesn't satisfy the ==2.3.1+cpu pin.
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      sed -i 's/torch==\([0-9.]*\)+cpu/torch==\1/' /tmp/admet.lock; \
    fi

# CPU-only PyTorch (~250 MB vs CUDA ~2 GB; ADMET is small-batch inference).
# amd64: the +cpu wheel index carries torch==2.3.1+cpu (matches the lock pin).
# arm64: standard PyPI has aarch64 CPU wheels as plain torch==2.3.1 (no +cpu suffix).
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      pip install --no-cache-dir -c /tmp/admet.lock torch; \
    else \
      pip install --no-cache-dir -c /tmp/admet.lock \
        torch --index-url https://download.pytorch.org/whl/cpu; \
    fi

# Everything else — versions come from the lock (numpy 1.26.4, chemprop 1.6.1,
# descriptastorus 2.8.0, admet-ai 1.3.1, mordred, PyTDC, sklearn, matplotlib,
# chembl client + all transitive deps).
#
# PyTDC arm64 note: PyTDC>=1.0 pulls in tiledbsoma→tiledb (a C++ extension with no
# arm64 pre-built wheel on PyPI; source-building it fails).  tiledb is only used by
# PyTDC's single-cell data path, which BioMate doesn't use — ADMET predictions come
# from admet-ai, not TDC.  On arm64 install PyTDC --no-deps and add only the deps
# that BioMate's ADMET path actually needs (omitting tiledb/tiledbsoma/anndata).
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      pip install --no-cache-dir -c /tmp/admet.lock \
        numpy scikit-learn matplotlib mordred chembl_webresource_client descriptastorus && \
      pip install --no-cache-dir --no-deps -c /tmp/admet.lock PyTDC; \
    else \
      pip install --no-cache-dir -c /tmp/admet.lock \
        numpy scikit-learn matplotlib mordred PyTDC chembl_webresource_client descriptastorus; \
    fi

RUN pip install --no-cache-dir -c /tmp/admet.lock \
    chemprop admet-ai

# ── Package verification ──────────────────────────────────────────────────────
# CI builds use native runners (amd64 on ubuntu-latest, arm64 on ubuntu-24.04-arm),
# so the full smoke test (ADMETModel.predict) runs natively inside the built image.
# No QEMU, no C-extension segfaults during build or smoke.
RUN pip show admet-ai mordred PyTDC chembl_webresource_client scikit-learn | \
    grep -E "^Name:|^Version:" && \
    aws --version && \
    echo "admet package verification passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate ADMET Container Ready')"]
