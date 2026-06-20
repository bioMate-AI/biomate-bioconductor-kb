# MAGMA v1.10 image — bakes binary + 1000G EUR reference panel + gene-loc + tutorial sumstats.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/magma_gene_based_test/container
#   docker build -t biomate/magma:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/magma:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/magma:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/magma:v1
#
# Image size estimate: ~600 MB (debian-slim ~80, MAGMA binary ~5, 1000G EUR ref ~370,
# gene-loc + sumstats ~3, python+pandas+numpy ~140).
#
# Required upstream of:
#   - Zhi UDIP-FA pipeline (PMC12458571) — TorchGWAS -> MAGMA -> METAL -> FUMA -> LDSC
#   - Zhao scGWAS pipeline (PMC9575201)  — MAGMA -> scGWAS

FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pandas numpy

# --- MAGMA v1.10 binary -------------------------------------------------------
# Upstream: https://cncr.nl/research/magma/
# License:  Academic Free License (AFL-3.0) — bundled in /opt/magma/LICENSE.
RUN mkdir -p /opt/magma \
    && curl -sSL "https://vu.data.surfsara.nl/index.php/s/zkKbNeNOZAhFXZB/download" \
         -o /tmp/magma.zip \
    && unzip -q /tmp/magma.zip -d /opt/magma \
    && chmod +x /opt/magma/magma \
    && rm /tmp/magma.zip \
    && /opt/magma/magma --version 2>&1 | head -5

ENV PATH="/opt/magma:${PATH}"

# --- Reference panel: 1000 Genomes Phase 3 EUR (g1000_eur) --------------------
# https://ctg.cncr.nl/software/magma_files — g1000_eur.zip (~370 MB, .bim/.bed/.fam)
RUN mkdir -p /opt/magma/reference \
    && curl -sSL "https://vu.data.surfsara.nl/index.php/s/VZNByNwpD8qqINe/download" \
         -o /tmp/g1000_eur.zip \
    && unzip -q /tmp/g1000_eur.zip -d /opt/magma/reference \
    && rm /tmp/g1000_eur.zip \
    && ls /opt/magma/reference

# --- Gene-location file: NCBI37.3.gene.loc -----------------------------------
RUN curl -sSL "https://vu.data.surfsara.nl/index.php/s/Pj2Orr2DiJEDfeM/download" \
         -o /tmp/NCBI37.zip \
    && unzip -q /tmp/NCBI37.zip -d /opt/magma/reference \
    && rm /tmp/NCBI37.zip \
    && ls /opt/magma/reference/NCBI37.3.gene.loc | head

# --- Tutorial / example sumstats ---------------------------------------------
# MAGMA's tutorial gwas_summary.txt — small enough to bake for offline smoke runs.
RUN mkdir -p /opt/magma/example \
    && curl -sSL "https://ctg.cncr.nl/software/MAGMA/tut/gwas_sample.zip" \
         -o /tmp/gwas_sample.zip \
    && unzip -q /tmp/gwas_sample.zip -d /opt/magma/example \
    && rm /tmp/gwas_sample.zip \
    && ls /opt/magma/example

WORKDIR /opt/magma

# Build-time self-test: ensure binary runs.
RUN /opt/magma/magma --version 2>&1 | head -5 \
    && echo "[magma:build] binary OK"

LABEL org.opencontainers.image.source=https://cncr.nl/research/magma/ \
      org.opencontainers.image.licenses=AFL-3.0 \
      org.opencontainers.image.description="MAGMA v1.10 + 1000G EUR reference + NCBI37.3 gene-loc + tutorial sumstats baked. de Leeuw et al. PLOS Comp Bio 2015 (10.1371/journal.pcbi.1004219)."
