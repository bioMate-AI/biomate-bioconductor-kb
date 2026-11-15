# BioMate General-Purpose Tools Container (workflow-tools)
#
# Used by 400+ BioMate workflows for:
#   - ViennaRNA     : RNA secondary structure prediction (RNAfold, MFE)
#   - AutoDock Vina : Molecular docking with real binding scores
#   - Meeko         : Ligand/receptor preparation (PDBQT)
#   - RDKit         : Cheminformatics (SMILES, descriptors, pharmacophore)
#   - Biopython     : Sequence handling, PDB parsing, FASTA I/O
#   - openbabel     : File format conversion (SDF/MOL2/PDBQT)
#   - codon_tools   : CAI calculation, codon optimisation
#   - Standard sci-python stack: numpy, scipy, pandas, scikit-learn
#
# Inherits from biomate-nextflow-base:latest which provides:
#   - AWS CLI v2 (required for Nextflow nxf_s3_upload / nxf_s3_download)
#   - numpy, scipy, pandas, biopython, rdkit, gget
#   - procps, curl, bash
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86 \
#     --push -f backend/docker/workflow-tools/Dockerfile .
#
# Local (ARM dev):
#   docker build -t biomate/workflow-tools:latest \
#     -f backend/docker/workflow-tools/Dockerfile .

# All BioMate Nextflow/Batch containers MUST start from this base so that
# nxf_s3_upload / nxf_s3_download shell functions have 'aws' on PATH.
ARG BASE_TAG=latest
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/nextflow-base:${BASE_TAG}

ARG TARGETARCH=amd64

LABEL maintainer="BioMate Team"
LABEL description="workflow-tools: ViennaRNA, AutoDock Vina, RDKit, Biopython, openbabel + pharmacology (statsmodels, scikit-image, DeepPurpose)"
LABEL version="2.1.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── Layer 1: System dependencies ───────────────────────────────────────────
# libgomp1    : OpenMP (needed by Vina, RDKit)
# libgfortran5: Fortran runtime (scipy)
# libxrender1 + libxext6: X11 stubs for RDKit 2D rendering
# swig        : needed by openbabel Python bindings
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libgfortran5 \
    libxrender1 \
    libxext6 \
    swig \
    && rm -rf /var/lib/apt/lists/*

# arm64: vina 1.2.7 has no aarch64 PyPI wheel and builds from source;
# its setup.py requires Boost headers and a C++ compiler (g++).
# amd64 pulls a pre-built vina wheel so neither is needed there.
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libboost-all-dev \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# ── Layer 2: Domain-specific Python packages ───────────────────────────────
# numpy/scipy/pandas/biopython/rdkit are already in biomate-nextflow-base.
RUN pip install --no-cache-dir \
    scikit-learn \
    matplotlib \
    requests \
    pubchempy

# ── Layer 3: ViennaRNA (RNA secondary structure) ───────────────────────────
RUN pip install --no-cache-dir ViennaRNA

# ── Layer 4: AutoDock Vina + Meeko (real molecular docking) ───────────────
RUN pip install --no-cache-dir \
    gemmi \
    vina \
    meeko \
    openbabel-wheel

# ── Layer 5: Codon optimisation tools ─────────────────────────────────────
RUN pip install --no-cache-dir \
    codon-tools \
    python-codon-tables

# ── Layer 6: Pharmacophore + enrichment ────────────────────────────────────
RUN pip install --no-cache-dir \
    adjustText \
    seaborn \
    plotly

# ── Layer 7: Pharmacology-specific packages ────────────────────────────────
# statsmodels  : ANOVA, regression, Tukey HSD (xenograft, MWAS workflows)
# scikit-image : western blot image analysis
# DeepPurpose  : MPNN/CNN ADMET models (ClinTox, solubility); optional in
#                ADMET workflows — falls back to RDKit heuristics if absent,
#                but should be present for full predictions.
RUN pip install --no-cache-dir \
    statsmodels \
    scikit-image \
    opencv-python-headless \
    PyPDF2 \
    flowio
# opencv (cv2, headless — no GUI libs): several image-analysis workflows
# (aortic geometry, mitochondrial morphology, cell morphology/cytoskeleton) import
# cv2. It was MISSING, so those workflows failed at `import cv2` — previously hidden
# by their dishonest-success bug, now an honest failure. Adding it makes them
# runnable. Rebuild + push workflow-tools:x86 for this to take effect on Batch.
# flowio: FCS file reader for flow-cytometry / FACS / CFSE immunophenotyping
# workflows (analyze_flow_cytometry_immunophenotyping and siblings). Missing
# flowio → ModuleNotFoundError → "Essential container in task exited".

# descriptastorus must be installed from GitHub — the PyPI package is stale.
# Canonical pharmacology functions require this dependency through DeepPurpose.
# at import time and returns an error dict if absent. No `|| echo` fallback: a swallowed failure
# ships an image whose ADMET tools no-op at runtime, so the build must fail loudly.
RUN pip install --no-cache-dir \
    "git+https://github.com/bp-kelley/descriptastorus" \
    pandas-flavor \
    six

# DeepPurpose needs a (CPU) torch — install it explicitly so the resolve is deterministic.
# The old `|| echo` swallowed build failures and shipped an image whose affinity/ADMET tools
# no-op at runtime (a fake-success stub). Fail the build loudly, and prove importability below.
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir DeepPurpose
RUN python3 -c "from DeepPurpose import DTI, utils; print('DeepPurpose OK')"

# Canonical workflows embed their implementations and use the scientific
# dependencies above directly. Do not install an obsolete wrapper SDK here.

# ── Smoke tests ────────────────────────────────────────────────────────────
RUN python3 -c "\
import RNA; seq='GGCAUAUGCUUAGUGCAUAUGC'; (struct, mfe) = RNA.fold(seq); \
print('ViennaRNA OK  mfe={:.2f} struct={}'.format(mfe, struct))" && \
    python3 -c "\
from vina import Vina; print('AutoDock Vina OK')" && \
    python3 -c "\
from rdkit import Chem; m=Chem.MolFromSmiles('c1ccccc1'); \
print('RDKit OK  atoms={}'.format(m.GetNumAtoms()))" && \
    python3 -c "\
import Bio; print('Biopython OK  version={}'.format(Bio.__version__))" && \
    python3 -c "\
import meeko; print('Meeko OK')" && \
    python3 -c "import statsmodels; print('statsmodels OK')" && \
    python3 -c "import skimage; print('scikit-image OK')" && \
    python3 -c "import cv2; print('OpenCV OK  version={}'.format(cv2.__version__))" && \
    python3 -c "import PyPDF2; print('PyPDF2 OK')" && \
    python3 -c "import flowio; print('flowio OK  version={}'.format(getattr(flowio, '__version__', '?')))" && \
    aws --version && \
    echo "All workflow-tools checks passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Tools Container Ready')"]
