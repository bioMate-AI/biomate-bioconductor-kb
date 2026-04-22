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
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ── Verify key installations ──────────────────────────────────────────────────
RUN python -c "import cryodrgn; print('cryoDRGN:', cryodrgn.__version__)" && \
    python -c "import torch; print('PyTorch:', torch.__version__)" && \
    python -c "import mrcfile; print('mrcfile OK')" && \
    python -c "import starfile; print('starfile OK')" && \
    (fpocket --version 2>/dev/null || fpocket -h 2>&1 | head -1 || echo "fpocket installed")

ENV PATH="/opt/aws-cli/bin:${PATH}"

WORKDIR /workspace
CMD ["python3"]
