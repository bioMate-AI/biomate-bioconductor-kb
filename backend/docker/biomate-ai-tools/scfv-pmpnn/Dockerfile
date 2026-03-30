# scFv-pMPNN: Single-chain Fv Antibody Design
# Built from local tools_repos/scFv_Pmpnn_AF2 + CLI wrappers
# Supports: x86_64 (linux/amd64) — CUDA required
# Requirements: 16GB+ GPU, 32GB+ RAM
# Build context: repo root  docker build -f backend/docker/biomate-ai-tools/scfv-pmpnn/Dockerfile .

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="scFv-pMPNN - Antibody design using ProteinMPNN with AlphaFold2"
LABEL architecture="x86_64"
LABEL version="latest"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies (hmmer for ANARCI antibody numbering)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    wget \
    hmmer \
    && rm -rf /var/lib/apt/lists/*

# Create working directory and copy source
WORKDIR /opt/scfv-pmpnn
COPY tools_repos/scFv_Pmpnn_AF2/ /opt/scfv-pmpnn/

# Install Python dependencies (torch already in base image)
RUN pip install --no-cache-dir \
    biopython \
    numpy \
    pandas \
    scipy \
    matplotlib \
    weblogo \
    anarci || true

# Copy CLI wrapper scripts (run_design.py, run_predict.py)
# These expose the pipeline as Python CLI tools for Nextflow
COPY backend/docker/biomate-ai-tools/scfv-pmpnn/run_design.py /opt/scfv-pmpnn/run_design.py
COPY backend/docker/biomate-ai-tools/scfv-pmpnn/run_predict.py /opt/scfv-pmpnn/run_predict.py
RUN chmod +x /opt/scfv-pmpnn/run_design.py /opt/scfv-pmpnn/run_predict.py

# Create models directories
RUN mkdir -p /models/scfv-pmpnn /models/alphafold2 /opt/ProteinMPNN

# Set environment variables
ENV SCFV_PMPNN_DIR=/opt/scfv-pmpnn
ENV SCFV_MODEL=/models/scfv-pmpnn
ENV AF2_MODEL=/models/alphafold2
ENV PMPNN_DIR=/opt/ProteinMPNN
ENV COLABFOLD_DIR=/opt/localcolabfold/colabfold-conda/bin
ENV PYTHONPATH="/opt/scfv-pmpnn:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY backend/docker/biomate-ai-tools/scfv-pmpnn/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
