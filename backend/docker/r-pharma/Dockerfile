# BioMate r-pharma container
# Consolidates nlmixr2 (PopPK/PD), rxode2, PKNCA, mrgsolve, PKPDsim for AWS Batch.
# AWS CLI v2 is baked in — required for Nextflow nxf_s3_upload / nxf_s3_download.
#
# Build:
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-pharma:x86 \
#     --push -f backend/docker/r-pharma/Dockerfile .
#
# ECR: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-pharma:x86

FROM rocker/r-ver:4.3.1

# ── System dependencies ───────────────────────────────────────────────────────
# libxml2-dev   : XML/HTML I/O (tidyverse readr, xml2)
# libssl-dev    : HTTPS downloads from CRAN
# libcurl4-openssl-dev : R curl package (httr, jsonlite download)
# libgit2-dev   : gert / credentials (needed by remotes)
# libharfbuzz-dev libfribidi-dev : textshaping → ragg → ggplot2 text rendering
# libfontconfig1-dev libfreetype6-dev : font metrics for PDF/PNG output
# libpng-dev libtiff-dev libjpeg-dev : raster graphics for VPC / GOF plots
# libhdf5-dev   : mrgsolve optional HDF5 output
# libgfortran-* : Fortran runtime for compiled ODE solvers (rxode2, mrgsolve)
# gfortran      : required to compile Fortran extensions in rxode2
# cmake         : required by some BH / lbfgsb3c build scripts
# unzip         : AWS CLI installer
# perl          : Nextflow launcher
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    perl \
    cmake \
    git \
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgit2-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff-dev \
    libjpeg-dev \
    libhdf5-dev \
    libgfortran-11-dev \
    gfortran \
    && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
# Required by Nextflow's nxf_s3_upload / nxf_s3_download shell helpers when
# running on AWS Batch. Must be available as /usr/local/bin/aws.
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && aws --version

# ── CRAN mirror ──────────────────────────────────────────────────────────────
# Set globally so all subsequent Rscript -e calls inherit it.
RUN echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' \
    >> /usr/local/lib/R/etc/Rprofile.site

# ── QEMU x86-on-ARM build pattern (matches aizynth Dockerfile) ───────────────
# Every R install layer has TWO jobs:
#   1. Real work — install.packages() compiles + writes .so files into
#      /usr/local/lib/R/site-library/<pkg>. This is what the image ships.
#   2. Smoke verification — stopifnot(requireNamespace(...)) loads the freshly
#      compiled native extension. Under QEMU x86-on-ARM emulation, this load
#      step segfaults for many native-extension packages (nlmixr2, rxode2,
#      mrgsolve, etc.).
# Solution: keep job 1 as the real work but soften it with '|| true' so a
# QEMU segfault in the verification tail doesn't abort the layer. Then add
# shell-only structural assertions that always run hard — check whether each
# package's site-library directory actually got written. The runtime smoke
# test on real x86 (Batch tasks pulling from ECR) is what catches actual
# load failures; that's not the build's job.

# ── Compilation helpers: Rcpp family + lbfgsb3c ──────────────────────────────
# Must be installed BEFORE nlmixr2 / rxode2 to satisfy their LinkingTo fields.
RUN Rscript -e " \
    install.packages( \
        c('Rcpp', 'RcppArmadillo', 'BH', 'lbfgsb3c'), \
        dependencies = c('Depends', 'Imports', 'LinkingTo') \
    ); \
    cat('Rcpp family install done\n') \
" || true
RUN test -d /usr/local/lib/R/site-library/Rcpp \
    && test -d /usr/local/lib/R/site-library/RcppArmadillo \
    && test -d /usr/local/lib/R/site-library/BH \
    && test -d /usr/local/lib/R/site-library/lbfgsb3c \
    || (echo "FATAL: Rcpp family missing from site-library" && exit 1)

# ── Core tidyverse + reporting ────────────────────────────────────────────────
# 2026-06-13: split into one-package-at-a-time install so a single failed
# subdep doesn't tank the whole layer silently under '|| true'. Each install
# is its own cache key so a partial failure is visible per-package.
RUN Rscript -e "install.packages('data.table', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('data.table install done\n')" || true
RUN Rscript -e "install.packages('nlme', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('nlme install done\n')" || true
RUN Rscript -e "install.packages('jsonlite', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('jsonlite install done\n')" || true
RUN Rscript -e "install.packages('ggplot2', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('ggplot2 install done\n')" || true
RUN Rscript -e "install.packages('rmarkdown', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('rmarkdown install done\n')" || true
RUN Rscript -e "install.packages('knitr', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('knitr install done\n')" || true
RUN Rscript -e "install.packages('DT', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('DT install done\n')" || true
RUN Rscript -e "install.packages('plotly', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('plotly install done\n')" || true
RUN Rscript -e "install.packages('tidyverse', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('tidyverse install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/tidyverse \
    && test -d /usr/local/lib/R/site-library/data.table \
    && test -d /usr/local/lib/R/site-library/nlme \
    && test -d /usr/local/lib/R/site-library/rmarkdown \
    && test -d /usr/local/lib/R/site-library/jsonlite \
    && test -d /usr/local/lib/R/site-library/ggplot2 \
    || (echo "FATAL: core tidyverse / reporting packages missing" && exit 1)

# ── rxode2 (ODE solver — nlmixr2 dependency) ─────────────────────────────────
# Installed separately before nlmixr2 so compilation errors surface clearly.
RUN Rscript -e "install.packages('rxode2', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('rxode2 install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/rxode2 \
    || (echo "FATAL: rxode2 missing from site-library" && exit 1)

# ── nlmixr2 (PopPK/PD — primary reason for this container) ───────────────────
RUN Rscript -e "install.packages('nlmixr2', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('nlmixr2 install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/nlmixr2 \
    || (echo "FATAL: nlmixr2 missing from site-library" && exit 1)

# ── PKNCA (non-compartmental analysis — replaces r-nca container) ─────────────
RUN Rscript -e "install.packages('PKNCA', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('PKNCA install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/PKNCA \
    || (echo "FATAL: PKNCA missing from site-library" && exit 1)

# ── mrgsolve (clinical trial simulation via compiled ODEs) ────────────────────
RUN Rscript -e "install.packages('mrgsolve', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('mrgsolve install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/mrgsolve \
    || (echo "FATAL: mrgsolve missing from site-library" && exit 1)

# ── PKPDsim (PK/PD simulation) ────────────────────────────────────────────────
RUN Rscript -e "install.packages('PKPDsim', dependencies = c('Depends', 'Imports', 'LinkingTo')); cat('PKPDsim install done\n')" || true
RUN test -d /usr/local/lib/R/site-library/PKPDsim \
    || (echo "FATAL: PKPDsim missing from site-library" && exit 1)

# ── xpose / xpose.nlmixr2 (GOF / VPC diagnostic plots) ───────────────────────
RUN Rscript -e " \
    install.packages(c('xpose', 'xpose.nlmixr2'), dependencies = c('Depends', 'Imports', 'LinkingTo')); \
    cat('xpose family install done\n') \
" || true
RUN test -d /usr/local/lib/R/site-library/xpose \
    && test -d /usr/local/lib/R/site-library/xpose.nlmixr2 \
    || (echo "FATAL: xpose family missing from site-library" && exit 1)

# ── Smoke test (non-fatal under QEMU; ECR-pulled x86 tasks run it for real) ──
RUN Rscript -e " \
    library(nlmixr2); \
    library(rxode2); \
    library(PKNCA); \
    library(mrgsolve); \
    library(jsonlite); \
    cat('Smoke test: all 5 key packages loaded OK\n') \
" || true

WORKDIR /data
