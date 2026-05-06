# AlphaFold 3 inference container for BioMate
# Base: CUDA 12.2 + Python 3.12 (AF3 requires Python >=3.12)
FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04

LABEL maintainer="BioMate Team"
LABEL description="AlphaFold 3 structure prediction for BioMate workflows"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── System dependencies ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-dev python3.12-venv python3-pip \
    curl unzip git build-essential cmake ninja-build \
    libhdf5-dev pkg-config pybind11-dev \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && python3.12 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install --install-dir /opt/aws-cli --bin-dir /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── AlphaFold 3 source ────────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/google-deepmind/alphafold3.git /opt/alphafold3

# ── AF3 Python dependencies ───────────────────────────────────────────────────
# Install JAX CUDA 12 first — prevents pip from pulling CPU-only jaxlib later
RUN pip install --no-cache-dir \
    "jax[cuda12]==0.8.1" \
    "dm-haiku==0.0.16" \
    "absl-py>=2.3.1" \
    "rdkit==2024.3.5" \
    "setuptools==78.1.0" \
    "tqdm" \
    "zstandard" \
    "numpy" \
    "scipy"

# ── Install AF3 package (builds pybind11 C++ extensions via cmake) ────────────
RUN pip install --no-cache-dir /opt/alphafold3 \
    && python3 -c "import alphafold3; print('AF3 installed OK')"

ENV PATH="/opt/aws-cli/bin:${PATH}"
ENV AF3_SRC="/opt/alphafold3"

WORKDIR /data
CMD ["bash"]
