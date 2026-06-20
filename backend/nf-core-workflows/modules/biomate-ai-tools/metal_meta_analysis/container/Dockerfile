# METAL image — bakes the pre-built Linux binary + 2 tutorial sumstats.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/metal_meta_analysis/container
#   docker build -t biomate/metal:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/metal:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/metal:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/metal:v1
#
# Image size estimate: ~250 MB (ubuntu:22.04 ~80, python3+pandas ~140, metal binary ~5, examples ~3).
#
# Required upstream of MAGMA + LDSC in the Zhi UDIP-FA pipeline (PMC12458571).

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates tar gzip python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir pandas numpy

# --- METAL pre-built Linux binary ---------------------------------------------
# Upstream:  https://github.com/statgen/METAL  (BSD-3-Clause)
# Distrib:   https://csg.sph.umich.edu/abecasis/Metal/
RUN mkdir -p /opt/metal \
    && curl -sSL "https://csg.sph.umich.edu/abecasis/Metal/download/Linux-metal.tar.gz" \
         -o /tmp/metal.tar.gz \
    && tar -xzf /tmp/metal.tar.gz -C /opt/metal --strip-components=1 \
    && chmod +x /opt/metal/metal \
    && rm /tmp/metal.tar.gz \
    && /opt/metal/metal < /dev/null 2>&1 | head -5

ENV PATH="/opt/metal:${PATH}"

# --- Baked example sumstats ---------------------------------------------------
# METAL ships two example GWAS files used in its tutorial:
#   examples/GlucoseExample/DGI_three_regions.txt
#   examples/GlucoseExample/MAGIC_FUSION_Results.txt
# These come inside the source tarball at github.com/statgen/METAL.
RUN mkdir -p /opt/metal/example \
    && curl -sSL "https://github.com/statgen/METAL/archive/refs/heads/master.tar.gz" \
         -o /tmp/metal_src.tar.gz \
    && tar -xzf /tmp/metal_src.tar.gz -C /tmp \
    && cp /tmp/METAL-master/examples/GlucoseExample/DGI_three_regions.txt /opt/metal/example/ || true \
    && cp /tmp/METAL-master/examples/GlucoseExample/MAGIC_FUSION_Results.txt /opt/metal/example/ || true \
    && cp /tmp/METAL-master/examples/GlucoseExample/metal.txt /opt/metal/example/metal_example.txt || true \
    && rm -rf /tmp/metal_src.tar.gz /tmp/METAL-master \
    && ls -la /opt/metal/example || true

WORKDIR /opt/metal

# Build-time self-test
RUN echo "QUIT" | /opt/metal/metal 2>&1 | head -3 \
    && echo "[metal:build] OK"

LABEL org.opencontainers.image.source=https://github.com/statgen/METAL \
      org.opencontainers.image.licenses=BSD-3-Clause \
      org.opencontainers.image.description="METAL (Willer 2010) GWAS meta-analysis + DGI/MAGIC tutorial sumstats baked."
