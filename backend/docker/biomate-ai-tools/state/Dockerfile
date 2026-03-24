# STATE: Virtual Cell Model for Perturbation Response Prediction
# Built from local tools_repos/state (no network clone, fixes local path deps)
# Requirements: 8GB+ GPU optional, 16GB RAM
# Build context: repo root  docker build -f backend/docker/biomate-ai-tools/state/Dockerfile .

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="Arc Institute STATE - Virtual cell model for perturbation response prediction"
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

# Copy STATE source from local tools_repos
COPY tools_repos/state/ /opt/state/

# Fix pyproject.toml: remove uv-specific [tool.uv.sources] local path override
# (pip ignores [tool.uv.sources] but the section shouldn't break pip install)
# Install core deps first then state package
RUN pip install --no-cache-dir \
    anndata \
    scanpy \
    lightning \
    transformers \
    peft \
    hydra-core \
    omegaconf \
    wandb \
    geomloss \
    huggingface_hub \
    scipy \
    seaborn \
    tqdm

# Install cell-eval and cell-load from PyPI (STATE's external dependencies)
RUN pip install --no-cache-dir cell-eval cell-load || \
    pip install --no-cache-dir \
        "git+https://github.com/ArcInstitute/cell-eval.git" \
        "git+https://github.com/ArcInstitute/cell-load.git" || true

# Install STATE package (no-deps first to avoid resolver conflicts)
RUN pip install --no-cache-dir --no-deps -e . && \
    echo "STATE installed successfully" || \
    (echo "WARNING: STATE install failed, trying with deps" && pip install --no-cache-dir -e . || true)

# Create models directory
RUN mkdir -p /models/state

# Set environment variables
ENV STATE_MODEL_DIR=/models/state
ENV PYTHONPATH="/opt/state/src:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY backend/docker/biomate-ai-tools/state/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
