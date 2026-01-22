# Boltz-2: Protein-Ligand Structure Prediction
# Supports: x86_64 with CUDA
# Requirements: 16-40GB GPU VRAM

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="Boltz-2 protein-ligand docking and binding affinity prediction"
LABEL version="2.2.1"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python3 -m venv /opt/boltz-env
ENV PATH="/opt/boltz-env/bin:$PATH"

# Install Boltz
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir boltz==2.2.1

# Create working directory
WORKDIR /workspace

# Create entrypoint script
RUN echo '#!/bin/bash\n\
if [ "$1" = "predict" ]; then\n\
    shift\n\
    exec boltz predict "$@"\n\
elif [ "$1" = "server" ]; then\n\
    shift\n\
    exec python -m tooluniverse.remote.boltz.boltz_mcp_server "$@"\n\
else\n\
    exec boltz "$@"\n\
fi' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
