# BioMate AmberTools + GROMACS Nextflow Container (AMD64)
# All packages installed via conda-forge to avoid wheel compilation under QEMU.
# Used by gromacs_protein_md and amber_pmemd_md workflows on AWS Batch.

FROM --platform=linux/amd64 continuumio/miniconda3:24.5.0-0

LABEL maintainer="BioMate Team"
LABEL description="AmberTools 23 + GROMACS 2024 for BioMate MD workflows"
LABEL version="1.2.0"

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip less && rm -rf /var/lib/apt/lists/*

# ── Install aws CLI v2 at /opt/aws-cli (matches Nextflow batch.cliPath) ───────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Conda environment: AmberTools + GROMACS + RDKit + acpype ────────────────
# Install everything via conda-forge to avoid pip wheel compilation under QEMU
RUN conda install -y -n base -c conda-forge \
    ambertools=23 \
    gromacs=2024.2 \
    openmpi \
    mpi4py \
    rdkit \
    acpype \
    gmx_mmpbsa \
    && conda clean -ya

# Verify gmx_MMPBSA can load MPI (Batch MM-GBSA failed with libmpi.so missing in v1.1.0)
RUN python3 -c "from mpi4py import MPI; import GMXMMPBSA" \
    && gmx_MMPBSA --version

# ── PATH ─────────────────────────────────────────────────────────────────────
ENV PATH="/opt/aws-cli/bin:/opt/conda/bin:${PATH}"

WORKDIR /data
CMD ["bash"]
