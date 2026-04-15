# BioMate SRA-Tools Container
#
# Provides NCBI SRA Toolkit for downloading sequencing data from SRA.
# Used by: genomics/wgs_germline_gatk (SRA download step)
#
# Inherits AWS CLI v2 from biomate-nextflow-base so that Nextflow
# nxf_s3_upload / nxf_s3_download have 'aws' on PATH.
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sra-tools:3.1.1 \
#     --push -f backend/docker/sra-tools/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="NCBI SRA Toolkit 3.1.1 + AWS CLI for Nextflow Batch workflows"
LABEL version="3.1.1"

ENV DEBIAN_FRONTEND=noninteractive

# ── NCBI SRA Toolkit 3.1.1 ────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libnghttp2-14 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/3.1.1/sratoolkit.3.1.1-ubuntu64.tar.gz" \
    -o /tmp/sratoolkit.tar.gz && \
    tar -xzf /tmp/sratoolkit.tar.gz -C /opt && \
    rm /tmp/sratoolkit.tar.gz && \
    ln -s /opt/sratoolkit.3.1.1-ubuntu64/bin/fastq-dump /usr/local/bin/fastq-dump && \
    ln -s /opt/sratoolkit.3.1.1-ubuntu64/bin/prefetch    /usr/local/bin/prefetch && \
    ln -s /opt/sratoolkit.3.1.1-ubuntu64/bin/fasterq-dump /usr/local/bin/fasterq-dump && \
    ln -s /opt/sratoolkit.3.1.1-ubuntu64/bin/sam-dump    /usr/local/bin/sam-dump && \
    ln -s /opt/sratoolkit.3.1.1-ubuntu64/bin/srapath     /usr/local/bin/srapath

# Disable interactive config check
RUN mkdir -p /root/.ncbi && \
    printf '/LIBS/GUID = "biomate-sra"\n/config/default = "false"\n' \
    > /root/.ncbi/user-settings.mkfg

# ── Smoke test ─────────────────────────────────────────────────────────────
RUN fastq-dump --version && \
    aws --version && \
    echo "sra-tools checks passed."

WORKDIR /data
CMD ["fastq-dump", "--version"]
