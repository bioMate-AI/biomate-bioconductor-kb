# BioMate Drug Discovery Nextflow Container
#
# Extends biomate/biomni-structure-to-drug (rdkit + scipy already present)
# and adds the gap-filling tools:
#   - aizynthfinder   : retrosynthesis (Gap 4)
#   - pydeseq2        : Python DESeq2 for drug MoA pipeline (Gap 9)
#   - gseapy          : GSEA / pathway enrichment (Gap 9)
#   - pubchempy       : vendor availability lookup (Gap 10)
#   - BioMate drug discovery Python modules (Gaps 1,5,6,7,10)
#
# Build:
#   docker build -t biomate/biomni-drug-discovery-nf:latest \
#     -f backend/docker/drug-discovery-nf/Dockerfile .
#
# The image is used by Nextflow workflows in:
#   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/

FROM biomate/biomni-structure-to-drug:latest

LABEL maintainer="BioMate Team"
LABEL description="Drug discovery Nextflow tools: aizynthfinder, pydeseq2, gseapy + BioMate modules"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV BIOMATE_DD=/opt/biomate/drug_discovery

# ── Layer 1: Extra system deps needed by aizynthfinder ─────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# ── Layer 2: Gap-filling Python packages ───────────────────────────────────
RUN pip install --no-cache-dir \
    aizynthfinder>=4.4.1 \
    pydeseq2 \
    gseapy \
    pubchempy \
    adjustText

# ── Layer 3: AiZynthFinder minimal config + stock ──────────────────────────
# We provide a self-contained config that uses a template-based expansion
# policy (SMARTS reaction templates shipped with the aizynthfinder package)
# and a small stock of commodity starting materials.
# No large model download required for this baseline config.
RUN mkdir -p /opt/aizynthfinder/stock

# Write a SMILES stock file of common starting materials and the AiZynthFinder config
COPY backend/docker/drug-discovery-nf/setup_aizynthfinder.py /tmp/setup_aizynthfinder.py
RUN python3 /tmp/setup_aizynthfinder.py && rm /tmp/setup_aizynthfinder.py

# Test that all tools are importable
RUN python3 -c "from importlib.metadata import version; print('aizynthfinder:', version('aizynthfinder'))" && \
    python3 -c "import gseapy; print('gseapy:', gseapy.__version__)" && \
    python3 -c "from pydeseq2.dds import DeseqDataSet; print('pydeseq2: OK')" && \
    python3 -c "import rdkit; print('rdkit:', rdkit.__version__)" && \
    echo "All drug discovery tools verified."

# ── Layer 4: USPTO expansion model + template (baked-in for real retrosynthesis) ─
RUN mkdir -p /opt/aizynthfinder/models
COPY backend/docker/drug-discovery-nf/uspto_model.onnx /opt/aizynthfinder/models/
COPY backend/docker/drug-discovery-nf/uspto_templates.csv /opt/aizynthfinder/models/

# Re-run setup script now that models are present — it will write the complete config
COPY backend/docker/drug-discovery-nf/setup_aizynthfinder.py /tmp/setup_aizynthfinder2.py
RUN python3 /tmp/setup_aizynthfinder2.py && rm /tmp/setup_aizynthfinder2.py && \
    echo "=== AiZynthFinder config ===" && cat /opt/aizynthfinder/config.yml

# ── Layer 5: Copy BioMate drug discovery Python modules ────────────────────
RUN mkdir -p ${BIOMATE_DD}
COPY backend/lib/galaxy/ai/drug_discovery/ /opt/biomate/drug_discovery/
RUN echo '# BioMate drug discovery package' > /opt/biomate/__init__.py && \
    echo '# BioMate drug discovery modules' > /opt/biomate/drug_discovery/__init__.py

# Make modules importable
ENV PYTHONPATH="/opt/biomate:${PYTHONPATH}"

# ── Verify complete stack ───────────────────────────────────────────────────
COPY backend/docker/drug-discovery-nf/verify_stack.py /tmp/verify_stack.py
RUN python3 /tmp/verify_stack.py && rm /tmp/verify_stack.py

WORKDIR /data
CMD ["python3", "-c", "print('BioMate Drug Discovery NF Container Ready')"]
