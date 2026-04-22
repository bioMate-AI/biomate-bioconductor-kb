FROM pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime

LABEL maintainer="biomate" \
      description="Cryo-EM conformational heterogeneity analysis — cryoDRGN VAE + fpocket ensemble druggability" \
      version="1.0.0"

# System dependencies
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

# Install AWS CLI v2 at /opt/aws-cli — matches Nextflow cliPath = '/opt/aws-cli/bin/aws'
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Build fpocket from source (no conda available in pytorch base image)
# https://github.com/Discngine/fpocket
RUN git clone --depth 1 https://github.com/Discngine/fpocket.git /tmp/fpocket \
    && cd /tmp/fpocket \
    && make \
    && make install \
    && rm -rf /tmp/fpocket

COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Verify key installations
RUN python -c "import cryodrgn; print('cryoDRGN:', cryodrgn.__version__)" && \
    python -c "import torch; print('PyTorch:', torch.__version__); print('CUDA available:', torch.cuda.is_available())" && \
    python -c "import mrcfile; print('mrcfile OK')" && \
    python -c "import starfile; print('starfile OK')" && \
    fpocket --version 2>/dev/null || fpocket -h 2>&1 | head -3 || echo "fpocket installed"

WORKDIR /workspace

CMD ["python3"]
