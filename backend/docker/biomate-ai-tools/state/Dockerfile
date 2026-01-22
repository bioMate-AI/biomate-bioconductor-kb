# State: Virtual Cell Model for Perturbation Response Prediction
# Supports: x86_64, ARM64 (CPU mode)
# Requirements: 8GB+ GPU optional, 16GB RAM

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="Arc Institute State - Virtual cell model for perturbation response prediction"
LABEL version="latest"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/state

# Clone State repository
RUN git clone --depth 1 https://github.com/ArcInstitute/state.git .

# Fix pyproject.toml - remove local path dependencies
RUN sed -i 's|file:///home/aadduri/cell-eval|git+https://github.com/ArcInstitute/cell-eval.git|g' pyproject.toml || true && \
    sed -i 's|file:///home/aadduri/cell-load|git+https://github.com/ArcInstitute/cell-load.git|g' pyproject.toml || true

# Install Python dependencies
RUN pip install --no-cache-dir \
    anndata \
    scanpy \
    torch \
    lightning \
    transformers \
    peft \
    hydra-core \
    omegaconf \
    wandb \
    geomloss \
    huggingface_hub

# Install State package (ignore dependency resolver issues)
RUN pip install --no-cache-dir --no-deps -e . || pip install --no-cache-dir -e . || true

# Create models directory
RUN mkdir -p /models/state

# Set environment variables
ENV STATE_MODEL_DIR=/models/state
ENV PYTHONPATH="/opt/state:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
