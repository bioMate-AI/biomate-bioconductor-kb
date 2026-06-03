# BioMate virtual_patient_cohort container (CPU)
#
# Powers: backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/virtual_patient_cohort
# Generates virtual patient PK/PD cohorts via 1-cmpt PK ODE + Monte Carlo IIV.
#
# Base (biomate-nextflow-base) provides numpy<2, scipy, pandas, awscli.
# Adds matplotlib + statsmodels for plotting and inter-individual variability fits.
#
# Build (x86 only, AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/virtual-patient-cohort-nf:1.0 \
#     --push -f backend/docker/virtual-patient-cohort-nf/Dockerfile .

FROM --platform=linux/amd64 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL description="virtual-patient-cohort-nf: virtual patient PK/PD cohort generator (Monte Carlo + statsmodels)"
LABEL version="1.0.0"

RUN pip install --no-cache-dir \
    matplotlib==3.9.2 \
    statsmodels==0.14.4

WORKDIR /work
