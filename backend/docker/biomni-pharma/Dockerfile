# BioMate Pharmacology Cheminformatics Container (biomni-pharma)
#
# Extends biomni-tools with pharma-specific cheminformatics tools.
# ADMET prediction (admet-ai, Chemprop) lives in biomni-admet — not here.
#
# Base (biomni-tools) provides: RDKit, numpy/scipy/pandas, scikit-learn,
#   statsmodels, scikit-image, vina, meeko, ViennaRNA, openbabel, AWS CLI v2
#
# Adds:
#   py2opsin     : IUPAC name → SMILES (requires Java)
#   molfeat      : Molecular fingerprints / featurization
#   chembl_webresource_client : ChEMBL REST API
#   aizynthfinder : Retrosynthesis planning (optional, heavy)
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86 \
#     --push -f backend/docker/biomni-pharma/Dockerfile .
#
# Local:
#   docker build -t biomate/biomni-pharma:latest \
#     -f backend/docker/biomni-pharma/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86

LABEL maintainer="BioMate Team"
LABEL version="1.1.0"
LABEL description="biomni-pharma: py2opsin, molfeat, chembl-webresource-client — pharma cheminformatics on top of biomni-tools"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── py2opsin (IUPAC name → SMILES) ────────────────────────────────────────
# Shells out to a bundled OPSIN JAR — needs a JRE at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jre-headless \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir py2opsin

# ── molfeat (molecular fingerprints / featurization) ──────────────────────
RUN pip install --no-cache-dir molfeat

# ── ChEMBL REST API client ─────────────────────────────────────────────────
RUN pip install --no-cache-dir chembl_webresource_client

# ── aizynthfinder (retrosynthesis — optional, heavy) ──────────────────────
RUN pip install --no-cache-dir aizynthfinder || \
    echo "WARNING: aizynthfinder install failed — retrosynthesis workflows unavailable"

# ── Smoke tests ────────────────────────────────────────────────────────────
RUN python3 -c "import molfeat; print('molfeat OK')" && \
    python3 -c "from chembl_webresource_client.new_client import new_client; print('chembl_webresource_client OK')" && \
    python3 -c "from rdkit import Chem; print('RDKit OK (from base)')" && \
    echo "All biomni-pharma smoke tests passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Pharmacology Container Ready')"]
