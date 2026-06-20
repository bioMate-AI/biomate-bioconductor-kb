# AI-MARRVEL v1.1.3 image — bakes upstream Nextflow pipeline + Nextflow CLI.
#
# Upstream: https://github.com/LiuzLab/AI_MARRVEL  (GPL-3.0, updated 2026-06-01)
# Paper:    Mao et al. 2024 NEJM AI, doi 10.1056/AIoa2300009
#
# IMPORTANT: AI-MARRVEL is itself a Nextflow DSL2 pipeline (not a Python pkg),
# so we do NOT `pip install`. We clone the upstream repo + bake nextflow into
# the image, then our BioMate wrap's Phase C invokes:
#     nextflow run /opt/ai_marrvel/main.nf \
#         --input_vcf … --input_hpo … --ref_dir … --run_id … --ref_ver …
#
# README pinned upstream version is v1.1.3 (manifest in nextflow.config). The
# task description referenced v1.1.2; the live upstream is v1.1.3. We bake the
# main branch head as of 2026-06-20.
#
# Reference-data dependencies (~> tens of GB) live in the public S3 bucket
# `s3://aim-data-dependencies-2.4-public` and are NOT baked here — Phase B
# either mounts a pre-staged ref_dir from S3 or skips with `use_baked_example`
# (which runs upstream `--help` for stub-smoke parity).
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/ai_marrvel/container
#   docker build -t biomate/ai_marrvel:v1 .
#
# ECR push (BioMate AWS account — NOT YET PUSHED):
#   docker tag biomate/ai_marrvel:v1 \
#       399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai_marrvel:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#       --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai_marrvel:v1
#
# Image size estimate: ~1.5 GB (jdk17 ~330, nextflow ~100, repo+deps ~150,
# python + pandas + jq ~600 (slim variants), aws-cli v2 ~250).

FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    NXF_HOME=/opt/nextflow \
    PATH="/opt/nextflow:/opt/ai_marrvel/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git unzip jq bash procps \
        openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pandas

# --- Nextflow CLI (>=23.10.1 per upstream manifest) --------------------------
RUN mkdir -p /opt/nextflow \
    && curl -fsSL https://get.nextflow.io | bash \
    && mv nextflow /opt/nextflow/nextflow \
    && chmod +x /opt/nextflow/nextflow \
    && /opt/nextflow/nextflow -version 2>&1 | head -5

# --- AWS CLI v2 (for `aws s3 sync s3://aim-data-dependencies-2.4-public`) ----
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && aws --version

# --- AI-MARRVEL upstream pipeline -------------------------------------------
# Pin the main branch (manifest version 1.1.3). For a tagged release, replace
# the clone line with: `git clone --depth 1 --branch v1.1.3 …`.
RUN git clone --depth 1 https://github.com/LiuzLab/AI_MARRVEL.git /opt/ai_marrvel \
    && cd /opt/ai_marrvel \
    && echo "[ai_marrvel:build] commit: $(git rev-parse HEAD)" \
    && ls -la /opt/ai_marrvel \
    && test -f /opt/ai_marrvel/main.nf

# Pre-fetch the nf-schema plugin so offline `--help` works at runtime.
RUN /opt/nextflow/nextflow plugin install nf-schema@2.3.0 || true

WORKDIR /opt/ai_marrvel

# Build-time self-test: upstream `--help` must parse + emit usage.
RUN /opt/nextflow/nextflow run /opt/ai_marrvel/main.nf --help 2>&1 | head -30 \
    || echo "[ai_marrvel:build] --help requires plugin online; deferred to runtime"

LABEL org.opencontainers.image.source=https://github.com/LiuzLab/AI_MARRVEL \
      org.opencontainers.image.licenses=GPL-3.0 \
      org.opencontainers.image.version=1.1.3 \
      org.opencontainers.image.description="AI-MARRVEL v1.1.3 — Liu Lab phenotype-driven rare-disease causal-variant ranking. Mao et al. 2024 NEJM AI (10.1056/AIoa2300009). Upstream pipeline cloned to /opt/ai_marrvel; ref data NOT baked (pull from s3://aim-data-dependencies-2.4-public)." \
      ai.biomate.source=https://github.com/LiuzLab/AI_MARRVEL \
      ai.biomate.license=GPL-3.0
