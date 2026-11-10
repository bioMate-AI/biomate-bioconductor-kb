# bioc-domain-radiology: radiomics feature extraction from supplied segmentations (CT / MR / PET images)
# RESEARCH USE ONLY. PyRadiomics 3.1.0 ships installable wheels for Python 3.7-3.9 only, so the image is
# pinned to Python 3.9 on purpose. Build on an x86_64 host:
#   REPO=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-radiology
#   docker build --platform linux/amd64 -t $REPO:1.0 .   # run from this directory
# The tests (test_radiomics_extract.py) and the reference verification (verify_against_references.py)
# are run by run_verify_spot.sh BEFORE the image is pushed.
FROM python:3.9-slim

ENV PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1 MPLCONFIGDIR=/tmp/matplotlib
RUN apt-get update && apt-get install -y --no-install-recommends procps curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN pip install "numpy==1.26.4" "SimpleITK==2.3.1" "pyradiomics==3.1.0" pytest

RUN mkdir -p /opt/biomate
COPY radiomics_extract.py merge_features.py test_radiomics_extract.py verify_against_references.py /opt/biomate/
ENV PATH=/opt/biomate:$PATH

# Build-time sanity gate: dependencies import and the CLI parses (the full tests run before push).
RUN python -c "import radiomics, SimpleITK, numpy; print('pyradiomics', radiomics.__version__, 'SimpleITK', SimpleITK.Version.VersionString())" \
 && python /opt/biomate/radiomics_extract.py --help > /dev/null
