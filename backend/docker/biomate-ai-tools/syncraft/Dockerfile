# SynCraft: LLM-Guided Synthesizability Optimization
# Supports: x86_64, ARM64 (CPU only - uses Gemini API)
# Requirements: No GPU needed, Gemini API key required

ARG PYTHON_VERSION=3.10

FROM python:${PYTHON_VERSION}-slim

LABEL maintainer="Biomate Team"
LABEL description="SynCraft - LLM-guided molecular synthesizability optimization"
LABEL version="latest"
LABEL arxiv="2512.20333"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /workspace

# Install Python dependencies
RUN pip install --no-cache-dir \
    rdkit \
    google-generativeai \
    numpy \
    pandas \
    tqdm

# Clone SynCraft
RUN git clone --depth 1 https://github.com/catalystforyou/SynCraft-Core.git /opt/syncraft

ENV PYTHONPATH="/opt/syncraft:$PYTHONPATH"

# Note: AutoDock Vina needs to be installed separately for local docking
# For API-based approach, only Gemini API is required

WORKDIR /opt/syncraft

ENTRYPOINT ["python"]
CMD ["--help"]
