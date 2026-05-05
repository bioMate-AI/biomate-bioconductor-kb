FROM pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime

LABEL maintainer="biomate" \
      description="Cryo-EM conformational heterogeneity analysis — cryoDRGN VAE + fpocket ensemble druggability" \
      version="1.0.1"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        unzip \
        jq \
        procps \
        git \
        build-essential \
        cmake \
        libnetcdf-dev \
        netcdf-bin \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# ── fpocket from source ───────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/Discngine/fpocket.git /tmp/fpocket \
    && cd /tmp/fpocket \
    && make \
    && make install \
    && rm -rf /tmp/fpocket

# ── Python packages ───────────────────────────────────────────────────────────
# Install torch CUDA version explicitly BEFORE requirements.txt to prevent
# pip from overwriting the base image's CUDA-enabled torch with a CPU-only build.
RUN pip install --no-cache-dir \
    "torch==2.1.0" \
    --index-url https://download.pytorch.org/whl/cu121

COPY requirements.txt /tmp/requirements.txt
# Install remaining deps without reinstalling torch
RUN pip install --no-cache-dir -r /tmp/requirements.txt --no-deps || \
    pip install --no-cache-dir -r /tmp/requirements.txt \
    && python -c "import torch; print('torch', torch.__version__, 'cuda:', torch.cuda.is_available())"

ENV PATH="/opt/aws-cli/bin:${PATH}"

WORKDIR /workspace
CMD ["python3"]
