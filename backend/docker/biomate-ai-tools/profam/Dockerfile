# ProFam-1: Protein Family Language Model for Fitness Prediction
# Built from local tools_repos/profam (reliable, no network clone)
# Requirements: 8GB+ GPU recommended, 16GB RAM
# Build context: repo root  docker build -f backend/docker/biomate-ai-tools/profam/Dockerfile .

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

# Copy ProFam source from local tools_repos (no GitHub clone dependency)
COPY tools_repos/profam/ /opt/profam/

# Install Python dependencies (torch already in base image)
RUN pip install --no-cache-dir \
    transformers \
    datasets \
    biopython \
    biotite \
    hydra-core \
    omegaconf \
    rootutils \
    rich \
    pyrootutils \
    huggingface_hub \
    pytorch-lightning \
    lightning \
    scikit-learn \
    pandas \
    numpy \
    tqdm

# Install ProFam package
RUN pip install --no-cache-dir -e . || pip install --no-cache-dir --no-deps -e .

# Ensure scripts are executable
RUN chmod +x /opt/profam/scripts/score_sequences.py 2>/dev/null || true && \
    chmod +x /opt/profam/scripts/generate_sequences.py 2>/dev/null || true

# Create models directory
RUN mkdir -p /models/profam

# Set environment variables
ENV PROFAM_DIR=/opt/profam
ENV PROFAM_CHECKPOINT=/models/profam
ENV PYTHONPATH="/opt/profam/src:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY backend/docker/biomate-ai-tools/profam/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
