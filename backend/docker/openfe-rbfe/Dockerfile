# BioMate OpenFE RBFE Container
# Relative Binding Free Energy (RBFE) calculations using OpenFE alchemical engine.
# All packages are open-source (MIT/BSD/Apache); no commercial license needed.
#
# Packages:
#   openfe          : Alchemical RBFE engine (lomap2 network + OpenMM simulation)
#   openff-toolkit  : Open Force Field toolkit for force field assignment
#   openmmforcefields: AMBER ff14sb, ff19sb, CHARMM36, OpenFF 2.x for OpenMM
#   cinnabar        : RBFE results analysis, network statistics, plotting
#   lomap2          : Lead optimization mapper for perturbation network generation
#   OpenMM          : GPU/CPU molecular simulation engine
#
# Build:
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-rbfe:1.0 \
#     --push -f backend/docker/openfe-rbfe/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="OpenFE RBFE: alchemical relative binding free energy via OpenMM + lomap2"

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnetcdf-dev \
    libhdf5-dev \
    && rm -rf /var/lib/apt/lists/*

# ── CPU-only PyTorch (OpenMM-ML optional dependency; RBFE runs on CPU/CUDA) ──
RUN pip install --no-cache-dir torch \
    --index-url https://download.pytorch.org/whl/cpu

# ── Core RBFE stack ───────────────────────────────────────────────────────────
RUN pip install --no-cache-dir \
    "openfe>=1.1.0" \
    "openff-toolkit>=0.16.0" \
    "openmmforcefields>=0.12.0" \
    "openmm>=8.1.0" \
    "lomap2>=2.2.0" \
    "cinnabar>=0.4.0" \
    "mdanalysis>=2.7.0" \
    "gufe>=1.1.0"

# ── Verify ────────────────────────────────────────────────────────────────────
RUN pip show openfe openff-toolkit openmmforcefields openmm lomap2 cinnabar | \
    grep -E "^Name:|^Version:" && \
    aws --version && \
    echo "openfe-rbfe checks passed."

WORKDIR /data
CMD ["python3", "-c", "import openfe; print('OpenFE', openfe.__version__, 'ready')"]
