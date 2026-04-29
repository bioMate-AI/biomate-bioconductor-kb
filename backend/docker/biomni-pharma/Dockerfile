# BioMate Pharmacology Container (biomni-pharma)
#
# Extends biomni-tools:x86 with pharmacology-specific packages:
#   - PyTDC         : Therapeutics Data Commons ADMET benchmarks
#   - mordred        : 1826 comprehensive molecular descriptors (PK property prediction)
#   - chembl-webresource-client : ChEMBL REST API client for bioactivity queries
#   - py2opsin       : IUPAC name → SMILES conversion
#   - molfeat        : Molecular featurization (fingerprints, descriptors)
#   - deepchem       : Deep learning for chemistry (optional; heavy GPU dep)
#   - DeepPurpose    : Pinned 0.0.3; must succeed (replaces silent-fail in biomni-tools)
#   - aizynthfinder  : Retrosynthesis (optional; heavy dep)
#
# Base image already provides (via biomni-tools:x86):
#   numpy, scipy, pandas, biopython, rdkit, scikit-learn, statsmodels,
#   scikit-image, vina, meeko, seaborn, plotly, ViennaRNA, DeepPurpose (unfixed),
#   AWS CLI v2, openbabel
#
# Build (x86 for AWS Batch):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86 \
#     --push -f backend/docker/biomni-pharma/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86

LABEL maintainer="BioMate Team"
LABEL version="1.0.0"
LABEL description="biomni-pharma: PyTDC, mordred, chembl-webresource-client, py2opsin, molfeat, DeepPurpose==0.0.3 (pinned), deepchem (optional), aizynthfinder (optional)"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ── Layer 1: PyTDC (Therapeutics Data Commons) ─────────────────────────────
# For TDC ADMET benchmarks and datasets
RUN pip install --no-cache-dir PyTDC

# ── Layer 2: mordred (comprehensive molecular descriptors) ─────────────────
# 1826 descriptors; rdkit-compatible; pin 1.2.1 for stability
RUN pip install --no-cache-dir "mordred==1.2.1"

# ── Layer 3: ChEMBL REST API client ────────────────────────────────────────
RUN pip install --no-cache-dir chembl_webresource_client

# ── Layer 4: py2opsin (IUPAC name → SMILES) ────────────────────────────────
# Requires Java at runtime; openjdk-11-jre-headless is sufficient
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jre-headless \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir py2opsin

# ── Layer 5: molfeat (molecular featurization) ─────────────────────────────
RUN pip install --no-cache-dir molfeat

# ── Layer 6: DeepPurpose pinned (fix silent failure from biomni-tools) ──────
# Must succeed loudly — no fallback. Reinstall pins to 0.0.3.
RUN pip install --no-cache-dir "DeepPurpose==0.0.3"

# ── Layer 7: deepchem (optional — heavy GPU dep, allowed to fail) ──────────
RUN pip install --no-cache-dir deepchem || echo "WARNING: deepchem install failed — GPU-dependent workflows will be unavailable"

# ── Layer 8: aizynthfinder (optional — retrosynthesis, heavy dep) ──────────
RUN pip install --no-cache-dir aizynthfinder || echo "WARNING: aizynthfinder install failed — retrosynthesis workflows will be unavailable"

# ── Smoke tests ────────────────────────────────────────────────────────────
RUN python3 -c "from tdc.single_pred import ADMET; print('PyTDC OK')" && \
    python3 -c "from mordred import Calculator, descriptors; calc = Calculator(descriptors, ignore_3D=True); print('mordred OK  descriptor_count={}'.format(len(calc.descriptors)))" && \
    python3 -c "from chembl_webresource_client.new_client import new_client; print('chembl_webresource_client OK')" && \
    echo "All biomni-pharma smoke tests passed."

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Pharmacology Container Ready')"]
