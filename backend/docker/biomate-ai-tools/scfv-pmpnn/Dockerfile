# scFv-pMPNN: Single-chain Fv Antibody Design
# Supports: x86_64 (CUDA required)
# Requirements: 16GB+ GPU, 32GB+ RAM

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="scFv-pMPNN - Antibody design using ProteinMPNN with AlphaFold2"
LABEL version="latest"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    wget \
    hmmer \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/scfv-pmpnn

# Clone repository
RUN git clone --depth 1 https://github.com/jbderoo/scFv_Pmpnn_AF2.git .

# Install Python dependencies
RUN pip install --no-cache-dir \
    torch \
    biopython \
    numpy \
    pandas \
    scipy \
    dm-haiku \
    jax \
    jaxlib \
    ml-collections

# Create models directory
RUN mkdir -p /models/scfv-pmpnn /models/alphafold2

# Set environment variables
ENV SCFV_PMPNN_DIR=/opt/scfv-pmpnn
ENV SCFV_MODEL=/models/scfv-pmpnn
ENV AF2_MODEL=/models/alphafold2
ENV PYTHONPATH="/opt/scfv-pmpnn:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
