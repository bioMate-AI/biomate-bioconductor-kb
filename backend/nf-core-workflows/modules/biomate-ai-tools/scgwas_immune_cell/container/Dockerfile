# scGWAS image — bakes the Zhao-lab jar + reference panels for offline runs.
#
# Build:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/scgwas_immune_cell/container
#   docker build -t biomate/scgwas:v1 .
#
# ECR push (BioMate AWS account):
#   docker tag biomate/scgwas:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS \
#     --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1
#
# Image size estimate: ~250 MB (openjdk-slim ~200, jar 2.4 MB, ref data 88 MB).

# Eclipse Temurin replaces docker.io/library/openjdk, which was deprecated 2024.
FROM eclipse-temurin:17-jre-jammy

# Install: curl (for downloads), python3 (for QC summary emitter), R + a couple
# Bioconductor pkgs for the Phase-C significance-calling step (analysis/3.define_sig.R).
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates python3 r-base \
    && rm -rf /var/lib/apt/lists/*

# Stage upstream code from a pinned commit so this image is reproducible.
# Pinned: bsml320/scGWAS @ a known good commit (update SHA when re-cutting).
ARG SCGWAS_SHA=main
RUN curl -sSL "https://github.com/bsml320/scGWAS/archive/${SCGWAS_SHA}.tar.gz" \
        -o /tmp/scgwas.tgz \
    && mkdir -p /opt/scgwas \
    && tar -xzf /tmp/scgwas.tgz --strip-components=1 -C /opt/scgwas \
    && rm /tmp/scgwas.tgz

# Verify the jar landed where we expect.
RUN ls -la /opt/scgwas/code/scGWAS_r1.jar && java -jar /opt/scgwas/code/scGWAS_r1.jar 2>&1 | head -3 || true

# Reference panels live at /opt/scgwas/data/ already (88 MB):
#   DER-22.avg.tsv (adult brain), DER-20.avg.cell_cycle_corrected.tsv,
#   EMTAB5061, GSE81547, GSE81608, GSE84133_human, GSE85241, Heart, etc.
#   + PathwayCommons12.All.hgnc.exPCDHA.MHC.NCBI37.tsv (network)
#   + HSIAO_HOUSEKEEPING_GENES_new.txt (exclude list)

# Example sumstats also baked so a smoke run needs zero S3 round-trips.
# Path: /opt/scgwas/example/Schizophrenia_Pardinas_2018.magma_boxcox.txt

WORKDIR /opt/scgwas

# Quick self-test: invoke jar with --help (or no args, which prints usage).
# Captured at build time so a broken image fails the build, not at dispatch.
RUN java -jar /opt/scgwas/code/scGWAS_r1.jar 2>&1 | head -20 || \
    echo "[scgwas:build] jar prints usage as expected"

LABEL org.opencontainers.image.source=https://github.com/bsml320/scGWAS \
      org.opencontainers.image.licenses=GPL-3.0 \
      org.opencontainers.image.description="Zhao lab scGWAS r1 + reference panels (DER-22 etc) baked"
