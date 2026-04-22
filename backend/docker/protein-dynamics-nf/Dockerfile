# BioMate Protein Dynamics Nextflow Container
# Tools: BioEmu-1 (conformational ensemble), PocketMiner, fpocket, MDAnalysis, OpenMM
# Base: PyTorch 2.1 with CUDA 12.1 / cuDNN 8 runtime

FROM pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime

LABEL maintainer="BioMate Team"
LABEL description="Protein dynamics & conformational ensemble sampling for BioMate workflows"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
# Prevent interactive prompts from OpenMM / conda solvers
ENV PIP_NO_INPUT=1

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    git \
    build-essential \
    cmake \
    libnetcdf-dev \
    libhdf5-dev \
    pkg-config \
    autoconf \
    automake \
    libtool \
    && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install --install-dir /opt/aws-cli --bin-dir /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── Conda: fpocket + OpenMM (easier via conda-forge than pip) ─────────────────
# Install miniconda alongside the existing base Python in the PyTorch image
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
        -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh

ENV PATH="/opt/conda/bin:${PATH}"

RUN conda install -y -n base -c bioconda -c conda-forge \
        fpocket \
        openmm \
    && conda clean -ya

# ── Python packages (pip into the conda base env) ─────────────────────────────
COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir \
    # Pinned direct deps first to avoid solver churn
    "numpy>=1.24.0,<2.0.0" \
    "scipy>=1.11.0" \
    "pandas>=2.0.0" \
    "matplotlib>=3.7.0" \
    "seaborn>=0.12.0" \
    "biopython>=1.81" \
    "mdanalysis>=2.6.0" \
    "nglview>=3.0.8" \
    "umap-learn>=0.5.5" \
    "scikit-learn>=1.3.0" \
    "tqdm>=4.65.0" \
    "h5py>=3.9.0" \
    && pip install --no-cache-dir \
    "bioemu>=0.1.0" \
    "cryodrgn>=3.0.0"

# ── PocketMiner (Hoecker-Lab) — clone & install ───────────────────────────────
RUN git clone --depth 1 https://github.com/Hoecker-Lab/pocketminer.git /opt/pocketminer \
    && pip install --no-cache-dir /opt/pocketminer

ENV POCKETMINER_HOME=/opt/pocketminer

# ── PATH additions ────────────────────────────────────────────────────────────
ENV PATH="/opt/aws-cli/bin:${PATH}"

WORKDIR /data
CMD ["bash"]
