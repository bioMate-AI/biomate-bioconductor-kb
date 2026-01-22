# ProFam-1: Protein Family Language Model for Fitness Prediction
# Supports: x86_64, ARM64
# Requirements: 8GB+ GPU recommended, 16GB RAM

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="ProFam-1 - 251M protein family language model for fitness prediction"
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
WORKDIR /opt/profam

# Clone ProFam repository
RUN git clone --depth 1 https://github.com/alex-hh/profam.git .

# Install Python dependencies
RUN pip install --no-cache-dir \
    torch \
    transformers \
    datasets \
    biopython \
    biotite \
    biotraj \
    hydra-core \
    omegaconf \
    rootutils \
    rich \
    pyrootutils \
    huggingface_hub

# Install ProFam package
RUN pip install --no-cache-dir -e .

# Create models directory
RUN mkdir -p /models/profam

# Set environment variables
ENV PROFAM_DIR=/opt/profam
ENV PROFAM_CHECKPOINT=/models/profam
ENV PYTHONPATH="/opt/profam/src:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
