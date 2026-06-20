# LDSC v1.0.1 image — bakes the LDSC repo + EUR LD scores (HapMap3) + tutorial sumstats.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/ldsc_heritability/container
#   docker build -t biomate/ldsc:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/ldsc:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ldsc:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ldsc:v1
#
# Image size estimate: ~700 MB (python:2.7-slim ~120, deps ~80, LDSC repo ~5,
# EUR LD scores ~270, tutorial sumstats ~20, hm3 snplist ~10).
#
# IMPORTANT: LDSC is Python 2.7 only — upstream has not migrated.
#
# Required upstream of:
#   - Zhi UDIP-FA pipeline (PMC12458571) — TorchGWAS -> MAGMA -> METAL -> FUMA -> LDSC

FROM python:2.7-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates bzip2 \
    && rm -rf /var/lib/apt/lists/*

# --- LDSC python-2.7 deps (pinned per upstream environment.yml) ---------------
RUN pip install --no-cache-dir \
        pandas==0.20.3 \
        scipy==1.0.0 \
        numpy==1.13.3 \
        bitarray==0.8.1 \
        nose==1.3.7

# --- LDSC v1.0.1 source -------------------------------------------------------
# Upstream: https://github.com/bulik/ldsc  (BSD-3-Clause)
RUN git clone --depth 1 https://github.com/bulik/ldsc.git /opt/ldsc \
    && chmod +x /opt/ldsc/ldsc.py /opt/ldsc/munge_sumstats.py \
    && python /opt/ldsc/ldsc.py --help 2>&1 | head -3

# --- Baked reference: EUR LD scores (HapMap3, 1000G Phase 3) ------------------
# https://data.broadinstitute.org/alkesgroup/LDSCORE/eur_w_ld_chr.tar.bz2  (~270 MB)
RUN mkdir -p /opt/ldsc/eur_w_ld_chr \
    && curl -sSL "https://data.broadinstitute.org/alkesgroup/LDSCORE/eur_w_ld_chr.tar.bz2" \
         -o /tmp/eur_w_ld_chr.tar.bz2 \
    && tar -xjf /tmp/eur_w_ld_chr.tar.bz2 -C /opt/ldsc/ \
    && rm /tmp/eur_w_ld_chr.tar.bz2 \
    && ls /opt/ldsc/eur_w_ld_chr | head

# --- Baked HapMap3 snplist (for munge_sumstats --merge-alleles) ---------------
RUN curl -sSL "https://data.broadinstitute.org/alkesgroup/LDSCORE/w_hm3.snplist.bz2" \
         -o /tmp/w_hm3.snplist.bz2 \
    && bunzip2 /tmp/w_hm3.snplist.bz2 \
    && mv /tmp/w_hm3.snplist /opt/ldsc/eur_w_ld_chr/w_hm3.snplist

# --- Baked tutorial sumstats (LDSC wiki examples) -----------------------------
# scz.sumstats.gz + bip.sumstats.gz used in the cross-trait rg tutorial.
RUN mkdir -p /opt/ldsc/example \
    && curl -sSL "https://data.broadinstitute.org/alkesgroup/LDSCORE/independent_sumstats/PGC_SCZ52.sumstats.gz" \
         -o /opt/ldsc/example/scz.sumstats.gz || true \
    && curl -sSL "https://data.broadinstitute.org/alkesgroup/LDSCORE/independent_sumstats/PGC_BIP32b.sumstats.gz" \
         -o /opt/ldsc/example/bip.sumstats.gz || true \
    && ls -la /opt/ldsc/example || true

WORKDIR /opt/ldsc

# Build-time self-test: LDSC --help (binary OK).
RUN python /opt/ldsc/ldsc.py --help 2>&1 | head -3 \
    && python /opt/ldsc/munge_sumstats.py --help 2>&1 | head -3 \
    && echo "[ldsc:build] OK"

LABEL org.opencontainers.image.source=https://github.com/bulik/ldsc \
      org.opencontainers.image.licenses=BSD-3-Clause \
      org.opencontainers.image.description="LDSC v1.0.1 (Bulik-Sullivan 2015) + EUR HapMap3 LD scores + HapMap3 snplist + tutorial sumstats baked."
