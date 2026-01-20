# DrugCLIP: Virtual Screening 10M× Faster
# Supports: x86_64, ARM64 (CPU mode)
# Requirements: 8GB+ GPU optional, 16GB RAM

ARG PYTHON_VERSION=3.10

FROM python:${PYTHON_VERSION}-slim

LABEL maintainer="Biomate Team"
LABEL description="DrugCLIP - Deep contrastive learning for genome-wide virtual screening"
LABEL version="latest"
LABEL doi="10.1126/science.ads9530"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Install conda for RDKit
RUN pip install --no-cache-dir conda-pack

# Create working directory
WORKDIR /workspace

# Install DrugCLIP dependencies
RUN pip install --no-cache-dir \
    torch \
    numpy \
    pandas \
    scikit-learn \
    tqdm

# Clone DrugCLIP
RUN git clone --depth 1 https://github.com/bowen-gao/DrugCLIP.git /opt/drugclip

# Install RDKit via pip (newer versions support this)
RUN pip install --no-cache-dir rdkit

ENV PYTHONPATH="/opt/drugclip:$PYTHONPATH"

WORKDIR /opt/drugclip

ENTRYPOINT ["python"]
CMD ["--help"]
