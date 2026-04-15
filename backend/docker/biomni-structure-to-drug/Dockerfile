# BioMate Structure-to-Drug Container
#
# Used by drug discovery workflows that need structure-based tools:
#   - pocket_detection_druggability  (fpocket + Python analysis)
#   - pharmacophore_filtering
#   - structure_prediction_docking   (AlphaFold3 path, non-GPU steps)
#
# Inherits AWS CLI v2 + numpy/scipy/pandas/biopython/rdkit from base.
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-structure-to-drug:x86 \
#     --push -f backend/docker/biomni-structure-to-drug/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="biomni-structure-to-drug: fpocket, AutoDock Vina, pharmacophore, structure-based drug design"
LABEL version="2.1.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── System dependencies + fpocket build ───────────────────────────────────
# libgomp1/libgfortran5: OpenMP + Fortran runtime (Vina, RDKit)
# libxrender1/libxext6:  X11 stubs for RDKit 2D rendering
# git/build-essential:   compile fpocket from source (not in apt)
# fpocket:               Binding-site detection (Le Guilloux et al. 2009)
#                        Required by pocket_detection_druggability workflow
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libgfortran5 \
    libxrender1 \
    libxext6 \
    git \
    build-essential \
    && git clone --depth 1 https://github.com/Discngine/fpocket.git /tmp/fpocket \
    && cd /tmp/fpocket && make \
    && cp bin/fpocket bin/dpocket bin/mdpocket /usr/local/bin/ \
    && rm -rf /tmp/fpocket \
    && apt-get purge -y --auto-remove git build-essential \
    && rm -rf /var/lib/apt/lists/*

# ── Structure-based drug design Python packages ───────────────────────────
# numpy/scipy/pandas/biopython/rdkit already in biomate-nextflow-base.
RUN pip install --no-cache-dir \
    gemmi \
    vina \
    meeko \
    openbabel-wheel \
    scikit-learn \
    matplotlib \
    plotly \
    pubchempy

# ── Smoke tests ────────────────────────────────────────────────────────────
RUN python3 -c "from rdkit import Chem; print('rdkit OK')" && \
    python3 -c "from vina import Vina; print('vina OK')" && \
    fpocket --help 2>&1 | head -1 && echo "fpocket OK" && \
    aws --version && \
    echo "biomni-structure-to-drug checks passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Structure-to-Drug Container Ready')"]
