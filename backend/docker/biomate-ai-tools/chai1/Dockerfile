# Chai-1: Multi-Modal Biomolecular Structure Prediction
# Supports: x86_64 (CUDA required)
# Requirements: 24-80GB GPU, 32GB+ RAM

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="Chai-1 - Multi-modal foundation model for molecular structure prediction"
LABEL version="latest"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/chai

# Clone Chai-1 repository
RUN git clone --depth 1 https://github.com/chaidiscovery/chai-lab.git .

# Install Python dependencies
RUN pip install --no-cache-dir \
    torch \
    einops \
    gemmi \
    modelcif \
    numpy \
    pandas \
    pyyaml \
    rdkit \
    huggingface_hub

# Install Chai-1 package
RUN pip install --no-cache-dir -e .

# Create models directory
RUN mkdir -p /models/chai1

# Set environment variables
ENV CHAI_DIR=/opt/chai
ENV CHAI_MODEL=/models/chai1
ENV PYTHONPATH="/opt/chai:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
