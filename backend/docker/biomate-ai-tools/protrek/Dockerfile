# ProTrek: Protein Sequence-Structure-Function Search
# Built from local tools_repos/ProTrek (reliable, no network clone)
# Requirements: 8GB+ GPU recommended, 16GB RAM
# Build context: repo root  docker build -f backend/docker/biomate-ai-tools/protrek/Dockerfile .

FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

LABEL maintainer="Biomate Team"
LABEL description="ProTrek - Navigating the Protein Universe through Tri-Modal Contrastive Learning"
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
WORKDIR /opt/protrek

# Copy ProTrek source from local tools_repos (no GitHub clone dependency)
COPY tools_repos/ProTrek/ /opt/protrek/

# Install Python dependencies (torch already in base image, exclude version pins)
RUN pip install --no-cache-dir \
    transformers \
    faiss-cpu \
    biopython \
    pandas \
    numpy \
    tqdm \
    huggingface_hub \
    sentencepiece \
    "gradio>=4.0,<5.0" \
    torchmetrics \
    pytorch-lightning \
    scikit-learn \
    tabulate \
    easydict \
    lmdb \
    multiprocess \
    pyspellchecker \
    uvicorn \
    fastapi

# Copy CLI wrapper scripts into the demo directory
COPY backend/docker/biomate-ai-tools/protrek/search.py /opt/protrek/demo/search.py
COPY backend/docker/biomate-ai-tools/protrek/embed.py /opt/protrek/demo/embed.py
RUN chmod +x /opt/protrek/demo/search.py /opt/protrek/demo/embed.py

# Create models directory
RUN mkdir -p /models/protrek

# Set environment variables
ENV PROTREK_DIR=/opt/protrek
ENV PROTREK_MODEL=/models/protrek
ENV PYTHONPATH="/opt/protrek:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY backend/docker/biomate-ai-tools/protrek/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
