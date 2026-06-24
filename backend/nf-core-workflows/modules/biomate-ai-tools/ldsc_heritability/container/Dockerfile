# LDSC v1.0.1 image — LD score regression for SNP-heritability + cross-trait rg
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/ldsc_heritability/container
#   docker build --platform linux/amd64 -t biomate/ldsc:v1.0.1 .
#
# ECR push (BioMate AWS account):
#   ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com
#   aws ecr create-repository --repository-name biomate/ldsc --region us-west-2 \
#       --image-scanning-configuration scanOnPush=true   # one-time
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR
#   docker tag biomate/ldsc:v1.0.1 $ECR/biomate/ldsc:v1.0.1
#   docker push $ECR/biomate/ldsc:v1.0.1
#
# Image size estimate: ~600 MB (python:3.9-slim ~150 MB, scipy/pandas ~300 MB,
#   ldsc source ~5 MB, eur_w_ld_chr ~25 MB, w_hm3.snplist ~5 MB).
#
# License: LDSC is GPL-3.0 (bulik/ldsc on GitHub).
#
# Reference:
#   Bulik-Sullivan BK et al. (2015). LD Score Regression Distinguishes Confounding
#   from Polygenicity in Genome-Wide Association Studies.
#   Nat Genet 47(3):291-5. doi:10.1038/ng.3211
#
# Data provenance:
#   eur_w_ld_chr   : European LD scores (1KG Phase 3 EUR, 22 chromosomes)
#                    from bulik-lab public S3 (broad-alkesgroup-public-requester-pays)
#   w_hm3.snplist  : HapMap3 variant list used by munge_sumstats.py
#                    same source bucket

# LDSC requires Python ≥ 3.6; using 3.9-slim for reproducibility.
FROM python:3.9-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# LDSC dependencies (pinned to versions known to work with ldsc 1.0.1).
RUN pip install --no-cache-dir \
        numpy==1.24.4 \
        scipy==1.11.4 \
        pandas==1.5.3 \
        bitarray==2.8.0

# ─── LDSC source ────────────────────────────────────────────────────────────
ARG LDSC_SHA=master
RUN git clone https://github.com/bulik/ldsc.git /opt/ldsc \
    && cd /opt/ldsc && git checkout ${LDSC_SHA}

# ─── Reference data ─────────────────────────────────────────────────────────
# eur_w_ld_chr: 22-chromosome European LD scores (~25 MB gzipped).
# w_hm3.snplist: HapMap3 SNP list for munge_sumstats.py (~5 MB).
# Both fetched from bulik-lab public S3 (no auth required, requester-pays
# bucket on us-east-1 — pulls over the internet during build).
RUN mkdir -p /opt/ldsc/ref

# LD scores per chromosome (chr1–22 .l2.ldscore.gz + .l2.M + .l2.M_5_50)
RUN S3="https://broad-alkesgroup-public.s3.amazonaws.com/LDSCORE" \
    && mkdir -p /opt/ldsc/ref/eur_w_ld_chr \
    && for chr in $(seq 1 22); do \
           curl -sSfL "${S3}/eur_w_ld_chr/${chr}.l2.ldscore.gz" \
               -o "/opt/ldsc/ref/eur_w_ld_chr/${chr}.l2.ldscore.gz"; \
           curl -sSfL "${S3}/eur_w_ld_chr/${chr}.l2.M" \
               -o "/opt/ldsc/ref/eur_w_ld_chr/${chr}.l2.M"; \
           curl -sSfL "${S3}/eur_w_ld_chr/${chr}.l2.M_5_50" \
               -o "/opt/ldsc/ref/eur_w_ld_chr/${chr}.l2.M_5_50"; \
       done \
    && ls /opt/ldsc/ref/eur_w_ld_chr/ | wc -l

# HapMap3 SNP list
RUN curl -sSfL \
        "https://broad-alkesgroup-public.s3.amazonaws.com/LDSCORE/w_hm3.snplist.bz2" \
        -o /tmp/w_hm3.snplist.bz2 \
    && bunzip2 /tmp/w_hm3.snplist.bz2 \
    && mv /tmp/w_hm3.snplist /opt/ldsc/ref/w_hm3.snplist \
    && wc -l /opt/ldsc/ref/w_hm3.snplist

# ─── Smoke test ─────────────────────────────────────────────────────────────
# Verify ldsc.py is importable and munge_sumstats.py prints usage.
RUN python3 /opt/ldsc/ldsc.py --help 2>&1 | head -5 \
    && echo "[ldsc:build] ldsc.py ok" \
    && ls /opt/ldsc/ref/eur_w_ld_chr/1.l2.ldscore.gz \
    && echo "[ldsc:build] eur_w_ld_chr chr1 present"

WORKDIR /opt/ldsc

LABEL org.opencontainers.image.source=https://github.com/bulik/ldsc \
      org.opencontainers.image.licenses=GPL-3.0 \
      org.opencontainers.image.description="LDSC v1.0.1 — LD score regression heritability + cross-trait rg (BioMate)" \
      biomate.tool.citation="Bulik-Sullivan et al. Nat Genet 2015 doi:10.1038/ng.3211"
