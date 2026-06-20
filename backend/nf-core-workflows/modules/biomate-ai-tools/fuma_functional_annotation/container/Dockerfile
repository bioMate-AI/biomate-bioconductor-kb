# FUMA HTTP-client wrap image.
#
# FUMA is a hosted web service (https://fuma.ctglab.nl) with no public binary
# distribution. This image is a thin Python HTTP client that submits sumstats
# to the FUMA web service, polls for completion, and downloads the result zip
# for parsing. If the upstream service exposes no public REST API (which we
# could not verify at build time — fuma.ctglab.nl was unreachable from the
# build sandbox), Phase B/C of the sibling main.nf wrap fall back to a
# documented TODO and the runtime will fail at submit — see main.nf header.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/fuma_functional_annotation/container
#   docker build -t biomate/fuma:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/fuma:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/fuma:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/fuma:v1
#
# Image size estimate: ~180 MB (python:3.11-slim ~120, requests+pandas ~60).
#
# Upstream:  https://fuma.ctglab.nl/  (TOS at fuma.ctglab.nl; license not
#            published as a public binary)
# Citation:  Watanabe, Taskesen, van Bochoven, Posthuma (2017). "Functional
#            mapping and annotation of genetic associations with FUMA."
#            Nature Communications 8:1826. doi:10.1038/s41467-017-01261-5
#
# Required to complete the Zhi UDIP-FA paper-faithful pipeline (PMC12458571).

FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir requests pandas

WORKDIR /opt/fuma

LABEL org.opencontainers.image.source=https://fuma.ctglab.nl \
      org.opencontainers.image.licenses="UNKNOWN — wrap-only; FUMA TOS at fuma.ctglab.nl" \
      org.opencontainers.image.description="FUMA HTTP-client wrap (Watanabe 2017 Nat Commun). Thin requests+pandas client; no upstream binary."
