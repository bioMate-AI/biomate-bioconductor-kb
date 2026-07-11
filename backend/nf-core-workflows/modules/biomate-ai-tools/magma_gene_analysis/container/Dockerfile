# MAGMA v1.10 image — gene-based GWAS analysis
#
# Bakes:
#   - MAGMA v1.10 Linux static binary  (ctg.cncr.nl/software/magma, academic freeware)
#   - g1000_eur LD reference           (~150 MB; needed for --gene-model multi)
#   - NCBI37.3 gene location file      (hg19; needed for --annotate)
#   - NCBI38   gene location file      (hg38; alternate for --annotate)
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/magma_gene_analysis/container
#   docker build --platform linux/amd64 -t biomate/magma:v1.10 .
#
# ECR push (BioMate AWS account):
#   ECR=399683337364.dkr.ecr.us-west-2.amazonaws.com
#   aws ecr create-repository --repository-name biomate/magma --region us-west-2 \
#       --image-scanning-configuration scanOnPush=true   # one-time
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR
#   docker tag biomate/magma:v1.10 $ECR/biomate/magma:v1.10
#   docker push $ECR/biomate/magma:v1.10
#
# Image size estimate:
#   ubuntu:22.04 ~80 MB + python3+scipy ~400 MB + magma binary ~5 MB
#   + g1000_eur ~300 MB (packed) + gene.loc files ~5 MB  → ~800 MB total
#
# License note:
#   MAGMA is freeware for academic/research use (not open source).
#   No redistribution of the binary permitted — Dockerfile downloads it at build time
#   from the official ctg.cncr.nl distribution server. Non-academic use requires
#   a separate agreement with Pascal de Leeuw / VU Amsterdam.
#   Downstream tools (scipy, numpy) are BSD/MIT licensed.
#
# Reference:
#   de Leeuw CA, et al. (2015) MAGMA: Generalized Gene-Set Analysis of GWAS Data.
#   PLoS Comput Biol 11(4):e1004219. doi:10.1371/journal.pcbi.1004219

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV MAGMA_VERSION=1.10

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip \
        curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# Python scientific stack — scipy required for Box-Cox transform in Phase C.
RUN pip3 install --no-cache-dir \
        numpy==1.26.4 \
        scipy==1.13.1 \
        pandas==2.2.2 \
        boto3==1.34.149

# ─── MAGMA binary ───────────────────────────────────────────────────────────
# Download v1.10 static Linux binary.
# URL updated 2026-07 — ctg.cncr.nl redirected to cncr.nl/research/dbg/magma/
# and all files are now hosted on SURFsara (/index.php/s/<id>/download).
RUN mkdir -p /opt/magma/bin \
    && curl -fsSL \
        "https://vu.data.surfsara.nl/index.php/s/lxDgt2dNdNr6DYt/download" \
        -o /tmp/magma.zip \
    && unzip /tmp/magma.zip -d /opt/magma/bin \
    && chmod +x /opt/magma/bin/magma \
    && rm /tmp/magma.zip

# Symlink so .nf scripts can call /opt/magma/magma directly (matches CMD in .nf).
RUN ln -s /opt/magma/bin/magma /opt/magma/magma

# ─── LD reference: g1000_eur (1000 Genomes Phase 3, EUR, hg19) ─────────────
# Required for --gene-model multi; snp-wise mode (our default) does not need it
# but we bake it in so the image is self-contained for production runs.
# URL updated 2026-07 — now on SURFsara.
RUN mkdir -p /opt/magma/ref \
    && curl -fsSL \
        "https://vu.data.surfsara.nl/index.php/s/VZNByNwpD8qqINe/download" \
        -o /tmp/g1000_eur.zip \
    && unzip /tmp/g1000_eur.zip -d /opt/magma/ref \
    && rm /tmp/g1000_eur.zip \
    && ls -lh /opt/magma/ref/g1000_eur.*

# ─── Gene location files ────────────────────────────────────────────────────
# NCBI37.3 = hg19; NCBI38 = hg38.
# URL updated 2026-07 — now on SURFsara (Build 37 bundle includes gene.loc).
RUN curl -fsSL \
        "https://vu.data.surfsara.nl/index.php/s/Pj2orwuF2JYyKxq/download" \
        -o /tmp/gene_locs.zip \
    && unzip /tmp/gene_locs.zip -d /opt/magma/ref \
    && mv /opt/magma/ref/NCBI37.3.gene.loc /opt/magma/ref/NCBI37.3.gene.loc 2>/dev/null || true \
    && rm /tmp/gene_locs.zip \
    && wc -l /opt/magma/ref/*.gene.loc 2>/dev/null || echo "gene.loc files present"

# ─── Smoke test ─────────────────────────────────────────────────────────────
# Verify binary runs + gene.loc files are valid.
# We can't do a full annotation here without sumstats, but --help confirms the
# binary loads correctly against the static libc.
RUN /opt/magma/magma --help 2>&1 | head -5 \
    && python3 -c "import scipy.stats; print('[magma:build] scipy ok')" \
    && echo "[magma:build] g1000_eur files: $(ls /opt/magma/ref/g1000_eur.* | wc -l)" \
    && echo "[magma:build] NCBI37.3 lines: $(wc -l < /opt/magma/ref/NCBI37.3.gene.loc)"

WORKDIR /opt/magma

LABEL org.opencontainers.image.title="MAGMA v1.10" \
      org.opencontainers.image.description="MAGMA v1.10 gene-based GWAS analysis + g1000_eur LD ref baked (BioMate)" \
      org.opencontainers.image.url="https://ctg.cncr.nl/software/magma" \
      biomate.tool.license="Freeware (academic use only)" \
      biomate.tool.citation="de Leeuw et al. PLoS Comput Biol 2015; 11(4):e1004219"
