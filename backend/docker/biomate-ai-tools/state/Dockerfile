# State: Virtual Cell Model for Perturbation Response Prediction
# Supports: x86_64, ARM64 (CPU mode)
# Requirements: 8GB+ GPU optional, 16GB RAM

ARG PYTHON_VERSION=3.11

FROM python:${PYTHON_VERSION}-slim

LABEL maintainer="Biomate Team"
LABEL description="Arc Institute State - Virtual cell model for perturbation response prediction"
LABEL version="latest"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast package management
RUN pip install --no-cache-dir uv

# Create working directory
WORKDIR /workspace

# Install State from Arc Institute
RUN git clone --depth 1 https://github.com/ArcInstitute/state.git /opt/state && \
    cd /opt/state && \
    uv pip install --system -e .

# Set Python path
ENV PYTHONPATH="/opt/state:$PYTHONPATH"

ENTRYPOINT ["python", "-m", "state"]
CMD ["--help"]
