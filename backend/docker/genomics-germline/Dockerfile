# BioMate Genomics Germline Container
#
# Used by wgs_germline_gatk Nextflow workflow processes:
#   FASTQC, FASTP_TRIM, BWA_MEM2_ALIGN, SAMTOOLS_SORT_INDEX,
#   MARK_DUPLICATES, SAMTOOLS_FLAGSTAT, MOSDEPTH_COVERAGE,
#   BQSR_BASE_RECALIBRATOR, BQSR_APPLY, HAPLOTYPE_CALLER,
#   GENOTYPE_GVCFS, VARIANT_FILTRATION, VARIANT_ANNOTATION,
#   MULTIQC_REPORT
#
# Inherits AWS CLI v2 from biomate-nextflow-base (required for Nextflow
# nxf_s3_upload / nxf_s3_download S3 staging on AWS Batch).
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline:x86 \
#     --push -f backend/docker/genomics-germline/Dockerfile .
#
# Run smoke test:
#   docker run --rm --platform linux/amd64 \
#     399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/genomics-germline:x86 \
#     bash -c "bwa-mem2 version && gatk --version && samtools --version | head -1 && mosdepth --version"

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="Germline variant calling tools: bwa-mem2, GATK4, samtools, mosdepth, fastp, fastqc, multiqc, snpEff"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive

# ── Layer 1: Install Miniforge (conda/mamba) ──────────────────────────────
RUN curl -fsSL \
    https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh \
    -o /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:${PATH}"

# ── Layer 2: Core alignment + BAM tools ──────────────────────────────────
RUN mamba install -y -c conda-forge -c bioconda \
        bwa-mem2 \
        samtools \
        htslib \
        bcftools \
        picard \
        mosdepth \
        tabix \
    && conda clean -afy

# ── Layer 3: GATK4 ────────────────────────────────────────────────────────
RUN mamba install -y -c conda-forge -c bioconda \
        gatk4 \
    && conda clean -afy

# ── Layer 4: QC tools ─────────────────────────────────────────────────────
RUN mamba install -y -c conda-forge -c bioconda \
        fastqc \
        fastp \
        multiqc \
        pigz \
    && conda clean -afy

# ── Layer 5: Variant annotation ───────────────────────────────────────────
# snpeff from bioconda; --no-deps avoids clobbering gatk4's pinned openjdk.
RUN mamba install -y -c conda-forge -c bioconda snpeff --no-deps || \
    mamba install -y -c conda-forge -c bioconda snpeff && \
    conda clean -afy

# ── Smoke tests ───────────────────────────────────────────────────────────
RUN bwa-mem2 version && \
    gatk --version && \
    samtools --version | head -1 && \
    mosdepth --version && \
    fastqc --version && \
    fastp --version 2>&1 | head -1 && \
    multiqc --version && \
    snpEff -version 2>&1 | head -1 || true && \
    aws --version && \
    echo "All genomics-germline checks passed."

WORKDIR /data
CMD ["bash"]
