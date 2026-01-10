# Biomni Galaxy Tools Docker Image
# Complete dependency installation for all 21 domains
#
# Build: docker build -t biomate/biomni-tools:latest -f biomni_galaxy/docker/Dockerfile .
# Run:   docker run -it biomate/biomni-tools:latest biomni-tool --list-domains

FROM python:3.11-slim

LABEL maintainer="BioMate Team"
LABEL description="Biomni bioinformatics tools organized by domain for Galaxy integration"
LABEL version="1.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV BIOMNI_HOME=/opt/biomni
ENV PATH="${BIOMNI_HOME}/bin:${PATH}"

# ============================================
# LAYER 1: System dependencies
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    gcc \
    g++ \
    cmake \
    make \
    gfortran \
    # Common bioinformatics tools
    wget \
    curl \
    git \
    gzip \
    bzip2 \
    unzip \
    # Image processing
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    # HDF5 for h5ad files
    libhdf5-dev \
    pkg-config \
    # For scipy/numpy
    libopenblas-dev \
    liblapack-dev \
    # For matplotlib
    libfreetype6-dev \
    # For OpenCV
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    # For pybedtools
    bedtools \
    # For ViennaRNA
    libgsl-dev \
    # Clean up
    && rm -rf /var/lib/apt/lists/*

# Create directory structure
RUN mkdir -p ${BIOMNI_HOME}/{bin,src,galaxy_tools}

# ============================================
# LAYER 2: Core Python dependencies (used by all domains)
# ============================================
RUN pip install --no-cache-dir \
    numpy \
    scipy \
    pandas \
    matplotlib \
    seaborn \
    biopython \
    requests \
    aiohttp \
    h5py \
    anndata \
    scikit-learn \
    pydantic \
    python-dotenv \
    tqdm \
    rich \
    langchain \
    langchain-core

# ============================================
# LAYER 3: Image processing (bioimaging, cell_biology, microbiology, pathology, physiology)
# ============================================
RUN pip install --no-cache-dir \
    scikit-image \
    opencv-python-headless \
    Pillow \
    nibabel \
    SimpleITK

# ============================================
# LAYER 4: Genomics & single-cell (genomics, genetics)
# ============================================
RUN pip install --no-cache-dir \
    scanpy \
    gseapy \
    gget \
    pybedtools \
    pybiomart \
    pyliftover \
    msprime \
    cooler

# ============================================
# LAYER 5: Pharmacology & chemistry
# ============================================
RUN pip install --no-cache-dir \
    rdkit \
    pubchempy \
    statsmodels

# ============================================
# LAYER 6: Systems biology & metabolic modeling
# ============================================
RUN pip install --no-cache-dir \
    cobra \
    networkx \
    python-libsbml

# ============================================
# LAYER 7: Flow cytometry (cancer_biology, cell_biology, immunology)
# ============================================
RUN pip install --no-cache-dir \
    flowio \
    flowkit \
    FlowCytometryTools

# ============================================
# LAYER 8: Literature & web scraping
# ============================================
RUN pip install --no-cache-dir \
    arxiv \
    scholarly \
    PyPDF2 \
    beautifulsoup4 \
    pymed \
    googlesearch-python \
    anthropic

# ============================================
# LAYER 9: Bioengineering & tracking
# ============================================
RUN pip install --no-cache-dir \
    trackpy \
    pykalman \
    reportlab

# ============================================
# LAYER 10: ML/Deep Learning (required for genetics, genomics, bioimaging)
# Note: These are heavy (~2GB+), but required for core domains
# ============================================
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && pip install --no-cache-dir transformers accelerate sentencepiece

# ============================================
# LAYER 11: Specialized packages (may fail on some platforms)
# ============================================
RUN pip install --no-cache-dir \
    ViennaRNA || echo "ViennaRNA not available, RNA folding disabled" \
    && pip install --no-cache-dir \
    primer3-py || echo "primer3-py not available, primer design disabled" \
    && pip install --no-cache-dir \
    nilearn || echo "nilearn not available, neuroimaging disabled" \
    && pip install --no-cache-dir \
    python-louvain || echo "python-louvain not available, community detection disabled"

# ============================================
# LAYER 12: ESM protein language model (required for genomics)
# ============================================
RUN pip install --no-cache-dir fair-esm || echo "fair-esm failed, trying alternative..." \
    && pip install --no-cache-dir esm || echo "esm not available, protein embeddings disabled"

# ============================================
# LAYER 13: googlesearch for literature domain
# The package name is different from import name
# ============================================
RUN pip install --no-cache-dir googlesearch-python || echo "googlesearch-python not available"

# ============================================
# LAYER 14: Verify critical packages are installed
# Re-install if they were overwritten by dependency conflicts
# ============================================
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && python3 -c "import torch; print(f'torch {torch.__version__} OK')" \
    && pip install --no-cache-dir fair-esm \
    && pip install --no-cache-dir googlesearch-python

# ============================================
# LAYER 15: Additional specialized packages (optional)
# These may not be available or may have issues
# Install AFTER critical packages to avoid conflicts
# ============================================
RUN pip install --no-cache-dir --no-deps scvi-tools || echo "scvi-tools not available" \
    && pip install --no-cache-dir --no-deps cellpose || echo "cellpose not available" \
    && pip install --no-cache-dir --no-deps harmony-pytorch || echo "harmony-pytorch not available"

# ============================================
# Copy and install Biomni package
# ============================================
WORKDIR ${BIOMNI_HOME}
COPY biomni/ ${BIOMNI_HOME}/src/biomni/
COPY pyproject.toml ${BIOMNI_HOME}/src/

RUN cd ${BIOMNI_HOME}/src && pip install -e . && echo "Biomni installed successfully"

# ============================================
# Copy Galaxy tool wrappers
# ============================================
COPY biomni_galaxy/tools/ ${BIOMNI_HOME}/galaxy_tools/
COPY biomni_galaxy/docker/domain_wrapper.py ${BIOMNI_HOME}/bin/biomni-tool

RUN chmod +x ${BIOMNI_HOME}/bin/biomni-tool \
    && find ${BIOMNI_HOME}/galaxy_tools -name "*.py" -exec chmod +x {} \;

# Create tool manifest
COPY biomni_galaxy/docker/create_manifest.py ${BIOMNI_HOME}/bin/create_manifest.py
RUN python3 ${BIOMNI_HOME}/bin/create_manifest.py

# ============================================
# Verification script
# ============================================
RUN echo '#!/bin/bash\n\
echo "=== Biomni Galaxy Tools Docker Image ==="\n\
echo ""\n\
echo "Testing domain imports..."\n\
for domain in biochemistry bioengineering bioimaging biophysics cancer_biology \\\n\
              cell_biology database genetics genomics glycoengineering \\\n\
              immunology lab_automation literature microbiology \\\n\
              molecular_biology pathology pharmacology physiology \\\n\
              protocols support_tools synthetic_biology systems_biology; do\n\
    python3 -c "from biomni.tool import $domain" 2>/dev/null && \\\n\
        echo "  ✓ $domain" || echo "  ✗ $domain (import failed)"\n\
done\n\
echo ""\n\
echo "Done."\n\
' > ${BIOMNI_HOME}/bin/verify-domains.sh && chmod +x ${BIOMNI_HOME}/bin/verify-domains.sh

# Set working directory
WORKDIR /data

# Default command
CMD ["python3", "-c", "print('Biomni Galaxy Tools Container Ready'); from biomni.tool import molecular_biology; print('Core imports OK')"]
