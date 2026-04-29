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

# ── Compilation helpers: Rcpp family + lbfgsb3c ──────────────────────────────
# Must be installed BEFORE nlmixr2 / rxode2 to satisfy their LinkingTo fields.
RUN Rscript -e " \
    install.packages( \
        c('Rcpp', 'RcppArmadillo', 'BH', 'lbfgsb3c'), \
        dependencies = TRUE \
    ); \
    stopifnot( \
        requireNamespace('Rcpp',         quietly=TRUE), \
        requireNamespace('RcppArmadillo',quietly=TRUE), \
        requireNamespace('BH',           quietly=TRUE), \
        requireNamespace('lbfgsb3c',     quietly=TRUE) \
    ); \
    cat('Rcpp family OK\n') \
"

# ── Core tidyverse + reporting ────────────────────────────────────────────────
RUN Rscript -e " \
    install.packages( \
        c('tidyverse', 'data.table', 'nlme', \
          'rmarkdown', 'knitr', 'DT', 'plotly', \
          'jsonlite', 'ggplot2'), \
        dependencies = TRUE \
    ); \
    stopifnot( \
        requireNamespace('tidyverse',  quietly=TRUE), \
        requireNamespace('data.table', quietly=TRUE), \
        requireNamespace('nlme',       quietly=TRUE), \
        requireNamespace('rmarkdown',  quietly=TRUE), \
        requireNamespace('jsonlite',   quietly=TRUE) \
    ); \
    cat('Core packages OK\n') \
"

# ── rxode2 (ODE solver — nlmixr2 dependency) ─────────────────────────────────
# Installed separately before nlmixr2 so compilation errors surface clearly.
RUN Rscript -e " \
    install.packages('rxode2', dependencies = TRUE); \
    stopifnot(requireNamespace('rxode2', quietly=TRUE)); \
    cat('rxode2', as.character(packageVersion('rxode2')), 'OK\n') \
"

# ── nlmixr2 (PopPK/PD — primary reason for this container) ───────────────────
RUN Rscript -e " \
    install.packages('nlmixr2', dependencies = TRUE); \
    stopifnot(requireNamespace('nlmixr2', quietly=TRUE)); \
    cat('nlmixr2', as.character(packageVersion('nlmixr2')), 'OK\n') \
"

# ── PKNCA (non-compartmental analysis — replaces r-nca container) ─────────────
RUN Rscript -e " \
    install.packages('PKNCA', dependencies = TRUE); \
    stopifnot(requireNamespace('PKNCA', quietly=TRUE)); \
    cat('PKNCA', as.character(packageVersion('PKNCA')), 'OK\n') \
"

# ── mrgsolve (clinical trial simulation via compiled ODEs) ────────────────────
RUN Rscript -e " \
    install.packages('mrgsolve', dependencies = TRUE); \
    stopifnot(requireNamespace('mrgsolve', quietly=TRUE)); \
    cat('mrgsolve', as.character(packageVersion('mrgsolve')), 'OK\n') \
"

# ── PKPDsim (PK/PD simulation) ────────────────────────────────────────────────
RUN Rscript -e " \
    install.packages('PKPDsim', dependencies = TRUE); \
    stopifnot(requireNamespace('PKPDsim', quietly=TRUE)); \
    cat('PKPDsim', as.character(packageVersion('PKPDsim')), 'OK\n') \
"

# ── xpose / xpose.nlmixr2 (GOF / VPC diagnostic plots) ───────────────────────
RUN Rscript -e " \
    install.packages(c('xpose', 'xpose.nlmixr2'), dependencies = TRUE); \
    stopifnot( \
        requireNamespace('xpose',         quietly=TRUE), \
        requireNamespace('xpose.nlmixr2', quietly=TRUE) \
    ); \
    cat('xpose family OK\n') \
"

# ── Smoke test — all key packages must load cleanly ──────────────────────────
RUN Rscript -e " \
    library(nlmixr2); \
    library(rxode2); \
    library(PKNCA); \
    library(mrgsolve); \
    library(jsonlite); \
    cat('Smoke test: all 5 key packages loaded OK\n') \
"

WORKDIR /data
