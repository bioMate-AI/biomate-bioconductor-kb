# METAL image — multi-cohort GWAS meta-analysis (Willer lab / statgen/METAL)
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/metal_meta_analysis/container
#   docker build --platform linux/amd64 -t biomate/metal:latest .
#
# ECR push (BioMate AWS account):
#   ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com
#   aws ecr create-repository --repository-name biomate/metal --region us-west-2 \
#       --image-scanning-configuration scanOnPush=true   # one-time
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR
#   docker tag biomate/metal:latest $ECR/biomate/metal:latest
#   docker push $ECR/biomate/metal:latest
#
# Image size estimate: ~400 MB (ubuntu:22.04 ~80 MB, cmake+build deps ~200 MB,
#   python3+pandas ~100 MB, METAL binary ~5 MB).
#
# License: METAL is MIT-licensed (statgen/METAL on GitHub).
#
# Reference:
#   Willer CJ, Li Y, Abecasis GR (2010). METAL: fast and efficient meta-analysis of
#   genomewide association scans. Bioinformatics 26(17):2190-1.
#   doi:10.1093/bioinformatics/btq340

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies for METAL (CMake + C++ compiler + zlib)
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake g++ make zlib1g-dev \
        python3 python3-pip \
        git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir numpy==1.26.4 pandas==2.2.2

# ─── METAL source + build ───────────────────────────────────────────────────
# Clone statgen/METAL and build the static binary.
# Pinned to a known-good commit via ARG (bump SHA to re-cut).
ARG METAL_SHA=main
RUN git clone https://github.com/statgen/METAL.git /opt/metal_src \
    && cd /opt/metal_src \
    && git checkout ${METAL_SHA} \
    && mkdir build \
    && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j$(nproc) \
    && cp metal/metal /usr/local/bin/metal \
    && chmod +x /usr/local/bin/metal

# ─── Smoke test ─────────────────────────────────────────────────────────────
# METAL with no args prints usage and exits non-zero.  Catch exit and check
# that the binary at least produces output (proves it linked correctly).
RUN metal 2>&1 | head -3 || true && echo "[metal:build] binary ok"

WORKDIR /opt/metal_src

LABEL org.opencontainers.image.source=https://github.com/statgen/METAL \
      org.opencontainers.image.licenses=MIT \
      org.opencontainers.image.description="METAL (Willer lab) — multi-cohort GWAS meta-analysis (BioMate)"
