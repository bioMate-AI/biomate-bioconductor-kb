# BioMate AmberTools + GROMACS Nextflow Container (AMD64)
# All packages installed via conda-forge to avoid wheel compilation under QEMU.
# Used by gromacs_protein_md and amber_pmemd_md workflows on AWS Batch.

FROM --platform=linux/amd64 continuumio/miniconda3:24.5.0-0

LABEL maintainer="BioMate Team"
LABEL description="AmberTools 23 + GROMACS 2024 for BioMate MD workflows"
LABEL version="1.1.0"

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip less && rm -rf /var/lib/apt/lists/*

# ── Install aws CLI v2 ───────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Conda environment: AmberTools + GROMACS + RDKit + acpype ────────────────
# Install everything via conda-forge to avoid pip wheel compilation under QEMU
RUN conda install -y -n base -c conda-forge \
    ambertools=23 \
    gromacs=2024.2 \
    rdkit \
    acpype \
    && conda clean -ya

# ── gmx_MMPBSA: try conda first, pip fallback (--no-build-isolation avoids
#    wheel failures when build tools are absent under QEMU emulation) ─────────
RUN conda install -y -n base -c conda-forge gmx_mmpbsa 2>/dev/null \
    || pip install --no-cache-dir --no-build-isolation gmx_MMPBSA \
    || echo "WARNING: gmx_MMPBSA not installed — MM-GBSA step will be skipped"

# ── PATH ─────────────────────────────────────────────────────────────────────
ENV PATH="/opt/conda/bin:${PATH}"

WORKDIR /data
CMD ["bash"]
