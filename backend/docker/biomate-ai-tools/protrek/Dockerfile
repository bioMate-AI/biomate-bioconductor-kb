# ProTrek: Protein Sequence-Structure-Function Search
# Supports: x86_64, ARM64
# Requirements: 8GB+ GPU recommended, 16GB RAM

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

# Clone ProTrek repository
RUN git clone --depth 1 https://github.com/westlake-repl/ProTrek.git .

# Install Python dependencies
RUN pip install --no-cache-dir \
    torch \
    transformers \
    faiss-cpu \
    biopython \
    pandas \
    numpy \
    tqdm \
    huggingface_hub \
    sentencepiece

# Create models directory
RUN mkdir -p /models/protrek

# Set environment variables
ENV PROTREK_DIR=/opt/protrek
ENV PROTREK_MODEL=/models/protrek
ENV PYTHONPATH="/opt/protrek:$PYTHONPATH"

# Default entrypoint
WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
