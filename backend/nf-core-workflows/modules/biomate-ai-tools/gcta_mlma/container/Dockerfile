# GCTA v1.94.4 image — bakes the pre-built Linux binary + GCTA tutorial example data.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/gcta_mlma/container
#   docker build -t biomate/gcta:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/gcta:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gcta:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gcta:v1
#
# Image size estimate: ~350 MB (ubuntu:22.04 ~80, python3+pandas+numpy ~140,
# GCTA binary ~80, baked PLINK tutorial example ~5).
#
# Upstream:  https://yanglab.westlake.edu.cn/software/gcta/  (GPL-3.0)
# Citation:  Yang, Lee, Goddard, Visscher (2011). "GCTA: A tool for genome-wide
#            complex trait analysis." AJHG 88(1):76-82.
#            doi: 10.1016/j.ajhg.2010.11.011
#
# Zhi's primary GWAS engine in the UDIP-FA paper (PMC12458571), upstream of
# MAGMA + METAL + LDSC + FUMA.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates unzip python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir pandas numpy

# --- GCTA v1.94.4 pre-built Linux binary --------------------------------------
RUN mkdir -p /opt/gcta \
    && curl -sSL "https://yanglab.westlake.edu.cn/software/gcta/bin/gcta-1.94.4-linux-kernel-3-x86_64.zip" \
         -o /tmp/gcta.zip \
    && unzip -q /tmp/gcta.zip -d /tmp/gcta_unzip \
    && cp /tmp/gcta_unzip/gcta-1.94.4-linux-kernel-3-x86_64/gcta64 /opt/gcta/gcta64 \
    && chmod +x /opt/gcta/gcta64 \
    && rm -rf /tmp/gcta.zip /tmp/gcta_unzip \
    && /opt/gcta/gcta64 --version 2>&1 | head -5 || true

ENV PATH="/opt/gcta:${PATH}"

# --- Baked tutorial example data ---------------------------------------------
# GCTA tutorial ships a small PLINK-format example set (~5 MB) + phenotype.
#   https://yanglab.westlake.edu.cn/software/gcta/res/test.zip
# Provides test.bed / test.bim / test.fam / test.phen
RUN mkdir -p /opt/gcta/example \
    && curl -sSL "https://yanglab.westlake.edu.cn/software/gcta/res/test.zip" \
         -o /tmp/gcta_test.zip \
    && unzip -q /tmp/gcta_test.zip -d /opt/gcta/example \
    && rm /tmp/gcta_test.zip \
    && ls -la /opt/gcta/example || true

WORKDIR /opt/gcta

# Build-time self-test
RUN /opt/gcta/gcta64 --version 2>&1 | head -3 || true \
    && echo "[gcta:build] OK"

LABEL org.opencontainers.image.source=https://yanglab.westlake.edu.cn/software/gcta/ \
      org.opencontainers.image.licenses=GPL-3.0 \
      org.opencontainers.image.description="GCTA v1.94.4 (Yang 2011 AJHG) MLMA + baked PLINK tutorial example. Zhi UDIP-FA primary GWAS engine (PMC12458571)."
